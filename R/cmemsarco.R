# cmemsarco - Cloud-native access to CMEMS ARCO Zarr stores
#
# STAC Hierarchy:
#   catalog.stac.json
#     └── {PRODUCT_ID}/product.stac.json (Collection)
#           └── {dataset_version_id}.stac.json (Item)
#                 └── assets: timeChunked, geoChunked, native
#
# URL pattern:
#   https://s3.waw3-1.cloudferro.com/mdl-arco-{time|geo}-{NNN}/arco/
#   {PRODUCT_ID}/{dataset_id}_{version}/{time|geo}Chunked.zarr

# Constants ---------------------------------------------------------------

CMEMS_STAC_ROOT <- "https://stac.marine.copernicus.eu/metadata"
CMEMS_S3_ENDPOINT <- "s3.waw3-1.cloudferro.com"

# Setup -------------------------------------------------------------------

#' Set up GDAL environment for CMEMS access
#'
#' Sets AWS environment variables required for anonymous S3 access to CMEMS.
#'
#' @return Invisible TRUE
#' @export
#' @examples
#' cmems_setup()
cmems_setup <- function() {

  Sys.setenv(
    AWS_NO_SIGN_REQUEST = "YES",
    AWS_S3_ENDPOINT = CMEMS_S3_ENDPOINT
  )
  invisible(TRUE)
}

# URL/DSN conversion ------------------------------------------------------

#' Convert S3 HTTPS URL to GDAL Zarr DSN
#'
#' @param url HTTPS URL to a Zarr store
#' @param array Optional array/variable name to access directly
#'
#' @return GDAL DSN string
#' @export
#' @examples
#' url <- "https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/PRODUCT/dataset/timeChunked.zarr"
#' cmems_gdal_dsn(url)
#' cmems_gdal_dsn(url, array = "sla")
cmems_gdal_dsn <- function(url, array = NULL) {
  if (is.na(url) || is.null(url)) return(NA_character_)

  parts <- regmatches(url, regexec("https://[^/]+/(.+)", url))[[1]]
  if (length(parts) < 2) return(NA_character_)

  path <- parts[2]

  if (is.null(array)) {
    sprintf('ZARR:"/vsis3/%s"', path)
  } else {
    sprintf('ZARR:"/vsis3/%s":/%s', path, array)
  }
}

#' Convert S3 HTTPS URL to s3:// URI
#'
#' @param url HTTPS URL to a Zarr store
#'
#' @return S3 URI string
#' @export
cmems_s3_uri <- function(url) {
  if (is.na(url) || is.null(url)) return(NA_character_)

  parts <- regmatches(url, regexec("https://[^/]+/([^/]+)/(.+)", url))[[1]]
  if (length(parts) < 3) return(NA_character_)

  sprintf("s3://%s/%s", parts[2], parts[3])
}

# Catalog building --------------------------------------------------------

#' Fetch JSON from URL
#' @noRd
fetch_json <- function(url) {
 httr2::request(url) |>
    httr2::req_perform() |>
    httr2::resp_body_json()
}

#' Get product IDs from STAC catalog
#' @noRd
stac_product_ids <- function() {
  catalog <- fetch_json(file.path(CMEMS_STAC_ROOT, "catalog.stac.json"))

  catalog$links |>
    purrr::keep(~ .x$rel == "child") |>
    purrr::map_chr(~ .x$title)
}

#' Get datasets from STAC for one product
#' @noRd
stac_product_datasets <- function(product_id) {
  product_url <- file.path(CMEMS_STAC_ROOT, product_id, "product.stac.json")

  tryCatch({
    product <- fetch_json(product_url)

    items <- product$links |>
      purrr::keep(~ .x$rel == "item")

    purrr::map_dfr(items, function(item) {
      item_url <- file.path(CMEMS_STAC_ROOT, product_id, item$href)

      tryCatch({
        item_data <- fetch_json(item_url)
        assets <- item_data$assets %||% list()

        tibble::tibble(
          product_id = product_id,
          dataset_version_id = item_data$id,
          timeChunked_url = assets$timeChunked$href %||% NA_character_,
          geoChunked_url = assets$geoChunked$href %||% NA_character_,
          native_url = assets$native$href %||% NA_character_
        )
      }, error = function(e) tibble::tibble())
    })

  }, error = function(e) {
    warning(sprintf("Failed to get STAC for %s: %s", product_id, e$message))
    tibble::tibble()
  })
}

#' Build CMEMS ARCO catalog from STAC
#'
#' Walks the STAC catalog to retrieve all products, datasets, and Zarr URLs.
#'
#' @param product_ids Character vector of product IDs, or NULL for all products
#' @param progress Show progress messages
#'
#' @return A tibble with columns: product_id, dataset_version_id, dataset_id,
#'   version, timeChunked_url, geoChunked_url, native_url, plus _gdal and _s3
#'   variants
#' @export
#' @examples
#' \dontrun{
#' # Single product
#' cat <- cmems_catalog("SEALEVEL_GLO_PHY_L4_NRT_008_046")
#'
#' # All products (takes a few minutes)
#' full <- cmems_catalog()
#' }
cmems_catalog <- function(product_ids = NULL, progress = TRUE) {

  if (is.null(product_ids)) {
    if (progress) message("Fetching STAC catalog...")
    product_ids <- stac_product_ids()
  }

  if (progress) message(sprintf("Processing %d products...", length(product_ids)))

  ##catalog <- future_map_dfr(seq_along(product_ids), function(i) {
  catalog <- purrr::map_dfr(seq_along(product_ids), function(i) {
    pid <- product_ids[i]
    if (progress) message(sprintf("  [%d/%d] %s", i, length(product_ids), pid))
    stac_product_datasets(pid)
  })

  # Parse version and add DSN columns
  catalog |>
    dplyr::mutate(
      dataset_id = dplyr::if_else(
        grepl("_\\d{6}$", dataset_version_id),
        sub("_\\d{6}$", "", dataset_version_id),
        dataset_version_id
      ),
      version = dplyr::if_else(
        grepl("_\\d{6}$", dataset_version_id),
        sub(".*_(\\d{6})$", "\\1", dataset_version_id),
        NA_character_
      ),
      timeChunked_gdal = purrr::map_chr(timeChunked_url, cmems_gdal_dsn),
      geoChunked_gdal = purrr::map_chr(geoChunked_url, cmems_gdal_dsn),
      timeChunked_s3 = purrr::map_chr(timeChunked_url, cmems_s3_uri),
      geoChunked_s3 = purrr::map_chr(geoChunked_url, cmems_s3_uri)
    )
}

#' Filter catalog to latest version per dataset
#'
#' @param catalog A catalog tibble from [cmems_catalog()]
#'
#' @return Filtered tibble with only the latest version of each dataset
#' @export
cmems_latest <- function(catalog) {
  catalog |>
    dplyr::filter(!is.na(version)) |>
    dplyr::group_by(product_id, dataset_id) |>
    dplyr::filter(version == max(version)) |>
    dplyr::ungroup()
}

#' Filter catalog to ARCO datasets only
#'
#' Removes datasets that don't have Zarr URLs (static/native-only datasets).
#'
#' @param catalog A catalog tibble from [cmems_catalog()]
#'
#' @return Filtered tibble with only ARCO datasets
#' @export
cmems_arco_only <- function(catalog) {
  catalog |>
    dplyr::filter(!is.na(timeChunked_url) | !is.na(geoChunked_url))
}

# Direct URL construction -------------------------------------------------

#' Construct ARCO Zarr URL directly
#'
#' Build a Zarr URL from known identifiers without querying STAC.
#' Requires knowing the bucket version suffix which varies by product family.
#'
#' @param product_id Product identifier
#' @param dataset_id Dataset identifier (without version)
#' @param version 6-digit version string (YYYYMM)
#' @param chunk_type "time" or "geo"
#' @param bucket_version Bucket suffix (e.g., "045", "042"). Varies by product.
#'
#' @return HTTPS URL to the Zarr store
#' @export
cmems_arco_url <- function(product_id, dataset_id, version,
                           chunk_type = c("time", "geo"),
                           bucket_version = "045") {
  chunk_type <- match.arg(chunk_type)

  dataset_version_id <- paste0(dataset_id, "_", version)
  zarr_name <- paste0(chunk_type, "Chunked.zarr")
  bucket <- paste0("mdl-arco-", chunk_type, "-", bucket_version)

  sprintf("https://%s/%s/arco/%s/%s/%s",
          CMEMS_S3_ENDPOINT, bucket, product_id, dataset_version_id, zarr_name)
}

#' Construct GDAL DSN directly
#'
#' Convenience wrapper combining [cmems_arco_url()] and [cmems_gdal_dsn()].
#'
#' @inheritParams cmems_arco_url
#' @param array Optional array/variable name
#'
#' @return GDAL DSN string
#' @export
cmems_arco_dsn <- function(product_id, dataset_id, version,
                           chunk_type = c("time", "geo"),
                           bucket_version = "045",
                           array = NULL) {
  url <- cmems_arco_url(product_id, dataset_id, version, chunk_type, bucket_version)
  cmems_gdal_dsn(url, array)
}

# CLI helper --------------------------------------------------------------

#' Generate gdalinfo command
#'
#' @param dsn GDAL DSN string
#'
#' @return Shell command string
#' @export
cmems_gdalinfo_cmd <- function(dsn) {
  sprintf(
    'AWS_NO_SIGN_REQUEST=YES AWS_S3_ENDPOINT=%s gdalinfo %s',
    CMEMS_S3_ENDPOINT, shQuote(dsn)
  )
}
