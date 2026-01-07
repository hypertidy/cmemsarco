library(cmemsarco)

# Get everything (takes a few minutes)
catalog <- build_cmems_catalog()

usethis::use_data(cmems_catalog, overwrite = TRUE)
