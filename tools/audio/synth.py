"""Procedural sounds for Age of Earth (made for the project, CC0). numpy only.

Writes 44.1 kHz mono/stereo float WAVs into the output dir; master.py normalises and encodes.
Usage: python3 -I synth.py <out_dir>
"""

import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
RNG = np.random.default_rng(4200)


def save(path: Path, x: np.ndarray) -> None:
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = x[:, None]
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * 0.89
    pcm = (x * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def t_axis(sec: float) -> np.ndarray:
    return np.arange(int(sec * SR)) / SR


def noise(sec: float) -> np.ndarray:
    return RNG.standard_normal(int(sec * SR))


def pink(sec: float) -> np.ndarray:
    n = int(sec * SR)
    f = np.fft.rfft(RNG.standard_normal(n))
    k = np.arange(len(f))
    k[0] = 1
    return np.fft.irfft(f / np.sqrt(k), n)


def brown(sec: float) -> np.ndarray:
    n = int(sec * SR)
    f = np.fft.rfft(RNG.standard_normal(n))
    k = np.arange(len(f)).astype(float)
    k[0] = 1.0
    return np.fft.irfft(f / k, n)


def band(x: np.ndarray, lo: float, hi: float, soft: float = 0.25) -> np.ndarray:
    """FFT band-pass with soft (log-domain) edges."""
    n = len(x)
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(n, 1.0 / SR)
    fr[0] = 1e-3
    lf = np.log(fr)
    g = np.ones_like(fr)
    if lo > 0:
        g *= 1.0 / (1.0 + np.exp(-(lf - np.log(lo)) / soft))
    if hi < SR / 2:
        g *= 1.0 / (1.0 + np.exp((lf - np.log(hi)) / soft))
    return np.fft.irfft(f * g, n)


def sweep_band(x: np.ndarray, lo0: float, lo1: float, bw_oct: float, steps: int = 48) -> np.ndarray:
    """Time-varying band-pass by overlap-add of short FFT blocks (centre glides lo0 -> lo1)."""
    n = len(x)
    out = np.zeros(n)
    seg = n // steps
    win_len = seg * 2
    win = np.hanning(win_len)
    for s in range(steps + 1):
        a = s * seg - seg // 2
        lo_i = max(a, 0)
        hi_i = min(a + win_len, n)
        if hi_i <= lo_i:
            continue
        part = x[lo_i:hi_i] * win[lo_i - a : hi_i - a]
        c = lo0 * (lo1 / lo0) ** (s / steps)
        out[lo_i:hi_i] += band(part, c / 2 ** (bw_oct / 2), c * 2 ** (bw_oct / 2))
    return out


def env_ar(n: int, att: float, rel: float, shape: float = 2.0) -> np.ndarray:
    t = np.arange(n) / SR
    a = np.clip(t / max(att, 1e-4), 0, 1)
    r = np.exp(-np.maximum(t - att, 0) / max(rel, 1e-4) * shape)
    return a * r


def fade(x: np.ndarray, fin: float, fout: float) -> np.ndarray:
    x = x.copy()
    a = int(fin * SR)
    b = int(fout * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a) ** 2
    if b:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def place(dst: np.ndarray, src: np.ndarray, at_s: float, gain: float = 1.0) -> None:
    i = int(at_s * SR)
    j = min(len(dst), i + len(src))
    if i < len(dst):
        dst[i:j] += src[: j - i] * gain


def loopify(x: np.ndarray, xf: float) -> np.ndarray:
    """Seamless loop: the last xf seconds are cross-faded (equal power) into the start."""
    k = int(xf * SR)
    body = x[: len(x) - k].copy()
    tail = x[len(x) - k :]
    g = np.linspace(0, 1, k)
    body[:k] = body[:k] * np.sqrt(g) + tail * np.sqrt(1 - g)
    return body


def modal(
    freqs, decays, amps, sec: float, click: float = 0.3, click_band=(2000, 9000)
) -> np.ndarray:
    t = t_axis(sec)
    y = np.zeros_like(t)
    for f, d, a in zip(freqs, decays, amps):
        y += a * np.sin(2 * np.pi * f * t + RNG.uniform(0, 6.28)) * np.exp(-t / d)
    c = band(noise(sec), *click_band) * np.exp(-t / 0.004)
    return y + click * c / (np.max(np.abs(c)) + 1e-9) * np.max(np.abs(y))


# ---------------- intro ----------------


def space_hum() -> np.ndarray:
    sec = 32.0
    t = t_axis(sec)
    y = np.zeros_like(t)
    for f, a, lfo in [
        (41.2, 1.0, 0.05),
        (55.0, 0.8, 0.071),
        (61.74, 0.5, 0.043),
        (82.4, 0.35, 0.09),
    ]:
        # LFO periods divide the loop length so the loop is seamless before the cross-fade
        y += (
            a
            * np.sin(2 * np.pi * f * t)
            * (0.75 + 0.25 * np.sin(2 * np.pi * round(lfo * sec) / sec * t))
        )
    y += 0.6 * band(brown(sec), 25, 180)
    air = band(pink(sec), 300, 1400) * (0.5 + 0.5 * np.sin(2 * np.pi * 2 / sec * t))
    y += 0.08 * air / (np.max(np.abs(air)) + 1e-9) * np.max(np.abs(y))
    return loopify(np.stack([y, np.roll(y, 1103)], 1).mean(1), 4.0)


def rise() -> np.ndarray:
    sec = 28.0
    t = t_axis(sec)
    f0 = 98.0 * (2.0 ** (t / sec * 1.0))  # one octave up over the shot
    ph = 2 * np.pi * np.cumsum(f0) / SR
    y = np.zeros_like(t)
    for h, a in [(1, 1.0), (2, 0.45), (3, 0.22), (4, 0.12), (6, 0.05)]:
        y += a * np.sin(h * ph)
    y += 0.3 * np.sin(1.5 * ph)  # a fifth for warmth
    shimmer = np.sin(8 * ph) * 0.04 * (t / sec) ** 2
    e = np.clip(t / 10.0, 0, 1) ** 1.5 * np.clip((sec - t) / 5.0, 0, 1)
    return (y + shimmer) * e


def dive_wind() -> np.ndarray:
    sec = 22.0
    t = t_axis(sec)
    x = pink(sec)
    y = sweep_band(x, 180.0, 1100.0, 1.6)
    gust = 0.75 + 0.25 * np.sin(2 * np.pi * 0.31 * t) * np.sin(2 * np.pi * 0.07 * t + 1.0)
    e = (np.clip(t / 16.0, 0, 1) ** 2.2) * np.clip((sec - t) / 2.5, 0, 1)
    rumble = band(brown(sec), 20, 120) * (np.clip(t / 18.0, 0, 1) ** 2)
    y = y / (np.max(np.abs(y)) + 1e-9) + 0.5 * rumble / (np.max(np.abs(rumble)) + 1e-9)
    return y * gust * e


def cloud_whoosh() -> np.ndarray:
    sec = 5.5
    t = t_axis(sec)
    y = sweep_band(noise(sec), 300.0, 2400.0, 1.2, 32) + 0.6 * band(pink(sec), 60, 400)
    peak = 2.4
    e = np.where(t < peak, (t / peak) ** 3, np.exp(-(t - peak) / 0.9))
    return y * e


# ---------------- ambience ----------------


def wind_grass() -> np.ndarray:
    """Soft wind in dry grass: pink noise 400-4000 Hz with slow gusts, a seamless 40 s loop."""
    sec = 44.0
    t = t_axis(sec)
    y = band(pink(sec), 350, 4200, 0.35)
    g = np.zeros_like(t)
    for f, a in [(1 / 11.0, 0.35), (1 / 4.0, 0.15), (1 / 22.0, 0.25)]:
        g += a * np.sin(2 * np.pi * f * t + RNG.uniform(0, 6.28))
    g = 0.75 + 0.5 * g / (np.max(np.abs(g)) + 1e-9)  # gusts between 0.25 and 1.25, never silent
    y *= g
    hiss = band(noise(sec), 3000, 9000) * 0.12 * g
    y = y / np.max(np.abs(y)) + hiss / (np.max(np.abs(hiss)) + 1e-9) * 0.15
    left = y
    right = np.roll(y, 397) * 0.9 + 0.1 * band(pink(sec), 350, 4200)
    return np.stack([loopify(left, 4.0), loopify(right, 4.0)], 1)


def lake_lap() -> np.ndarray:
    """Small waves lapping on a sand-and-reed shore: irregular low sloshes with a fizzing tail."""
    sec = 36.0
    out = np.zeros(int(sec * SR))
    at = 0.3
    while at < sec - 2.0:
        d = RNG.uniform(0.9, 1.6)
        n = int(d * SR)
        body = band(noise(d), RNG.uniform(140, 220), RNG.uniform(700, 1100))
        e = env_ar(n, RNG.uniform(0.12, 0.3), d * 0.6, 2.5)
        fizz_d = d + 0.6
        fizz = band(noise(fizz_d), 1500, 4500) * env_ar(int(fizz_d * SR), 0.35, fizz_d * 0.7, 3.0)
        grains = (RNG.random(int(fizz_d * SR)) < 0.004).astype(float)
        fizz *= 0.4 + 2.5 * np.convolve(grains, np.hanning(60), "same")
        place(out, body * e, at, RNG.uniform(0.6, 1.0))
        place(out, fizz, at + 0.15, RNG.uniform(0.03, 0.06))
        at += RNG.uniform(1.4, 3.6)
    bed = band(pink(sec), 80, 600) * 0.05
    out = out / np.max(np.abs(out)) + bed / np.max(np.abs(bed)) * 0.12
    st = np.stack([out, np.roll(out, 2205)], 1)
    return np.stack([loopify(st[:, 0], 3.0), loopify(st[:, 1], 3.0)], 1)


# ---------------- foley ----------------


def rustle(sec: float, lo: float = 1800, hi: float = 9000, density: float = 0.05) -> np.ndarray:
    n = int(sec * SR)
    grains = (RNG.random(n) < density * 0.01).astype(float) * RNG.uniform(0.3, 1.0, n)
    k = np.hanning(int(0.006 * SR))
    tex = np.convolve(grains, k, "same") * noise(sec)
    y = band(tex, lo, hi) + 0.15 * band(noise(sec), lo, hi)
    return y * env_ar(n, sec * 0.25, sec * 0.6, 2.2)


def knock(base: float, sec: float = 0.35) -> np.ndarray:
    r = RNG.uniform(0.92, 1.08)
    fr = [base * r, base * 1.61 * r, base * 2.37 * r, base * 3.3 * r]
    return modal(fr, [0.03, 0.022, 0.016, 0.01], [1.0, 0.6, 0.4, 0.25], sec, click=0.5)


def stone_knock() -> np.ndarray:
    a = knock(RNG.uniform(1700, 2300), 0.3)
    b = band(noise(0.3), 400, 2000) * env_ar(int(0.3 * SR), 0.001, 0.05, 2.0) * 0.3
    return a / np.max(np.abs(a)) + b


def knap_crack() -> np.ndarray:
    """Two sharp stone strikes, a flake ticks off after the second."""
    out = np.zeros(int(1.2 * SR))
    for at, base in [(0.02, 2400), (0.42, 2700)]:
        k = knock(base, 0.35)
        c = band(noise(0.08), 3000, 14000) * np.exp(-t_axis(0.08) / 0.006)
        place(out, k / np.max(np.abs(k)), at)
        place(out, c / np.max(np.abs(c)) * 0.8, at)
    tick = knock(5200, 0.12)
    place(out, tick / np.max(np.abs(tick)) * 0.35, 0.62)
    return out


def wood_snap() -> np.ndarray:
    sec = 0.6
    n = int(sec * SR)
    out = np.zeros(n)
    # fibres tearing: a quick train of micro-cracks, then the break
    at = 0.0
    for _ in range(int(RNG.integers(4, 8))):
        c = band(noise(0.01), 1500, 8000) * np.hanning(int(0.01 * SR))
        place(out, c, at, RNG.uniform(0.15, 0.4))
        at += RNG.uniform(0.006, 0.02)
    brk = band(noise(0.25), 500, 6000) * env_ar(int(0.25 * SR), 0.0008, 0.07, 3.0)
    body = modal(
        [RNG.uniform(380, 520), RNG.uniform(900, 1200)], [0.02, 0.012], [1.0, 0.5], 0.3, click=0.0
    )
    place(out, brk / np.max(np.abs(brk)), at)
    place(out, body / np.max(np.abs(body)) * 0.5, at)
    place(out, rustle(0.3, 2500, 9000) * 0.25, at + 0.02)
    return out


def bark_scrape() -> np.ndarray:
    sec = RNG.uniform(0.28, 0.42)
    t = t_axis(sec)
    stick = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * RNG.uniform(28, 55) * t))
    y = band(noise(sec), 900, 5000) * (0.35 + 0.65 * stick)
    return y * env_ar(len(t), sec * 0.3, sec * 0.5, 2.0)


def footstep() -> np.ndarray:
    sec = 0.32
    th = modal([RNG.uniform(70, 95)], [0.05], [1.0], sec, click=0.0)
    r = rustle(0.25, 1500, 7000, 0.08)
    out = th / np.max(np.abs(th)) * 0.5
    place(out, r / np.max(np.abs(r)) * 0.6, 0.0)
    return out


def land_thud() -> np.ndarray:
    sec = 0.9
    t = t_axis(sec)
    f = 75 * np.exp(-t / 0.12) + 42
    th = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.13)
    dirt = band(noise(sec), 200, 2500) * np.exp(-t / 0.05)
    out = th + 0.35 * dirt / np.max(np.abs(dirt))
    r = rustle(0.5, 1800, 8000, 0.08)
    place(out, r / np.max(np.abs(r)) * 0.35, 0.03)
    return out


def build_place() -> np.ndarray:
    """Branches set down on the ground: two wooden knocks and a rustle of leaves."""
    out = np.zeros(int(0.9 * SR))
    for at in [0.0, RNG.uniform(0.12, 0.2)]:
        k = knock(RNG.uniform(420, 620), 0.3)
        place(out, k / np.max(np.abs(k)), at, RNG.uniform(0.6, 1.0))
    r = rustle(0.6, 1500, 8000, 0.07)
    place(out, r / np.max(np.abs(r)) * 0.5, 0.05)
    return out


def build_knock() -> np.ndarray:
    k = knock(RNG.uniform(380, 700), 0.28)
    out = k / np.max(np.abs(k))
    if RNG.random() < 0.5:
        r = rustle(0.25, 2000, 8000, 0.06)
        place(out, r / np.max(np.abs(r)) * 0.3, 0.01)
    return out


def hooves() -> np.ndarray:
    """A few antelope bounding off: paired hoof knocks on dry ground, fading away."""
    sec = 2.6
    out = np.zeros(int(sec * SR))
    at = 0.05
    k = 0
    while at < sec - 0.3:
        for off in (0.0, RNG.uniform(0.05, 0.09)):
            th = modal(
                [RNG.uniform(140, 220), RNG.uniform(600, 900)],
                [0.025, 0.01],
                [1.0, 0.4],
                0.15,
                click=0.6,
                click_band=(1000, 6000),
            )
            place(out, th / np.max(np.abs(th)), at + off, np.exp(-at / 1.4) * RNG.uniform(0.6, 1.0))
        at += RNG.uniform(0.2, 0.28)
        k += 1
    d = band(noise(sec), 300, 3000) * np.exp(-t_axis(sec) / 0.8) * 0.05
    return out + d


def croc_hiss() -> np.ndarray:
    sec = RNG.uniform(1.1, 1.6)
    t = t_axis(sec)
    y = band(noise(sec), 700, 5500, 0.4) + 0.4 * band(noise(sec), 150, 600)
    flutter = 1.0 + 0.25 * np.sin(2 * np.pi * RNG.uniform(9, 14) * t)
    e = np.clip(t / 0.18, 0, 1) * np.clip((sec - t) / (sec * 0.55), 0, 1) ** 1.5
    return y * flutter * e


def splash() -> np.ndarray:
    sec = 1.4
    t = t_axis(sec)
    hit = band(noise(sec), 250, 6000) * np.exp(-t / 0.09)
    out = hit / np.max(np.abs(hit))
    # drops falling back
    for _ in range(40):
        d = RNG.uniform(0.05, 0.9)
        f = RNG.uniform(500, 2200)
        tt = t_axis(0.05)
        b = np.sin(2 * np.pi * (f + 6000 * tt) * tt) * np.exp(-tt / 0.012)
        place(out, b, 0.04 + d, RNG.uniform(0.05, 0.25) * np.exp(-d * 2.0))
    body = band(noise(sec), 80, 400) * np.exp(-t / 0.25)
    return out + 0.5 * body / np.max(np.abs(body))


def age_swell() -> np.ndarray:
    """Rising swell into a low drum-like hit and a ringing fifth (age-up sting)."""
    sec = 4.5
    t = t_axis(sec)
    sw = sweep_band(pink(sec), 150.0, 1800.0, 1.2, 30) * np.clip(t / 2.2, 0, 1) ** 2 * (t < 2.3)
    out = sw / (np.max(np.abs(sw)) + 1e-9) * 0.6
    hit_t = t_axis(2.2)
    f = 65 * np.exp(-hit_t / 0.08) + 48
    drum = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-hit_t / 0.35)
    place(out, drum, 2.3, 1.0)
    ring = np.zeros(int(2.2 * SR))
    for fr, a in [(196.0, 1.0), (293.7, 0.7), (392.0, 0.4), (587.3, 0.15)]:
        ring += a * np.sin(2 * np.pi * fr * hit_t) * np.exp(-hit_t / 0.9)
    place(out, ring * 0.35, 2.3)
    return out


def research_shimmer() -> np.ndarray:
    sec = 1.6
    t = t_axis(sec)
    y = np.zeros_like(t)
    for fr in [1318.5, 1975.5, 2637.0]:
        y += np.sin(2 * np.pi * fr * t) * np.exp(-t / 0.5) * RNG.uniform(0.5, 1.0)
    return y * np.clip(t / 0.02, 0, 1)


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    one = {
        "intro_space_hum": space_hum,
        "intro_rise": rise,
        "intro_dive_wind": dive_wind,
        "intro_cloud_whoosh": cloud_whoosh,
        "amb_wind_grass": wind_grass,
        "amb_lake_lap": lake_lap,
        "sfx_land_thud": land_thud,
        "sfx_knap_crack": knap_crack,
        "sfx_age_swell": age_swell,
        "sfx_research_shimmer": research_shimmer,
    }
    for name, fn in one.items():
        save(out / f"{name}.wav", fn())
    multi = {
        "sfx_rustle": (lambda: rustle(RNG.uniform(0.35, 0.6)), 4),
        "sfx_stone_knock": (stone_knock, 4),
        "sfx_wood_snap": (wood_snap, 3),
        "sfx_bark_scrape": (bark_scrape, 4),
        "sfx_footstep": (footstep, 4),
        "sfx_build_place": (build_place, 2),
        "sfx_build_knock": (build_knock, 4),
        "sfx_croc_hiss": (croc_hiss, 2),
        "sfx_hooves": (hooves, 2),
        "sfx_splash": (splash, 2),
    }
    for name, (fn, k) in multi.items():
        for i in range(k):
            save(out / f"{name}_{i + 1}.wav", fn())
    print("ok", len(list(out.glob("*.wav"))))


if __name__ == "__main__":
    main()
