"""Rift Lake map -> game-ready terrain maps and layer arrays (offline, numpy + Pillow + scipy).

python3 tools/game/bake_terrain.py

Reads assets/terrain/rift_lake/{height,water,shore,splat_a,splat_b}.png + meta.json and the Poly Haven
sets in assets/textures/terrain. Writes assets/terrain/game/:
  height_f32.bin  game height y (m), 1025 x 1025 raw float32 (what the game loads)
  height_rg.png   game height y (m) as 16 bits, R = high byte, G = low byte, y = ENC_MIN + v / 65535 * ENC_RANGE
                  (Godot's PNG loader drops 16-bit grey to 8 bits, so the height is split over two channels)
  normal.png      terrain normal from the full 0.5 m grid with the vertical exaggeration (RGB = n * 0.5 + 0.5, x/y/z)
  sky_ao.png      sky occlusion of the relief (0 = closed, 255 = open), horizon test at 6 radii
  albedo_array.png  7 slices of 2048 x 2048 stacked vertically (Texture2DArray, sRGB)
  normal_array.png  7 slices of 1024 x 1024 (OpenGL normal maps)
  mat_array.png     7 slices of 1024 x 1024: R ambient occlusion, G roughness, B height (displacement)
Layer order = splat_a RGBA then splat_b RGB (DESIGN 7.2).
The numbers that Godot needs (ENC_MIN, ENC_RANGE, EXAGGERATION) are mirrored in scripts/SpikeConfig.gd.
"""

import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/terrain/rift_lake"
TEX = ROOT / "assets/textures/terrain"
OUT = ROOT / "assets/terrain/game"
EXAGGERATION = 3.0  # owner's builder call 2026-10-11: real relief is only 4.8 m at 1:10
ENC_MIN, ENC_RANGE = -16.0, 64.0
LAYERS = [
    "withered_grass",
    "red_mud_stones",
    "dark_rock",
    "coast_sand_01",
    "brown_mud_02",
    "dry_river_pebbles",
    "mud_cracked_dry_riverbed_002",
]


def game_heights() -> np.ndarray:
    meta = json.loads((SRC / "meta.json").read_text())
    raw = np.asarray(Image.open(SRC / "height.png"), dtype=np.float64) / 65535.0
    h = meta["h_min"] + raw * (meta["h_max"] - meta["h_min"])
    return (h - meta["water_level"]) * EXAGGERATION


def save_height(y: np.ndarray) -> None:
    # raw little-endian float32, row 0 = north: the game loads it with FileAccess (no per-pixel decode)
    y.astype("<f4").tofile(OUT / "height_f32.bin")
    v = np.clip(np.round((y - ENC_MIN) / ENC_RANGE * 65535.0), 0, 65535).astype(np.uint32)
    rgb = np.zeros(y.shape + (3,), np.uint8)
    rgb[..., 0] = v >> 8
    rgb[..., 1] = v & 255
    Image.fromarray(rgb).save(OUT / "height_rg.png")


def save_normal(y: np.ndarray, spacing: float) -> np.ndarray:
    gx = np.gradient(y, spacing, axis=1)
    gz = np.gradient(y, spacing, axis=0)
    n = np.stack([-gx, np.ones_like(y), -gz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    Image.fromarray(np.round((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(OUT / "normal.png")
    return n


def save_sky_ao(y: np.ndarray, spacing: float) -> None:
    # Fraction of the sky dome left open: for each radius, how far the mean ring height rises above
    # the point (as an elevation angle). Cheap stand-in for a horizon scan; good enough for gullies.
    occl = np.zeros_like(y)
    for r_m in (1.5, 3.0, 6.0, 12.0, 24.0, 48.0):
        r = r_m / spacing
        mean = ndimage.uniform_filter(y, size=int(r * 2) | 1, mode="nearest")
        ang = np.arctan2(np.maximum(mean - y, 0.0), r_m)
        occl += np.sin(ang)
    open_ = np.clip(1.0 - occl / 6.0 * 2.2, 0.0, 1.0)
    Image.fromarray(np.round(open_ * 255).astype(np.uint8)).save(OUT / "sky_ao.png")


def load(path: Path, size: int, mode: str) -> np.ndarray:
    im = Image.open(path)
    if im.mode in ("I;16", "I"):
        a = np.asarray(im, dtype=np.float64)
        im = Image.fromarray((a / max(a.max(), 1.0) * 255).astype(np.uint8))
    im = im.convert(mode)
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im)


def save_arrays() -> None:
    alb = []
    nor = []
    mat = []
    for name in LAYERS:
        alb.append(load(TEX / f"{name}_diff_2k.png", 2048, "RGB"))
        nor.append(load(TEX / f"{name}_nor_gl_2k.png", 1024, "RGB"))
        arm = load(TEX / f"{name}_arm_2k.png", 1024, "RGB")
        disp = load(TEX / f"{name}_disp_2k.png", 1024, "L").astype(np.float64)
        # stretch every layer's height to 0..1 so the height blend treats all layers alike
        lo, hi = np.percentile(disp, 1), np.percentile(disp, 99)
        disp = np.clip((disp - lo) / max(hi - lo, 1.0), 0, 1) * 255
        m = np.stack([arm[..., 0], arm[..., 1], disp.astype(np.uint8)], -1)
        mat.append(m)
        print(name, "ok")
    Image.fromarray(np.concatenate(alb, 0)).save(OUT / "albedo_array.png", optimize=False)
    Image.fromarray(np.concatenate(nor, 0)).save(OUT / "normal_array.png", optimize=False)
    Image.fromarray(np.concatenate(mat, 0)).save(OUT / "mat_array.png", optimize=False)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    meta = json.loads((SRC / "meta.json").read_text())
    spacing = meta["game_m_per_sample"]
    y = game_heights()
    print("game y", round(y.min(), 2), round(y.max(), 2), "land relief", round(y.max() - 0.0, 2))
    save_height(y)
    save_normal(y, spacing)
    save_sky_ao(y, spacing)
    save_arrays()
    print("wrote", OUT)


if __name__ == "__main__":
    main()
