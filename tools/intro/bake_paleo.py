"""Step 3 of the intro asset bake: turn the modern Earth into the Earth of the intro.

Globe (~7 Ma) and rift patch (~4.2 Ma, Kanapoi / Lake Lonyumun). Every edit is a design
inference, listed in CREDITS.md ("Opening intro") and docs/DESIGN.md; nothing here is a
reconstruction from data except where a source is named.

Inputs under <src> (download list: CREDITS.md):
  bmng/world.topo.bathy.200412.3x21600x10800.jpg   NASA Blue Marble NG, December 2004
  bmng/world.topo.bathy.200407.3x21600x10800.jpg   same, July 2004 (northern summer: no snow)
  bmng/world.topo.bathy.200412.3x21600x21600.C1/C2 500 m East Africa tiles
  bmng/gebco_08_rev_bath_21600x10800.png           ocean mask
  paleo/Scotese_Wright_2018_Maps_1-88_6minX6min_PaleoDEMS_nc/Map01_..._0Ma.nc   (Chad basin)
  s2/kanapoi_coarse_l10.jpg  s2/kanapoi_fine_l13.jpg  EOX Sentinel-2 cloudless 2016 (s2fetch.py)
  rift_dem.npy                                     Copernicus GLO-30 mosaic (bake_dem.py)

~/MWM/data/tools/geo-venv/bin/python tools/intro/bake_paleo.py <src> assets/intro [global|rift|all]
Writes earth_albedo_16k.jpg, earth_albedo_8k.jpg, earth_ocean_8k.png, rift_bmng_4k.jpg,
rift_s2_coarse.jpg, rift_s2_fine.jpg, rift_height.png, rift_normal.png and a few
check images to <src>/paleo/check_*.jpg.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bake_intro_assets import (  # noqa: E402
    BMNG_REGION,
    crop_deg,
    freq_match,
    region_bmng,
    save_jpg,
)

Image.MAX_IMAGE_PIXELS = None

# Keep in sync with scripts/IntroConfig.gd and bake_dem.py.
PATCH = (34.8, 1.05, 37.35, 3.6)
FINE = (35.895, 2.145, 36.245, 2.495)
# Kanapoi: PBDB collection 22234 (Patterson, Behrensmeyer & Sill 1970), 2.3167 N 36.0667 E.
KANAPOI = (36.0667, 2.3167)
MODERN_TURKANA_M = 362.7  # Copernicus lake surface (flat) + tolerance
# Lake Lonyumun: water below this level inside LAKE_POLY. INVENTED outline (the real one is not
# known); the level puts the shore at the Kanapoi site, which sits in lake-margin deposits.
LAKE_LEVEL_M = 560.0
LAKE_POLY = [
    (35.97, 2.21),
    (36.12, 2.13),
    (36.33, 2.30),
    (36.52, 2.52),
    (36.68, 2.84),
    (36.62, 3.14),
    (36.36, 3.30),
    (36.06, 3.22),
    (35.93, 2.92),
    (35.90, 2.56),
]
# Ancestral Kerio River: INVENTED course drawn along today's Kerio valley into the lake at Kanapoi,
# ending in a three-arm delta.
KERIO = [
    (35.74, 1.10),
    (35.80, 1.38),
    (35.86, 1.62),
    (35.92, 1.86),
    (35.98, 2.05),
    (36.03, 2.20),
    (36.055, 2.27),
]
DELTA = [
    [(36.055, 2.27), (36.07, 2.30), (36.09, 2.325)],
    [(36.055, 2.27), (36.085, 2.285), (36.115, 2.29)],
    [(36.055, 2.27), (36.05, 2.305), (36.055, 2.335)],
]
# Mount Kulal (volcano, ~2.4 Ma and younger) and South Island: removed from the 4.2 Ma rift.
REMOVE_PEAKS = [((36.92, 2.69), (0.13, 0.24)), ((36.59, 2.63), (0.05, 0.05))]
# Central American Seaway, open at ~7 Ma (INVENTED course across the Darien, where the Scotese
# 5 Ma and 10 Ma PaleoDEMs leave their gap).
PANAMA = [(-76.85, 8.45), (-77.25, 8.15), (-77.65, 8.0), (-78.0, 8.1), (-78.35, 8.25)]
PANAMA_W_DEG = 0.32

# Colours (sRGB 0..1), picked from Blue Marble pixels of today's savanna, woodland and lakes.
SAVANNA = np.array([0.44, 0.44, 0.24], np.float32)
WOODLAND = np.array([0.19, 0.27, 0.11], np.float32)
SHRUB = np.array([0.30, 0.36, 0.17], np.float32)
TUNDRA = np.array([0.34, 0.32, 0.26], np.float32)
LAKE_DEEP = np.array([0.09, 0.22, 0.27], np.float32)
LAKE_SHALLOW = np.array([0.20, 0.33, 0.30], np.float32)
RIVER = np.array([0.20, 0.24, 0.20], np.float32)


def smoothstep(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ----------------------------------------------------------------- noise (periodic, global)
def _fft_noise(w: int, h: int, beta: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    f = np.fft.rfft2(rng.standard_normal((h, w)))
    ky = np.fft.fftfreq(h)[:, None] * h
    kx = np.fft.rfftfreq(w)[None, :] * w / 2.0  # lon spans 2x lat
    k = np.sqrt(kx * kx + ky * ky)
    k[0, 0] = 1.0
    f *= 1.0 / k**beta
    f[0, 0] = 0.0
    n = np.fft.irfft2(f, s=(h, w))
    n = (n - n.mean()) / n.std()
    return (0.5 + 0.5 * np.tanh(n * 0.9)).astype(np.float32)


NOISE: dict[int, np.ndarray] = {}


def noise(lon: np.ndarray, lat: np.ndarray, seed: int) -> np.ndarray:
    """0..1 fbm-like noise sampled at lon/lat (degrees), same value for every layer."""
    if seed not in NOISE:
        NOISE[seed] = _fft_noise(4096, 2048, 1.35, seed)
    g = NOISE[seed]
    x = (lon + 180.0) / 360.0 * g.shape[1] - 0.5
    y = (90.0 - lat) / 180.0 * g.shape[0] - 0.5
    return ndimage.map_coordinates(g, [y, x], order=1, mode="grid-wrap").astype(np.float32)


# ----------------------------------------------------------------- geometry helpers
def dist_to_polyline(lon: np.ndarray, lat: np.ndarray, pts: list) -> np.ndarray:
    """Distance in km (local flat approximation) to a polyline."""
    best = np.full(lon.shape, 1e9, np.float32)
    kx = 111.32 * math.cos(math.radians(float(np.mean(lat))))
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        ax, ay = (lon - x0) * kx, (lat - y0) * 110.57
        bx, by = (x1 - x0) * kx, (y1 - y0) * 110.57
        t = np.clip((ax * bx + ay * by) / max(bx * bx + by * by, 1e-9), 0.0, 1.0)
        d = np.hypot(ax - t * bx, ay - t * by)
        best = np.minimum(best, d)
    return best


def meander(pts: list, amp_deg: float, seed: int) -> list:
    """Dense polyline along `pts` with river-like bends (sine of drifting wavelength + noise)."""
    rng = np.random.default_rng(seed)
    out = []
    s_tot = 0.0
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        nx, ny = -(y1 - y0) / seg, (x1 - x0) / seg
        steps = max(4, int(seg / 0.002))
        for i in range(steps):
            t = i / steps
            s = s_tot + seg * t
            off = amp_deg * (
                math.sin(s / 0.011 + 0.6 * math.sin(s / 0.037)) + 0.35 * rng.standard_normal() * 0.2
            )
            fade = min(1.0, s / 0.01)
            out.append((x0 + (x1 - x0) * t + nx * off * fade, y0 + (y1 - y0) * t + ny * off * fade))
        s_tot += seg
    out.append(pts[-1])
    return out


def inside_poly(lon: np.ndarray, lat: np.ndarray, poly: list) -> np.ndarray:
    ins = np.zeros(lon.shape, bool)
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        c = ((y0 > lat) != (y1 > lat)) & (lon < (x1 - x0) * (lat - y0) / (y1 - y0 + 1e-12) + x0)
        ins ^= c
    return ins


def push_pull(img: np.ndarray, hole: np.ndarray) -> np.ndarray:
    """Fill `hole` (bool HxW) of an HxW(xC) float image from its surroundings (pyramid)."""
    a = img.astype(np.float32)
    if a.ndim == 2:
        a = a[..., None]
    w = (~hole).astype(np.float32)[..., None]
    levels = [(a * w, w)]
    while min(levels[-1][1].shape[:2]) > 2 and (levels[-1][1] <= 0).any():
        ca, cw = levels[-1]
        h2, w2 = (ca.shape[0] + 1) // 2, (ca.shape[1] + 1) // 2
        pa = np.zeros((h2 * 2, w2 * 2, ca.shape[2]), np.float32)
        pw = np.zeros((h2 * 2, w2 * 2, 1), np.float32)
        pa[: ca.shape[0], : ca.shape[1]] = ca
        pw[: cw.shape[0], : cw.shape[1]] = cw
        sa = pa.reshape(h2, 2, w2, 2, -1).sum((1, 3))
        sw = pw.reshape(h2, 2, w2, 2, 1).sum((1, 3))
        levels.append((sa, sw))
    # pull: fill each level's empty texels from the coarser level
    fa, fw = levels[-1]
    col = fa / np.maximum(fw, 1e-6)
    for ca, cw in reversed(levels[:-1]):
        up = np.repeat(np.repeat(col, 2, 0), 2, 1)[: ca.shape[0], : ca.shape[1]]
        up = ndimage.uniform_filter(up, size=(3, 3, 1))
        own = ca / np.maximum(cw, 1e-6)
        k = np.clip(cw, 0.0, 1.0)
        col = own * k + up * (1.0 - k)
    out = img.astype(np.float32).copy()
    if out.ndim == 2:
        out[hole] = col[..., 0][hole]
    else:
        out[hole] = col[hole]
    return out


def lowpass(a: np.ndarray, sigma: float) -> np.ndarray:
    if a.ndim == 3:
        return np.stack([ndimage.gaussian_filter(a[..., c], sigma) for c in range(3)], -1)
    return ndimage.gaussian_filter(a, sigma)


def lum_of(a: np.ndarray) -> np.ndarray:
    return a[..., 0] * 0.3 + a[..., 1] * 0.55 + a[..., 2] * 0.15


# ----------------------------------------------------------------- rift features (patch grid)
class Rift:
    """Lake, river and peak masks of the 4.2 Ma rift on the patch grid, sampled by lon/lat."""

    def __init__(self, dem: np.ndarray) -> None:
        n = dem.shape[0]
        self.n = n
        lon, lat = self.grid(n)
        self.h0 = dem.astype(np.float32)
        self.modern = (self.h0 < MODERN_TURKANA_M).astype(np.float32)
        peaks = np.zeros((n, n), np.float32)
        for (cx, cy), (rx, ry) in REMOVE_PEAKS:
            e = np.hypot((lon - cx) / rx, (lat - cy) / ry)
            peaks = np.maximum(peaks, 1.0 - smoothstep(0.75, 1.0, e))
        self.peaks = peaks
        # lake: inside the (noisy) polygon and below the level
        jitter = (noise(lon * 6.0, lat * 6.0, 11) - 0.5) * 0.16 + (
            noise(lon * 25.0, lat * 25.0, 12) - 0.5
        ) * 0.04
        ins = inside_poly(lon + jitter, lat - jitter * 0.8, LAKE_POLY)
        h = self.h0.copy()
        h = np.where(peaks > 0.02, push_pull(h, peaks > 0.02), h)
        lake = ins & (h < LAKE_LEVEL_M)
        lake = ndimage.binary_opening(lake, iterations=2)
        lab, nlab = ndimage.label(lake)
        if nlab > 1:  # keep the main water body
            sizes = ndimage.sum(lake, lab, range(1, nlab + 1))
            lake = lab == (1 + int(np.argmax(sizes)))
        lake = ndimage.binary_fill_holes(lake)
        self.lake = ndimage.gaussian_filter(lake.astype(np.float32), 1.2)
        # river + delta: distance (km) to the drawn course, meandered by noise
        d = dist_to_polyline(lon, lat, meander(KERIO, 0.012, 7))
        for k, arm in enumerate(DELTA):
            d = np.minimum(d, dist_to_polyline(lon, lat, meander(arm, 0.004, 30 + k)) * 1.3)
        self.river = (1.0 - smoothstep(0.05, 0.12, d)) * (1.0 - self.lake)
        # distance to any water (km) for gallery woodland
        water = (self.lake > 0.5) | (d < 0.08)
        px_km = (PATCH[2] - PATCH[0]) / n * 111.0
        self.wdist = (ndimage.distance_transform_edt(~water) * px_km).astype(np.float32)
        # heights: no peaks, flat lake, no ground below the lake level outside it
        floor = LAKE_LEVEL_M + 6.0 + noise(lon, lat, 31) * 14.0
        low = (h < floor) & (self.lake < 0.5)
        h = np.where(low, floor, h)
        h = ndimage.gaussian_filter(h, 1.0)
        lk = self.lake
        h = h * (1.0 - lk) + (LAKE_LEVEL_M - 2.0) * lk
        self.h = h.astype(np.float32)

    @staticmethod
    def grid(n: int) -> tuple:
        lon = np.linspace(PATCH[0], PATCH[2], n, dtype=np.float32)[None, :].repeat(n, 0)
        lat = np.linspace(PATCH[3], PATCH[1], n, dtype=np.float32)[:, None].repeat(n, 1)
        return lon, lat

    def sample(self, field: np.ndarray, lon: np.ndarray, lat: np.ndarray, outside: float):
        x = (lon - PATCH[0]) / (PATCH[2] - PATCH[0]) * (self.n - 1)
        y = (PATCH[3] - lat) / (PATCH[3] - PATCH[1]) * (self.n - 1)
        return ndimage.map_coordinates(field, [y, x], order=1, mode="constant", cval=outside)


# ----------------------------------------------------------------- the edit itself
def paleo_edit(
    rgb: np.ndarray,
    lon: np.ndarray,
    lat: np.ndarray,
    ocean: np.ndarray,
    rift: Rift | None,
    blur_px: float,
    chad: np.ndarray | None = None,
) -> np.ndarray:
    """rgb float 0..1 (HxWx3) at lon/lat (HxW). Returns the edited copy."""
    out = rgb.copy()
    land = 1.0 - ocean
    L = lum_of(rgb)
    Lb = ndimage.gaussian_filter(L, blur_px) + 1e-3
    detail = np.clip(L / Lb, 0.55, 1.6)[..., None]
    sat = rgb.max(-1) - rgb.min(-1)
    # dry ground: reddish/tan, not already green
    dry = smoothstep(0.02, 0.10, rgb[..., 0] - rgb[..., 2]) * smoothstep(
        -0.01, 0.03, rgb[..., 0] - rgb[..., 1]
    )
    n1 = noise(lon, lat, 1)
    n2 = noise(lon, lat, 2)
    n3 = noise(lon * 4.0, lat * 4.0, 3)
    # --- Sahara / Sahel (patchy tan-green, more to the south), Arabia (greener), East Africa
    sah = (
        smoothstep(-18.0, -14.0, lon)
        * (1.0 - smoothstep(32.0, 35.0, lon))
        * smoothstep(7.0, 11.0, lat)
        * (1.0 - smoothstep(27.0, 32.0, lat))
    )
    sah_str = sah * np.interp(lat, [10.0, 16.0, 22.0, 30.0], [0.9, 0.8, 0.6, 0.35]).astype(
        np.float32
    )
    ara = (
        smoothstep(34.0, 37.0, lon)
        * (1.0 - smoothstep(57.0, 60.0, lon))
        * smoothstep(11.0, 14.0, lat)
        * (1.0 - smoothstep(29.0, 33.0, lat))
        * 0.7
    )
    eaf = (
        smoothstep(27.0, 31.0, lon)
        * (1.0 - smoothstep(43.0, 47.0, lon))
        * smoothstep(-6.0, -2.0, lat)
        * (1.0 - smoothstep(11.0, 15.0, lat))
        * 0.65
    )
    patch_n = 0.15 + 0.85 * smoothstep(0.38, 0.62, n1)
    amt = np.maximum(np.maximum(sah_str, ara), eaf) * patch_n * dry * land
    tcol = SAVANNA[None, None] * (1.0 - n2[..., None]) + SHRUB[None, None] * n2[..., None]
    if rift is not None:
        # 4.2 Ma rift: closed woodland near water, shrubs, grassland (Kanapoi; Manthi et al.)
        # radial fade, gone well inside the patch box so no layer shows the box edge
        cx, cy = (PATCH[0] + PATCH[2]) * 0.5, (PATCH[1] + PATCH[3]) * 0.5
        rr = np.hypot(lon - cx, lat - cy) + (n1 - 0.5) * 0.25
        inr = (1.0 - smoothstep(0.55, 1.1, rr)).astype(np.float32)
        wd = rift.sample(rift.wdist, lon, lat, 50.0)
        nh = noise(lon * 30.0, lat * 30.0, 5)
        nm = noise(lon * 8.0, lat * 8.0, 6)
        gallery = 1.0 - smoothstep(0.2, 1.6, wd + (nh - 0.5) * 2.5)
        stands = smoothstep(0.45, 0.62, nm * 0.6 + nh * 0.4) * (1.0 - smoothstep(6.0, 25.0, wd))
        wood = np.clip(np.maximum(gallery * 0.95, stands * 0.8), 0.0, 1.0)
        rcol = (SAVANNA[None, None] * (1.0 - n2[..., None]) + SHRUB[None, None] * n2[..., None]) * (
            1.0 - wood[..., None]
        ) + WOODLAND[None, None] * wood[..., None]
        rift_amt = inr * (0.7 + 0.25 * wood) * land
        tcol = tcol * (1.0 - inr[..., None]) + rcol * inr[..., None]
        amt = np.maximum(amt, rift_amt * np.maximum(dry, 0.5))
    new = tcol * detail
    out = out * (1.0 - amt[..., None]) + new * amt[..., None]
    # --- Greenland: smaller, patchier ice (INVENTED extent, kept on the east-central highlands)
    gl = (
        smoothstep(-74.0, -70.0, lon)
        * (1.0 - smoothstep(-14.0, -10.0, lon))
        * smoothstep(58.5, 60.5, lat)
        * (1.0 - smoothstep(83.0, 84.0, lat))
        * (1.0 - smoothstep(0.0, 1.0, (lat - 76.0) * 0.5) * smoothstep(-62.0, -58.0, -lon) * 0.0)
    )
    ice = smoothstep(0.55, 0.75, L) * (1.0 - smoothstep(0.06, 0.15, sat))
    keep = 1.0 - smoothstep(
        0.7, 1.0, np.hypot((lon + 38.0) / 10.0, (lat - 73.5) / 6.0) + (n1 - 0.5) * 0.6
    )
    melt = gl * ice * (1.0 - keep) * land
    tundra = TUNDRA[None, None] * (0.8 + 0.4 * n3[..., None]) * np.clip(detail, 0.8, 1.2)
    out = out * (1.0 - melt[..., None]) + tundra * melt[..., None]
    # --- Panama seaway (INVENTED course)
    if lon.min() < -70.0 and lat.min() < 12.0:
        dp = dist_to_polyline(lon + (n3 - 0.5) * 0.1, lat, PANAMA) / 111.0
        sea = 1.0 - smoothstep(PANAMA_W_DEG * 0.35, PANAMA_W_DEG * 0.5, dp)
        shallow = np.array([0.10, 0.25, 0.38], np.float32)
        out = out * (1.0 - sea[..., None]) + shallow * (0.9 + 0.2 * n3[..., None]) * sea[..., None]
    # --- Chad basin lakes (below 280 m on the Scotese 0 Ma DEM; INVENTED as a 7 Ma state)
    if chad is not None:
        lk = chad
        out = (
            out * (1.0 - lk[..., None])
            + (LAKE_DEEP * (1.0 - lk[..., None] * 0.0) * (0.9 + 0.2 * n3[..., None]))
            * lk[..., None]
        )
    # --- Lake Lonyumun + Kerio (patch only)
    if rift is not None:
        lk = rift.sample(rift.lake, lon, lat, 0.0)
        rv = rift.sample(rift.river, lon, lat, 0.0)
        depth = smoothstep(0.5, 1.0, ndimage.gaussian_filter(lk, max(blur_px * 0.6, 1.0)))
        wcol = (
            LAKE_SHALLOW[None, None] * (1.0 - depth[..., None])
            + LAKE_DEEP[None, None] * depth[..., None]
        )
        out = out * (1.0 - lk[..., None]) + wcol * lk[..., None]
        out = out * (1.0 - rv[..., None]) + RIVER[None, None] * rv[..., None]
    return np.clip(out, 0.0, 1.0)


def chad_mask(src: Path, lon: np.ndarray, lat: np.ndarray) -> np.ndarray:
    import rasterio

    f = (
        src
        / "paleo/Scotese_Wright_2018_Maps_1-88_6minX6min_PaleoDEMS_nc/Map01_PALEOMAP_6min_Holocene_0Ma.nc"
    )
    a = rasterio.open(f).read(1).astype(np.float32)
    box = (12.0, 11.0, 20.5, 19.5)
    r0, r1 = int((90.05 - box[3]) / 0.1), int((90.05 - box[1]) / 0.1)
    c0, c1 = int((box[0] + 180.05) / 0.1), int((box[2] + 180.05) / 0.1)
    sub = ndimage.gaussian_filter(a[r0:r1, c0:c1], 2.0)
    x = (lon - box[0]) / 0.1
    y = (box[3] - lat) / 0.1
    jit = (noise(lon * 3.0, lat * 3.0, 41) - 0.5) * 18.0
    h = ndimage.map_coordinates(sub, [y, x], order=1, mode="constant", cval=999.0) + jit
    return (1.0 - smoothstep(279.0, 283.0, h)).astype(np.float32)


# Today's Lake Turkana from the Copernicus mosaic of the first intro (34.4-37.0 E, 2.5-5.1 N, lake
# surface flat at 362 m) plus the new patch; set in main().
TURKANA: dict = {}


def turkana_mask(lon: np.ndarray, lat: np.ndarray) -> np.ndarray:
    m = np.zeros(lon.shape, bool)
    for box, mask in TURKANA.values():
        n = mask.shape[0]
        x = (lon - box[0]) / (box[2] - box[0]) * (n - 1)
        y = (box[3] - lat) / (box[3] - box[1]) * (n - 1)
        m |= ndimage.map_coordinates(mask, [y, x], order=1, mode="constant", cval=0.0) > 0.5
    return m


def remove_turkana(rgb: np.ndarray, lon: np.ndarray, lat: np.ndarray, blur_px: float) -> np.ndarray:
    """Today's Lake Turkana (and Kulal) out of a Blue Marble crop: fill from the shores, add
    texture borrowed from the land 0.9 deg west."""
    hole = ndimage.binary_dilation(turkana_mask(lon, lat), iterations=max(2, int(blur_px)))
    for (cx, cy), (rx, ry) in REMOVE_PEAKS[:1]:
        hole |= np.hypot((lon - cx) / rx, (lat - cy) / ry) < 1.0
    if not hole.any():
        return rgb
    filled = push_pull(rgb, hole)
    shift = int(round(0.9 / abs(float(lon[0, 1] - lon[0, 0]))))
    donor = np.roll(rgb, shift, axis=1)
    hf = donor - lowpass(donor, blur_px * 2.0)
    soft = ndimage.gaussian_filter(hole.astype(np.float32), blur_px)[..., None]
    return np.clip(rgb * (1 - soft) + (filled + hf * 0.9) * soft, 0.0, 1.0)


# ----------------------------------------------------------------- stages
def lonlat_rows(y0: int, y1: int, w: int, h: int, box=(-180.0, -90.0, 180.0, 90.0)):
    lon0, lat0, lon1, lat1 = box
    xs = lon0 + (np.arange(w, dtype=np.float32) + 0.5) / w * (lon1 - lon0)
    ys = lat1 - (np.arange(y0, y1, dtype=np.float32) + 0.5) / h * (lat1 - lat0)
    return np.meshgrid(xs, ys)


def global_stage(src: Path, out: Path, rift: Rift) -> None:
    W, H = 16384, 8192
    dec = np.asarray(
        Image.open(src / "bmng/world.topo.bathy.200412.3x21600x10800.jpg")
        .convert("RGB")
        .resize((W, H), Image.Resampling.LANCZOS)
    )
    jul = np.asarray(
        Image.open(src / "bmng/world.topo.bathy.200407.3x21600x10800.jpg")
        .convert("RGB")
        .resize((W, H), Image.Resampling.LANCZOS)
    )
    b = (
        Image.open(src / "bmng/gebco_08_rev_bath_21600x10800.png")
        .convert("L")
        .resize((W, H), Image.Resampling.BOX)
    )
    ocean = np.clip((252.0 - np.asarray(b).astype(np.float32)) / 6.0, 0.0, 1.0)
    res = np.zeros((H, W, 3), np.uint8)
    ocean_out = ocean.copy()
    step, pad = 512, 32
    for y0 in range(0, H, step):
        a0, a1 = max(0, y0 - pad), min(H, y0 + step + pad)
        lon, lat = lonlat_rows(a0, a1, W, H)
        # northern summer (July) north of ~28 N: no seasonal snow on North America or Eurasia
        wj = smoothstep(22.0, 34.0, lat)[..., None]
        rgb = (dec[a0:a1] * (1.0 - wj) + jul[a0:a1] * wj) / 255.0
        oc = ocean[a0:a1]
        chad = None
        if lat.max() > 11.0 and lat.min() < 19.5:
            chad = chad_mask(src, lon, lat)
        if lat.max() > 1.0 and lat.min() < 5.0:
            rgb = remove_turkana(rgb, lon, lat, 2.0)
        rgb = paleo_edit(rgb, lon, lat, oc, rift, 4.0, chad)
        oc2 = oc.copy()
        if lon.min() < -70.0 and lat.min() < 12.0 and lat.max() > 4.0:
            dp = dist_to_polyline(lon, lat, PANAMA) / 111.0
            oc2 = np.maximum(oc2, 1.0 - smoothstep(PANAMA_W_DEG * 0.3, PANAMA_W_DEG * 0.45, dp))
        if chad is not None:
            oc2 = np.maximum(oc2, chad)
        oc2 = np.maximum(oc2, rift.sample(rift.lake, lon, lat, 0.0))
        k0 = y0 - a0
        k1 = k0 + min(step, H - y0)
        res[y0 : y0 + (k1 - k0)] = (rgb[k0:k1] * 255.0 + 0.5).astype(np.uint8)
        ocean_out[y0 : y0 + (k1 - k0)] = oc2[k0:k1]
        print("global rows", y0, flush=True)
    img = Image.fromarray(res)
    save_jpg(img, out / "earth_albedo_16k.jpg")
    save_jpg(img.resize((8192, 4096), Image.Resampling.LANCZOS), out / "earth_albedo_8k.jpg")
    Image.fromarray((ocean_out * 255).astype(np.uint8)).resize(
        (8192, 4096), Image.Resampling.BOX
    ).save(out / "earth_ocean_8k.png")
    print("earth_ocean_8k.png")
    chk = src / "paleo"
    img.crop(
        (
            int((-25 + 180) / 360 * W),
            int((90 - 42) / 180 * H),
            int((65 + 180) / 360 * W),
            int((90 + 12) / 180 * H),
        )
    ).resize((1800, 1080)).save(chk / "check_africa_7ma.jpg", quality=90)
    img.resize((2048, 1024)).save(chk / "check_world_7ma.jpg", quality=90)


def region_stage(src: Path, out: Path, rift: Rift) -> Image.Image:
    reg = region_bmng(src).resize((4096, 4096), Image.Resampling.LANCZOS)
    a = np.asarray(reg).astype(np.float32) / 255.0
    lon, lat = lonlat_rows(0, 4096, 4096, 4096, BMNG_REGION)
    b = Image.open(src / "bmng/gebco_08_rev_bath_21600x10800.png").convert("L")
    oc = np.clip(
        (
            252.0
            - np.asarray(
                crop_deg(b, (-180, -90, 180, 90), BMNG_REGION).resize((4096, 4096))
            ).astype(np.float32)
        )
        / 6.0,
        0,
        1,
    )
    a = remove_turkana(a, lon, lat, 6.0)
    a = paleo_edit(a, lon, lat, oc, rift, 10.0)
    img = Image.fromarray((a * 255 + 0.5).astype(np.uint8))
    save_jpg(img, out / "rift_bmng_4k.jpg")
    return img


def s2_stage(src: Path, out: Path, rift: Rift, reg: Image.Image) -> None:
    ref = crop_deg(reg, BMNG_REGION, PATCH)
    coarse = (
        Image.open(src / "s2/kanapoi_coarse_l10.jpg")
        .convert("RGB")
        .resize((4096, 4096), Image.Resampling.LANCZOS)
    )
    a = np.asarray(coarse).astype(np.float32) / 255.0
    lon, lat = lonlat_rows(0, 4096, 4096, 4096, PATCH)
    # today's lake and Kulal out (DEM masks), texture from the land 0.9 deg west
    modern = rift.sample(rift.modern, lon, lat, 0.0) > 0.5
    peaks = rift.sample(rift.peaks, lon, lat, 0.0) > 0.05
    hole = ndimage.binary_dilation(modern | peaks, iterations=6)
    small = Image.fromarray((a * 255).astype(np.uint8)).resize((1024, 1024), Image.Resampling.BOX)
    sh = np.asarray(Image.fromarray(hole.astype(np.uint8) * 255).resize((1024, 1024))) > 0
    fill = push_pull(np.asarray(small).astype(np.float32) / 255.0, sh)
    fill = (
        np.asarray(
            Image.fromarray((np.clip(fill, 0, 1) * 255).astype(np.uint8)).resize(
                (4096, 4096), Image.Resampling.BICUBIC
            )
        ).astype(np.float32)
        / 255.0
    )
    donor = np.roll(a, int(0.9 / 2.55 * 4096), axis=1)
    hf = donor - lowpass(donor, 12.0)
    soft = ndimage.gaussian_filter(hole.astype(np.float32), 8.0)[..., None]
    a = np.clip(a * (1 - soft) + (fill + hf) * soft, 0, 1)
    a = paleo_edit(a, lon, lat, np.zeros(lon.shape, np.float32), rift, 14.0)
    coarse_m = Image.fromarray((a * 255 + 0.5).astype(np.uint8))
    # large-scale colour from the (edited) Blue Marble, as bake_intro_assets.rift_maps does
    coarse_m = freq_match(coarse_m, ref, 65.0, 0.5)
    save_jpg(coarse_m, out / "rift_s2_coarse.jpg")
    fine = (
        Image.open(src / "s2/kanapoi_fine_l13.jpg")
        .convert("RGB")
        .resize((4096, 4096), Image.Resampling.LANCZOS)
    )
    # soften 10 m detail (modern dirt tracks, fences, huts) before the colour edit
    fine = Image.blend(fine, fine.filter(ImageFilter.MedianFilter(7)), 0.7)
    f = np.asarray(fine).astype(np.float32) / 255.0
    flon, flat = lonlat_rows(0, 4096, 4096, 4096, FINE)
    f = paleo_edit(f, flon, flat, np.zeros(flon.shape, np.float32), rift, 40.0)
    fine_m = Image.fromarray((f * 255 + 0.5).astype(np.uint8))
    fine_m = freq_match(fine_m, crop_deg(coarse_m, PATCH, FINE), 120.0, 0.0)
    save_jpg(fine_m, out / "rift_s2_fine.jpg")
    coarse_m.resize((1400, 1400)).save(src / "paleo/check_rift_coarse.jpg", quality=90)
    fine_m.resize((1400, 1400)).save(src / "paleo/check_rift_fine.jpg", quality=90)


def dem_stage(out: Path, rift: Rift) -> None:
    h = rift.h.copy()
    h[:, -1] = h[:, -2]
    h[-1, :] = h[-2, :]
    hm = Image.fromarray(h).resize((1025, 1025), Image.Resampling.BILINEAR)
    hq = np.clip(np.asarray(hm) * 16.0, 0, 65535).astype(np.uint16)
    rg = np.zeros((1025, 1025, 3), np.uint8)
    rg[..., 0] = hq >> 8
    rg[..., 1] = hq & 255
    Image.fromarray(rg).save(out / "rift_height.png")
    n = h.shape[0]
    lat_mid = math.radians((PATCH[1] + PATCH[3]) * 0.5)
    dx = (PATCH[2] - PATCH[0]) / n * 111320.0 * math.cos(lat_mid)
    dy = (PATCH[3] - PATCH[1]) / n * 110570.0
    gy, gx = np.gradient(h)
    nx, ny, nz = -gx / dx, gy / dy, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    water = np.clip(rift.lake + rift.river, 0.0, 1.0)
    nm = np.zeros((n, n, 3), np.uint8)
    nm[..., 0] = np.clip((nx / ln * 0.5 + 0.5) * 255, 0, 255)
    nm[..., 1] = np.clip((ny / ln * 0.5 + 0.5) * 255, 0, 255)
    nm[..., 2] = np.clip(water * 255, 0, 255)
    Image.fromarray(nm).save(out / "rift_normal.png")
    print("rift_height.png / rift_normal.png", float(h.min()), float(h.max()))


def main() -> None:
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    which = sys.argv[3] if len(sys.argv) > 3 else "all"
    rift = Rift(np.load(src / "rift_dem.npy"))
    old = src / "rift_dem_turkana_old.npy"
    if old.exists():
        h_old = np.load(old)
        TURKANA["old"] = (
            (34.4, 2.5, 37.0, 5.1),
            ndimage.binary_dilation(h_old < MODERN_TURKANA_M, iterations=3).astype(np.float32),
        )
    TURKANA["new"] = (
        PATCH,
        ndimage.binary_dilation(rift.modern > 0.5, iterations=3).astype(np.float32),
    )
    lon, lat = Rift.grid(rift.n)
    k = rift.sample(rift.lake, np.array([[KANAPOI[0]]]), np.array([[KANAPOI[1]]]), 0.0)
    kh = rift.sample(rift.h, np.array([[KANAPOI[0]]]), np.array([[KANAPOI[1]]]), 0.0)
    print("lake at Kanapoi", float(k[0, 0]), "ground m", float(kh[0, 0]))
    if which in ("all", "rift"):
        dem_stage(out, rift)
        reg = region_stage(src, out, rift)
        s2_stage(src, out, rift, reg)
    if which in ("all", "global"):
        global_stage(src, out, rift)


if __name__ == "__main__":
    main()
