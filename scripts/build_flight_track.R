# Parse the flight GPX track, simplify it (9,368 raw trackpoints is far
# more than needed for a smooth web display), and export as GeoJSON.
#
# The GPX has 3 track segments (track_seg_id 0/1/2 -- separate recorded
# legs/stops), and track_seg_point_id resets to 0 at the start of each
# segment. Sorting only by track_seg_point_id (ignoring track_seg_id)
# interleaves all three segments together into a chaotic zigzag across the
# whole country -- found this the hard way: it froze the browser trying to
# render/simplify a "line" whose consecutive points jumped ~70km on
# average. Each segment must be sorted and simplified on its own, and kept
# as a separate line rather than bridged with a fake straight segment.

library(sf)

root <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps"
gpx_path <- "C:/Users/mathe/Downloads/Kajjansi-Mbarara-Entebbe.gpx"
out_dir <- file.path(root, "webmap-vector/data")

pts <- st_read(gpx_path, layer = "track_points", quiet = TRUE)
cat("raw trackpoints:", nrow(pts), " segments:", paste(sort(unique(pts$track_seg_id)), collapse = ", "), "\n")

# Chronologically, segment 0 (08:31-08:59) is first, starting near
# Kajjansi; segment 1 continues on to Mbarara; segment 2 (after a ground
# gap) flies back toward Entebbe. Prepend the true starting point (GPS lock
# was acquired a little into the flight) to the start of segment 0.
start_point <- c(lon = 32.55604247853805, lat = 0.1930323930385642)

lines <- list()
for (seg in sort(unique(pts$track_seg_id))) {
  seg_pts <- pts[pts$track_seg_id == seg, ]
  seg_pts <- seg_pts[order(seg_pts$track_seg_point_id), ]
  coords <- st_coordinates(seg_pts)[, 1:2]
  if (seg == 0) coords <- rbind(start_point, coords)
  if (nrow(coords) < 2) next
  line <- st_sfc(st_linestring(coords), crs = 4326)
  line_utm <- st_transform(st_sf(geometry = line), 32636)
  line_simplified <- st_simplify(line_utm, dTolerance = 100, preserveTopology = FALSE)
  n_before <- nrow(coords)
  n_after <- nrow(st_coordinates(line_simplified))
  cat("segment", seg, ":", n_before, "->", n_after, "points\n")
  lines[[length(lines) + 1]] <- st_transform(line_simplified, 4326)
}

track_sf <- do.call(rbind, lines)
track_sf$segment <- seq_len(nrow(track_sf)) - 1

out_path <- file.path(out_dir, "flight_track.geojson")
if (file.exists(out_path)) file.remove(out_path)
st_write(track_sf, out_path, driver = "GeoJSON", quiet = TRUE)
cat("wrote", out_path, "(", round(file.info(out_path)$size / 1024), "KB )\n")
