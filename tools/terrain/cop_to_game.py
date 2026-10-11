"""Copernicus GLO-30 crop of the West Turkana shore -> Age of Earth "Rift Lake" map (512 x 512 m at 1:10).

Data: Copernicus WorldDEM-30 (GLO-30), see assets/_raw/dem/cop30/SOURCE.md for licence + required notices.
Adapted from mwm-wayfarer tools/terrain/cop_to_game.py (transverse Mercator frame, bicubic resample).

Run: ~/MWM/data/tools/geo-venv/bin/python tools/terrain/cop_to_game.py [turkana]

Writes assets/terrain/rift_lake/:
  height.png       16-bit grey, 1025 x 1025, row 0 = north, col 0 = west. Game height (m) =
                   h_min + v/65535 * (h_max - h_min), from meta.json. Already at 1:10 (real metres / 10).
  splat_a.png      RGBA8 weights: R dry grass, G red soil, B volcanic rock, A shore sand
  splat_b.png      RGBA8 weights: R wet mud, G cobble bed (dry channel floors), B cracked mud flat, A unused (0)
                   splat_a + splat_b sum to 255 per texel.
  water.png        8-bit: water depth 0..1 (1 = 4 m game depth or deeper), 0 on land
  shore.png        8-bit: distance to the waterline, 0 at the line, 255 = 40 m game or more (foam, wet band)
  veg.png          RGBA8 placement density: R acacia woodland, G doum palm, B grass tufts, A reeds
  meta.json        frame, scale, heights, lake level, licence line
"""

import json
import sys
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image
from pyproj import Transformer
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
COP = ROOT / "assets" / "_raw" / "dem" / "cop30"
OUT = ROOT / "assets" / "terrain" / "rift_lake"

PRESETS = {
    # Centre on the West Turkana shore east of Lomekwi (LOM3 at 3.874 N 35.751 E, ~10 km west of this box).
    # Box chosen for ~30 % lake and the most land relief along this shore (see SOURCE.md).
    "turkana": dict(
        tile="N03_00_E035_00",
        lon=35.845,
        lat=3.880,
        real_size=5120.0,
        scale=10.0,
        n=1025,
        lake_level=362.4,
    ),
}
SEED = 7


def tm_grid(p):
    tm = Transformer.from_crs(
        f"+proj=tmerc +lat_0={p['lat']} +lon_0={p['lon']} +k=1 +x_0=0 +y_0=0 +ellps=WGS84",
        "EPSG:4326",
        always_xy=True,
    )
    half = p["real_size"] / 2
    xs = np.linspace(-half, half, p["n"])
    ys = np.linspace(half, -half, p["n"])  # row 0 = north
    gx, gy = np.meshgrid(xs, ys)
    return tm.transform(gx, gy)


def fill_pits(h):
    """Priority-flood depression filling (Barnes 2014) so D8 flow reaches the lake instead of dying in DSM pits."""
    import heapq

    n = h.shape[0]
    out = h.copy()
    seen = np.zeros(h.shape, bool)
    heap = []
    for r in range(n):
        for c in (0, n - 1):
            heap.append((out[r, c], r, c))
            seen[r, c] = True
    for c in range(1, n - 1):
        for r in (0, n - 1):
            heap.append((out[r, c], r, c))
            seen[r, c] = True
    heapq.heapify(heap)
    while heap:
        z, r, c = heapq.heappop(heap)
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                rr, cc = r + dr, c + dc
                if 0 <= rr < n and 0 <= cc < n and not seen[rr, cc]:
                    seen[rr, cc] = True
                    if out[rr, cc] < z:
                        out[rr, cc] = z + 1e-4
                    heapq.heappush(heap, (out[rr, cc], rr, cc))
    return out


def flow_accumulation(h):
    """D8 flow accumulation (cells draining through each cell)."""
    n = h.shape[0]
    hp = np.pad(h, 1, constant_values=np.inf)
    offs = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    drops = np.stack([h - hp[1 + dy : 1 + dy + n, 1 + dx : 1 + dx + n] for dy, dx in offs])
    drops /= np.array([1.414 if dy and dx else 1.0 for dy, dx in offs])[:, None, None]
    best = drops.argmax(0)
    valid = drops.max(0) > 0
    acc = np.ones_like(h)
    order = np.argsort(h, axis=None)[::-1]
    flat_acc = acc.ravel()
    for idx in order:
        if not valid.flat[idx]:
            continue
        r, c = divmod(idx, n)
        dy, dx = offs[best.flat[idx]]
        flat_acc[(r + dy) * n + (c + dx)] += flat_acc[idx]
    return acc


def noise(n, scale, rng):
    w = rng.standard_normal((n, n))
    w = ndimage.gaussian_filter(w, scale, mode="wrap")
    return (w - w.mean()) / (w.std() + 1e-9)


def main(name: str) -> None:
    p = PRESETS[name]
    rng = np.random.default_rng(SEED)
    src = rasterio.open(COP / f"Copernicus_DSM_COG_10_{p['tile']}_DEM.tif")
    dem = src.read(1).astype(np.float64)
    lon, lat = tm_grid(p)
    col, row = ~src.transform * (lon, lat)
    real = ndimage.map_coordinates(
        dem,
        [np.clip(row - 0.5, 0, dem.shape[0] - 1.001), np.clip(col - 0.5, 0, dem.shape[1] - 1.001)],
        order=3,
        mode="nearest",
    )
    n = p["n"]
    cell_real = p["real_size"] / (n - 1)  # 5 m real
    lake = real <= p["lake_level"]
    lake = ndimage.binary_opening(lake, iterations=2)
    # Shelf: DSM has a flat lake surface; shape the bed by distance from shore (real metres)
    d_in = ndimage.distance_transform_edt(lake) * cell_real
    bed = p["lake_level"] - (0.5 + 18.0 * (1 - np.exp(-((d_in / 350.0) ** 1.3))))
    land = np.maximum(real, p["lake_level"] + 0.3)
    real_h = np.where(lake, bed, land)
    # 30 m data stair-steps after a 6x upsample: soften, keep the shore line crisp
    # (GLO-30 is a surface model: bush and DSM noise read as 1-2 m bumps, which become pimples after the 6x upsample)
    real_h = np.where(
        lake, ndimage.gaussian_filter(real_h, 3), ndimage.gaussian_filter(real_h, 2.5)
    )
    g = real_h / p["scale"]  # game metres
    gmin, gmax = float(g.min()), float(g.max())
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.round((g - gmin) / (gmax - gmin) * 65535).astype(np.uint16)).save(
        OUT / "height.png"
    )

    cell = cell_real / p["scale"]  # 0.5 m game
    water_level_g = p["lake_level"] / p["scale"]
    depth = np.clip((water_level_g - g) / 4.0, 0, 1) * lake
    d_out = ndimage.distance_transform_edt(~lake) * cell  # game m from the waterline, on land
    d_wat = ndimage.distance_transform_edt(lake) * cell
    shore_d = np.where(lake, d_wat, d_out)
    Image.fromarray((depth * 255).astype(np.uint8)).save(OUT / "water.png")
    Image.fromarray((np.clip(shore_d / 40.0, 0, 1) * 255).astype(np.uint8)).save(OUT / "shore.png")

    # Terrain analysis on real heights (real slopes = game slopes at uniform 1:10)
    gy, gx = np.gradient(real_h, cell_real)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    curv = ndimage.gaussian_filter(real_h, 6) - ndimage.gaussian_filter(real_h, 1.5)  # >0 = hollow
    acc = flow_accumulation(
        fill_pits(np.where(lake, p["lake_level"] - 50, ndimage.gaussian_filter(real_h, 2)))
    )
    chan = (
        np.clip((np.log10(acc) - 2.3) / 1.0, 0, 1) * ~lake
    )  # dry channels (laggas), > ~0.5 km2 catchment
    chan = np.maximum(ndimage.grey_dilation(chan, size=3), 0) * 1.0
    chan = ndimage.gaussian_filter(chan, 2.0)
    n1, n2, n3 = noise(n, 30, rng), noise(n, 8, rng), noise(n, 70, rng)

    w = {}
    w["sand"] = np.clip(1 - d_out / 22.0, 0, 1) ** 1.5 * ~lake + np.clip(0.3 * n2 - 0.2, 0, 1) * (
        d_out < 45
    )
    w["mud"] = np.clip(1 - d_out / 5.0, 0, 1) * ~lake + lake * 1.0
    w["cobble"] = chan * 1.4 * (d_out > 6)
    w["rock"] = np.clip((slope - 6) / 8, 0, 1) + np.clip(-curv * 0.35 + 0.25 * n1 - 0.55, 0, 1) * (
        d_out > 30
    )
    w["red"] = np.clip(0.15 + 0.6 * n3 - 0.25 * chan, 0, 1) * (d_out > 15)
    w["crack"] = np.clip(0.5 * n1 + 0.4 - d_out / 60, 0, 1) * (d_out > 4) * (d_out < 60)
    w["grass"] = np.clip(0.8 + 0.4 * n2 + 0.6 * chan - 0.5 * w["rock"], 0, 1.5) * (d_out > 8)
    keys = ["grass", "red", "rock", "sand", "mud", "cobble", "crack"]
    stack = np.stack([np.clip(w[k], 0, None) for k in keys]) + 1e-4
    stack = stack**1.6  # sharper transitions
    stack /= stack.sum(0)
    b = np.round(stack * 255).astype(np.int32)
    b[0] += 255 - b.sum(0)  # exact 255 sum
    b = np.clip(b, 0, 255).astype(np.uint8)
    Image.fromarray(np.dstack([b[0], b[1], b[2], b[3]]), "RGBA").save(OUT / "splat_a.png")
    Image.fromarray(np.dstack([b[4], b[5], b[6], np.zeros_like(b[0])]), "RGBA").save(
        OUT / "splat_b.png"
    )

    # Vegetation density (0..1): woodland and doum palms follow channels and the shore, grass on flats
    acacia = np.clip(chan * 1.2 + 0.25 * n1 - 0.15, 0, 1) * (d_out > 12) * (slope < 12)
    palm = np.clip(
        np.exp(-(((d_out - 25) / 18) ** 2)) * (0.6 + 0.5 * n2) + chan * 0.5 * (d_out < 150), 0, 1
    ) * (d_out > 6)
    tuft = np.clip(0.55 + 0.35 * n2 - w["rock"] * 0.8 - w["sand"] * 0.7, 0, 1) * (d_out > 4)
    reeds = np.clip(1 - np.abs(shore_d - 1.0) / 4.0, 0, 1) * np.clip(0.6 + 0.6 * n2, 0, 1)
    veg = np.dstack([acacia, palm, tuft, reeds])
    Image.fromarray((np.clip(veg, 0, 1) * 255).astype(np.uint8), "RGBA").save(OUT / "veg.png")

    meta = {
        "preset": name,
        "centre_lon": p["lon"],
        "centre_lat": p["lat"],
        "projection": "transverse Mercator at centre",
        "real_size_m": p["real_size"],
        "scale": f"1:{int(p['scale'])} (horizontal and vertical)",
        "game_size_m": p["real_size"] / p["scale"],
        "samples": n,
        "game_m_per_sample": cell,
        "h_min": gmin,
        "h_max": gmax,
        "water_level": water_level_g,
        "frame": "row 0 = north, col 0 = west; Godot: x = col * spacing - 256, z = row * spacing - 256 (+z south)",
        "lake_fraction": float(lake.mean()),
        "land_relief_game_m": float(g[~lake].max() - g[~lake].min()),
        "splat_a": "R dry grass, G red soil, B volcanic rock, A shore sand",
        "splat_b": "R wet mud, G cobble bed, B cracked mud, A unused",
        "veg": "R acacia woodland, G doum palm, B grass tufts, A reeds",
        "credit": "Produced using Copernicus WorldDEM-30 (c) DLR e.V. 2010-2014 and (c) Airbus Defence and Space GmbH "
        "2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved",
    }
    (OUT / "meta.json").write_text(json.dumps(meta, indent=1))
    print(
        json.dumps(
            {
                k: meta[k]
                for k in ("h_min", "h_max", "water_level", "lake_fraction", "land_relief_game_m")
            }
        )
    )


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "turkana")
