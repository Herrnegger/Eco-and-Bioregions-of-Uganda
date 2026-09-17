# Generate simple PWA app icons (192x192, 512x512) by cropping a square
# from the ecoregions map and nearest-neighbor resizing (no magick needed).

library(png)

root <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps"
src_path <- file.path(root, "output/png/ecoregions.png")
out_dir <- file.path(root, "webmap/icons")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

img <- readPNG(src_path)  # H x W x 4, values 0..1
h <- dim(img)[1]; w <- dim(img)[2]

# square crop centered horizontally, biased toward the upper-middle (Uganda
# body, not the southern lake strip) so the icon reads clearly at small size
side <- min(h, w)
row_start <- max(1, round(h * 0.05))
row_end <- min(h, row_start + side - 1)
col_start <- max(1, round((w - side) / 2))
col_end <- col_start + side - 1

crop <- img[row_start:row_end, col_start:col_end, ]

resize_nn <- function(arr, out_size) {
  n <- dim(arr)[1]
  idx <- round(seq(1, n, length.out = out_size))
  arr[idx, idx, ]
}

# flatten alpha onto a white background (PWA icons shouldn't rely on
# transparency being handled well everywhere)
flatten_white <- function(arr) {
  alpha <- arr[, , 4]
  out <- arr[, , 1:3]
  for (b in 1:3) {
    out[, , b] <- arr[, , b] * alpha + 1 * (1 - alpha)
  }
  out
}

for (size in c(512, 192)) {
  resized <- resize_nn(crop, size)
  flat <- flatten_white(resized)
  out_path <- file.path(out_dir, paste0("icon-", size, ".png"))
  writePNG(flat, out_path)
  cat("wrote", out_path, "\n")
}
