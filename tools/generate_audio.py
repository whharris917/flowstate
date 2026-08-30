"""Generate the game's placeholder audio as WAV files, procedurally.

Run from the project root:

    .venv\\Scripts\\python.exe tools\\generate_audio.py

Writes to game/audio/:
  music_loop.wav  32 s seamless ambient pad — D minor palette over a
                  constant D drone; lonely, sacred, slow
  hum_loop.wav    8 s seamless ship hum — 55 Hz fundamental + harmonics
                  and a whisper of low noise
  step_1..4.wav   footstep thumps (pitch-swept sine + noise burst)
  land.wav        heavier landing thump

Loops are made seamless by quantizing every sustained frequency to an
integer number of cycles per loop and forcing envelopes to zero at the
seam. Deterministic (fixed seed). Stdlib only.
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SR = 32000
OUT_DIR = Path(__file__).resolve().parents[1] / "game" / "audio"

rng = random.Random(20260829)


def write_wav(path: Path, channels: list[list[float]],
              normalize_to: float | None = None) -> None:
    peak = max(1e-9, max(abs(sample) for chan in channels for sample in chan))
    if normalize_to is not None:
        scale = normalize_to / peak
    else:
        scale = 0.9 / peak if peak > 0.9 else 1.0
    frames = bytearray()
    for i in range(len(channels[0])):
        for chan in channels:
            value = int(max(-1.0, min(1.0, chan[i] * scale)) * 32767)
            frames += struct.pack("<h", value)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(len(channels))
        wav.setsampwidth(2)
        wav.setframerate(SR)
        wav.writeframes(bytes(frames))
    print(f"  {path.name}  ({len(channels[0]) / SR:.2f} s, {len(channels)} ch)")


def quantize(freq: float, duration: float) -> float:
    """Snap freq to an integer number of cycles over the loop."""
    return round(freq * duration) / duration


def add_partial(buf: list[float], freq: float, amp: float, duration: float,
                env=None) -> None:
    freq = quantize(freq, duration)
    omega = 2.0 * math.pi * freq / SR
    for i in range(len(buf)):
        value = amp * math.sin(omega * i)
        if env is not None:
            value *= env(i / SR)
        buf[i] += value


def chord_env(start: float, length: float, attack: float, release: float,
              loop: float):
    """Raised-cosine gate, wrapped around the loop seam."""
    def env(t: float) -> float:
        pos = (t - start) % loop
        if pos >= length:
            return 0.0
        if pos < attack:
            return 0.5 * (1.0 - math.cos(math.pi * pos / attack))
        if pos > length - release:
            return 0.5 * (1.0 - math.cos(math.pi * (length - pos) / release))
        return 1.0
    return env


def brown_noise(n: int, leak: float = 0.996, gain: float = 0.03) -> list[float]:
    out = [0.0] * n
    acc = 0.0
    for i in range(n):
        acc = acc * leak + (rng.random() * 2.0 - 1.0) * gain
        out[i] = acc
    return out


def loop_crossfade(buf: list[float], fade_s: float) -> list[float]:
    """Fold the tail into the head so noise loops without a click."""
    fade = int(fade_s * SR)
    body = buf[:-fade]
    tail = buf[-fade:]
    for i in range(fade):
        weight = i / fade
        body[i] = body[i] * weight + tail[i] * (1.0 - weight)
    return body


def make_music() -> None:
    duration = 32.0
    n = int(duration * SR)
    left = [0.0] * n
    right = [0.0] * n

    # Constant drone: D2 and its fifth. The room never goes silent.
    for freq, amp in ((73.42, 0.050), (110.0, 0.022)):
        for mult, ha in ((1, 1.0), (2, 0.30), (3, 0.10)):
            add_partial(left, freq * mult, amp * ha, duration)
            add_partial(right, freq * mult, amp * ha, duration)

    chords = [
        (0.0,  [146.83, 174.61, 220.00]),          # D minor
        (8.0,  [116.54, 146.83, 174.61]),          # Bb major
        (16.0, [87.31, 130.81, 220.00]),           # F major
        (24.0, [130.81, 164.81, 196.00]),          # C major -> back to Dm
    ]
    detune = 0.0006
    for start, tones in chords:
        env = chord_env(start, 8.0, 2.5, 2.5, duration)
        for freq in tones:
            for mult, ha in ((1, 1.0), (2, 0.28), (3, 0.09)):
                amp = 0.042 * ha
                add_partial(left, freq * mult * (1.0 - detune), amp, duration, env)
                add_partial(right, freq * mult * (1.0 + detune), amp, duration, env)

    write_wav(OUT_DIR / "music_loop.wav", [left, right])


def make_hum() -> None:
    duration = 8.0
    n = int(duration * SR)
    left = [0.0] * n
    right = [0.0] * n
    for freq, amp in ((55.0, 0.090), (110.0, 0.045), (165.0, 0.018), (220.0, 0.008)):
        add_partial(left, freq, amp, duration)
        add_partial(right, freq, amp, duration)
    # Slow loop-periodic breathing (2 cycles per loop).
    for buf in (left, right):
        for i in range(n):
            buf[i] *= 1.0 + 0.15 * math.sin(2.0 * math.pi * 2.0 * i / n)
    # A whisper of machinery noise, decorrelated per channel.
    for buf in (left, right):
        noise = loop_crossfade(brown_noise(n + int(0.5 * SR)), 0.5)
        for i in range(n):
            buf[i] += noise[i] * 0.35
    write_wav(OUT_DIR / "hum_loop.wav", [left[:n], right[:n]])


def make_step(path: Path, f0: float, decay: float, noise_amp: float,
              duration: float = 0.28, level: float = 0.42) -> None:
    """A soft sole on concrete: low pitch-swept thump, a whisper of
    lowpassed noise, a gentle attack ramp so there is no click, and
    quiet normalization. No clipping, no crunch."""
    n = int(duration * SR)
    buf = [0.0] * n
    noise = brown_noise(n, leak=0.97, gain=0.3)
    # One-pole lowpass ~450 Hz takes the abrasive edge off the noise.
    alpha = 1.0 - math.exp(-2.0 * math.pi * 450.0 / SR)
    lp = 0.0
    for i in range(n):
        lp += alpha * (noise[i] - lp)
        noise[i] = lp
    for i in range(n):
        t = i / SR
        attack = min(1.0, t / 0.006)
        sweep = f0 * math.exp(-t * 5.0) + 38.0
        body = math.sin(2.0 * math.pi * sweep * t) * math.exp(-t * decay)
        soft = noise[i] * math.exp(-t * decay * 1.4) * noise_amp
        buf[i] = (body + soft) * attack
    write_wav(path, [buf], normalize_to=level)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("generating audio ->", OUT_DIR)
    make_music()
    make_hum()
    for idx, (f0, decay, noise_amp) in enumerate(
            [(72.0, 16.0, 0.50), (78.0, 18.0, 0.42), (66.0, 15.0, 0.55), (84.0, 17.0, 0.38)],
            start=1):
        make_step(OUT_DIR / f"step_{idx}.wav", f0, decay, noise_amp)
    make_step(OUT_DIR / "land.wav", 46.0, 7.0, 0.50, duration=0.55, level=0.55)
    print("done")


if __name__ == "__main__":
    main()
