# Build webmap-vector/index.html from template.html, injecting Leaflet and
# the 4 GeoJSON layers + classification breaks directly as JS data (so the
# page is self-contained like the raster version, and works whether opened
# as a local file or hosted).

root <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps"
webmap <- file.path(root, "webmap-vector")
data_dir <- file.path(webmap, "data")

read_text <- function(path) {
  raw <- readBin(path, what = "raw", n = file.info(path)$size)
  rawToChar(raw)
}
write_text_binary <- function(text, path) {
  con <- file(path, open = "wb")
  writeChar(text, con, eos = NULL, useBytes = TRUE)
  close(con)
}
replace_literal <- function(text, pattern, replacement) {
  gsub(pattern, replacement, text, fixed = TRUE)
}

html <- read_text(file.path(webmap, "template.html"))

replacements <- list(
  "__LEAFLET_CSS__"            = read_text(file.path(webmap, "vendor/leaflet.css")),
  "__LEAFLET_JS__"             = read_text(file.path(webmap, "vendor/leaflet.js")),
  "__GEOJSON_ECOREGIONS__"     = read_text(file.path(data_dir, "ecoregions.geojson")),
  "__GEOJSON_BIOREGION_I__"    = read_text(file.path(data_dir, "bioregion_i.geojson")),
  "__GEOJSON_BIOREGION_II__"   = read_text(file.path(data_dir, "bioregion_ii.geojson")),
  "__GEOJSON_BIOREGION_III__"  = read_text(file.path(data_dir, "bioregion_iii.geojson")),
  "__GEOJSON_LAKES__"          = read_text(file.path(data_dir, "lakes.geojson")),
  "__GEOJSON_FLIGHT_TRACK__"   = read_text(file.path(data_dir, "flight_track.geojson")),
  "__PHOTOS_JSON__"            = read_text(file.path(data_dir, "photos.json")),
  "__BREAKS_JSON__"            = read_text(file.path(data_dir, "breaks.json"))
)

for (key in names(replacements)) {
  html <- replace_literal(html, key, replacements[[key]])
}

out_html <- file.path(webmap, "index.html")
write_text_binary(html, out_html)
cat("Wrote", out_html, "(", format(file.info(out_html)$size, big.mark = ","), "bytes )\n")

## service worker (cache-busted so every rebuild invalidates old caches)
sw <- read_text(file.path(webmap, "sw_template.js"))
cache_version <- format(Sys.time(), "%Y%m%d%H%M%S", tz = "UTC")
sw <- replace_literal(sw, "__CACHE_VERSION__", cache_version)
out_sw <- file.path(webmap, "sw.js")
write_text_binary(sw, out_sw)
cat("Wrote", out_sw, "(cache version", cache_version, ")\n")
