#!/usr/bin/env python3
"""Generate Pocket Strangers music with Google's Lyria models (Gemini API).

Run from the repo root:

    python tools/audio/generate_music.py --dry-run
    python tools/audio/generate_music.py                 # all tracks, skip existing
    python tools/audio/generate_music.py title puzzle    # only these
    python tools/audio/generate_music.py puzzle --force  # regenerate (costs money)
    python tools/audio/generate_music.py --reprocess     # re-run DSP on saved raw files (free)

Reads tools/audio/music_tracks.json. Needs GEMINI_API_KEY in the environment
(the key is never printed or written anywhere).

Budget: every API request is recorded in tools/audio/generation_log.json and the
tool refuses to make a request that would push the ledger total over BUDGET_USD.
A failed request still counts. Each track may be requested at most
MAX_REQUESTS_PER_TRACK times in total (the first pass plus one retry).

Raw API responses are saved to build/audio_raw/ before any processing.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

REPO = Path(__file__).resolve().parents[2]
TRACKS_JSON = REPO / "tools" / "audio" / "music_tracks.json"
LEDGER = REPO / "tools" / "audio" / "generation_log.json"
RAW_DIR = REPO / "build" / "audio_raw"
MUSIC_DIR = REPO / "assets" / "audio" / "music"
SFX_DIR = REPO / "assets" / "audio" / "sfx"
CREDITS = MUSIC_DIR / "CREDITS.md"

BUDGET_USD = 2.00
MAX_REQUESTS_PER_TRACK = 2  # first attempt + one retry
COST_PER_REQUEST = {"lyria-3.5": 0.08, "lyria-3-clip-preview": 0.04}

SR = 44100
LOOP_XFADE_S = 2.5
TARGET_RMS_DB = -18.0
PEAK_CEIL_DB = -1.0
VORBIS_QUALITY = 0.6  # libsndfile compression_level = 1 - quality
SILENCE_DB = -50.0
STING_MAX_S = 6.0
MIN_TRACK_S = 45.0
REQUEST_TIMEOUT_S = 900


# ---------------------------------------------------------------- utilities

def log(msg: str = "") -> None:
    print(msg, flush=True)


def scrub(text: str) -> str:
    """Remove the API key from any text before it is printed or stored."""
    for var in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
        key = os.environ.get(var)
        if key and key in text:
            text = text.replace(key, "<redacted>")
    return text


def db(x: float) -> float:
    return 20.0 * np.log10(max(float(x), 1e-12))


def from_db(d: float) -> float:
    return float(10.0 ** (d / 20.0))


def now_iso() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


# ------------------------------------------------------------------- ledger

def load_ledger() -> dict:
    if LEDGER.exists():
        return json.loads(LEDGER.read_text(encoding="utf-8"))
    return {"budget_usd": BUDGET_USD, "entries": []}


def save_ledger(ledger: dict) -> None:
    ledger["budget_usd"] = BUDGET_USD
    ledger["total_usd"] = ledger_total(ledger)
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(ledger, indent=2, ensure_ascii=False) + "\n"
    with open(LEDGER, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def ledger_total(ledger: dict) -> float:
    cents = sum(int(round(e.get("cost_usd", 0.0) * 100)) for e in ledger["entries"])
    return cents / 100.0


def requests_for(ledger: dict, name: str) -> int:
    return sum(1 for e in ledger["entries"] if e.get("track") == name)


# -------------------------------------------------------------- API calling

def walk(obj):
    """Yield every dict found anywhere inside a nested dict/list structure."""
    if isinstance(obj, dict):
        yield obj
        for v in obj.values():
            yield from walk(v)
    elif isinstance(obj, (list, tuple)):
        for v in obj:
            yield from walk(v)


def extract_outputs(interaction) -> tuple[bytes | None, dict, str]:
    """Return (audio_bytes, audio_block_meta, output_text) from an Interaction.

    Handles SDK shapes with output_audio / output_text properties, and falls back
    to scanning interaction.steps / interaction.outputs for audio/text blocks.
    """
    meta: dict = {}
    audio_bytes: bytes | None = None

    audio = getattr(interaction, "output_audio", None)
    if audio is not None and getattr(audio, "data", None):
        audio_bytes = base64.b64decode(audio.data)
        meta = {"mime_type": getattr(audio, "mime_type", None),
                "rate": getattr(audio, "rate", None),
                "channels": getattr(audio, "channels", None)}

    try:
        dump = interaction.model_dump(mode="python")
    except Exception:  # pragma: no cover - very defensive
        dump = {}
    dump.pop("input", None)  # do not mistake an echoed prompt for model output

    texts: list[str] = []
    for d in walk(dump):
        t = d.get("type")
        if t == "audio" and d.get("data") and audio_bytes is None:
            audio_bytes = base64.b64decode(d["data"])
            meta = {"mime_type": d.get("mime_type"), "rate": d.get("rate"),
                    "channels": d.get("channels")}
        elif t == "text" and d.get("text"):
            texts.append(d["text"])

    out_text = getattr(interaction, "output_text", None)
    if not out_text:
        out_text = "\n".join(texts)
    return audio_bytes, meta, out_text or ""


def detect_ext(data: bytes, meta: dict) -> str:
    if data[:4] == b"RIFF":
        return "wav"
    if data[:3] == b"ID3" or (len(data) > 2 and data[0] == 0xFF and (data[1] & 0xE0) == 0xE0):
        return "mp3"
    if data[:4] == b"OggS":
        return "ogg"
    if data[:4] == b"fLaC":
        return "flac"
    mime = (meta or {}).get("mime_type") or ""
    if "l16" in mime or "pcm" in mime:
        return "pcm"
    return "bin"


def call_lyria(model: str, prompt: str, use_response_format: bool):
    from google import genai  # imported lazily so --dry-run needs no SDK/key

    client = genai.Client()  # reads GEMINI_API_KEY from the environment
    kwargs = {"model": model, "input": prompt, "timeout": REQUEST_TIMEOUT_S}
    if use_response_format:
        kwargs["response_format"] = {"type": "audio"}
    return client.interactions.create(**kwargs)


# ------------------------------------------------------------------ audio DSP

def load_audio(path: Path, meta: dict) -> tuple[np.ndarray, int]:
    """Load to float32 array shaped (n, 2) at SR."""
    if path.suffix == ".pcm":
        rate = int(meta.get("rate") or SR)
        ch = int(meta.get("channels") or 2)
        raw = np.frombuffer(path.read_bytes(), dtype=">i2").astype(np.float32) / 32768.0
        x = raw[: len(raw) // ch * ch].reshape(-1, ch)
        sr = rate
    else:
        x, sr = sf.read(str(path), dtype="float32", always_2d=True)
    if x.shape[1] == 1:
        x = np.repeat(x, 2, axis=1)
    elif x.shape[1] > 2:
        x = x[:, :2]
    if sr != SR:
        log(f"  note: resampling {sr} Hz -> {SR} Hz (linear)")
        n_new = int(round(x.shape[0] * SR / sr))
        t_old = np.arange(x.shape[0]) / sr
        t_new = np.arange(n_new) / SR
        x = np.stack([np.interp(t_new, t_old, x[:, c]) for c in range(2)], axis=1).astype(np.float32)
    return np.ascontiguousarray(x, dtype=np.float32), SR


def frame_rms_db(x: np.ndarray, win: int) -> np.ndarray:
    mono = x.mean(axis=1) if x.ndim == 2 else x
    n = len(mono) // win
    if n == 0:
        return np.array([db(np.sqrt(np.mean(mono ** 2)))]) if len(mono) else np.array([-120.0])
    frames = mono[: n * win].reshape(n, win)
    rms = np.sqrt(np.mean(frames ** 2, axis=1))
    return 20.0 * np.log10(np.maximum(rms, 1e-12))


def trim_silence(x: np.ndarray, pad_s: float, thresh_db: float = SILENCE_DB,
                 trim_end: bool = True) -> np.ndarray:
    win = int(0.010 * SR)
    levels = frame_rms_db(x, win)
    active = np.where(levels > thresh_db)[0]
    if len(active) == 0:
        return x[:0]
    start = max(0, active[0] * win - int(pad_s * SR))
    end = min(len(x), (active[-1] + 1) * win + int(pad_s * SR)) if trim_end else len(x)
    return x[start:end]


def gated_rms_db(x: np.ndarray) -> float:
    """RMS over 100 ms windows that are above the silence gate."""
    win = int(0.100 * SR)
    mono_pow = (x ** 2).mean(axis=1)
    n = len(mono_pow) // win
    if n == 0:
        return db(np.sqrt(mono_pow.mean())) if len(mono_pow) else -120.0
    p = mono_pow[: n * win].reshape(n, win).mean(axis=1)
    lv = 10.0 * np.log10(np.maximum(p, 1e-24))
    keep = p[lv > SILENCE_DB]
    if len(keep) == 0:
        return -120.0
    return 10.0 * np.log10(keep.mean())


def soft_limit(x: np.ndarray, ceiling: float, knee: float = 0.75) -> np.ndarray:
    """tanh soft knee: identity below knee*ceiling, asymptotically ceiling above."""
    t = ceiling * knee
    a = np.abs(x)
    over = a > t
    if not over.any():
        return x
    y = x.copy()
    y[over] = np.sign(x[over]) * (t + (ceiling - t) * np.tanh((a[over] - t) / (ceiling - t)))
    return y


def normalize(x: np.ndarray) -> tuple[np.ndarray, float]:
    """Gain to TARGET_RMS_DB (gated RMS), soft limit to PEAK_CEIL_DB. Returns (audio, gain_db)."""
    cur = gated_rms_db(x)
    gain_db = TARGET_RMS_DB - cur
    y = x * from_db(gain_db)
    # Ceiling slightly under -1 dBFS so Vorbis encoder overshoot stays near -1.
    y = soft_limit(y, from_db(PEAK_CEIL_DB - 0.25))
    return y.astype(np.float32), float(gain_db)


def make_loop(x: np.ndarray, xfade_s: float = LOOP_XFADE_S) -> tuple[np.ndarray, float]:
    """Equal-power crossfade of the last L samples into the first L samples.

    Output = x[:N-L] with its first L samples replaced by
        tail * cos(t) + head * sin(t)      (t: 0 -> pi/2)
    so out[-1] = x[N-L-1] flows directly into out[0] = x[N-L] (tail start): no jump.
    """
    n = len(x)
    L = int(xfade_s * SR)
    L = min(L, n // 4)
    if L < SR // 10:
        return x, 0.0
    t = np.linspace(0.0, np.pi / 2, L, endpoint=False, dtype=np.float32)[:, None]
    head = x[:L]
    tail = x[n - L:]
    mixed = tail * np.cos(t) + head * np.sin(t)
    out = x[: n - L].copy()
    out[:L] = mixed
    return out, L / SR


def trim_ending_fade(x: np.ndarray, drop_db: float = 9.0, max_trim_s: float = 12.0) -> tuple[np.ndarray, float]:
    """Cut a composed ending/fade-out so the loop point lands at full level.

    Walks back from the end while the 250 ms level is more than drop_db below the
    track's median level (bounded by max_trim_s). Returns (audio, seconds_removed).
    """
    win = int(0.25 * SR)
    lv = frame_rms_db(x, win)
    if len(lv) < 8:
        return x, 0.0
    med = float(np.median(lv[lv > SILENCE_DB])) if (lv > SILENCE_DB).any() else float(np.median(lv))
    n_back = 0
    max_frames = int(max_trim_s / 0.25)
    while n_back < max_frames and n_back < len(lv) - 4 and lv[len(lv) - 1 - n_back] < med - drop_db:
        n_back += 1
    # frame_rms_db drops a partial last frame; keep that remainder out as well
    cut = len(x) - n_back * win
    cut = min(cut, (len(x) // win) * win) if n_back else len(x)
    return x[:cut], (len(x) - cut) / SR


def find_sting_end(x: np.ndarray) -> tuple[int, str]:
    """Where a sting that starts at x[0] ends.

    1) the first real drop to silence after 1.5 s, else
    2) Lyria clips always fill 30 s with continuing music, so the sting itself is the
       first event: cut at the deepest dip of the 100 ms level between 1.5 s and
       4.0 s (needs to be >= 3 dB under the median there), else
    3) cut at 4.0 s (hard cap is STING_MAX_S).
    The result is a best guess; the caller reports the reason so it can be audited.
    """
    win = int(0.100 * SR)
    lv = frame_rms_db(x[: int(STING_MAX_S * SR)], win)
    lo, hi = int(1.5 / 0.1), min(int(4.0 / 0.1), len(lv) - 1)
    for i in range(lo, len(lv) - 1):
        if lv[i] < SILENCE_DB and lv[i + 1] < SILENCE_DB:
            return i * win, "tail decays to silence"
    if hi > lo:
        seg = lv[lo:hi]
        i = lo + int(np.argmin(seg))
        if lv[i] <= float(np.median(seg)) - 3.0:
            return min((i + 1) * win, len(x)), f"cut at level dip near {(i + 1) * win / SR:.1f} s (no silent tail in clip)"
    end = min(len(x), int(4.0 * SR))
    return end, "no decay found in clip, cut at 4.0 s"


def process_track(x: np.ndarray) -> tuple[np.ndarray, dict]:
    info: dict = {}
    x = trim_silence(x, pad_s=0.0)
    x, cut_s = trim_ending_fade(x)
    info["ending_fade_cut_s"] = float(cut_s)
    info["trimmed_s"] = len(x) / SR
    x, xf = make_loop(x)
    info["crossfade_s"] = xf
    x, gain_db = normalize(x)
    info["gain_db"] = gain_db
    return x, info


def process_sting(x: np.ndarray) -> tuple[np.ndarray, dict]:
    info: dict = {}
    x = trim_silence(x, pad_s=0.005, trim_end=False)  # start at the first sound
    end, reason = find_sting_end(x)
    x = x[:end].copy()
    info["cut_reason"] = reason
    fi = int(0.020 * SR)
    fo = min(int(0.5 * SR), len(x))
    if len(x) > fi:
        x[:fi] *= np.linspace(0.0, 1.0, fi, dtype=np.float32)[:, None]
    if fo > 0:
        x[len(x) - fo:] *= np.linspace(1.0, 0.0, fo, dtype=np.float32)[:, None]
    x, gain_db = normalize(x)
    info["gain_db"] = gain_db
    return x, info


def write_ogg(path: Path, x: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Write in small chunks: one big sf.write() call overflows the C stack inside
    # libsndfile's Vorbis encoder on Windows for multi-second buffers.
    with sf.SoundFile(str(path), "w", samplerate=SR, channels=x.shape[1], format="OGG",
                      subtype="VORBIS", compression_level=1.0 - VORBIS_QUALITY) as f:
        for i in range(0, len(x), 4096):
            f.write(x[i:i + 4096])


def measure(path: Path) -> dict:
    y, sr = sf.read(str(path), dtype="float32", always_2d=True)
    return {
        "duration_s": float(round(len(y) / sr, 2)),
        "sample_rate": sr,
        "channels": y.shape[1],
        "rms_dbfs": float(round(db(np.sqrt(np.mean(y ** 2))), 1)),
        "gated_rms_dbfs": float(round(gated_rms_db(y), 1)),
        "peak_dbfs": float(round(db(np.abs(y).max()), 2)),
        "bytes": path.stat().st_size,
    }


def check_quality(kind: str, raw: np.ndarray) -> list[str]:
    """Return a list of reasons the *raw* result looks unusable (empty = fine)."""
    problems = []
    dur = len(raw) / SR
    if len(raw) == 0 or np.abs(raw).max() < 1e-4:
        return ["no audible audio"]
    levels = frame_rms_db(raw, int(0.1 * SR))
    silent = float((levels < SILENCE_DB).mean())
    if kind == "track":
        if dur < MIN_TRACK_S:
            problems.append(f"only {dur:.1f} s long (< {MIN_TRACK_S:.0f} s)")
        if silent > 0.5:
            problems.append(f"{silent:.0%} of the track is silence")
    else:
        active = trim_silence(raw, 0.0)
        if len(active) / SR < 0.3:
            problems.append("sting has under 0.3 s of sound")
    clipped = float((np.abs(raw) >= 0.999).mean())
    if clipped > 0.005:
        problems.append(f"{clipped:.2%} of samples are clipped")
    return problems


# -------------------------------------------------------------------- credits

def write_credits(tracks: list[dict], ledger: dict) -> None:
    rows = []
    for t in tracks:
        ok = [e for e in ledger["entries"] if e.get("track") == t["name"] and e.get("success")
              and e.get("output_file") and (REPO / e["output_file"]).exists()]
        if not ok:
            continue
        e = ok[-1]
        prompt = t["prompt"].replace("|", "\\|").replace("\n", " ")
        notes = e.get("notes", "")
        rows.append(f"| `{Path(e['output_file']).name}` | {e['model']} | {e['time'][:10]} | {prompt} | {notes} |")
    lines = [
        "# Music credits",
        "",
        "The music in this folder (and the two stings `sfx_sting_reveal.ogg` and "
        "`sfx_sting_success.ogg` in `assets/audio/sfx/`) was generated with Google's "
        "Lyria models via the Gemini API, using `tools/audio/generate_music.py`. "
        "The audio carries a SynthID watermark. The prompts deliberately describe "
        "musical style only (instruments, tempo, key, mood); they name no game, "
        "composer or artist.",
        "",
        "Post-processing (trim, loop crossfade, loudness normalisation, Ogg Vorbis "
        "encode) is done by the same script. Raw model output is kept outside the "
        "repository in `build/audio_raw/`.",
        "",
        "| File | Model | Date | Prompt | Notes |",
        "|------|-------|------|--------|-------|",
        *rows,
        "",
    ]
    CREDITS.parent.mkdir(parents=True, exist_ok=True)
    with open(CREDITS, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


# ----------------------------------------------------------------------- main

def out_path(t: dict) -> Path:
    if t["kind"] == "sting":
        return SFX_DIR / f"sfx_{t['name']}.ogg"
    return MUSIC_DIR / f"mus_{t['name']}.ogg"


def find_raw(name: str) -> Path | None:
    for p in sorted(RAW_DIR.glob(f"{name}.*")):
        if p.suffix.lower() in (".mp3", ".wav", ".ogg", ".flac", ".pcm"):
            return p
    return None


def process_and_write(t: dict, raw_path: Path, meta: dict) -> tuple[dict, list[str]]:
    raw, _ = load_audio(raw_path, meta)
    problems = check_quality(t["kind"], raw)
    info: dict = {"raw_duration_s": round(len(raw) / SR, 2)}
    if "no audible audio" in problems:
        return info, problems
    if t["kind"] == "sting":
        y, extra = process_sting(raw)
    else:
        y, extra = process_track(raw)
    info.update(extra)
    dest = out_path(t)
    write_ogg(dest, y)
    # Vorbis can overshoot the input peak a little: re-encode with less gain if needed.
    for _ in range(4):
        peak = db(np.abs(sf.read(str(dest), dtype="float32")[0]).max())
        if peak <= PEAK_CEIL_DB + 0.05:
            break
        y = (y * from_db(PEAK_CEIL_DB - peak - 0.1)).astype(np.float32)
        info["gain_db"] = float(info.get("gain_db", 0.0) + PEAK_CEIL_DB - peak - 0.1)
        write_ogg(dest, y)
    info["output_file"] = dest.relative_to(REPO).as_posix()
    info["measure"] = measure(dest)
    return info, problems


def notes_for(t: dict, info: dict, text_note: str) -> str:
    m = info["measure"]
    parts = [f"{m['duration_s']} s", f"RMS {m['gated_rms_dbfs']} dBFS", f"peak {m['peak_dbfs']} dBFS"]
    if t["kind"] == "track":
        parts.append(f"loop crossfade {info.get('crossfade_s', 0):.1f} s")
        if info.get("ending_fade_cut_s"):
            parts.append(f"composed ending cut ({info['ending_fade_cut_s']:.1f} s)")
    else:
        parts.append(f"one-shot sting, {info.get('cut_reason', '')}")
    if text_note:
        parts.append(text_note)
    return "; ".join(parts)


def main(argv: list[str]) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="track names to process (default: all)")
    ap.add_argument("--force", action="store_true", help="regenerate even if the output exists (costs money)")
    ap.add_argument("--dry-run", action="store_true", help="print the plan and cost; make no API calls")
    ap.add_argument("--reprocess", action="store_true",
                    help="re-run processing on saved raw files in build/audio_raw (no API calls, free)")
    ap.add_argument("--no-response-format", action="store_true",
                    help="omit response_format (model default, MP3)")
    args = ap.parse_args(argv)

    os.chdir(REPO)
    spec = json.loads(TRACKS_JSON.read_text(encoding="utf-8"))
    tracks = spec["tracks"]
    by_name = {t["name"]: t for t in tracks}
    unknown = [n for n in args.names if n not in by_name]
    if unknown:
        log(f"error: unknown track(s): {', '.join(unknown)}. Known: {', '.join(by_name)}")
        return 2
    selected = [by_name[n] for n in args.names] if args.names else tracks
    for t in selected:
        if t["model"] not in COST_PER_REQUEST:
            log(f"error: no known price for model {t['model']!r} (track {t['name']}); refusing")
            return 2

    ledger = load_ledger()
    total = ledger_total(ledger)

    # ---- plan
    plan = []  # (track, action)
    for t in selected:
        dest = out_path(t)
        if args.reprocess:
            plan.append((t, "reprocess" if find_raw(t["name"]) else "skip (no raw file)"))
        elif dest.exists() and not args.force:
            plan.append((t, "skip (output exists)"))
        else:
            plan.append((t, "generate"))

    planned_cost = sum(COST_PER_REQUEST[t["model"]] for t, a in plan if a == "generate")
    log(f"Budget ${BUDGET_USD:.2f} | ledger total so far ${total:.2f} | "
        f"remaining ${BUDGET_USD - total:.2f}")
    for t, a in plan:
        c = COST_PER_REQUEST[t["model"]] if a == "generate" else 0.0
        log(f"  {t['name']:<15} {t['kind']:<6} {t['model']:<22} {a:<22} ${c:.2f}")
    log(f"Planned new spend: ${planned_cost:.2f} -> ledger would be ${total + planned_cost:.2f}")

    if args.dry_run:
        log("(dry run: no API calls made)")
        return 0

    if not args.reprocess and planned_cost > 0 and not (
            os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")):
        log("error: GEMINI_API_KEY is not set in the environment")
        return 2

    failures = 0
    warnings_out: list[str] = []
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    for t, action in plan:
        name = t["name"]
        if action.startswith("skip"):
            continue
        log(f"\n== {name} ({t['kind']}, {t['model']})")

        text_note = ""
        meta: dict = {}
        entry = None

        if action == "generate":
            cost = COST_PER_REQUEST[t["model"]]
            if requests_for(ledger, name) >= MAX_REQUESTS_PER_TRACK:
                log(f"  REFUSED: {name} already used {MAX_REQUESTS_PER_TRACK} requests "
                    "(first pass + one retry)")
                failures += 1
                continue
            if int(round((total + cost) * 100)) > int(round(BUDGET_USD * 100)):
                log(f"  REFUSED: request (${cost:.2f}) would push the ledger "
                    f"(${total:.2f}) over the ${BUDGET_USD:.2f} budget")
                failures += 1
                continue

            # Record the spend BEFORE the call so a crash or timeout still counts.
            entry = {"time": now_iso(), "track": name, "model": t["model"], "cost_usd": cost,
                     "success": False, "status": "pending", "output_duration_s": None}
            ledger["entries"].append(entry)
            total = ledger_total(ledger)
            save_ledger(ledger)

            log("  requesting from the Gemini API (can take a minute or two)...")
            try:
                interaction = call_lyria(t["model"], t["prompt"], not args.no_response_format)
                audio_bytes, meta, out_text = extract_outputs(interaction)
                status = getattr(interaction, "status", None)
            except Exception as e:  # noqa: BLE001 - any API failure is logged and counted
                msg = scrub(f"{type(e).__name__}: {e}")
                log(f"  FAILED: {msg}")
                entry.update(status="error", error=msg[:2000])
                save_ledger(ledger)
                failures += 1
                continue

            if out_text:
                (RAW_DIR / f"{name}.txt").write_text(out_text, encoding="utf-8", newline="\n")
                preview = out_text.strip().replace("\n", " ")
                log(f"  output_text ({len(out_text)} chars): {preview[:300]}{'...' if len(preview) > 300 else ''}")
                entry["output_text_chars"] = len(out_text)
            if not audio_bytes:
                msg = f"no audio in response (status={status}); output_text={out_text[:300]!r}"
                log(f"  FAILED: {scrub(msg)}")
                entry.update(status="no_audio", error=scrub(msg))
                save_ledger(ledger)
                failures += 1
                continue

            ext = detect_ext(audio_bytes, meta)
            raw_path = RAW_DIR / f"{name}.{ext}"
            raw_path.write_bytes(audio_bytes)
            log(f"  saved raw response: {raw_path.relative_to(REPO).as_posix()} "
                f"({len(audio_bytes) / 1e6:.2f} MB, mime={meta.get('mime_type')})")
            entry["raw_file"] = raw_path.relative_to(REPO).as_posix()
        else:
            raw_path = find_raw(name)
            log(f"  reprocessing {raw_path.relative_to(REPO).as_posix()}")
            txt = RAW_DIR / f"{name}.txt"
            out_text = txt.read_text(encoding="utf-8") if txt.exists() else ""

        # ---- process
        try:
            info, problems = process_and_write(t, raw_path, meta)
        except Exception as e:  # noqa: BLE001
            msg = scrub(f"{type(e).__name__}: {e}")
            log(f"  PROCESSING FAILED: {msg}")
            if entry is not None:
                entry.update(status="decode_error", error=msg[:2000])
                save_ledger(ledger)
            failures += 1
            continue

        if entry is not None:
            entry["output_duration_s"] = info["raw_duration_s"]
        log(f"  raw duration {info['raw_duration_s']} s")
        if problems:
            for p in problems:
                log(f"  WARNING (looks unusable): {p}")
                warnings_out.append(f"{name}: {p}")
        if "measure" not in info:
            if entry is not None:
                entry.update(status="unusable", error="; ".join(problems))
                save_ledger(ledger)
            failures += 1
            continue

        m = info["measure"]
        log(f"  wrote {info['output_file']}: {m['duration_s']} s, {m['sample_rate']} Hz, "
            f"{m['channels']} ch, RMS {m['rms_dbfs']} dBFS (gated {m['gated_rms_dbfs']}), "
            f"peak {m['peak_dbfs']} dBFS, {m['bytes'] / 1024:.0f} KiB")

        note_bits = []
        if t["kind"] == "track" and "lyric" in out_text.lower():
            note_bits.append("output_text mentions lyrics (check)")
        text_note = "; ".join(note_bits)
        if entry is not None:
            entry.update(success=True, status="ok", output_file=info["output_file"],
                         notes=notes_for(t, info, text_note), measure=m)
            if problems:
                entry["warnings"] = problems
            save_ledger(ledger)
        else:
            # reprocess: update the notes of the latest successful entry
            for e in reversed(ledger["entries"]):
                if e.get("track") == name and e.get("success"):
                    e.update(output_file=info["output_file"], notes=notes_for(t, info, text_note),
                             measure=m)
                    break
            save_ledger(ledger)

    save_ledger(ledger)
    write_credits(tracks, ledger)
    log(f"\nLedger total: ${ledger_total(ledger):.2f} of ${BUDGET_USD:.2f}")
    if warnings_out:
        log("Warnings:")
        for w in warnings_out:
            log(f"  - {w}")
    if failures:
        log(f"{failures} track(s) failed")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
