# Zonal-statistics helper: proper, area-weighted mean elevation and annual
# precipitation for arbitrary polygons, from clean public WorldClim source
# rasters -- NOT from the shapefiles' own attribute table, which we
# confirmed holds leftover single-basin values from a GIS dissolve rather
# than true regional aggregates.
#
# Sourced by build_vector_layers.R, which computes stats on lake-clipped
# geometry (VKWW's polygons otherwise include Lake Victoria/Kyoga's water,
# inflating its area and skewing its elevation/precipitation means).
# Can also be run standalone: prints stats for the four raw shapefiles.

library(terra)
library(sf)

wc_dir <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps/data_external/worldclim"

load_climate_rasters <- function(bbox_ll, buffer_deg = 0.3) {
  uganda_ext <- ext(
    bbox_ll["xmin"] - buffer_deg, bbox_ll["xmax"] + buffer_deg,
    bbox_ll["ymin"] - buffer_deg, bbox_ll["ymax"] + buffer_deg
  )
  elev <- crop(rast(file.path(wc_dir, "elev/wc2.1_2.5m_elev.tif")), uganda_ext)
  prec_files <- sprintf(file.path(wc_dir, "prec/wc2.1_2.5m_prec_%02d.tif"), 1:12)
  prec_annual <- sum(crop(rast(prec_files), uganda_ext))
  names(elev) <- "elev_m"
  names(prec_annual) <- "annual_precip_mm"
  list(elev = elev, precip = prec_annual)
}

# v: sf polygons (any CRS). Returns a data.frame with area_km2 (from the
# geometry as given -- clip before calling this if lake area should be
# excluded), elev_mean_m, annual_precip_mm, one row per feature.
compute_zonal_stats <- function(v, climate) {
  v_ll <- st_transform(v, 4326)
  v_terra <- vect(v_ll)
  area_km2 <- as.numeric(st_area(v)) / 1e6
  elev_mean <- extract(climate$elev, v_terra, fun = mean, weights = TRUE, na.rm = TRUE)[, 2]
  precip_mean <- extract(climate$precip, v_terra, fun = mean, weights = TRUE, na.rm = TRUE)[, 2]
  data.frame(
    area_km2 = round(area_km2, 1),
    elev_mean_m = round(elev_mean, 0),
    annual_precip_mm = round(precip_mean, 0)
  )
}

## Standalone mode: only runs when this script is executed directly (not
## when source()'d), prints stats for the raw, unclipped shapefiles.
if (sys.nframe() == 0) {
  shp_dir <- "D:/OneDrive - Universität für Bodenkultur Wien/Manuscripts/2026_Amon_Aine_Ecoregions/GIS/Ecoregions_Bioregions/Shapefiles"
  shapefiles <- list(
    ecoregions    = "Ecoregions_n=4.shp",
    bioregion_i   = "Bioregions_I_n=8.shp",
    bioregion_ii  = "Bioregions_II_n=12.shp",
    bioregion_iii = "Bioregions_III_n=21.shp"
  )
  ecor <- st_read(file.path(shp_dir, "Ecoregions_n=4.shp"), quiet = TRUE)
  climate <- load_climate_rasters(st_bbox(st_transform(ecor, 4326)))
  for (nm in names(shapefiles)) {
    v <- st_read(file.path(shp_dir, shapefiles[[nm]]), quiet = TRUE)
    cat("\n===", nm, "(unclipped) ===\n")
    print(compute_zonal_stats(v, climate))
  }
}
