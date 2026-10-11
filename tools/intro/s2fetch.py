"""Fetch EOX Sentinel-2 cloudless 2016 (CC BY 4.0) WGS84 tiles for a lon/lat box and mosaic them."""

import sys
import time
import urllib.request
from pathlib import Path

from PIL import Image

lvl = int(sys.argv[1])
lon0, lat0, lon1, lat1 = map(float, sys.argv[2:6])
out = sys.argv[6]
deg = 180.0 / 2**lvl
c0 = int((lon0 + 180) / deg)
c1 = int((lon1 + 180) / deg)
r0 = int((90 - lat1) / deg)
r1 = int((90 - lat0) / deg)
cache = Path("s2/cache")
cache.mkdir(parents=True, exist_ok=True)
W = (c1 - c0 + 1) * 256
H = (r1 - r0 + 1) * 256
img = Image.new("RGB", (W, H))
for r in range(r0, r1 + 1):
    for c in range(c0, c1 + 1):
        f = cache / f"{lvl}_{r}_{c}.jpg"
        if not f.exists():
            u = f"https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless/default/WGS84/{lvl}/{r}/{c}.jpg"
            for k in range(4):
                try:
                    f.write_bytes(urllib.request.urlopen(u, timeout=30).read())
                    break
                except Exception as e:
                    print("retry", u, e)
                    time.sleep(2)
            time.sleep(0.05)
        img.paste(Image.open(f), ((c - c0) * 256, (r - r0) * 256))
# crop to exact box
px = 256 / deg
x0 = (lon0 + 180) / deg * 256 - c0 * 256
x1 = (lon1 + 180) / deg * 256 - c0 * 256
y0 = (90 - lat1) / deg * 256 - r0 * 256
y1 = (90 - lat0) / deg * 256 - r0 * 256
img = img.crop((round(x0), round(y0), round(x1), round(y1)))
img.save(out, quality=95)
print(out, img.size, "px/deg", px)
