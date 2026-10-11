"""Step 1 of the intro asset bake (run with the geo venv, needs rasterio):
mosaic Copernicus GLO-30 tiles round Lake Turkana into the rift patch box and save float32 metres (.npy).

~/MWM/data/tools/geo-venv/bin/python tools/intro/bake_dem.py <src_dir> <out.npy>
"""

import sys
from pathlib import Path

import numpy as np
import rasterio
from scipy import ndimage

# keep in sync with bake_intro_assets.py PATCH
LON0, LAT0, LON1, LAT1 = 34.4, 2.5, 37.0, 5.1
N = 2048


def main(src: Path, out: Path) -> None:
    tiles = {}
    for f in sorted((src / "dem").glob("Copernicus_DSM_COG_10_*_DEM.tif")):
        with rasterio.open(f) as r:
            b = r.bounds
            tiles[(round(b.left), round(b.bottom))] = (r.read(1).astype(np.float32), r.transform)
    # 3600 rows per degree; columns 3600 below 50 deg latitude
    lats = range(int(np.floor(LAT0)), int(np.ceil(LAT1)))
    lons = range(int(np.floor(LON0)), int(np.ceil(LON1)))
    rows = []
    for la in reversed(list(lats)):
        rows.append(np.concatenate([tiles[(lo, la)][0][:3600, :3600] for lo in lons], axis=1))
    mos = np.concatenate(rows, axis=0)
    lon_a, lat_top = lons[0], lats[-1] + 1
    # sample grid (pixel centres) in the patch box
    xs = (np.linspace(LON0, LON1, N) - lon_a) * 3600.0
    ys = (lat_top - np.linspace(LAT1, LAT0, N)) * 3600.0
    gy, gx = np.meshgrid(ys, xs, indexing="ij")
    smooth = ndimage.gaussian_filter(mos, 1.2)
    h = ndimage.map_coordinates(smooth, [gy, gx], order=1)
    np.save(out, h.astype(np.float32))
    print(out, h.shape, float(h.min()), float(h.max()))


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
