"""Cut, clean, normalise and encode every game sound from tools/spec.py; measure each result.

python3 master.py <scratch_root> <game_root> [only_prefix]
Writes <game_root>/assets/... files, <scratch_root>/work/manifest.json and spectrogram PNGs.
"""

import json
import re
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import spec  # noqa: E402

SR = 44100
TARGET = {"amb": -24.0, "sfx": -18.0, "animal": -18.0, "voice": -20.0, "ui": -18.0, "intro": -24.0}
TP_MAX = -1.0


def run(cmd: list[str]) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(" ".join(cmd) + "\n" + r.stderr[-2000:])
    return r.stderr


def read_wav(p: Path) -> np.ndarray:
    with wave.open(str(p)) as w:
        n = w.getnframes()
        ch = w.getnchannels()
        x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float64) / 32768.0
    return x.reshape(-1, ch)


def write_wav(p: Path, x: np.ndarray) -> None:
    x = np.clip(x, -1.0, 32767 / 32768)
    with wave.open(str(p), "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32768.0).astype("<i2").tobytes())


def loudness(p: Path) -> tuple[float, float]:
    """Integrated LUFS and true peak (dBTP). Short clips are padded with silence (gated out)."""
    err = run(
        [
            "ffmpeg",
            "-hide_banner",
            "-nostats",
            "-i",
            str(p),
            "-af",
            "apad=pad_dur=1.5,ebur128=peak=true",
            "-f",
            "null",
            "-",
        ]
    )
    i = re.findall(r"I:\s+(-?[\d.]+|-inf) LUFS", err)
    tp = re.findall(r"Peak:\s+(-?[\d.]+|-inf) dBFS", err)
    lufs = float(i[-1]) if i and i[-1] != "-inf" else -99.0
    peak = float(tp[-1]) if tp and tp[-1] != "-inf" else -99.0
    return lufs, peak


def loopify(x: np.ndarray, xf: float) -> np.ndarray:
    k = int(xf * SR)
    body = x[: len(x) - k].copy()
    tail = x[len(x) - k :]
    g = np.linspace(0, 1, k)[:, None]
    body[:k] = body[:k] * np.sqrt(g) + tail * np.sqrt(1 - g)
    return body


def analyse(x: np.ndarray, loop: bool) -> dict:
    m = x.mean(1)
    win = int(0.05 * SR)
    nwin = max(1, len(m) // win)
    rms = np.sqrt(np.mean(m[: nwin * win].reshape(nwin, win) ** 2, axis=1) + 1e-12)
    db = 20 * np.log10(rms)
    spec_ = np.abs(np.fft.rfft(m * np.hanning(len(m)))) ** 2
    fr = np.fft.rfftfreq(len(m), 1 / SR)
    tot = spec_.sum() + 1e-12
    bands = {
        "lt200": float(spec_[fr < 200].sum() / tot),
        "200_2k": float(spec_[(fr >= 200) & (fr < 2000)].sum() / tot),
        "2k_8k": float(spec_[(fr >= 2000) & (fr < 8000)].sum() / tot),
        "gt8k": float(spec_[fr >= 8000].sum() / tot),
    }
    out = {
        "dur": round(len(m) / SR, 2),
        "silent_pct": round(float(np.mean(db < -50.0)) * 100, 1),
        "clipped": int(np.sum(np.abs(x) >= 0.999)),
        "centroid_hz": int((fr * spec_).sum() / tot),
        "bands": {k: round(v, 3) for k, v in bands.items()},
        "loud_span_s": round(float(np.sum(db > db.max() - 20.0)) * 0.05, 2),
    }
    if loop:
        # seam: sample jump at the wrap vs the median jump, and RMS of 100 ms either side
        jump = float(np.max(np.abs(x[0] - x[-1])))
        med = float(np.median(np.abs(np.diff(m)))) + 1e-9
        a = np.sqrt(np.mean(x[-4410:] ** 2))
        b = np.sqrt(np.mean(x[:4410] ** 2))
        out["seam_jump_vs_median"] = round(jump / med, 1)
        out["seam_rms_db"] = round(float(20 * np.log10((a + 1e-9) / (b + 1e-9))), 2)
    return out


def build(e: dict, scratch: Path, game: Path) -> dict:
    src = (
        scratch / "dl" / e["src"]
        if not e["src"].startswith("synth/")
        else scratch / "work" / e["src"]
    )
    tmp = scratch / "work" / "tmp"
    tmp.mkdir(parents=True, exist_ok=True)
    stem = e["out"].replace("/", "__")
    raw = tmp / f"{stem}_raw.wav"
    chain = [c for c in [e.get("chain", "")] if c]
    p = e.get("pitch", 1.0)
    if p != 1.0:
        chain.append(f"asetrate={SR}*{p},aresample={SR}")
    ch = "1" if e.get("mono", True) else "2"
    cmd = ["ffmpeg", "-hide_banner", "-y", "-v", "error"]
    if "start" in e:
        cmd += ["-ss", str(e["start"])]
    if "dur" in e:
        cmd += ["-t", str(e["dur"])]
    cmd += ["-i", str(src)]
    if chain:
        cmd += ["-af", ",".join(chain)]
    cmd += ["-ac", ch, "-ar", str(SR), "-c:a", "pcm_s16le", str(raw)]
    run(cmd)
    x = read_wav(raw)
    fi, fo = e.get("fade", (0.01, 0.05))
    if e.get("loop"):
        x = loopify(x, e.get("xfade", 3.0))
    else:
        a = int(fi * SR)
        b = int(fo * SR)
        if a:
            x[:a] *= np.linspace(0, 1, a)[:, None]
        if b:
            x[-b:] *= np.linspace(1, 0, b)[:, None] ** 1.5
    write_wav(raw, x / (np.max(np.abs(x)) + 1e-9) * 0.5)
    target = TARGET[e["cat"]] + e.get("trim_db", 0.0)
    lufs, tp = loudness(raw)
    gain = target - lufs
    norm = tmp / f"{stem}_norm.wav"
    # gain, then a true-peak safe limiter only if needed
    af = f"volume={gain:.2f}dB"
    if tp + gain > TP_MAX:
        af += ",alimiter=limit=0.79:attack=1:release=40:level=disabled"
    run(
        [
            "ffmpeg",
            "-hide_banner",
            "-y",
            "-v",
            "error",
            "-i",
            str(raw),
            "-af",
            af,
            "-ar",
            str(SR),
            "-c:a",
            "pcm_s16le",
            str(norm),
        ]
    )
    lufs2, tp2 = loudness(norm)
    x2 = read_wav(norm)
    ext = "ogg" if e.get("ogg", False) or len(x2) / SR > 4.0 or e.get("loop") else "wav"
    dest = game / f"{e['dir']}/{e['out']}.{ext}"
    dest.parent.mkdir(parents=True, exist_ok=True)
    for old in dest.parent.glob(Path(e["out"]).name + ".*"):
        if old.suffix in (".ogg", ".wav") and old != dest:
            old.unlink()
    if ext == "ogg":
        q = "4" if ch == "2" else "3"
        run(
            [
                "ffmpeg",
                "-hide_banner",
                "-y",
                "-v",
                "error",
                "-i",
                str(norm),
                "-c:a",
                "libvorbis",
                "-q:a",
                q,
                "-ar",
                str(SR),
                str(dest),
            ]
        )
    else:
        run(
            [
                "ffmpeg",
                "-hide_banner",
                "-y",
                "-v",
                "error",
                "-i",
                str(norm),
                "-c:a",
                "pcm_s16le",
                "-ar",
                str(SR),
                str(dest),
            ]
        )
    lufs3, tp3 = loudness(dest)
    info = analyse(x2, bool(e.get("loop")))
    spec_png = scratch / "work" / "specout" / f"{stem}.png"
    spec_png.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            "ffmpeg",
            "-hide_banner",
            "-y",
            "-v",
            "error",
            "-i",
            str(dest),
            "-lavfi",
            "showspectrumpic=s=800x200:legend=0:scale=log:stop=10000",
            str(spec_png),
        ]
    )
    rel = str(dest.relative_to(game))
    return {
        "file": rel,
        "src": e["src"],
        "cat": e["cat"],
        "what": e["what"],
        "lufs": lufs3,
        "tp": tp3,
        "target": target,
        "ext": ext,
        "channels": int(ch),
        **info,
        "loop": bool(e.get("loop")),
    }


def main() -> None:
    scratch = Path(sys.argv[1])
    game = Path(sys.argv[2])
    only = sys.argv[3] if len(sys.argv) > 3 else ""
    man_p = scratch / "work" / "manifest.json"
    man = json.loads(man_p.read_text()) if man_p.exists() else {}
    for e in spec.ENTRIES:
        key = f"{e['dir']}/{e['out']}"
        if only and not key.startswith(only) and not e["out"].startswith(only):
            continue
        try:
            r = build(e, scratch, game)
        except Exception as ex:  # report and go on with the rest
            print("FAIL", key, str(ex)[:400])
            continue
        man[key] = r
        print(
            f"{r['file']:52s} {r['dur']:6.2f}s {r['lufs']:6.1f} LUFS tp {r['tp']:5.1f} "
            f"sil {r['silent_pct']:4.1f}% clip {r['clipped']} c {r['centroid_hz']}"
            + (f" seam {r['seam_jump_vs_median']}x {r['seam_rms_db']}dB" if r["loop"] else "")
        )
    man_p.write_text(json.dumps(man, indent=1))


if __name__ == "__main__":
    main()
