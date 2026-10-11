"""Step 2 of the intro asset bake: turn the downloaded public sources into the textures in assets/intro/.

Sources (download list and licences: CREDITS.md, "Opening intro"), expected under <src>:
  bmng/world.topo.bathy.200412.3x21600x10800.jpg       NASA Blue Marble Next Generation, Dec 2004, 2 km/px
  bmng/world.topo.bathy.200412.3x21600x21600.C1.jpg    same, 500 m/px tile 0-90E, 0-90N
  bmng/world.topo.bathy.200412.3x21600x21600.C2.jpg    same, 500 m/px tile 0-90E, 0-90S
  bmng/gebco_08_rev_bath_21600x10800.png               NASA Visible Earth bathymetry (ocean mask)
  bmng/cloud_combined_8192.tif                         NASA Visible Earth Blue Marble clouds
  s2/coarse_l10.jpg  s2/fine_l13.jpg                   EOX Sentinel-2 cloudless 2016 mosaics (s2fetch.py)
  rift_dem.npy                                         Copernicus GLO-30 mosaic (bake_dem.py)
  stars/catalog.gz                                     Yale Bright Star Catalogue 5 (CDS V/50)

python3 tools/intro/bake_intro_assets.py <src> assets/intro
"""

import gzip
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

Image.MAX_IMAGE_PIXELS = None

# lon0, lat0, lon1, lat1 (degrees). Keep in sync with scripts/IntroConfig.gd.
BMNG_REGION = (27.5, -4.7, 44.5, 12.3)
PATCH = (34.4, 2.5, 37.0, 5.1)  # S2 coarse + DEM (bake_dem.py)
FINE = (35.625, 3.825, 35.975, 4.175)  # S2 fine
LAKE_LEVEL_M = 362.0


def save_jpg(img: Image.Image, path: Path, q: int = 93) -> None:
    img.save(path, quality=q, subsampling=0)
    print(path.name, img.size)


def global_maps(src: Path, out: Path) -> None:
    g = Image.open(src / "bmng/world.topo.bathy.200412.3x21600x10800.jpg").convert("RGB")
    save_jpg(g.resize((16384, 8192), Image.Resampling.LANCZOS), out / "earth_albedo_16k.jpg")
    save_jpg(g.resize((8192, 4096), Image.Resampling.LANCZOS), out / "earth_albedo_8k.jpg")
    b = Image.open(src / "bmng/gebco_08_rev_bath_21600x10800.png").convert("L")
    b = b.resize((8192, 4096), Image.Resampling.BOX)
    a = np.asarray(b).astype(np.float32)
    ocean = np.clip((252.0 - a) / 6.0, 0.0, 1.0)  # land = 255, ocean depth < 255
    Image.fromarray((ocean * 255).astype(np.uint8)).save(out / "earth_ocean_8k.png")
    print("earth_ocean_8k.png")
    c = Image.open(src / "bmng/cloud_combined_8192.tif").convert("L")
    save_jpg(c, out / "earth_clouds_8k.jpg", 95)


def region_bmng(src: Path) -> Image.Image:
    """500 m/px Blue Marble crop of BMNG_REGION from the C1 (north) and C2 (south) tiles."""
    lon0, lat0, lon1, lat1 = BMNG_REGION
    ppd = 240.0
    c1 = Image.open(src / "bmng/world.topo.bathy.200412.3x21600x21600.C1.jpg")
    c2 = Image.open(src / "bmng/world.topo.bathy.200412.3x21600x21600.C2.jpg")
    x0, x1 = round(lon0 * ppd), round(lon1 * ppd)
    north = c1.crop((x0, round((90 - lat1) * ppd), x1, 21600))
    south = c2.crop((x0, 0, x1, round(-lat0 * ppd)))
    img = Image.new("RGB", (x1 - x0, north.height + south.height))
    img.paste(north, (0, 0))
    img.paste(south, (0, north.height))
    return img


def crop_deg(img: Image.Image, box: tuple, sub: tuple) -> Image.Image:
    lon0, lat0, lon1, lat1 = box
    w, h = img.size
    sx = w / (lon1 - lon0)
    sy = h / (lat1 - lat0)
    return img.crop(
        (
            round((sub[0] - lon0) * sx),
            round((lat1 - sub[3]) * sy),
            round((sub[2] - lon0) * sx),
            round((lat1 - sub[1]) * sy),
        )
    )


def lowpass(a: np.ndarray, sigma_px: float) -> np.ndarray:
    """Gaussian low-pass of an HxWx3 float image, done on a downsampled copy (large sigmas)."""
    h, w = a.shape[:2]
    f = max(1, int(sigma_px / 4))
    small = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).resize(
        (max(1, w // f), max(1, h // f)), Image.Resampling.BOX
    )
    small = small.filter(ImageFilter.GaussianBlur(sigma_px / f))
    return np.asarray(small.resize((w, h), Image.Resampling.BILINEAR)).astype(np.float32)


def edge_weight(h: int, w: int, centre: float) -> np.ndarray:
    """1 at the box edges, `centre` in the middle (square falloff)."""
    y, x = np.mgrid[0:h, 0:w]
    r = np.maximum(np.abs(x / (w - 1) - 0.5), np.abs(y / (h - 1) - 0.5)) * 2.0
    t = np.clip((r - 0.5) / 0.45, 0.0, 1.0)
    t = t * t * (3 - 2 * t)
    return (centre + (1.0 - centre) * t)[..., None].astype(np.float32)


def freq_match(img: Image.Image, ref: Image.Image, sigma_px: float, centre: float) -> Image.Image:
    """Keep img's detail, take its large-scale colour from ref (fully at the edges, `centre` in the
    middle): no seam where the layer meets the coarser one."""
    a = np.asarray(img).astype(np.float32)
    r = np.asarray(ref.resize(img.size, Image.Resampling.BICUBIC)).astype(np.float32)
    la = lowpass(a, sigma_px)
    lr = lowpass(r, sigma_px)
    wgt = edge_weight(a.shape[0], a.shape[1], centre)
    out = a + (lr - la) * wgt
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def match_colour(img: Image.Image, ref: Image.Image) -> tuple:
    """Per-channel mean/std transfer (on blurred copies) so S2 meets Blue Marble without a seam."""
    a = np.asarray(img.resize(ref.size, Image.Resampling.BOX)).astype(np.float32)
    r = np.asarray(ref).astype(np.float32)
    gain = r.std(axis=(0, 1)) / np.maximum(a.std(axis=(0, 1)), 1.0)
    off = r.mean(axis=(0, 1)) - a.mean(axis=(0, 1)) * gain
    return gain, off


def apply_colour(img: Image.Image, gain: np.ndarray, off: np.ndarray, amount: float) -> Image.Image:
    a = np.asarray(img).astype(np.float32)
    m = a * gain + off
    a = a + (m - a) * amount
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def rift_maps(src: Path, out: Path) -> None:
    reg = region_bmng(src)
    save_jpg(reg.resize((4096, 4096), Image.Resampling.LANCZOS), out / "rift_bmng_4k.jpg")
    ref = crop_deg(reg, BMNG_REGION, PATCH)  # ~624 px of Blue Marble under the patch
    coarse = Image.open(src / "s2/coarse_l10.jpg").convert("RGB")
    gain, off = match_colour(coarse, ref)
    print("S2 -> BMNG gain", gain.round(3), "offset", off.round(1))
    # global grade 70 % of the way to Blue Marble, then large-scale colour (> ~5 km) from Blue
    # Marble: all of it at the patch edges, half in the middle, so no seam shows from orbit
    coarse_m = apply_colour(coarse, gain, off, 0.7)
    coarse_m = freq_match(coarse_m, ref, 65.0, 0.5)
    save_jpg(coarse_m.resize((4096, 4096), Image.Resampling.LANCZOS), out / "rift_s2_coarse.jpg")
    fine = apply_colour(Image.open(src / "s2/fine_l13.jpg").convert("RGB"), gain, off, 0.7)
    fine_ref = crop_deg(coarse_m, PATCH, FINE)
    fine = freq_match(fine, fine_ref, 120.0, 0.0)
    save_jpg(fine.resize((4096, 4096), Image.Resampling.LANCZOS), out / "rift_s2_fine.jpg")
    # DEM: height (16 bit in R + G) for the mesh, normals + lake mask for shading
    h = np.load(src / "rift_dem.npy")
    h[:, -1] = h[:, -2]
    h[-1, :] = h[-2, :]
    hm = Image.fromarray(h).resize((1025, 1025), Image.Resampling.BILINEAR)
    hq = np.clip(np.asarray(hm) * 16.0, 0, 65535).astype(np.uint16)  # 1/16 m steps
    rg = np.zeros((1025, 1025, 3), np.uint8)
    rg[..., 0] = hq >> 8
    rg[..., 1] = hq & 255
    Image.fromarray(rg).save(out / "rift_height.png")
    print("rift_height.png", float(h.min()), float(h.max()))
    n = h.shape[0]
    lat_mid = math.radians((PATCH[1] + PATCH[3]) * 0.5)
    dx = (PATCH[2] - PATCH[0]) / n * 111320.0 * math.cos(lat_mid)
    dy = (PATCH[3] - PATCH[1]) / n * 110570.0
    gy, gx = np.gradient(h)
    # tangent frame: +x east, +y north (image rows run south, so north slope = -gy)
    nx = -gx / dx
    ny = gy / dy
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    lake = (np.abs(h - LAKE_LEVEL_M) < 0.6).astype(np.float32)
    lake = np.asarray(
        Image.fromarray((lake * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))
    )
    nm = np.zeros((n, n, 3), np.uint8)
    nm[..., 0] = np.clip((nx / ln * 0.5 + 0.5) * 255, 0, 255)
    nm[..., 1] = np.clip((ny / ln * 0.5 + 0.5) * 255, 0, 255)
    nm[..., 2] = lake
    Image.fromarray(nm).save(out / "rift_normal.png")
    print("rift_normal.png", nm.shape)


def stars(src: Path, out: Path) -> None:
    """Yale BSC5 -> 2 RGBA pixels per star: RA (16 bit), Dec (16 bit); V mag, B-V."""
    rows = []
    with gzip.open(src / "stars/catalog.gz", "rt", encoding="latin-1") as f:
        for line in f:
            if len(line) < 114 or not line[75:77].strip() or not line[102:107].strip():
                continue
            ra = (int(line[75:77]) + int(line[77:79]) / 60.0 + float(line[79:83]) / 3600.0) * 15.0
            dec = int(line[84:86]) + int(line[86:88]) / 60.0 + int(line[88:90]) / 3600.0
            if line[83] == "-":
                dec = -dec
            vmag = float(line[102:107])
            bv = float(line[109:114]) if line[109:114].strip() else 0.6
            rows.append((ra, dec, vmag, bv))
    w = 256
    hgt = math.ceil(len(rows) * 2 / w)
    px = np.zeros((hgt * w, 4), np.uint8)
    for i, (ra, dec, vmag, bv) in enumerate(rows):
        r = int(round(ra / 360.0 * 65535)) & 65535
        d = int(round((dec + 90.0) / 180.0 * 65535))
        px[2 * i] = (r >> 8, r & 255, d >> 8, d & 255)
        px[2 * i + 1] = (
            int(np.clip((vmag + 2.0) * 25.0, 0, 255)),
            int(np.clip((bv + 0.5) * 100.0, 0, 255)),
            0,
            255,
        )
    Image.fromarray(px.reshape(hgt, w, 4), "RGBA").save(out / "stars_bsc5.png")
    print("stars_bsc5.png", len(rows), "stars")


def main(src: Path, out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    which = sys.argv[3] if len(sys.argv) > 3 else "all"
    if which in ("all", "global"):
        global_maps(src, out)
    if which in ("all", "rift"):
        rift_maps(src, out)
    if which in ("all", "stars"):
        stars(src, out)


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
