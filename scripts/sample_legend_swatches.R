library(png)

path <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps/output/png/ecoregions_legend.png"
img <- readPNG(path)  # H x W x (3 or 4), 0..1
h <- dim(img)[1]; w <- dim(img)[2]
cat("dims:", w, "x", h, "\n")

# scan a handful of x columns inside the swatch strip and, for each row,
# use the median color across them (robust to being slightly off-center)
xs <- round(seq(0.06, 0.14, length.out = 6) * w)
cat("sampling columns:", xs, "\n")

row_col <- function(y) {
  px <- sapply(xs, function(x) img[y, x, 1:3])
  apply(px, 1, median)
}

is_bg <- function(rgb) {
  # near-white, near-black, or near-gray (low saturation) -> not a swatch
  mx <- max(rgb); mn <- min(rgb)
  (mx > 0.94) || (mx < 0.15) || ((mx - mn) < 0.06)
}

rows <- lapply(seq_len(h), row_col)
bg <- sapply(rows, is_bg)

# find contiguous non-background runs
runs <- rle(bg)
starts <- cumsum(c(1, head(runs$lengths, -1)))
swatches <- list()
for (i in seq_along(runs$lengths)) {
  if (!runs$values[i] && runs$lengths[i] >= 5) {  # a real swatch band, not noise
    y0 <- starts[i]; y1 <- y0 + runs$lengths[i] - 1
    mid <- rows[[round((y0 + y1) / 2)]]
    swatches[[length(swatches) + 1]] <- list(y0 = y0, y1 = y1, rgb = mid)
  }
}

cat("\nfound", length(swatches), "swatch bands:\n")
for (s in swatches) {
  hexcol <- rgb(s$rgb[1], s$rgb[2], s$rgb[3])
  cat(sprintf("  y=%d-%d  %s\n", s$y0, s$y1, hexcol))
}
