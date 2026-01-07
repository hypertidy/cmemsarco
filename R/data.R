#' CMEMS ARCO Catalog
#'
#' Cached catalog of Copernicus Marine ARCO Zarr datasets with URLs for
#' timeChunked and geoChunked stores.
#'
#' @format A tibble with columns:
#' \describe{
#'   \item{product_id}{CMEMS product identifier (e.g., "SEALEVEL_GLO_PHY_L4_NRT_008_046")}
#'   \item{dataset_version_id}{Dataset with version suffix (e.g., "cmems_obs-sl_..._202411")}
#'   \item{dataset_id}{Dataset identifier without version}
#'   \item{version}{6-digit version string (YYYYMM)}
#'   \item{timeChunked_url}{HTTPS URL to timeChunked.zarr (spatial slice access)}
#'   \item{geoChunked_url}{HTTPS URL to geoChunked.zarr (time series access)}
#'   \item{native_url}{URL to native files (if available)}
#'   \item{timeChunked_gdal}{GDAL-ready DSN for timeChunked store}
#'   \item{geoChunked_gdal}{GDAL-ready DSN for geoChunked store}
#'   \item{timeChunked_s3}{S3 URI for timeChunked store}
#'   \item{geoChunked_s3}{S3 URI for geoChunked store}
#' }
#'
#' @source STAC catalog at <https://stac.marine.copernicus.eu/metadata/catalog.stac.json>
#' @seealso [cmems_catalog()] to refresh, [cmems_latest()] to filter to latest versions
"cmems_catalog_data"
