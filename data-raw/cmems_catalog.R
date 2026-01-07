library(cmemsarco)

# Get everything (takes a few minutes)
cmems_catalog_data <- build_cmems_catalog()

usethis::use_data(cmems_catalog_data, overwrite = TRUE)
