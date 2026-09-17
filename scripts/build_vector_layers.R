# Build GeoJSON layers for the vector web map: validated hierarchical names
# (derived from the Bioregion III shapefile's own descriptive codes, the
# only one of the 4 that has them -- see derive_names.R), proper
# area-weighted elevation/precipitation stats (see compute_zonal_stats.R),
# a coherent color scheme (one base hue per ecoregion, shaded by
# subdivision so hierarchy reads visually), and Jenks-classified breaks
# for the elevation/precipitation choropleth modes.

library(sf)
library(terra)
library(classInt)
library(grDevices)

sf_use_s2(TRUE)

root <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps"
shp_dir <- "D:/OneDrive - Universität für Bodenkultur Wien/Manuscripts/2026_Amon_Aine_Ecoregions/GIS/Ecoregions_Bioregions/Shapefiles"
out_dir <- file.path(root, "webmap-vector/data")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

source(file.path(root, "scripts/compute_zonal_stats.R"))

## ---- 1. name derivation (validated: BR-III codes + spatial join) ------

br3 <- st_read(file.path(shp_dir, "Bioregions_III_n=21.shp"), quiet = TRUE)
br3_pts <- st_point_on_surface(st_geometry(br3))
br3_area <- as.numeric(st_area(br3))

split_code <- function(code) {
  has_space <- grepl(" ", code, fixed = TRUE)
  prefix <- ifelse(has_space, sub("^(.*)\\s+\\S+$", "\\1", code), "")
  name   <- ifelse(has_space, sub("^.*\\s+(\\S+)$", "\\1", code), code)
  cbind(prefix = prefix, name = name)
}
sp <- split_code(br3$EcoR16)
br3$base_name <- sp[, "name"]
br3$prefix <- sp[, "prefix"]
br3$prefix_br1 <- ifelse(br3$prefix == "", "", sub("^(A[0-9]+).*$", "\\1", br3$prefix))
br3$prefix_br2 <- ifelse(br3$prefix == "", "", sub("^(A[0-9]+B[0-9]+).*$", "\\1", br3$prefix))
br3$name_ecor <- br3$base_name
br3$name_br1  <- ifelse(br3$prefix_br1 == "", br3$base_name, paste(br3$prefix_br1, br3$base_name))
br3$name_br2  <- ifelse(br3$prefix_br2 == "", br3$base_name, paste(br3$prefix_br2, br3$base_name))
br3$name_br3  <- br3$EcoR16

derive_names_for <- function(v, out_col_from_br3, is_ecor_level = FALSE) {
  matches <- st_within(br3_pts, st_geometry(v))
  parent_idx <- sapply(matches, function(m) if (length(m) >= 1) m[1] else NA_integer_)
  v$derived_name <- NA_character_
  for (i in seq_len(nrow(v))) {
    sel <- which(parent_idx == i)
    if (length(sel) == 0) { next }
    codes <- br3[[out_col_from_br3]][sel]
    areas <- br3_area[sel]
    vote <- sort(tapply(areas, codes, sum), decreasing = TRUE)
    winner <- names(vote)[1]
    if (is_ecor_level && winner == "Lake" && length(vote) > 1) {
      # EcoR level has no standalone "Lake" unit -- the paper's own text
      # confirms VKWW subsumes the lake area at this coarsest resolution.
      winner <- names(vote)[names(vote) != "Lake"][1]
    }
    v$derived_name[i] <- winner
  }
  v
}

lakes <- br3[br3$base_name == "Lake", ]
lake_union <- st_union(st_geometry(lakes))  # native UTM, precise; sfc length 1
lake_union_sfg <- lake_union[[1]]

## ---- 2. per-layer build -------------------------------------------------
## Every layer's polygons are clipped against the lake union before area,
## elevation, and precipitation are computed. This matters most for
## Ecoregions: its VKWW polygon geometrically includes Lake Victoria/Kyoga's
## water (merged at that coarsest level, per the paper's own text), which
## was inflating VKWW's area and skewing its elevation/precipitation means.
## "Lake" rows themselves are set to exactly lake_union (not clipped against
## themselves), so every layer's lake geometry is identical and consistent
## with the standalone lakes overlay.

layers <- list(
  ecoregions    = list(shp = "Ecoregions_n=4.shp",     col = "name_ecor", ecor = TRUE),
  bioregion_i   = list(shp = "Bioregions_I_n=8.shp",   col = "name_br1",  ecor = FALSE),
  bioregion_ii  = list(shp = "Bioregions_II_n=12.shp", col = "name_br2",  ecor = FALSE),
  bioregion_iii = list(shp = "Bioregions_III_n=21.shp",col = "name_br3",  ecor = FALSE)
)

climate <- load_climate_rasters(st_bbox(st_transform(br3, 4326)))

all_data <- list()

for (nm in names(layers)) {
  L <- layers[[nm]]
  if (nm == "bioregion_iii") {
    v <- br3
    v$derived_name <- v$name_br3
  } else {
    v <- st_read(file.path(shp_dir, L$shp), quiet = TRUE)
    v <- derive_names_for(v, L$col, is_ecor_level = L$ecor)
  }

  is_lake <- v$derived_name == "Lake"
  geom <- st_make_valid(st_geometry(v))
  if (any(!is_lake)) {
    geom[!is_lake] <- st_difference(geom[!is_lake], lake_union)
  }
  for (i in which(is_lake)) geom[[i]] <- lake_union_sfg
  st_geometry(v) <- geom

  stats <- compute_zonal_stats(v, climate)
  v$area_km2 <- stats$area_km2
  v$elev_mean_m <- stats$elev_mean_m
  v$annual_precip_mm <- stats$annual_precip_mm
  v$base_ecoregion <- sub("^.*\\s+(\\S+)$|^(\\S+)$", "\\1\\2", v$derived_name)

  v_out <- v[, c("derived_name", "base_ecoregion", "area_km2", "elev_mean_m", "annual_precip_mm")]
  all_data[[nm]] <- v_out

  cat(nm, ": ", nrow(v_out), "features, names:\n")
  print(st_drop_geometry(v_out)[, c("derived_name", "base_ecoregion", "area_km2")])
}

## ---- 3. color scheme: sampled from the original published legend -------
## Rather than inventing a palette, use the true fill color of each base
## ecoregion as it appears in the original cartography. Sampled directly
## from output/png/ecoregions_legend.png's swatch bands (clean, unambiguous
## solid-fill rectangles -- see scripts/sample_legend_swatches.R), plus
## Lake from a BR-III sub-polygon sample (the legend's "Lakes" swatch
## wasn't reliably auto-detected, but this geometry-based sample was
## consistent and verified against the map: bright cyan, as expected).
## Geographic point-sampling directly off the map render was tried first
## but proved fragile -- e.g. VKWW's EcoR-level polygon geometrically
## includes Lake Victoria's water (merged at that level, as established
## earlier), so a representative point too easily landed on the lake
## portion instead of VKWW's own land/woodland fill. Subdivisions within an
## ecoregion are shaded from these base colors using colorspace's
## perceptually-uniform sequential ramps, so hierarchy still reads visually.

library(colorspace)

sampled_hex <- c(
  CNP  = "#E8C547",
  SSWL = "#B8985F",
  KDS  = "#C17C74",
  MAR  = "#4A90A4",
  VKWW = "#2D5F3F",
  Lake = "#1DCEF7"
)

cat("\nbase colors (sampled from ecoregions_legend.png / map):\n")
print(sampled_hex)

base_hex <- sampled_hex

# Anchor exactly on the sampled/true color rather than reconstructing it
# from hue alone: reconstructing via sequential_hcl(h=<hue only>, fixed
# c/l) lost fidelity to the original swatch (e.g. CNP's bright gold came
# back noticeably darker/more muted, enough to read as SSWL's tan instead).
# The largest sibling in a family (shade 1, used directly for n=1 -- i.e.
# every Ecoregions-layer feature) now gets the *exact* sampled hex; further
# siblings are progressively lightened tints of that same true color.
make_family_colors <- function(base_name, n) {
  base <- base_hex[[base_name]]
  if (is.null(base)) base <- "#888888"
  if (n == 1) return(base)
  amounts <- seq(0, 0.55, length.out = n)
  sapply(amounts, function(a) if (a == 0) base else colorspace::lighten(base, amount = a))
}

for (nm in names(all_data)) {
  v <- all_data[[nm]]
  df <- st_drop_geometry(v)
  df$color <- NA_character_
  for (base in unique(df$base_ecoregion)) {
    idx <- which(df$base_ecoregion == base)
    # order shades by area descending for a stable, sensible progression
    ord <- idx[order(-df$area_km2[idx])]
    shades <- make_family_colors(base, length(ord))
    for (k in seq_along(ord)) {
      df$color[ord[k]] <- shades[k]
    }
  }
  v$color <- df$color
  all_data[[nm]] <- v
}

## ---- 4. simplify + reproject + write GeoJSON ---------------------------

## Ecoregions has no standalone Lake row (always overridden to a real
## ecoregion name -- see derive_names_for), so its polygons alone now
## undercount the true national total by the lake area, which was just
## clipped out of them. Add it back for a correct denominator.
total_uganda_area <- sum(all_data$ecoregions$area_km2) + as.numeric(st_area(lake_union)) / 1e6
cat("\ntotal Uganda area (km2):", total_uganda_area, "\n")

for (nm in names(all_data)) {
  v <- all_data[[nm]]
  v$pct_of_uganda <- round(100 * v$area_km2 / total_uganda_area, 1)
  all_data[[nm]] <- v

  v_simplified <- st_simplify(v, dTolerance = 250, preserveTopology = TRUE)
  v_ll <- st_transform(v_simplified, 4326)

  out_path <- file.path(out_dir, paste0(nm, ".geojson"))
  if (file.exists(out_path)) file.remove(out_path)
  st_write(v_ll, out_path, driver = "GeoJSON", quiet = TRUE)
  cat(nm, "-> ", out_path, " (", round(file.info(out_path)$size / 1024), "KB )\n")
}

## ---- 4b. standalone lakes overlay --------------------------------------
## The EcoR-level shapefile has no separate lake polygon at all -- it's
## geometrically merged into VKWW (see build note above), so simply naming
## it correctly isn't enough to *show* it distinctly the way the original
## published maps do at every level. Draw the lake geometry (from BR-III,
## the most detailed source) as its own always-on overlay on top of
## whichever classification layer is active, carrying the same stats
## (identical across layers, since every layer's Lake row was set to
## exactly this geometry) so it can be clicked/highlighted like any other
## feature.

lake_stats <- st_drop_geometry(all_data$bioregion_i[all_data$bioregion_i$derived_name == "Lake", ])
lakes_color <- make_family_colors("Lake", 1)
lakes_simplified <- st_simplify(lake_union, dTolerance = 250, preserveTopology = TRUE)
lakes_ll <- st_transform(st_sf(
  geometry = lakes_simplified,
  derived_name = "Lakes",
  base_ecoregion = "Lake",
  area_km2 = lake_stats$area_km2,
  elev_mean_m = lake_stats$elev_mean_m,
  annual_precip_mm = lake_stats$annual_precip_mm,
  pct_of_uganda = lake_stats$pct_of_uganda,
  color = lakes_color
), 4326)
lakes_out <- file.path(out_dir, "lakes.geojson")
if (file.exists(lakes_out)) file.remove(lakes_out)
st_write(lakes_ll, lakes_out, driver = "GeoJSON", quiet = TRUE)
cat("lakes overlay -> ", lakes_out, " (", round(file.info(lakes_out)$size / 1024), "KB )\n")

## ---- 5. Jenks breaks for choropleth modes (pooled across all layers) ---

pool <- do.call(rbind, lapply(all_data, st_drop_geometry))

elev_breaks <- classIntervals(pool$elev_mean_m, n = 6, style = "jenks")$brks
precip_breaks <- classIntervals(pool$annual_precip_mm, n = 6, style = "jenks")$brks

cat("\nelevation Jenks breaks:", paste(round(elev_breaks), collapse = ", "), "\n")
cat("precipitation Jenks breaks:", paste(round(precip_breaks), collapse = ", "), "\n")

breaks_json <- sprintf(
  '{\n  "elevation": {"breaks": [%s], "unit": "m", "label": "Elevation"},\n  "precipitation": {"breaks": [%s], "unit": "mm/yr", "label": "Annual precipitation"}\n}\n',
  paste(round(elev_breaks), collapse = ", "),
  paste(round(precip_breaks), collapse = ", ")
)
writeLines(breaks_json, file.path(out_dir, "breaks.json"))
cat("\nWrote", file.path(out_dir, "breaks.json"), "\n")
