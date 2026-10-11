"""Bakes the vegetation biome mask for the Rift Lake map: assets/terrain/game/biome.png.

python3 tools/game/bake_biome.py [--preview out.png]

Setting (owner 2026-10-11): ~4.2 million years ago at Kanapoi, closed woodland with shrubs and
grassland patches by a river and lake, greener and more wooded than today's Turkana (the
existing DEM geometry stays). RGBA, 1024 x 1024 = 0.5 m per pixel over the 512 m map
(pixel (i, j) covers x = i / 2, z = j / 2):
  R forest   0..1 closed woodland / gallery forest density (trees, understory, shade floor)
  G lush     0..1 green vs sun-cured grass (wetter near water and channels)
  B path     0..1 trampled bare ground: animal paths and the camp's foot trails
  A reeds    0..1 reed and sedge beds at the waterline
The camp area is hand-authored: a glade round the Home Tree, foot trails to every resource and
to the lake, gallery forest walls north and along the shore. The coordinates below mirror
scripts/GameConfig.gd (keep them in step when the camp moves).
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/terrain/rift_lake"
OUT = ROOT / "assets/terrain/game/biome.png"
N = 1024

HOME = (406.0, 262.0)
WOODLAND = (378.0, 250.0)
FIGS = [(418, 252), (421, 266), (413, 276), (395, 273), (393, 255), (404, 247)]
TUBERS = [(398, 220), (420, 224)]
CARCASSES = [(418, 318), (398, 322)]
WOOD = [(381, 244), (374, 255), (384, 258), (370, 243)]
STONES = [(374, 304), (381, 309), (368, 312)]
RIVAL = (372.0, 120.0)
GAZELLES = (352.0, 228.0)
HYENA_DEN = (424.0, 334.0)
BENCH = (395.0, 292.0)
LEOPARD = [(330, 300), (300, 260), (320, 220), (350, 270)]


def noise(seed: int, cell_m: float, octaves: int = 4) -> np.ndarray:
    """Fractal value noise 0..1 on the N x N grid, base wavelength cell_m metres."""
    rng = np.random.default_rng(seed)
    out = np.zeros((N, N))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cells = max(int(512 / (cell_m / 2**o)), 2)
        g = rng.random((cells + 3, cells + 3))
        z = ndimage.zoom(g, (N + 3 * N / cells) / (cells + 3), order=3)[:N, :N]
        out += amp * z
        tot += amp
        amp *= 0.5
    out /= tot
    lo, hi = np.percentile(out, 1), np.percentile(out, 99)
    return np.clip((out - lo) / (hi - lo), 0, 1)


def grid() -> tuple[np.ndarray, np.ndarray]:
    j, i = np.mgrid[0:N, 0:N]
    return (i + 0.5) / 2.0, (j + 0.5) / 2.0


def disc(x, z, c, r, soft) -> np.ndarray:
    d = np.hypot(x - c[0], z - c[1])
    return np.clip((r - d) / soft, 0, 1)


def path(x, z, pts, width, wobble_seed) -> np.ndarray:
    """Soft trail through the points (metres), meandering by a little noise."""
    rng = np.random.default_rng(wobble_seed)
    dense = []
    for a, b in zip(pts[:-1], pts[1:], strict=True):
        a = np.array(a, float)
        b = np.array(b, float)
        n = max(int(np.linalg.norm(b - a) / 1.0), 2)
        for t in np.linspace(0, 1, n, endpoint=False):
            dense.append(a + (b - a) * t)
    dense.append(np.array(pts[-1], float))
    dense = np.array(dense)
    # meander: low-frequency sideways offset
    k = np.cumsum(rng.normal(0, 0.35, len(dense)))
    k = ndimage.gaussian_filter1d(k, 10) * 2.5
    d = np.gradient(dense, axis=0)
    nrm = np.stack([-d[:, 1], d[:, 0]], 1)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-6)
    dense = dense + nrm * k[:, None]
    mask = np.zeros((N, N))
    for px, pz in dense:
        i0, j0 = int(px * 2), int(pz * 2)
        r = int(width * 2) + 2
        sl = (slice(max(j0 - r, 0), min(j0 + r, N)), slice(max(i0 - r, 0), min(i0 + r, N)))
        dd = np.hypot(x[sl] - px, z[sl] - pz)
        mask[sl] = np.maximum(mask[sl], np.clip((width - dd) / (width * 0.8), 0, 1))
    return mask


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview")
    a = ap.parse_args()
    x, z = grid()
    h = np.fromfile(ROOT / "assets/terrain/game/height_f32.bin", dtype=np.float32).reshape(
        1025, 1025
    )
    h = h[:N, :N]
    shore = np.asarray(Image.open(SRC / "shore.png"), float)[:N, :N] / 255.0 * 40.0
    veg = np.asarray(Image.open(SRC / "veg.png"), float)[:N, :N] / 255.0
    land = h > 0.0
    # dry stream channels (laggas): the source veg R/G lines; distance to the nearest channel
    chan = (veg[..., 0] > 0.35) | (veg[..., 1] > 0.35)
    chan_d = ndimage.distance_transform_edt(~chan) / 2.0
    n_big = noise(11, 90.0)
    n_mid = noise(12, 30.0)
    n_fine = noise(13, 8.0, 3)

    # --- forest: closed woodland in big patches, gallery forest on channels and the shore band ---
    wood = np.clip((n_big * 0.7 + n_mid * 0.3 - 0.5) * 4.0, 0, 1)
    gallery_ch = np.clip(1.0 - (chan_d - 6.0) / 10.0, 0, 1) * np.clip(n_mid * 1.6 - 0.15, 0, 1)
    belt = np.clip((shore - 4.0) / 3.0, 0, 1) * np.clip((34.0 - shore) / 8.0, 0, 1)
    gallery_sh = belt * np.clip(n_mid * 1.8 - 0.2, 0, 1)
    forest = np.maximum.reduce([wood, gallery_ch, gallery_sh])
    forest *= np.clip(0.75 + n_fine * 0.5, 0, 1)
    # grassland patches: the uplands far from water open up
    forest *= np.clip(1.25 - np.clip((h - 7.0) / 6.0, 0, 1), 0, 1)

    # --- hand-authored camp (the first screen) ---
    # an open mosaic round the camp: scattered clumps, not a closed wall, out to ~55 m
    d_home = np.hypot(x - HOME[0], z - HOME[1])
    # the play area (camp, kit, carcasses, wildlife) stays open so units are never hidden under
    # canopy: scattered clumps out to ~45 m, full woodland from ~80 m
    forest *= 0.2 + 0.8 * np.clip((d_home - 45.0) / 35.0, 0, 1)
    keep_open = np.zeros((N, N))
    keep_open = np.maximum(keep_open, disc(x, z, HOME, 21.0, 6.0))
    for c in FIGS:
        keep_open = np.maximum(keep_open, disc(x, z, c, 3.5, 2.0))
    for c in TUBERS:
        keep_open = np.maximum(keep_open, disc(x, z, c, 7.0, 3.0))
    for c in CARCASSES + STONES:
        keep_open = np.maximum(keep_open, disc(x, z, c, 7.0, 3.0))
    keep_open = np.maximum(keep_open, disc(x, z, WOODLAND, 9.0, 3.0))
    keep_open = np.maximum(keep_open, disc(x, z, RIVAL, 14.0, 4.0))
    keep_open = np.maximum(keep_open, disc(x, z, GAZELLES, 22.0, 6.0))
    keep_open = np.maximum(keep_open, disc(x, z, HYENA_DEN, 14.0, 4.0))
    for c in CARCASSES:
        keep_open = np.maximum(keep_open, disc(x, z, c, 14.0, 5.0))
    # bench / crowd test ground and the leopard's beat
    keep_open = np.maximum(keep_open, disc(x, z, BENCH, 18.0, 5.0))
    for c in LEOPARD:
        keep_open = np.maximum(keep_open, disc(x, z, c, 10.0, 4.0))
    # designed walls: a forest edge north of the camp and gallery forest east toward the lake
    wall_n = disc(x, z, (412, 236), 15.0, 5.0) * (n_fine * 0.5 + 0.6)
    wall_ne = disc(x, z, (432, 248), 10.0, 5.0)
    wall_e = disc(x, z, (433, 285), 9.0, 4.0)
    stand = np.zeros((N, N))
    for c in [(372, 238), (366, 252), (387, 238), (364, 262)]:
        stand = np.maximum(stand, disc(x, z, c, 6.0, 3.0))
    forest = np.maximum.reduce([forest, wall_n, wall_ne, wall_e, stand])

    # --- trails ---
    trails = np.zeros((N, N))
    trails = np.maximum(trails, path(x, z, [HOME, (424, 266), (437, 270), (446, 271)], 0.95, 1))
    trails = np.maximum(trails, path(x, z, [HOME, (392, 256), WOODLAND], 0.8, 2))
    trails = np.maximum(trails, path(x, z, [HOME, (405, 240), (400, 226), TUBERS[0]], 0.75, 3))
    trails = np.maximum(trails, path(x, z, [(405, 240), TUBERS[1]], 0.6, 4))
    trails = np.maximum(trails, path(x, z, [HOME, (396, 286), STONES[1]], 0.75, 5))
    trails = np.maximum(trails, path(x, z, [(401, 280), (410, 300), CARCASSES[0]], 0.7, 6))
    # an animal trail along the shore and one down to the water from the gazelle grounds
    trails = np.maximum(
        trails, path(x, z, [(430, 120), (436, 200), (440, 240), (442, 300), (436, 380)], 0.65, 7)
    )
    trails = np.maximum(trails, path(x, z, [GAZELLES, (390, 232), (440, 232)], 0.6, 8))
    forest *= 1.0 - np.clip(keep_open, 0, 1)
    forest *= 1.0 - np.clip(trails * 1.5, 0, 1)
    forest *= land & (shore > 3.0)
    forest = ndimage.gaussian_filter(forest, 1.5)

    # --- lushness: wetter near water and channels, under and near forest ---
    near_w = np.clip(1.0 - shore / 30.0, 0, 1)
    near_c = np.clip(1.0 - chan_d / 25.0, 0, 1)
    near_f = ndimage.gaussian_filter(forest, 12.0)
    lush = np.clip(0.3 + 0.35 * near_w + 0.25 * near_c + 0.5 * near_f + (n_mid - 0.5) * 0.5, 0, 1)
    lush -= np.clip((h - 8.0) / 8.0, 0, 0.35)
    lush = np.clip(lush, 0, 1)

    # --- reeds: a broken band 0-4 m from the waterline, thicker in sheltered bays ---
    reeds = np.clip((4.5 - shore) / 2.0, 0, 1) * np.clip(n_mid * 2.2 - 0.6, 0, 1)
    reeds *= 1.0 - np.clip(trails * 2.0, 0, 1)

    rgba = np.stack([forest, lush, trails, reeds], -1)
    img = Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA")
    img.save(OUT)
    print(f"wrote {OUT}: forest {forest[land].mean():.2f}, lush {lush[land].mean():.2f}")
    if a.preview:
        p = np.zeros((N, N, 3))
        p[..., 0] = 0.75 - 0.4 * lush
        p[..., 1] = 0.6 + 0.2 * lush
        p[..., 2] = 0.3
        p *= 1.0 - 0.65 * forest[..., None]
        p[trails > 0.3] = [0.55, 0.35, 0.2]
        p[reeds > 0.3] = [0.2, 0.6, 0.3]
        p[~land] = [0.1, 0.3, 0.6]
        Image.fromarray((p * 255).astype(np.uint8)).save(a.preview)


if __name__ == "__main__":
    main()
