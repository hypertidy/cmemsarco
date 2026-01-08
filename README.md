
<!-- badges: start -->

[![R-CMD-check](https://github.com/hypertidy/cmemsarco/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/hypertidy/cmemsarco/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

# cmemsarco

Cloud-native access to Copernicus Marine (CMEMS) ARCO Zarr stores. No
file downloads, no directory listings, no NetCDF wrangling - just URLs
and GDAL.

## Installation

``` r
# install.packages("remotes")
remotes::install_github("hypertidy/cmemsarco")
```

## Analysis ready data sources from Copernicus Marine

CMEMS provides Analysis-Ready Cloud-Optimized (ARCO) Zarr stores for
their marine datasets. These are chunked for two access patterns:

| Bucket | Zarr | Chunks | Use case |
|----|----|----|----|
| `mdl-arco-geo-*` | `geoChunked.zarr` | (138, 32, 64) | Time series at a point |
| `mdl-arco-time-*` | `timeChunked.zarr` | (1, 720, 512) | Spatial slice at one time |

The S3 buckets don’t allow LIST operations, but GDAL’s Zarr driver
doesn’t need them - it reads `/.zmetadata` and derives chunk paths from
the Zarr spec. This means you can go straight from URL to pixels with no
intermediate steps.

## Usage

cmemsarco comes with a ready to use catalog:

``` r
library(cmemsarco)
data(cmems_catalog_data)
catalog <- cmems_catalog_data
```

See [Build a catalog](#build-a-catalog) for building this from scratch.

### Get a GDAL source

``` r
# Filter to what you need
sla <- catalog |>
  dplyr::filter(product_id == "SEALEVEL_GLO_PHY_L4_MY_008_047") |>
  cmems_latest()  # latest version per dataset

# Get the GDAL-ready DSN
dsn <- sla$timeChunked_gdal[1]
dsn
#> [1] "ZARR:\"/vsicurl/https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr\""
```

### Read data directly

The default `*_gdal` columns use `/vsicurl/` and work without any setup:

``` r
## first band of "adt" var (using Classic syntax for ZARR driver)
dsn_2d <- sprintf("%s:/adt:0", dsn)

ds <- new(gdalraster::GDALRaster, dsn_2d)
#> GDAL WARNING 1: HTTP response code on https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr/.zarray: 403
#> GDAL WARNING 1: HTTP response code on https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr/crs/.zarray: 403
#> GDAL WARNING 1: HTTP response code on https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr/longitude/.zarray.gmac: 403
#> GDAL WARNING 1: HTTP response code on https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr/latitude/.zarray.gmac: 403
#> GDAL WARNING 1: HTTP response code on https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr/adt/.zarray.aux.xml: 403
#> GDAL WARNING 1: HTTP response code on https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr/adt/.aux: 403
#> GDAL WARNING 1: HTTP response code on https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr/adt/.AUX: 403
#> GDAL WARNING 1: HTTP response code on https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr/adt/.zarray.aux: 403
#> GDAL WARNING 1: HTTP response code on https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr/adt/.zarray.AUX: 403
ds$info()
#> Driver: Zarr/Zarr
#> Files: /vsicurl/https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr/adt/.zarray
#> Size is 2880, 1440
#> Origin = (-180.000000000000000,-90.000000000000000)
#> Pixel Size = (0.125000000000000,0.125000000000000)
#> Metadata:
#>   comment=The absolute dynamic topography is the sea surface height above geoid; the adt is obtained as follows: adt=sla+mdt where mdt is the mean dynamic topography; see the product user manual for details
#>   coordinates=longitude latitude
#>   grid_mapping=crs
#>   long_name=Absolute dynamic topography
#>   standard_name=sea_surface_height_above_geoid
#> Corner Coordinates:
#> Upper Left  (-180.0000000, -90.0000000) 
#> Lower Left  (-180.0000000,  90.0000000) 
#> Upper Right ( 180.0000000, -90.0000000) 
#> Lower Right ( 180.0000000,  90.0000000) 
#> Center      (   0.0000000,   0.0000000) 
#> Band 1 Block=1024x512 Type=Int32, ColorInterp=Undefined
#>   NoData Value=-2147483647
#>   Unit Type: m
#>   Offset: 0,   Scale:0.0001
ds$close()

writeLines(substr(gdalraster::mdim_info(dsn, cout = FALSE), 1, 500))
#> {
#>   "type": "group",
#>   "driver": "Zarr",
#>   "name": "/",
#>   "attributes": {
#>     "Conventions": "CF-1.6",
#>     "Metadata_Conventions": "Unidata Dataset Discovery v1.0",
#>     "cdm_data_type": "Grid",
#>     "comment": "Sea Surface Height measured by Altimetry and derived variables",
#>     "contact": "servicedesk.cmems@mercator-ocean.eu",
#>     "coordinates": "lon_bnds lat_bnds",
#>     "creator_email": "servicedesk.cmems@mercator-ocean.eu",
#>     "creator_name": "CMEMS - Sea Level Thematic Assembly Center",
#>     "


library(vapour)

# List available arrays/variables
sds <- vapour_sds_names(dsn)
gsub(substr(sds[1], 21, 166), "...", sds)
#>  [1] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/adt"      
#>  [2] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/err_sla"  
#>  [3] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/err_ugosa"
#>  [4] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/err_vgosa"
#>  [5] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/flag_ice" 
#>  [6] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/lat_bnds" 
#>  [7] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/lon_bnds" 
#>  [8] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/sla"      
#>  [9] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/ugos"     
#> [10] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/ugosa"    
#> [11] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/vgos"     
#> [12] "ZARR:\"/vsicurl/https...timeChunked.zarr\":/vgosa"


# Get var-specific DSN
sla_dsn <- cmems_gdal_dsn(sla$timeChunked_url[1], array = "sla")

# Read var info
vapour_raster_info(sla_dsn)
#> $geotransform
#> [1] -180.000    0.125    0.000  -90.000    0.000    0.125
#> 
#> $dimension
#> [1] 2880 1440
#> 
#> $dimXY
#> [1] 2880 1440
#> 
#> $minmax
#> NULL
#> 
#> $block
#> [1] 1024  512
#> 
#> $projection
#> NULL
#> 
#> $bands
#> [1] 11809
#> 
#> $projstring
#> NULL
#> 
#> $nodata_value
#> [1] -2147483647
#> 
#> $overviews
#> NULL
#> 
#> $filelist
#> [1] "/vsicurl/https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_MY_008_047/cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D_202411/timeChunked.zarr/sla/.zarray"
#> 
#> $datatype
#> [1] "Int32"
#> 
#> $extent
#> [1] -180  180  -90   90
#> 
#> $subdatasets
#> NULL
#> 
#> $corners
#>            [,1] [,2]
#> upperLeft  -180  -90
#> lowerLeft  -180   90
#> lowerRight  180   90
#> upperRight  180  -90
#> center        0    0

# Read a spatial subset at specific time index (band)
extent <- c(100, 160, -50, 0)  
band <- 1000  # time index
## TBD "vrt://ZARR:\"/vsicurl/https://s3.waw3-1.cloudferro.com/mdl-arco-time-045/arco/SEALEVEL_GLO_PHY_L4_NRT_008_046/cmems_obs-sl_glo_phy-ssh_nrt_allsat-l4-duacs-0.25deg_P1D_202311/timeChunked.zarr\":/sla?bands=1&a_srs=EPSG:4326"

# dat <- gdal_raster_data(
#  sla_dsn, 
#  extent = extent,
#  dimension = c(512, 512),
#  bands = band
# )
```

With terra:

``` r
library(terra)
#> terra 1.8.91

## first band of "adt" var (using Classic syntax for ZARR driver)
dsn_2d <- sprintf("%s:/adt:0", dsn)
r <- rast(dsn_2d)
plot(crop(r, ext(110, 160, -60, -30)), smooth = FALSE)
```

![](README_files/figure-gfm/unnamed-chunk-4-1.png)<!-- -->

For `/vsis3/` access (may be faster in some cases), use the `*_gdals3`
columns with `cmems_setup()`:

``` r
cmems_setup()  # Sets AWS_NO_SIGN_REQUEST=YES, AWS_S3_ENDPOINT=...
dsn_s3 <- sla$timeChunked_gdals3[1]
```

### Direct URL construction

If you already know the product, dataset, and version (e.g. from
`copernicusmarine describe`), skip the catalog:

``` r
dsn <- cmems_arco_dsn(
 product_id = "SEALEVEL_GLO_PHY_L4_NRT_008_046",
 dataset_id = "cmems_obs-sl_glo_phy-ssh_nrt_allsat-l4-duacs-0.25deg_P1D",
 version = "202411",
 chunk_type = "time",
 array = "sla"
)
```

Note: This requires knowing the bucket version suffix (e.g., “045”)
which varies by product family. The catalog approach handles this
automatically.

## Why this works

CMEMS ARCO infrastructure:

    https://s3.waw3-1.cloudferro.com/
     └── mdl-arco-{time|geo}-{NNN}/
           └── arco/
                 └── {PRODUCT_ID}/
                       └── {dataset_id}_{version}/
                             └── {time|geo}Chunked.zarr/
                                   ├── .zmetadata
                                   ├── .zattrs  
                                   └── {variable}/{chunk_indices}

GDAL with `/vsis3/` reads `.zmetadata` to understand the array
structure, then fetches only the chunks needed for your read operation.
No LIST calls, no full downloads.

The STAC catalog at
`https://stac.marine.copernicus.eu/metadata/catalog.stac.json` provides
the authoritative mapping from product/dataset to actual S3 URLs.

## Chunk strategy

Choose your Zarr based on access pattern:

**timeChunked** (chunks: 1 × 720 × 512 in time × lat × lon) - Spatial
slices: maps at one or few time steps - Efficient for: `crop()`,
regional extracts, spatial analysis

**geoChunked** (chunks: 138 × 32 × 64 in time × lat × lon) - Time
series: values at one or few locations over many times - Efficient for:
point extraction, time series analysis

Wrong chunk type = many more HTTP requests = slow.

### Build a catalog

Walk the STAC catalog to get all products, datasets, and their Zarr
URLs:

``` r
library(cmemsarco)

# Get everything (takes a few minutes)
catalog <- cmems_catalog()

# Or specific products
catalog <- cmems_catalog(
  product_ids = c(
    "SEALEVEL_GLO_PHY_L4_NRT_008_046",
    "GLOBAL_ANALYSISFORECAST_PHY_001_024"
  )
)

# Filter to ARCO-only (drops static/native-only datasets)
catalog <- cmems_arco_only(catalog)

catalog
#> # A tibble
#>   product_id                      dataset_id                    version timeChunked_url
#>   <chr>                           <chr>                         <chr>   <chr>
#> 1 SEALEVEL_GLO_PHY_L4_NRT_008_046 cmems_obs-sl_glo_phy-ssh_...  202411  https://s3...
#> ...
```

## Related

- [CopernicusMarine](https://github.com/pepijn-devries/CopernicusMarine) -
  R interface for CMEMS (WMTS, native files, subsetting via their API)
- [copernicusmarine](https://pypi.org/project/copernicusmarine/) -
  Official Python toolbox
- [vapour](https://github.com/hypertidy/vapour) - Lightweight GDAL
- [ZarrDatasets.jl](https://github.com/JuliaGeo/ZarrDatasets.jl) - Julia
  equivalent (where I found clear STAC examples)

## Data source

EU Copernicus Marine Service Information. See individual products for
citation requirements.
