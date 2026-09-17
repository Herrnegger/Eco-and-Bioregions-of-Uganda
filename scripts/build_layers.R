# Build the web-map source layers from the rendered map GeoTIFFs:
#   1. Main map image: cropped to Uganda's real extent (drops the
#      legend/globe-inset panel, which sits east of Uganda and would
#      otherwise be geographically draped over Kenya), reprojected to
#      EPSG:4326, exported as PNG for a Leaflet image overlay.
#   2. Legend image: the legend/color-key panel cropped separately (in
#      native pixel space, not geo-referenced) for display as a fixed
#      corner box in the web map, reusing the original validated styling.
#
# Run from the scripts/ folder: Rscript build_layers.R

library(terra)

in_dir  <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps/eco_bioregions_geotiffs"
out_dir <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps/output/png"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

files <- list(
  ecoregions    = "EcoR_17_9_26.tiff",
  bioregion_i   = "Bioregion_I geotiff.tiff",
  bioregion_ii  = "Bioregion_II geotiff.tiff",
  bioregion_iii = "Bioregion_III geotiff.tiff"
)

# Uganda's real bounding box + small buffer, in EPSG:4326 (degrees).
crop_bbox_ll <- c(xmin = 29.3, xmax = 35.05, ymin = -1.7, ymax = 4.6)

# per-file legend crop parameters, hand-tuned by visual inspection:
#   title_buffer_m: how far left of Uganda's edge (in metres, native UTM) the
#                   legend crop starts, so the panel title isn't clipped
#   col_frac, row_frac: fraction of the legend-panel crop to keep (drops the
#                   globe inset / duplicate reference legend / excess margin)
legend_params <- list(
  ecoregions    = list(title_buffer_m = 10000, col_frac = 1.00, row_frac = 0.62),
  bioregion_i   = list(title_buffer_m = 10000, col_frac = 0.48, row_frac = 0.55),
  bioregion_ii  = list(title_buffer_m = 10000, col_frac = 0.30, row_frac = 0.78),
  bioregion_iii = list(title_buffer_m = 10000, col_frac = 0.53, row_frac = 0.735)
)

bounds <- list()

for (nm in names(files)) {
  f <- file.path(in_dir, files[[nm]])
  r <- rast(f)
  cat("===", nm, "=== original dims:", ncol(r), "x", nrow(r), "\n")

  uganda_vec_ll  <- vect(ext(crop_bbox_ll["xmin"], crop_bbox_ll["xmax"],
                              crop_bbox_ll["ymin"], crop_bbox_ll["ymax"]),
                          crs = "EPSG:4326")
  uganda_vec_utm <- project(uganda_vec_ll, crs(r))
  uganda_ext_utm <- ext(uganda_vec_utm)

  ## 1. main map layer: crop to Uganda extent, reproject, export
  r_crop <- crop(r, uganda_ext_utm)
  r_ll   <- project(r_crop, "EPSG:4326", method = "near")
  e <- ext(r_ll)
  bounds[[nm]] <- c(xmin = unname(e$xmin), xmax = unname(e$xmax),
                     ymin = unname(e$ymin), ymax = unname(e$ymax))

  out_png <- file.path(out_dir, paste0(nm, ".png"))
  writeRaster(r_ll, out_png, overwrite = TRUE, datatype = "INT1U", NAflag = 0)
  cat("  map layer ->", out_png, "\n")

  ## 2. legend panel: crop the region east of Uganda, in native UTM pixels
  lp <- legend_params[[nm]]
  full_ext <- ext(r)
  legend_ext <- ext(uganda_ext_utm$xmax - lp$title_buffer_m, full_ext$xmax,
                     full_ext$ymin, full_ext$ymax)
  r_legend <- crop(r, legend_ext)

  col_end <- round(ncol(r_legend) * lp$col_frac)
  row_end <- round(nrow(r_legend) * lp$row_frac)
  r_legend_trim <- r_legend[1:row_end, 1:col_end, drop = FALSE]

  out_legend_png <- file.path(out_dir, paste0(nm, "_legend.png"))
  writeRaster(r_legend_trim, out_legend_png, overwrite = TRUE, datatype = "INT1U")
  cat("  legend panel ->", out_legend_png, "(", ncol(r_legend_trim), "x", nrow(r_legend_trim), ")\n\n")
}

cat("\n--- Leaflet bounds  [[south, west], [north, east]] ---\n")
for (nm in names(bounds)) {
  b <- bounds[[nm]]
  cat(sprintf('%s: [[%.6f, %.6f], [%.6f, %.6f]]\n', nm, b["ymin"], b["xmin"], b["ymax"], b["xmax"]))
}
