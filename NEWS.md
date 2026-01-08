# cmemsarco 0.1.0

* Initial release.

* `cmems_catalog()` builds catalog from STAC, walking all products and datasets
  to retrieve Zarr asset URLs.

* `cmems_latest()` filters catalog to latest version per dataset.

* `cmems_arco_only()` removes static/native-only datasets without Zarr URLs.

* `cmems_gdal_dsn()` converts HTTPS URLs to GDAL Zarr DSNs using `/vsicurl/`
  (works without environment configuration).

* `cmems_gdal_dsn_s3()` converts HTTPS URLs to GDAL Zarr DSNs using `/vsis3/`
  (requires `cmems_setup()` first).

* `cmems_s3_uri()` converts HTTPS URLs to `s3://` URIs.

* `cmems_arco_url()` and `cmems_arco_dsn()` construct URLs directly from 
  known product/dataset/version identifiers.

* `cmems_setup()` configures GDAL environment for `/vsis3/` CMEMS S3 access.

* Bundled `cmems_catalog_data` with 1730 ARCO datasets across 327 products.
