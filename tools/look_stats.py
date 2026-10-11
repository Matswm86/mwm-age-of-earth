"""Compare the global look of game captures against reference screenshots.

Prints mean luminance, contrast (luminance standard deviation), mean saturation
and green share (pixels whose strongest channel is green) per image, then the
reference range and a PASS/FAIL per capture on contrast and saturation.

Usage: python3 tools/look_stats.py --ref DIR_OR_FILES... --cap FILES...
The reference images stay outside the repo (they belong to other games).
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def stats(path: Path) -> dict[str, float]:
    img = Image.open(path).convert("RGB").resize((480, 270))
    rgb = np.asarray(img, dtype=float) / 255.0
    hsv = np.asarray(img.convert("HSV"), dtype=float) / 255.0
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    return {
        "lum": float(lum.mean()),
        "contrast": float(lum.std()),
        "sat": float(hsv[..., 1].mean()),
        "green": float((np.argmax(rgb, axis=2) == 1).mean()),
    }


def expand(items: list[str]) -> list[Path]:
    out: list[Path] = []
    for it in items:
        p = Path(it)
        out += sorted(p.glob("*.png")) + sorted(p.glob("*.jpg")) if p.is_dir() else [p]
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", nargs="+", required=True)
    ap.add_argument("--cap", nargs="+", required=True)
    a = ap.parse_args()
    refs = {p: stats(p) for p in expand(a.ref)}
    for p, s in refs.items():
        print(f"ref  {p.name:28s} " + "  ".join(f"{k} {v:.3f}" for k, v in s.items()))
    lo = {k: min(s[k] for s in refs.values()) for k in ("contrast", "sat")}
    print(f"gate: contrast >= {lo['contrast']:.3f}, sat >= {lo['sat']:.3f} (lowest reference)")
    for p in expand(a.cap):
        s = stats(p)
        ok = s["contrast"] >= lo["contrast"] and s["sat"] >= lo["sat"]
        print(
            f"cap  {p.name:28s} "
            + "  ".join(f"{k} {v:.3f}" for k, v in s.items())
            + f"  {'PASS' if ok else 'FAIL'}"
        )


if __name__ == "__main__":
    main()
