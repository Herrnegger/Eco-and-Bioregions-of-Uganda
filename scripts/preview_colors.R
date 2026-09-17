library(jsonlite)
library(png)

root <- "D:/OneDrive - Universität für Bodenkultur Wien/github/Ecoregions_Uganda_maps"
data_dir <- file.path(root, "webmap-vector/data")

layers <- c("ecoregions", "bioregion_i", "bioregion_ii", "bioregion_iii")

rows <- list()
for (nm in layers) {
  x <- fromJSON(file.path(data_dir, paste0(nm, ".geojson")), simplifyVector = FALSE)
  nz <- function(x) if (is.null(x)) NA_character_ else x
  for (f in x[["features"]]) {
    p <- f[["properties"]]
    rows[[length(rows) + 1]] <- data.frame(layer = nm, name = nz(p$derived_name), base = nz(p$base_ecoregion), color = nz(p$color), stringsAsFactors = FALSE)
  }
}
df <- do.call(rbind, rows)
df <- df[!duplicated(df$name), ]
df <- df[order(df$layer, df$base, df$name), ]

n <- nrow(df)
row_h <- 24
png_path <- file.path(root, "scripts/color_preview.png")
png(png_path, width = 500, height = n * row_h + 20, res = 96)
par(mar = c(0, 0, 0, 0))
plot(0, 0, type = "n", xlim = c(0, 500), ylim = c(0, n * row_h), xaxt = "n", yaxt = "n", bty = "n", xlab = "", ylab = "")
for (i in seq_len(n)) {
  y <- n * row_h - i * row_h
  rect(5, y, 30, y + row_h - 4, col = df$color[i], border = "gray30")
  text(38, y + (row_h - 4) / 2, paste0(df$layer[i], ": ", df$name[i]), adj = c(0, 0.5), cex = 0.75)
}
dev.off()
cat("wrote", png_path, "\n")
