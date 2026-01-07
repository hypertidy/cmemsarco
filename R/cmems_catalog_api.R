# CMEMS Catalog Builder - API + Pattern Approach
# Uses the CopernicusMarine API strategy for product/dataset discovery
# then constructs Zarr URLs from the known bucket pattern
#
# Key discovery from STAC structure:
#
# STAC Hierarchy:
#   catalog.stac.json
#     └── {PRODUCT_ID}/product.stac.json (Collection)
#           └── {dataset_version_id}.stac.json (Item)
#                 └── assets: timeChunked, geoChunked, native
#
# Asset URL pattern (from French ODATIS PDF and Julia ZarrDatasets.jl):
#   https://s3.waw3-1.cloudferro.com/mdl-arco-time-042/arco/OCEANCOLOUR_GLO_BGC_L3_MY_009_103/
#   cmems_obs-oc_glo_bgc-optics_my_l3-multi-4km_P1D_202311/timeChunked.zarr
#
# Bucket naming (NNN varies by dataset):
#   mdl-arco-geo-{NNN}   -> geoChunked.zarr   (time-series at point use case)
#   mdl-arco-time-{NNN}  -> timeChunked.zarr  (spatial slice at time use case)
#
# For GDAL access, source doesn't allow LIST so GDAL guesses paths from
# Zarr conventions: /.zmetadata, /.zattrs, chunk paths from zmetadata
#
# NOTE on CopernicusMarine R package:
# - cms_products_list() gives product metadata but NOT dataset-level details
# - cms_products_list2() uses different API with even less detail
# - Neither provides the ARCO Zarr URLs directly
# - STAC catalog is the authoritative source for ARCO asset URLs
# - CopernicusMarine package is good for: WMTS, native files, STAC file lists,
#   but the native files are NetCDF on a different bucket (mdl-native-{NNN})

library(httr2)
library(jsonlite)
library(dplyr)
library(purrr)

globalVariables("cmems_catalog_data")
cmems_cached_catalog <- function() {
  cmems_catalog_data
}
cmems_catalog <- function(refresh = FALSE) {

  cached <- cmems_cached_catalog()  # bundled or ~/.cache/cmemsarco/

  if (!refresh) return(cached)

  # Just fetch the item list (fast, no asset URLs yet)
  current_items <- get_stac_item_ids()  # product_id + dataset_version_id pairs

  cached_items <- cached |>
    distinct(product_id, dataset_version_id)

  new_items <- anti_join(current_items, cached_items)

  if (nrow(new_items) == 0) {
    message("Catalog up to date")
    return(cached)
  }

  message(sprintf("Fetching %d new datasets...", nrow(new_items)))

  # Only hit STAC for the new ones
  new_data <- new_items |>
    group_by(product_id) |>
    group_map(~ get_stac_datasets(.y$product_id, items = .x$dataset_version_id))

  bind_rows(cached, new_data)
}
# ============================================================================
# Known patterns from CMEMS ARCO infrastructure
# ============================================================================

# Bucket patterns:
#   mdl-arco-geo-{NNN}  -> geoChunked.zarr  (138, 32, 64) - time series at point
#   mdl-arco-time-{NNN} -> timeChunked.zarr (1, 720, 512) - spatial slice at time
#
# URL template:
#   https://s3.waw3-1.cloudferro.com/mdl-arco-{geo|time}-{version}/arco/{PRODUCT_ID}/{dataset_version_id}/{geo|time}Chunked.zarr
#
# The {version} in bucket name corresponds to dataset version (e.g., 045, 042)
# but bucket versioning != dataset versioning - buckets seem to use different numbers

S3_ENDPOINT <- "s3.waw3-1.cloudferro.com"

# ============================================================================
# Product discovery via API (CopernicusMarine strategy)
# ============================================================================

#' Get all products from CMEMS API
#' Uses the same endpoint as CopernicusMarine::cms_products_list()
get_all_products <- function() {

  payload <- list(
    facets = c("mainVariables", "areas", "tempResolutions", "sources"),
    facetValues = setNames(list(), character(0)),
    freeText = "",
    dateRange = list(begin = NA, end = NA, coverFull = FALSE),
    favoriteIds = list(),
    offset = 0,
    size = 1000,  # Should be enough for all products
    variant = "summary",
    includeOmis = TRUE,
    `__myOcean__` = TRUE
  )

  resp <- request("https://data-be-prd.marine.copernicus.eu/api/datasets") |>
    req_method("POST") |>
    req_body_json(payload) |>
    req_perform() |>
    resp_body_json()

  # resp$datasets is a named list keyed by product_id
  products <- resp$datasets

  # Flatten to tibble
  map_dfr(names(products), function(pid) {
    p <- products[[pid]]
    tibble(
      product_id = pid,
      title = p$title %||% NA_character_,
      description = p$abstract %||% NA_character_
    )
  })
}

#' Get product details including layers (datasets)
#' This requires product-specific API call
get_product_details <- function(product_id) {
  # The describe endpoint gives full structure
  url <- sprintf("https://data-be-prd.marine.copernicus.eu/api/datasets/%s", product_id)

  tryCatch({
    resp <- request(url) |>
      req_perform() |>
      resp_body_json()

    resp
  }, error = function(e) {
    warning(sprintf("Failed to get details for %s: %s", product_id, e$message))
    NULL
  })
}

# ============================================================================
# STAC-based dataset discovery (more reliable for ARCO URLs)
# ============================================================================

STAC_ROOT <- "https://stac.marine.copernicus.eu/metadata"

#' Get datasets from STAC product file
#' Returns dataset items with asset URLs
get_stac_datasets <- function(product_id) {

  product_url <- file.path(STAC_ROOT, product_id, "product.stac.json")

  tryCatch({
    product <- request(product_url) |>
      req_perform() |>
      resp_body_json()

    # Get item links
    items <- product$links |>
      keep(~ .x$rel == "item")

    # Fetch each item to get assets
    map_dfr(items, function(item) {
      item_url <- file.path(STAC_ROOT, product_id, item$href)

      tryCatch({
        item_data <- request(item_url) |>
          req_perform() |>
          resp_body_json()

        assets <- item_data$assets %||% list()

        tibble(
          product_id = product_id,
          dataset_version_id = item_data$id,
          timeChunked_url = assets$timeChunked$href %||% NA_character_,
          geoChunked_url = assets$geoChunked$href %||% NA_character_,
          native_url = assets$native$href %||% NA_character_
        )
      }, error = function(e) {
        tibble()
      })
    })

  }, error = function(e) {
    warning(sprintf("Failed to get STAC for %s: %s", product_id, e$message))
    tibble()
  })
}

# ============================================================================
# URL/DSN generation
# ============================================================================

#' Convert S3 HTTPS URL to GDAL Zarr DSN
#' @param url The https URL to zarr store
#' @param array Optional: specific array/variable name
make_gdal_zarr_dsn <- function(url, array = NULL) {
  if (is.na(url)) return(NA_character_)

  # Parse: https://s3.waw3-1.cloudferro.com/bucket/path/store.zarr
  parts <- regmatches(url, regexec("https://[^/]+/(.+)", url))[[1]]
  if (length(parts) < 2) return(NA_character_)

  path <- parts[2]

  if (is.null(array)) {
    sprintf('ZARR:"/vsis3/%s"', path)
  } else {
    sprintf('ZARR:"/vsis3/%s":/%s', path, array)
  }
}

#' Convert to s3:// URI
make_s3_uri <- function(url) {
  if (is.na(url)) return(NA_character_)

  parts <- regmatches(url, regexec("https://[^/]+/([^/]+)/(.+)", url))[[1]]
  if (length(parts) < 3) return(NA_character_)

  sprintf("s3://%s/%s", parts[2], parts[3])
}

#' Convert to CLI-friendly URL for tools like s5cmd
make_s5cmd_url <- function(url) {
  if (is.na(url)) return(NA_character_)
  make_s3_uri(url)
}

# ============================================================================
# Main catalog builder
# ============================================================================

#' Build catalog from STAC
#' @param product_ids Character vector of product IDs, or NULL for all
#' @param progress Show progress
build_cmems_catalog <- function(product_ids = NULL, progress = TRUE) {

  # Get product list if not provided
  if (is.null(product_ids)) {
    if (progress) message("Fetching STAC catalog...")

    catalog <- request(file.path(STAC_ROOT, "catalog.stac.json")) |>
      req_perform() |>
      resp_body_json()

    product_ids <- catalog$links |>
      keep(~ .x$rel == "child") |>
      map_chr(~ .x$title)
  }

  if (progress) message(sprintf("Processing %d products...", length(product_ids)))

  # Fetch datasets for each product
  catalog_df <- map_dfr(seq_along(product_ids), function(i) {
    pid <- product_ids[i]
    if (progress) message(sprintf("  [%d/%d] %s", i, length(product_ids), pid))
    get_stac_datasets(pid)
  })

  # Add DSN columns
  catalog_df <- catalog_df |>
    mutate(
      # Parse dataset_id and version
      dataset_id = sub("_\\d{6}$", "", dataset_version_id),
      version = sub(".*_(\\d{6})$", "\\1", dataset_version_id),

      # GDAL DSNs
      timeChunked_gdal = map_chr(timeChunked_url, make_gdal_zarr_dsn),
      geoChunked_gdal = map_chr(geoChunked_url, make_gdal_zarr_dsn),

      # S3 URIs
      timeChunked_s3 = map_chr(timeChunked_url, make_s3_uri),
      geoChunked_s3 = map_chr(geoChunked_url, make_s3_uri)
    )

  catalog_df
}

#' Get latest version for each dataset
get_latest_versions <- function(catalog) {
  catalog |>
    group_by(product_id, dataset_version_id) |>
    filter(version == max(version)) |>
    ungroup()
}

# ============================================================================
# Convenience functions for common access patterns
# ============================================================================

#' Set up GDAL environment for CMEMS access
setup_gdal_env <- function() {
  Sys.setenv(
    AWS_NO_SIGN_REQUEST = "YES",
    AWS_S3_ENDPOINT = S3_ENDPOINT
  )
  invisible(TRUE)
}

#' Generate GDAL command line for gdalinfo on a Zarr
gdal_info_cmd <- function(dsn) {
  sprintf(
    'AWS_NO_SIGN_REQUEST=YES AWS_S3_ENDPOINT=%s gdalinfo %s',
    S3_ENDPOINT, shQuote(dsn)
  )
}

#' List subdatasets/arrays in a Zarr
#' Requires vapour or similar
list_zarr_arrays <- function(url) {
  setup_gdal_env()
  dsn <- make_gdal_zarr_dsn(url)

  # Use vapour if available
  if (requireNamespace("vapour", quietly = TRUE)) {
    vapour::vapour_sds_names(dsn)
  } else {
    message("Install 'vapour' package for listing arrays")
    NULL
  }
}

# ============================================================================
# Example usage
# ============================================================================

if (FALSE) {

  # Build catalog for specific products
  cat <- build_cmems_catalog(
    product_ids = c(
      "SEALEVEL_GLO_PHY_L4_NRT_008_046",
      "GLOBAL_ANALYSISFORECAST_PHY_001_024"
    )
  )

  print(cat)

  # Get just latest versions
  latest <- get_latest_versions(cat)

  # Filter to sea level product, timeChunked
  sla <- cat |>
    filter(product_id == "SEALEVEL_GLO_PHY_L4_NRT_008_046") |>
    select(dataset_id, version, timeChunked_gdal)

  print(sla)

  # Setup environment and test
  setup_gdal_env()

  # The DSN for GDAL
  dsn <- sla$timeChunked_gdal[1]
  message("GDAL DSN: ", dsn)

  # Command line equivalent
  message("CLI: ", gdal_info_cmd(dsn))

  # With terra
  # library(terra)
  # r <- rast(dsn)  # Needs GDAL Zarr driver

  # With stars via vapour
  # library(stars)
  # library(vapour)
  # sds <- vapour_sds_names(dsn)

  # Build full catalog (all products - takes a while)
  # full_catalog <- build_cmems_catalog()
  # saveRDS(full_catalog, "cmems_arco_catalog.rds")
}

# ============================================================================
# Direct URL construction (when you know product/dataset/version)
# ============================================================================
#
# If you already have the product_id, dataset_id, and version from another
# source (e.g. the CopernicusMarine package or copernicusmarine CLI describe),
# you can construct URLs directly:

#' Construct ARCO Zarr URL from known identifiers
#' @param product_id e.g. "SEALEVEL_GLO_PHY_L4_NRT_008_046"
#' @param dataset_id e.g. "cmems_obs-sl_glo_phy-ssh_nrt_allsat-l4-duacs-0.25deg_P1D"
#' @param version 6-digit version e.g. "202311"
#' @param chunk_type "time" or "geo"
#' @param bucket_version The bucket number suffix (varies per dataset family)
#'
#' @details The bucket_version is NOT the same as dataset version. Common values:
#'   - 042, 045 for different product families
#'   - You'll need to look this up from STAC or trial-and-error
make_arco_url <- function(product_id, dataset_id, version,
                          chunk_type = c("time", "geo"),
                          bucket_version = "045") {
  chunk_type <- match.arg(chunk_type)

  dataset_version_id <- paste0(dataset_id, "_", version)
  zarr_name <- paste0(chunk_type, "Chunked.zarr")
  bucket <- paste0("mdl-arco-", chunk_type, "-", bucket_version)

  sprintf("https://%s/%s/arco/%s/%s/%s",
          S3_ENDPOINT, bucket, product_id, dataset_version_id, zarr_name)
}

#' Make GDAL DSN directly
make_arco_gdal <- function(product_id, dataset_id, version,
                           chunk_type = c("time", "geo"),
                           bucket_version = "045",
                           array = NULL) {
  url <- make_arco_url(product_id, dataset_id, version, chunk_type, bucket_version)
  make_gdal_zarr_dsn(url, array)
}

# Example:
# For SEALEVEL_GLO_PHY_L4_NRT_008_046 / cmems_obs-sl_glo_phy-ssh_nrt_allsat-l4-duacs-0.25deg_P1D
#
# make_arco_gdal(
#   "SEALEVEL_GLO_PHY_L4_NRT_008_046",
#   "cmems_obs-sl_glo_phy-ssh_nrt_allsat-l4-duacs-0.25deg_P1D",
#   "202311",
#   chunk_type = "time"
# )
# => 'ZARR:"/vsis3/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_NRT_008_046/cmems_obs-sl_glo_phy-ssh_nrt_allsat-l4-duacs-0.25deg_P1D_202311/timeChunked.zarr"'
