import os
from PIL import Image
from PIL.ExifTags import TAGS, GPSTAGS

root = r"D:\OneDrive - Universität für Bodenkultur Wien\github\Ecoregions_Uganda_maps\data_external\flight_photos\raw"

def get_gps(exif):
    gps_info = {}
    try:
        ifd = exif.get_ifd(0x8825)  # GPSInfo IFD
    except Exception:
        ifd = {}
    for key, val in ifd.items():
        name = GPSTAGS.get(key, key)
        gps_info[name] = val
    return gps_info

def dms_to_dd(dms, ref):
    d, m, s = [float(x) for x in dms]
    dd = d + m / 60 + s / 3600
    if ref in ("S", "W"):
        dd = -dd
    return dd

count_total = 0
count_gps = 0
for sub in ["gabriel", "mathew"]:
    d = os.path.join(root, sub)
    files = []
    for dirpath, dirnames, filenames in os.walk(d):
        for fn in filenames:
            if fn.lower().endswith((".jpg", ".jpeg")):
                files.append(os.path.join(dirpath, fn))
    for path in sorted(files):
        f = os.path.basename(path)
        count_total += 1
        try:
            img = Image.open(path)
            exif = img.getexif()
            gps = get_gps(exif)
            if "GPSLatitude" in gps and "GPSLongitude" in gps:
                lat = dms_to_dd(gps["GPSLatitude"], gps.get("GPSLatitudeRef", "N"))
                lon = dms_to_dd(gps["GPSLongitude"], gps.get("GPSLongitudeRef", "E"))
                count_gps += 1
                print(f"{sub}/{f}: lat={lat:.5f} lon={lon:.5f} size={img.size}")
            else:
                print(f"{sub}/{f}: NO GPS  size={img.size}")
        except Exception as e:
            print(f"{sub}/{f}: ERROR {e}")

print(f"\n{count_gps}/{count_total} photos have GPS")
