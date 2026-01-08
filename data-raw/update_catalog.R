# Update cached CMEMS catalog
# Run this periodically to refresh data/cmems_catalog_data.rda

library(cmemsarco)

# Build full catalog from STAC (takes a few minutes)
cmems_catalog_data <- cmems_catalog(progress = TRUE)

# Filter to ARCO-only (optional - keeps file smaller)
#cmems_catalog_data <- cmems_arco_only(cmems_catalog_data)

# Save to package data
usethis::use_data(cmems_catalog_data, overwrite = TRUE)

message(sprintf(
  "Catalog updated: %d datasets from %d products",
  nrow(cmems_catalog_data),
  length(unique(cmems_catalog_data$product_id))
))
