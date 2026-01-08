#' CMEMS ARCO Catalog
#'
#' Cached catalog of Copernicus Marine ARCO Zarr datasets with URLs for
#' timeChunked and geoChunked stores. Updated periodically via
#' `data-raw/update_catalog.R`.
#'
#' @format A tibble with columns:
#' \describe{
#'   \item{product_id}{CMEMS product identifier}
#'   \item{dataset_version_id}{Full dataset identifier with version suffix}
#'   \item{dataset_id}{Dataset identifier without version}
#'   \item{version}{6-digit version string (YYYYMM), NA for static datasets}
#'   \item{timeChunked_url}{HTTPS URL to timeChunked.zarr (spatial slice access)}
#'   \item{geoChunked_url}{HTTPS URL to geoChunked.zarr (time series access)}
#'   \item{native_url}{URL to native files (if available)}
#'   \item{timeChunked_gdal}{GDAL DSN using /vsicurl/ (no setup needed)}
#'   \item{geoChunked_gdal}{GDAL DSN using /vsicurl/ (no setup needed)}
#'   \item{timeChunked_gdals3}{GDAL DSN using /vsis3/ (needs cmems_setup())}
#'   \item{geoChunked_gdals3}{GDAL DSN using /vsis3/ (needs cmems_setup())}
#'   \item{timeChunked_s3}{S3 URI for timeChunked store}
#'   \item{geoChunked_s3}{S3 URI for geoChunked store}
#' }
#'
#' @source STAC catalog at <https://stac.marine.copernicus.eu/metadata/catalog.stac.json>
#' @seealso [cmems_catalog()] to refresh, [cmems_latest()] to filter to latest versions,
#'   [cmems_arco_only()] to remove non-ARCO datasets
"cmems_catalog_data"
