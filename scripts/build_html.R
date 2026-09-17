# Build the standalone web map (webmap/index.html) and its service worker
# (webmap/sw.js) from template.html / sw_template.js, injecting the Leaflet
# library and all layer/legend PNGs as base64 data URIs.
#
# Replaces the earlier Perl build script so the whole pipeline (build_layers.R
# + this file) runs on R alone.
#
# Run from the scripts/ folder: Rscript build_html.R

library(base64enc)

root   <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps"
webmap <- file.path(root, "webmap")
png_dir <- file.path(root, "output/png")

read_text <- function(path) {
  raw <- readBin(path, what = "raw", n = file.info(path)$size)
  rawToChar(raw)
}

img_data_uri <- function(path) {
  base64enc::dataURI(file = path, mime = "image/png")
}

replace_literal <- function(text, pattern, replacement) {
  # fixed=TRUE: pattern and replacement are both treated as literal text,
  # so base64 content ('+', '/', '=') and JS ('$', backslashes, etc.) can't
  # be misinterpreted as regex syntax or backreferences.
  gsub(pattern, replacement, text, fixed = TRUE)
}

## ---- 1. build webmap/index.html -------------------------------------

html <- read_text(file.path(webmap, "template.html"))

replacements <- list(
  "__LEAFLET_CSS__"             = read_text(file.path(webmap, "vendor/leaflet.css")),
  "__LEAFLET_JS__"              = read_text(file.path(webmap, "vendor/leaflet.js")),
  "__IMG_ECOREGIONS__"          = img_data_uri(file.path(png_dir, "ecoregions.png")),
  "__IMG_ECOREGIONS_LEGEND__"   = img_data_uri(file.path(png_dir, "ecoregions_legend.png")),
  "__IMG_BIOREGION_I__"         = img_data_uri(file.path(png_dir, "bioregion_i.png")),
  "__IMG_BIOREGION_I_LEGEND__"  = img_data_uri(file.path(png_dir, "bioregion_i_legend.png")),
  "__IMG_BIOREGION_II__"        = img_data_uri(file.path(png_dir, "bioregion_ii.png")),
  "__IMG_BIOREGION_II_LEGEND__" = img_data_uri(file.path(png_dir, "bioregion_ii_legend.png")),
  "__IMG_BIOREGION_III__"        = img_data_uri(file.path(png_dir, "bioregion_iii.png")),
  "__IMG_BIOREGION_III_LEGEND__" = img_data_uri(file.path(png_dir, "bioregion_iii_legend.png"))
)

for (key in names(replacements)) {
  html <- replace_literal(html, key, replacements[[key]])
}

write_text_binary <- function(text, path) {
  con <- file(path, open = "wb")
  writeChar(text, con, eos = NULL, useBytes = TRUE)
  close(con)
}

out_html <- file.path(webmap, "index.html")
write_text_binary(html, out_html)
cat("Wrote", out_html, "(", format(file.info(out_html)$size, big.mark = ","), "bytes )\n")

## ---- 2. build webmap/sw.js (cache-busted) -----------------------------

sw <- read_text(file.path(webmap, "sw_template.js"))
cache_version <- format(Sys.time(), "%Y%m%d%H%M%S", tz = "UTC")
sw <- replace_literal(sw, "__CACHE_VERSION__", cache_version)

out_sw <- file.path(webmap, "sw.js")
write_text_binary(sw, out_sw)
cat("Wrote", out_sw, "(cache version", cache_version, ")\n")
