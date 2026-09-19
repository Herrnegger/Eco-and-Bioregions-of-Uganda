import os
import json
from datetime import datetime
from PIL import Image, ImageOps
from PIL.ExifTags import TAGS, GPSTAGS

ROOT = r"D:\OneDrive - Universität für Bodenkultur Wien\github\Ecoregions_Uganda_maps"
RAW_DIR = os.path.join(ROOT, "data_external", "flight_photos", "raw")
OUT_DIR = os.path.join(ROOT, "webmap-vector", "photos")
MAX_DIM = 1400
JPEG_QUALITY = 78

os.makedirs(OUT_DIR, exist_ok=True)

def get_gps(exif):
    try:
        ifd = exif.get_ifd(0x8825)
    except Exception:
        ifd = {}
    return {GPSTAGS.get(k, k): v for k, v in ifd.items()}

def dms_to_dd(dms, ref):
    d, m, s = [float(x) for x in dms]
    dd = d + m / 60 + s / 3600
    if ref in ("S", "W"):
        dd = -dd
    return dd

def get_datetime(exif):
    # 36867 = DateTimeOriginal, 306 = DateTime
    raw = exif.get(36867) or exif.get(306)
    if not raw:
        return None
    try:
        return datetime.strptime(raw, "%Y:%m:%d %H:%M:%S")
    except Exception:
        return None

sources = [
    ("gabriel", os.path.join(RAW_DIR, "gabriel"), "Gabriel Stecher"),
    ("mathew", os.path.join(RAW_DIR, "mathew"), "Mathew Herrnegger"),
]

records = []
for tag, d, author in sources:
    files = []
    for dirpath, dirnames, filenames in os.walk(d):
        for fn in filenames:
            if fn.lower().endswith((".jpg", ".jpeg")):
                files.append(os.path.join(dirpath, fn))
    for path in files:
        img = Image.open(path)
        exif = img.getexif()
        gps = get_gps(exif)
        if "GPSLatitude" not in gps or "GPSLongitude" not in gps:
            print(f"SKIP (no GPS): {path}")
            continue
        lat = dms_to_dd(gps["GPSLatitude"], gps.get("GPSLatitudeRef", "N"))
        lon = dms_to_dd(gps["GPSLongitude"], gps.get("GPSLongitudeRef", "E"))
        dt = get_datetime(exif)

        img = ImageOps.exif_transpose(img)  # apply EXIF rotation, then it's baked into pixels
        img = img.convert("RGB")
        w, h = img.size
        scale = MAX_DIM / max(w, h)
        if scale < 1:
            img = img.resize((round(w * scale), round(h * scale)), Image.LANCZOS)

        records.append({
            "path": path, "lat": lat, "lon": lon,
            "dt": dt, "author": author, "img": img,
        })

records.sort(key=lambda r: r["dt"] or datetime.min)

manifest = []
for i, r in enumerate(records, start=1):
    out_name = f"photo_{i:03d}.jpg"
    out_path = os.path.join(OUT_DIR, out_name)
    r["img"].save(out_path, "JPEG", quality=JPEG_QUALITY, optimize=True)
    manifest.append({
        "file": out_name,
        "lat": round(r["lat"], 6),
        "lon": round(r["lon"], 6),
        "time": r["dt"].strftime("%Y-%m-%dT%H:%M:%SZ") if r["dt"] else None,
        "author": r["author"],
    })
    print(f"{out_name} <- {os.path.basename(r['path'])}  ({r['lat']:.5f},{r['lon']:.5f})  {os.path.getsize(out_path)//1024}KB")

manifest_path = os.path.join(ROOT, "webmap-vector", "data", "photos.json")
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=1)

total_kb = sum(os.path.getsize(os.path.join(OUT_DIR, m["file"])) for m in manifest) // 1024
print(f"\n{len(manifest)} photos written to {OUT_DIR} ({total_kb} KB total)")
print(f"manifest -> {manifest_path}")
