#!/usr/bin/env python3
"""Synthesize Pocket Strangers' sound effects and the night-street ambience.

Pure numpy (no scipy). Deterministic: every sound has its own fixed RNG seed,
so re-running reproduces identical sample data.

Usage (from the project root):
    python tools/audio/synth_sfx.py            # render everything + verify
    python tools/audio/synth_sfx.py ui_click   # render only the named sounds
    python tools/audio/synth_sfx.py --verify   # only print stats of existing files

Outputs (OGG Vorbis, 44.1 kHz):
    assets/audio/sfx/sfx_<name>.ogg        mono
    assets/audio/ambience/amb_night_street.ogg   stereo, 60 s, seamless loop

The music stings (sfx_sting_reveal.ogg, sfx_sting_success.ogg) are produced by
a different tool and are never touched here.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 44100
ROOT = Path(__file__).resolve().parents[2]
SFX_DIR = ROOT / "assets" / "audio" / "sfx"
AMB_DIR = ROOT / "assets" / "audio" / "ambience"

TAU = 2.0 * math.pi


# --------------------------------------------------------------------------
# Small DSP toolkit
# --------------------------------------------------------------------------
def tvec(dur: float) -> np.ndarray:
    return np.arange(int(round(dur * SR))) / SR


def db(x: float) -> float:
    return 10.0 ** (x / 20.0)


def to_db(x: float) -> float:
    return 20.0 * math.log10(max(x, 1e-12))


def attack_env(t: np.ndarray, a: float) -> np.ndarray:
    """Smooth raised-cosine attack from 0 to 1 over `a` seconds."""
    x = np.clip(t / max(a, 1e-6), 0.0, 1.0)
    return 0.5 - 0.5 * np.cos(math.pi * x)


def expdecay(t: np.ndarray, tau: float) -> np.ndarray:
    return np.exp(-np.maximum(t, 0.0) / tau)


def smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def biquad_coeffs(kind: str, f0: float, q: float = 0.7071):
    """RBJ audio-EQ-cookbook biquads. Returns normalized (b, a)."""
    w0 = TAU * f0 / SR
    cw, sw = math.cos(w0), math.sin(w0)
    alpha = sw / (2.0 * q)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
    elif kind == "bp":  # constant 0 dB peak gain
        b = [alpha, 0.0, -alpha]
    else:
        raise ValueError(kind)
    a = [1 + alpha, -2 * cw, 1 - alpha]
    return [x / a[0] for x in b], [a[1] / a[0], a[2] / a[0]]


def biquad(x: np.ndarray, kind: str, f0: float, q: float = 0.7071) -> np.ndarray:
    """Direct-form-I biquad written by hand (sample loop; fine for short sfx)."""
    (b0, b1, b2), (a1, a2) = biquad_coeffs(kind, f0, q)
    xs = x.tolist()
    y = [0.0] * len(xs)
    x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(xs):
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, xi
        y2, y1 = y1, yi
        y[i] = yi
    return np.asarray(y)


def onepole_lp(x: np.ndarray, fc: float) -> np.ndarray:
    a = 1.0 - math.exp(-TAU * fc / SR)
    xs = x.tolist()
    y = [0.0] * len(xs)
    s = 0.0
    for i, xi in enumerate(xs):
        s += a * (xi - s)
        y[i] = s
    return np.asarray(y)


def white(rng: np.random.Generator, n: int) -> np.ndarray:
    return rng.standard_normal(n)


def place(buf: np.ndarray, sig: np.ndarray, t0: float, gain: float = 1.0) -> None:
    i0 = int(round(t0 * SR))
    if i0 >= len(buf):
        return
    n = min(len(sig), len(buf) - i0)
    buf[i0:i0 + n] += gain * sig[:n]


def sine_sweep(t: np.ndarray, f_start: float, f_end: float, tau: float) -> np.ndarray:
    """Sine whose frequency glides exponentially from f_start to f_end."""
    df = f_start - f_end
    phase = TAU * (f_end * t + df * tau * (1.0 - np.exp(-t / tau)))
    return np.sin(phase)


def bell(t: np.ndarray, f: float, tau: float, partials=((1.0, 1.0, 1.0), (2.0, 0.30, 0.55), (3.0, 0.10, 0.30))):
    """Soft bell: additive partials, each (ratio, amp, decay-scale)."""
    out = np.zeros_like(t)
    for ratio, amp, dscale in partials:
        out += amp * np.sin(TAU * f * ratio * t) * expdecay(t, tau * dscale)
    return out * attack_env(t, 0.004)


def finalize(x: np.ndarray, peak_db: float = -6.0, fade_in_ms: float = 5.0, fade_out_ms: float = 5.0,
             trim_db: float = -50.0, max_len: float | None = None) -> np.ndarray:
    """Trim lead/trail silence, 5 ms fades, normalise peak."""
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x))
    thr = peak * db(trim_db)
    idx = np.nonzero(np.abs(x) > thr)[0]
    if len(idx):
        x = x[idx[0]: idx[-1] + 1]
    if max_len is not None:
        x = x[: int(max_len * SR)]
    nfi = min(int(fade_in_ms * SR / 1000), len(x) // 2)
    nfo = min(int(fade_out_ms * SR / 1000), len(x) // 2)
    if nfi > 0:
        x[:nfi] *= np.linspace(0.0, 1.0, nfi)
    if nfo > 0:
        x[-nfo:] *= np.linspace(1.0, 0.0, nfo)
    x = x / max(np.max(np.abs(x)), 1e-12) * db(peak_db)
    return x.astype(np.float32)


def write_ogg(path: Path, data: np.ndarray) -> None:
    """Write OGG Vorbis in small chunks.

    libsndfile's Vorbis writer can overflow the stack on Windows when handed a
    long array in one call (seen with the 60 s stereo ambience), so feed it
    4096-frame blocks instead.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    channels = 1 if data.ndim == 1 else data.shape[1]
    kwargs = dict(samplerate=SR, channels=channels, format="OGG", subtype="VORBIS")
    try:
        f = sf.SoundFile(str(path), "w", compression_level=0.8, **kwargs)
    except TypeError:  # older soundfile without compression_level
        f = sf.SoundFile(str(path), "w", **kwargs)
    with f:
        for i in range(0, len(data), 4096):
            f.write(data[i:i + 4096])


# --------------------------------------------------------------------------
# UI sounds
# --------------------------------------------------------------------------
def snd_ui_click() -> np.ndarray:
    rng = np.random.default_rng(1001)
    t = tvec(0.09)
    body = sine_sweep(t, 980.0, 640.0, 0.006) * expdecay(t, 0.011)
    body += 0.22 * np.sin(TAU * 1280.0 * t) * expdecay(t, 0.005)
    tick = onepole_lp(white(rng, len(t)), 2600.0) * expdecay(t, 0.0015) * 0.45
    x = (body + tick) * attack_env(t, 0.0008)
    x = onepole_lp(x, 4200.0)
    return finalize(x, -6.0)


def snd_ui_back() -> np.ndarray:
    rng = np.random.default_rng(1002)
    t = tvec(0.11)
    body = sine_sweep(t, 560.0, 330.0, 0.009) * expdecay(t, 0.016)
    body += 0.15 * np.sin(TAU * 660.0 * t) * expdecay(t, 0.006)
    tick = onepole_lp(white(rng, len(t)), 1800.0) * expdecay(t, 0.0018) * 0.30
    x = (body + tick) * attack_env(t, 0.0015)
    x = onepole_lp(x, 3000.0)
    return finalize(x, -7.0)


def snd_ui_toggle() -> np.ndarray:
    rng = np.random.default_rng(1003)
    t = tvec(0.04)
    body = sine_sweep(t, 1650.0, 1150.0, 0.004) * expdecay(t, 0.005)
    tick = onepole_lp(white(rng, len(t)), 3200.0) * expdecay(t, 0.0008) * 0.25
    x = (body + tick) * attack_env(t, 0.0005)
    x = onepole_lp(x, 4500.0)
    return finalize(x, -13.0)


def snd_save_done() -> np.ndarray:
    t = tvec(0.5)
    x = np.zeros_like(t)
    # E5 then A5: a gentle rising fourth.
    place(x, bell(tvec(0.5), 659.26, 0.085), 0.0, 0.85)
    place(x, bell(tvec(0.4), 880.0, 0.095), 0.125, 1.0)
    # faint octave shimmer from the second note
    place(x, bell(tvec(0.3), 1760.0, 0.05, partials=((1.0, 1.0, 1.0),)), 0.125, 0.07)
    x = onepole_lp(x, 6000.0)
    return finalize(x, -6.0, fade_out_ms=40.0, max_len=0.42)


# --------------------------------------------------------------------------
# Lock mechanics
# --------------------------------------------------------------------------
def snd_dial_tick() -> np.ndarray:
    rng = np.random.default_rng(2001)
    x = np.zeros(int(0.07 * SR))

    def click(t0, gain, f_noise, f_ring, f_thock):
        t = tvec(0.04)
        n = biquad(white(rng, len(t)), "bp", f_noise, 2.5) * expdecay(t, 0.0010)
        ring = np.sin(TAU * f_ring * t) * expdecay(t, 0.0055) * 0.5
        thock = sine_sweep(t, f_thock * 1.4, f_thock, 0.003) * expdecay(t, 0.0075) * 0.8
        place(x, (n * 1.4 + ring + thock) * attack_env(t, 0.0003), t0, gain)

    click(0.000, 1.0, 2900.0, 1900.0, 250.0)   # dial notch drops in
    click(0.022, 0.55, 2300.0, 1500.0, 210.0)  # pawl settles
    x = onepole_lp(x, 6500.0)
    return finalize(x, -6.0, trim_db=-46.0)


def snd_lock_fail() -> np.ndarray:
    rng = np.random.default_rng(2002)
    x = np.zeros(int(0.36 * SR))
    t = tvec(0.3)
    # the dull thunk of a shackle that will not give
    thunk = sine_sweep(t, 150.0, 62.0, 0.045) * expdecay(t, 0.055)
    thunk += 0.5 * onepole_lp(white(rng, len(t)), 700.0) * expdecay(t, 0.012)
    place(x, thunk * attack_env(t, 0.001), 0.0, 1.0)
    # loose metal chatter after it
    for t0, g, f in ((0.060, 0.50, 720.0), (0.115, 0.34, 840.0), (0.165, 0.22, 780.0), (0.205, 0.12, 900.0)):
        tt = tvec(0.1)
        hit = biquad(white(rng, len(tt)), "bp", f, 5.0) * expdecay(tt, 0.020) * 2.0
        hit += 0.6 * np.sin(TAU * 410.0 * tt) * expdecay(tt, 0.010)
        place(x, hit * attack_env(tt, 0.0008), t0, g)
    x = onepole_lp(x, 1700.0)
    return finalize(x, -6.0, fade_out_ms=20.0, max_len=0.32)


def snd_lock_open() -> np.ndarray:
    rng = np.random.default_rng(2003)
    x = np.zeros(int(0.62 * SR))
    # 1. crisp latch release
    t = tvec(0.04)
    latch = biquad(white(rng, len(t)), "bp", 3300.0, 2.0) * expdecay(t, 0.0018) * 1.6
    latch += 0.5 * np.sin(TAU * 2350.0 * t) * expdecay(t, 0.007)
    place(x, latch * attack_env(t, 0.0003), 0.0, 1.0)
    # 2. shackle clunk
    t = tvec(0.12)
    clunk = sine_sweep(t, 230.0, 125.0, 0.03) * expdecay(t, 0.035)
    clunk += 0.4 * onepole_lp(white(rng, len(t)), 1000.0) * expdecay(t, 0.008)
    place(x, clunk * attack_env(t, 0.001), 0.040, 0.75)
    # 3. small spring: inharmonic partials with a wobble
    t = tvec(0.45)
    spring = np.zeros_like(t)
    for f, a in ((1650.0, 1.0), (2480.0, 0.7), (3330.0, 0.45), (4150.0, 0.25)):
        wob = 1.0 + 0.018 * np.sin(TAU * 29.0 * t + f)
        spring += a * np.sin(TAU * f * t * wob + 1.3 * np.sin(TAU * 31.0 * t))
    spring *= (0.55 + 0.45 * np.sin(TAU * 31.0 * t + 0.6)) * expdecay(t, 0.115) * attack_env(t, 0.004)
    place(x, spring, 0.065, 0.11)
    # 4. spring bottoms out with a last faint tick
    t = tvec(0.03)
    tick = biquad(white(rng, len(t)), "bp", 2600.0, 3.0) * expdecay(t, 0.002) * 1.4
    place(x, tick, 0.30, 0.22)
    x = onepole_lp(x, 7000.0)
    return finalize(x, -6.0, fade_out_ms=40.0, trim_db=-58.0, max_len=0.52)


# --------------------------------------------------------------------------
# Phone vibrating on a wooden bench
# --------------------------------------------------------------------------
def snd_phone_buzz() -> np.ndarray:
    rng = np.random.default_rng(3001)
    total = 1.05
    x = np.zeros(int(total * SR))

    def buzz(t0: float, dur: float):
        n = int((dur + 0.04) * SR)
        t = np.arange(n) / SR
        # motor spins up from ~115 Hz and settles at ~172 Hz, spins down at the end
        f = 172.0 - 58.0 * np.exp(-t / 0.035)
        f = np.where(t > dur, f * np.exp(-(t - dur) / 0.03), f)
        phase = np.cumsum(TAU * f / SR)
        wave = np.zeros(n)
        for h in range(1, 7):
            wave += np.sin(h * phase + 0.7 * h) / h ** 1.15
        wave *= 1.0 + 0.12 * np.sin(TAU * 13.0 * t)
        env = attack_env(t, 0.014) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.012))
        motor = wave * env
        # the bench: wood resonances excited by the vibration
        wood = 0.9 * biquad(motor, "bp", 310.0, 3.0) + 0.55 * biquad(motor, "bp", 690.0, 4.0)
        # the phone's case rattling against the wood
        rattle_noise = biquad(white(rng, n), "bp", 1500.0, 1.3)
        rattle = rattle_noise * np.abs(wave) * env * 0.6
        sig = 0.55 * onepole_lp(motor, 900.0) + 0.9 * wood + 0.5 * rattle
        place(x, sig, t0, 1.0)

    buzz(0.015, 0.30)
    buzz(0.620, 0.32)
    x = onepole_lp(x, 5000.0)
    return finalize(x, -6.0, fade_out_ms=30.0, trim_db=-60.0, max_len=1.0)


# --------------------------------------------------------------------------
# Bus pulling in
# --------------------------------------------------------------------------
def snd_bus_arrive() -> np.ndarray:
    rng = np.random.default_rng(4001)
    total = 5.0
    n = int(total * SR)
    t = np.arange(n) / SR

    # --- engine: level + pitch envelopes -------------------------------
    approach = smoothstep(t / 2.7)                       # bus gets closer
    after = smoothstep((t - 2.8) / 0.5)                  # braked to a stop -> idle
    level = approach * (1.0 - 0.38 * after)
    level = level * (1.0 - smoothstep((t - 4.2) / 0.8))  # driver lets it idle away
    level = level + 0.015
    f_fire = 23.0 + 9.0 * approach - 8.0 * after + 0.5 * np.sin(TAU * 0.7 * t)
    # a bit of irregular lumpiness, as on an old diesel
    lump = onepole_lp(white(rng, n), 9.0)
    lump = lump / (np.std(lump) + 1e-9)
    f_fire = f_fire * (1.0 + 0.012 * lump)
    phase = np.cumsum(TAU * f_fire / SR)
    rumble = np.zeros(n)
    for h in range(1, 15):
        rumble += (h ** -0.55) * np.sin(h * phase + 0.9 * h * h)
    # firing-synchronous clatter
    cyc = np.floor(phase / TAU).astype(np.int64)
    fire_idx = np.nonzero(np.diff(cyc) > 0)[0] + 1
    clatter = np.zeros(n)
    burst_t = tvec(0.012)
    for i in fire_idx:
        burst = biquad(white(rng, len(burst_t)), "bp", 900.0, 1.0) * expdecay(burst_t, 0.003)
        g = 0.6 + 0.4 * rng.random()
        m = min(len(burst), n - i)
        clatter[i:i + m] += g * burst[:m]
    rumble = onepole_lp(rumble, 420.0)
    engine = (0.9 * rumble + 0.30 * clatter) * level
    # chassis shudder (low, noisy)
    shudder = onepole_lp(white(rng, n), 130.0) * level * 1.5
    engine += shudder

    # --- tyres on road, only while moving ------------------------------
    moving = approach * (1.0 - smoothstep((t - 2.75) / 0.55))
    tyres = biquad(white(rng, n), "bp", 520.0, 0.6) * moving * 0.28
    tyres += onepole_lp(white(rng, n), 2200.0) * moving * (0.07 + 0.08 * approach)

    mix = engine + tyres

    # --- air-brake hiss (pssshht) ---------------------------------------
    def hiss(dur, f_hi, f_lo, tau, atk):
        tt = tvec(dur)
        w = white(rng, len(tt))
        hi = biquad(biquad(w, "hp", 1800.0, 0.7), "lp", f_hi, 0.7)
        lo = biquad(biquad(w, "hp", 1800.0, 0.7), "lp", f_lo, 0.7)
        mixk = smoothstep(tt / (dur * 0.7))
        s = hi * (1 - mixk) + lo * mixk                  # spectrum darkens as pressure bleeds off
        return s * attack_env(tt, atk) * expdecay(tt, tau)

    place(mix, hiss(1.5, 9000.0, 4200.0, 0.36, 0.012), 2.88, 0.95)
    # kneeling thump as the suspension lets go
    tt = tvec(0.25)
    place(mix, sine_sweep(tt, 95.0, 48.0, 0.05) * expdecay(tt, 0.06), 2.86, 0.55)

    # --- door fold -------------------------------------------------------
    place(mix, hiss(0.55, 8000.0, 3500.0, 0.14, 0.02), 3.62, 0.55)  # pneumatic ram
    # two door panels folding: rubber rattle + dull thumps
    for t0, g in ((3.76, 0.8), (3.96, 0.6)):
        tt = tvec(0.28)
        rub = biquad(white(rng, len(tt)), "bp", 760.0, 1.6)
        rub *= (0.55 + 0.45 * np.sin(TAU * 27.0 * tt)) * attack_env(tt, 0.015) * expdecay(tt, 0.07)
        place(mix, rub, t0, 0.32 * g)
        th = tvec(0.15)
        thump = sine_sweep(th, 150.0, 80.0, 0.02) * expdecay(th, 0.04)
        thump += 0.35 * onepole_lp(white(rng, len(th)), 900.0) * expdecay(th, 0.01)
        place(mix, thump, t0 + 0.07, 0.55 * g)
    # final clack of the door seating
    tt = tvec(0.1)
    clack = biquad(white(rng, len(tt)), "bp", 1500.0, 2.0) * expdecay(tt, 0.012) * 1.5
    clack += 0.7 * sine_sweep(tt, 220.0, 130.0, 0.015) * expdecay(tt, 0.03)
    place(mix, clack, 4.20, 0.5)

    mix = onepole_lp(mix, 9000.0)
    # long gentle tail: no hard 5 ms cut on a sound that is already idling away
    return finalize(mix, -6.0, fade_in_ms=5.0, fade_out_ms=5.0, trim_db=-55.0)


# --------------------------------------------------------------------------
# Night street ambience (60 s, stereo, circular construction = seamless loop)
# --------------------------------------------------------------------------
def snd_amb_night_street() -> np.ndarray:
    dur = 60.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    f = np.maximum(freqs, 1e-3)

    def shaped(rng, gain: np.ndarray) -> np.ndarray:
        """White noise with a frequency-domain magnitude `gain`. Periodic in n."""
        spec = np.fft.rfft(rng.standard_normal(n)) * gain
        spec[0] = 0.0
        out = np.fft.irfft(spec, n)
        return out / (np.std(out) + 1e-12)

    def slow_mod(rng, cycles, depth, base=1.0) -> np.ndarray:
        """Sum of sinusoids with integer cycle counts per loop (so the loop is exact)."""
        m = np.zeros(n)
        for k in cycles:
            m += rng.uniform(0.5, 1.0) * np.sin(TAU * k * t / dur + rng.uniform(0, TAU))
        m /= max(np.max(np.abs(m)), 1e-9)
        return base + depth * m

    # --- wind: low, soft, gusting --------------------------------------
    wind_lo_g = (1.0 / (1.0 + (f / 380.0) ** 2)) * (f / (f + 45.0)) ** 2
    wind_lo_g = wind_lo_g * (1.0 + 0.8 * np.exp(-0.5 * ((f - 300.0) / 110.0) ** 2))
    wind_hi_g = (1.0 / (1.0 + (f / 1600.0) ** 2)) * (f / (f + 400.0)) ** 2
    hum_g = (f / (f + 40.0)) ** 2 / (1.0 + (f / 170.0) ** 4)

    wind = np.zeros((n, 2))
    for ch in range(2):
        rng = np.random.default_rng(5100 + ch)
        gust = slow_mod(rng, (2, 3, 5, 8, 13), 0.5, 0.55)
        gust = np.clip(gust, 0.06, None)
        low = shaped(rng, wind_lo_g)
        high = shaped(rng, wind_hi_g)
        wind[:, ch] = low * gust + 0.35 * high * gust ** 3

    # --- distant traffic hum: steady low band + a faint mains-ish tone --
    hum = np.zeros((n, 2))
    common = shaped(np.random.default_rng(5200), hum_g)
    for ch in range(2):
        rng = np.random.default_rng(5201 + ch)
        own = shaped(rng, hum_g)
        sway = slow_mod(rng, (4, 9, 17), 0.18, 1.0)
        tone = 0.10 * np.sin(TAU * 55.0 * t + ch) + 0.05 * np.sin(TAU * 110.0 * t + 2 * ch)
        hum[:, ch] = (0.7 * common + 0.5 * own) * sway + tone

    # --- far-off cars: soft whooshes with a Doppler-ish tone ------------
    cars = np.zeros((n, 2))
    car_specs = [
        # centre (s), sigma (s), direction (+1 L->R), level, seed
        (11.0, 1.7, +1, 1.00, 5301),
        (30.5, 2.4, -1, 0.70, 5302),
        (49.0, 1.5, +1, 0.90, 5303),
    ]
    band_lo = (1.0 / (1.0 + (f / 330.0) ** 2)) * (f / (f + 60.0)) ** 2
    band_mid = (1.0 / (1.0 + (f / 1300.0) ** 2)) * (f / (f + 250.0)) ** 2
    for c, sig, direction, lvl, seed in car_specs:
        rng = np.random.default_rng(seed)
        d = (t - c + dur / 2.0) % dur - dur / 2.0  # circular distance to the pass
        env = np.exp(-0.5 * (d / sig) ** 2)
        road = shaped(rng, band_lo) * env + 0.55 * shaped(rng, band_mid) * env ** 2.4
        f_eng = 78.0 - 16.0 * np.tanh(d / (sig * 0.9))  # pitch falls as it passes
        eng_phase = TAU * np.cumsum(f_eng) / SR
        engine = (np.sin(eng_phase) + 0.5 * np.sin(2 * eng_phase + 0.4)) * env ** 1.5 * 0.35
        pan = 0.5 + direction * 0.42 * np.tanh(d / (sig * 1.1))
        gl, gr = np.cos(pan * math.pi / 2), np.sin(pan * math.pi / 2)
        sig_mono = (road + engine) * lvl
        cars[:, 0] += sig_mono * gl
        cars[:, 1] += sig_mono * gr

    mix = 0.11 * wind + 0.085 * hum + 0.075 * cars
    # RMS of the whole stereo file -> -30 dBFS
    rms = math.sqrt(float(np.mean(mix ** 2)))
    mix = mix / rms * db(-30.0)
    return mix.astype(np.float32)


# --------------------------------------------------------------------------
# Registry / driver
# --------------------------------------------------------------------------
SFX = {
    "ui_click": snd_ui_click,
    "ui_back": snd_ui_back,
    "ui_toggle": snd_ui_toggle,
    "save_done": snd_save_done,
    "dial_tick": snd_dial_tick,
    "lock_fail": snd_lock_fail,
    "lock_open": snd_lock_open,
    "phone_buzz": snd_phone_buzz,
    "bus_arrive": snd_bus_arrive,
}
AMB = {"night_street": snd_amb_night_street}


def targets():
    for name in SFX:
        yield name, SFX_DIR / f"sfx_{name}.ogg"
    for name in AMB:
        yield name, AMB_DIR / f"amb_{name}.ogg"


def verify(names=None) -> None:
    print(f"{'file':<28}{'dur(s)':>8}{'ch':>4}{'peak dBFS':>11}{'rms dBFS':>10}")
    for name, path in targets():
        if names and name not in names:
            continue
        if not path.exists():
            print(f"{path.name:<28}  MISSING")
            continue
        data, sr = sf.read(str(path), always_2d=True)
        peak = float(np.max(np.abs(data)))
        rms = math.sqrt(float(np.mean(data ** 2)))
        print(f"{path.name:<28}{len(data) / sr:>8.3f}{data.shape[1]:>4}{to_db(peak):>11.2f}{to_db(rms):>10.2f}  sr={sr}")
        if name in AMB:
            seam = np.abs(data[-1] - data[0])
            step = np.median(np.abs(np.diff(data, axis=0)), axis=0)
            step99 = np.percentile(np.abs(np.diff(data, axis=0)), 99, axis=0)
            print(f"    loop seam |last-first| per channel: {seam}  "
                  f"(median step {step}, 99th pct step {step99})")


def main(argv) -> int:
    args = [a for a in argv if not a.startswith("--")]
    if "--verify" in argv:
        verify(args or None)
        return 0
    wanted = set(args) if args else None
    for name, path in targets():
        if wanted and name not in wanted:
            continue
        fn = SFX.get(name) or AMB[name]
        data = fn()
        write_ogg(path, data)
        print(f"wrote {path.relative_to(ROOT)}")
    verify(wanted)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
