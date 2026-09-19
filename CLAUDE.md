# Project: Eco- and Bioregions of Uganda

Interactive web maps of the classification published in Aine et al. (2026),
IJAEOG 148, 105221. GitHub repo `Herrnegger/Eco-and-Bioregions-of-Uganda`,
GitHub Pages serves from `main` root. Two parallel maps:

- **`webmap-vector/`** — primary, published map. Real Leaflet vector
  polygons, click-for-stats popups, categorical/elevation/precipitation
  display modes. Live at `/webmap-vector/`.
- **`webmap/`** — lighter image-based alternative (static PNG overlays).
  Live at `/webmap/`.

Both are installable PWAs (manifest + service worker). `webmap/` is fully
self-contained (base64 images inlined). `webmap-vector/` inlines the
classification GeoJSON but serves flight photos as separate static files
under `webmap-vector/photos/` (80 photos, ~20MB — too much to inline;
service worker caches them opportunistically as viewed, not on install).
`webmap-vector/` also has a flight-track overlay (`data/flight_track.geojson`)
and photo markers (`data/photos.json`), independently toggleable.

## External data (not in repo, hardcoded absolute paths in scripts)

- Shapefiles: `D:/OneDrive - Universität für Bodenkultur Wien/Manuscripts/2026_Amon_Aine_Ecoregions/GIS/Ecoregions_Bioregions/Shapefiles/` — `Ecoregions_n=4.shp` (5 features), `Bioregions_I_n=8.shp` (9), `Bioregions_II_n=12.shp` (13), `Bioregions_III_n=21.shp` (21). CRS UTM 36N.
- Source GeoTIFFs (rendered map images, legend baked in): `eco_bioregions_geotiffs/` in this repo.
- WorldClim elevation/precipitation: downloaded to `data_external/worldclim/` (gitignored, re-download via `compute_zonal_stats.R`'s URLs, 2.5m resolution, ~90MB).

## Key gotchas found the hard way

1. **Shapefile attribute table is NOT trustworthy.** `Area`, `Elev_mean`,
   `Annppt_Tot` etc. are leftover values from a single representative
   micro-basin surviving a GIS dissolve — not true regional aggregates.
   Proof: `Elev_mean` for one EcoR row was exactly 614.4masl, matching the
   paper's quoted *lowest point* for CNP, not a mean. Always compute area
   from geometry (`st_area`) and elevation/precip via fresh area-weighted
   zonal stats (`compute_zonal_stats.R`), never from the shapefile columns.

2. **Only Bioregion III has reliable descriptive names** (field `EcoR16`,
   e.g. `"A1B1C2 CNP"`, `"Lake"`). The other 3 shapefiles only have generic
   `"EcoR1".."EcoR5"` codes. Names for EcoR/BR-I/BR-II are derived by
   spatial-joining BR-III's `point_on_surface` against each coarser
   polygon and taking the area-weighted majority vote (see
   `derive_names_for()` in `build_vector_layers.R`). Validated 3 ways:
   spatial join, computed area vs. paper's published areas, and
   elevation/precip matching the paper's ecological descriptions.

3. **Ecoregions level has no standalone Lake polygon** — it's
   geometrically merged into VKWW (the paper's own text confirms VKWW
   "includes all Lake Victoria islands"). `derive_names_for(..., is_ecor_level=TRUE)`
   overrides a "Lake" majority-vote winner to the runner-up real name.

4. **Every layer's polygons are clipped against a unified lake geometry**
   (from BR-III's Lake rows) before computing area/elevation/precip —
   otherwise VKWW's stats include Lake Victoria's water, inflating area
   ~3x. `lake_union` computed once, subtracted via `st_difference()` from
   every non-Lake row; Lake rows get `lake_union` assigned directly so all
   layers show byte-identical lake geometry/stats.

5. **PNG read via `terra::rast()` has no row-orientation metadata.**
   Assigning `ext()` after reading puts row 1 at y=0 (south), silently
   flipping north/south. Always `flip(r, direction="vertical")` after
   setting the extent on a plain PNG. Verified empirically (Lake Victoria's
   true color only appeared at its real coordinates after flipping).

6. **Categorical map colors are sampled from the original legend PNG**
   (`output/png/ecoregions_legend.png` swatches), not invented — see
   `sample_legend_swatches.R`. For subdivision shading, anchor the
   **exact** sampled hex as the darkest/primary shade; reconstructing a
   color from hue-alone via `sequential_hcl(h=hue, fixed c/l)` loses
   fidelity (CNP's gold came back muted enough to look like SSWL's tan).

7. **`Rscript -e '...'` via Bash segfaults intermittently** (path has
   non-ASCII `ü`). Always write an R script file and run
   `Rscript file.R` instead of inline `-e`.

8. **`L.geoJSON()`/`L.layerGroup()` return a `FeatureGroup`, which has no
   `bringToFront()`** — and neither does `L.marker()` (only `L.Path` and
   its subclasses — Polyline, Polygon, Circle — have it). Calling it on a
   group or a marker throws a `TypeError` that silently kills the rest of
   whatever function it's in, including code registered *later* in the
   script (this broke the legend, locate button, and info button all at
   once — the crash was inside `loadLayer()`, called before those were set
   up). Use `group.eachLayer(l => l.bringToFront())` for Path-based groups
   only; markers render above vector fills by default and need nothing.
   Avoid reordering z-index on every hover — only do it once on layer load.

9. **GPX files can have multiple track segments** (`track_seg_id`), and
   the point-index field (`track_seg_point_id`) resets to 0 at the start
   of each one. Sorting only by point-index without also sorting by
   segment interleaves all segments into a chaotic zigzag (consecutive
   "points" jumping ~70km) — this passed `st_simplify()` without error but
   froze the browser trying to render/simplify it. Always
   `order(track_seg_id, track_seg_point_id)`, and keep segments as
   separate line features rather than bridging them with a straight line.

10. **Debugging a built page without a live browser**: headless Chrome
    prints console errors (including uncaught exceptions) to stderr with
    `--enable-logging=stderr --v=1`:
    `chrome.exe --headless=new --disable-gpu --enable-logging=stderr --v=1
    --virtual-time-budget=8000 --dump-dom "file:///<path>" > dom.html
    2> console.log`, then grep console.log for `Uncaught`/`CONSOLE`. Found
    the marker `bringToFront()` bug this way in seconds instead of
    guessing from symptoms.

11. **Photo EXIF (GPS + orientation) via Python/Pillow**, no exiftool
    needed: GPS lives in a sub-IFD, not a flat tag —
    `exif.get_ifd(0x8825)`, not `exif.get(34853)` (that returns an int
    offset, not a dict). Auto-rotate with
    `ImageOps.exif_transpose(img)` *before* resizing (bakes the EXIF
    Orientation tag into pixels; iPhone/Pixel photos are stored
    unrotated with just an orientation flag).

12. **Git push works via cached Git Credential Manager** (account
    `Herrnegger`) — no `gh` CLI installed. To call GitHub's API directly
    (e.g. enabling Pages), extract a token with
    `git credential fill <<< $'protocol=https\nhost=github.com\n'` and use
    it in a `curl -H "Authorization: token $TOKEN"` call. Never print the
    token to chat.

## Build commands

```r
# Vector map (primary):
Rscript scripts/build_vector_layers.R   # names, stats, lake clip, colors -> webmap-vector/data/*.geojson
Rscript scripts/build_flight_track.R    # GPX -> webmap-vector/data/flight_track.geojson (optional overlay)
Rscript scripts/build_vector_html.R     # inject into webmap-vector/index.html + sw.js

# Image map (lighter alternative):
Rscript scripts/build_layers.R          # crop/reproject GeoTIFFs + legend panels -> output/png/
Rscript scripts/build_html.R            # inject into webmap/index.html + sw.js
```

```
# Flight photos (optional overlay): extracts GPS+time via EXIF, auto-rotates,
# resizes to 1400px, writes webmap-vector/photos/*.jpg + data/photos.json
python scripts/process_flight_photos.py
```

R packages needed: `terra`, `sf`, `classInt`, `colorspace`, `png`, `base64enc`.
Python: `Pillow`.
