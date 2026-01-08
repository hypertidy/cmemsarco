# CMEMS ARCO Zarr Catalog Builder
# Walks the STAC catalog to build a full products/datasets table with
# GDAL DSNs and s3:// paths for geoChunked and timeChunked Zarrs

# STAC catalog root
STAC_ROOT <- "https://stac.marine.copernicus.eu/metadata"

#' Fetch JSON from URL
fetch_json <- function(url) {
  request(url) |>
    req_perform() |>
    resp_body_json()
}

#' Get all product IDs from the root catalog
get_product_ids <- function() {
  catalog <- fetch_json(file.path(STAC_ROOT, "catalog.stac.json"))

  # Extract child links (products)
  children <- catalog$links |>
    keep(~ .x$rel == "child") |>
    map_chr(~ .x$title)

  children
}

#' Get dataset items for a product
#' Returns list of item IDs (dataset_version combos)
get_product_datasets <- function(product_id) {
  url <- file.path(STAC_ROOT, product_id, "product.stac.json")

  tryCatch({
    product <- fetch_json(url)

    # Items are linked with rel="item"
    items <- product$links |>
      keep(~ .x$rel == "item")

    tibble(
      product_id = product_id,
      item_href = map_chr(items, ~ .x$href),
      item_title = map_chr(items, ~ .x$title %||% NA_character_)
    )
  }, error = function(e) {
    warning(sprintf("Failed to fetch product %s: %s", product_id, e$message))
    tibble(product_id = character(), item_href = character(), item_title = character())
  })
}

#' Get asset URLs from a dataset item
get_item_assets <- function(product_id, item_href) {
  # item_href is relative like "cmems_obs-sl_glo_phy-ssh_nrt_allsat-l4-duacs-0.25deg_P1D_202311.stac.json"
  url <- file.path(STAC_ROOT, product_id, item_href)

  tryCatch({
    item <- fetch_json(url)

    # Extract the dataset_id (item id without version suffix)
    dataset_version_id <- item$id

    # Get assets - typically "timeChunked" and "geoChunked"
    assets <- item$assets %||% list()

    asset_names <- names(assets)

    tibble(
      dataset_version_id = dataset_version_id,
      asset_name = asset_names,
      asset_href = map_chr(asset_names, ~ assets[[.x]]$href %||% NA_character_)
    )
  }, error = function(e) {
    warning(sprintf("Failed to fetch item %s: %s", item_href, e$message))
    tibble(dataset_version_id = character(), asset_name = character(), asset_href = character())
  })
}

#' Build full catalog table
#' @param products Optional vector of product_ids to process (NULL = all)
#' @param progress Show progress messages
build_catalog <- function(products = NULL, progress = TRUE) {

  if (is.null(products)) {
    if (progress) message("Fetching product list...")
    products <- get_product_ids()
  }

  if (progress) message(sprintf("Processing %d products...", length(products)))

  # Get datasets for all products
  datasets <- map_dfr(products, function(pid) {
    if (progress) message(sprintf("  %s", pid))
    get_product_datasets(pid)
  })

  if (progress) message(sprintf("Found %d dataset items, fetching assets...", nrow(datasets)))

  # Get assets for all items
  assets <- map2_dfr(datasets$product_id, datasets$item_href, function(pid, href) {
    get_item_assets(pid, href)
  })

  # Join and reshape
  result <- datasets |>
    left_join(assets, by = c("item_title" = "dataset_version_id")) |>
    select(-item_href) |>
    rename(dataset_version_id = item_title)

  result
}

#' Generate GDAL Zarr DSN from S3 URL
#' @param s3_url The https:// URL to the Zarr store
#' @param array Optional array name to access a specific variable
to_gdal_zarr <- function(s3_url, array = NULL) {
  # Convert https://s3.waw3-1.cloudferro.com/bucket/path/store.zarr
  # to ZARR:"/vsis3/bucket/path/store.zarr"

  # Parse the URL
  parsed <- regmatches(s3_url, regexec("https://([^/]+)/(.+)", s3_url))[[1]]
  endpoint <- parsed[2]
  path <- parsed[3]

  # Build vsis3 path
  vsis3_path <- sprintf("/vsis3/%s", path)

  if (is.null(array)) {
    sprintf('ZARR:"%s"', vsis3_path)
  } else {
    sprintf('ZARR:"%s":/%s', vsis3_path, array)
  }
}

#' Generate s3:// URI from HTTPS URL
to_s3_uri <- function(s3_url) {
  parsed <- regmatches(s3_url, regexec("https://[^/]+/([^/]+)/(.+)", s3_url))[[1]]
  bucket <- parsed[2]
  key <- parsed[3]
  sprintf("s3://%s/%s", bucket, key)
}

#' Add GDAL and S3 columns to catalog table
add_dsn_columns <- function(catalog) {
  catalog |>
    mutate(
      gdal_dsn = map_chr(asset_href, to_gdal_zarr),
      s3_uri = map_chr(asset_href, to_s3_uri)
    )
}

# Helper: parse dataset_id and version from dataset_version_id
parse_dataset_version <- function(dataset_version_id) {
  # Pattern: {dataset_id}_{YYYYMM} where version is typically 6 digits
  pattern <- "^(.+)_(\\d{6})$"
  matches <- regmatches(dataset_version_id, regexec(pattern, dataset_version_id))[[1]]

  if (length(matches) == 3) {
    list(dataset_id = matches[2], version = matches[3])
  } else {
    list(dataset_id = dataset_version_id, version = NA_character_)
  }
}

#' Pivot catalog to wide format with geo/time columns
pivot_catalog <- function(catalog) {
  catalog |>
    pivot_wider(
      id_cols = c(product_id, dataset_version_id),
      names_from = asset_name,
      values_from = c(asset_href, gdal_dsn, s3_uri),
      names_glue = "{asset_name}_{.value}"
    )
}

# ============================================================================
# Example usage
# ============================================================================

if (FALSE) {
  # Build catalog for a single product
  cat <- build_catalog(products = "SEALEVEL_GLO_PHY_L4_NRT_008_046")
  cat <- add_dsn_columns(cat)

  # See what we got
  cat |> print(n = 20)

  # Get just the timeChunked assets
  cat |>
    filter(asset_name == "timeChunked") |>
    select(product_id, dataset_version_id, gdal_dsn)

  # Build for multiple products
  products <- c(
    "SEALEVEL_GLO_PHY_L4_NRT_008_046",
    "SEALEVEL_GLO_PHY_L4_MY_008_047",
    "GLOBAL_ANALYSISFORECAST_PHY_001_024"
  )
  full_cat <- build_catalog(products = products)
  full_cat <- add_dsn_columns(full_cat)

  # Pivot to wide format
  wide_cat <- pivot_catalog(full_cat)

  # GDAL environment setup for access
  Sys.setenv(
    AWS_NO_SIGN_REQUEST = "YES",
    AWS_S3_ENDPOINT = "s3.waw3-1.cloudferro.com"
  )

  # Use with terra/sf/stars
  library(terra)
  dsn <- wide_cat$timeChunked_gdal_dsn[1]
  # rast(dsn)  # Would work with proper GDAL build

  # List subdatasets
  library(vapour)
  # vapour_sds_names(dsn)
}
