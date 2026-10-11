"""Log-frequency spectrogram PNG (50 Hz-16 kHz) with a waveform strip and second ticks.

python3 spectro.py out.png file1 [file2 ...]   (files stacked vertically, label = file name)
"""

import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

SR = 22050
W = 1400
H = 220


def load(p: str) -> np.ndarray:
    r = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", p, "-ac", "1", "-ar", str(SR), "-f", "s16le", "-"],
        capture_output=True,
        check=True,
    )
    return np.frombuffer(r.stdout, "<i2").astype(np.float64) / 32768.0


def panel(p: str) -> Image.Image:
    x = load(p)
    dur = len(x) / SR
    n = 1024
    hop = max(64, (len(x) - n) // W)
    frames = max(1, (len(x) - n) // hop)
    win = np.hanning(n)
    idx = np.arange(n)[None, :] + hop * np.arange(frames)[:, None]
    S = np.abs(np.fft.rfft(x[idx] * win, axis=1)) + 1e-9
    f = np.fft.rfftfreq(n, 1 / SR)
    logf = np.geomspace(50, 11000, H)
    cols = np.stack([np.interp(logf, f, s) for s in S], 1)
    db = 20 * np.log10(cols)
    db = np.clip((db - (db.max() - 80)) / 80, 0, 1)
    img = (db[::-1] * 255).astype(np.uint8)
    im = Image.fromarray(img).resize((W, H))
    rgb = Image.merge(
        "RGB", (im, im.point(lambda v: int(v * 0.8)), im.point(lambda v: int(v * 0.3)))
    )
    canvas = Image.new("RGB", (W, H + 70), (0, 0, 0))
    canvas.paste(rgb, (0, 20))
    d = ImageDraw.Draw(canvas)
    d.text((4, 2), f"{p.split('/')[-1]}  {dur:.2f}s", fill=(255, 255, 255))
    # frequency guides
    for hz in [100, 500, 1000, 2000, 5000, 10000]:
        y = 20 + H - int(np.log(hz / 50) / np.log(11000 / 50) * H)
        d.line([(0, y), (12, y)], fill=(0, 255, 0))
        d.text((14, y - 6), str(hz), fill=(0, 255, 0))
    # waveform
    env = np.abs(x)
    seg = max(1, len(env) // W)
    pk = env[: seg * W].reshape(W, seg).max(1) if len(env) >= W else np.pad(env, (0, W - len(env)))
    for i, v in enumerate(pk):
        d.line([(i, H + 45 - int(v * 24)), (i, H + 45 + int(v * 24))], fill=(80, 160, 255))
    step = 1 if dur < 15 else 5 if dur < 80 else 20
    for s in np.arange(0, dur, step):
        xx = int(s / dur * W)
        d.line([(xx, 20 + H), (xx, 20 + H + 6)], fill=(255, 255, 0))
        d.text((xx + 2, 20 + H + 6), f"{s:g}", fill=(255, 255, 0))
    return canvas


def main() -> None:
    ims = [panel(p) for p in sys.argv[2:]]
    out = Image.new("RGB", (W, sum(i.height for i in ims)))
    y = 0
    for i in ims:
        out.paste(i, (0, y))
        y += i.height
    out.save(sys.argv[1])


if __name__ == "__main__":
    main()
