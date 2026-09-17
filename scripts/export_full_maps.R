# Export each source GeoTIFF as a plain PNG, unmodified (no crop, no
# reprojection) -- i.e. including the legend/globe-inset panel that the web
# map deliberately excludes. For use as static images in the README, where
# there's no geographic-overlay concern and the legend is a plus.

library(terra)

in_dir  <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps/eco_bioregions_geotiffs"
out_dir <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps/output/png"

files <- list(
  ecoregions    = "EcoR_17_9_26.tiff",
  bioregion_i   = "Bioregion_I geotiff.tiff",
  bioregion_ii  = "Bioregion_II geotiff.tiff",
  bioregion_iii = "Bioregion_III geotiff.tiff"
)

for (nm in names(files)) {
  f <- file.path(in_dir, files[[nm]])
  r <- rast(f)
  out_png <- file.path(out_dir, paste0(nm, "_full.png"))
  writeRaster(r, out_png, overwrite = TRUE, datatype = "INT1U")
  cat(nm, "->", out_png, " (", ncol(r), "x", nrow(r), ")\n")
}
