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
              duration: float = 0.28, level: float = 0.30) -> None:
    """A soft sole on concrete: low pitch-swept thump, a whisper of
    lowpassed noise, a gentle attack ramp so there is no click, and
    quiet normalization. No clipping, no crunch. Tuned dull enough to
    sit right even fully dry (the outdoor sandbox has almost no
    reverb to hide behind)."""
    n = int(duration * SR)
    buf = [0.0] * n
    noise = brown_noise(n, leak=0.97, gain=0.3)
    # Two-pole lowpass ~300 Hz: 12 dB/oct leaves only the thud.
    alpha = 1.0 - math.exp(-2.0 * math.pi * 300.0 / SR)
    for _pass in range(2):
        lp = 0.0
        for i in range(n):
            lp += alpha * (noise[i] - lp)
            noise[i] = lp
    for i in range(n):
        t = i / SR
        attack = min(1.0, t / 0.012)
        sweep = f0 * math.exp(-t * 5.0) + 38.0
        body = math.sin(2.0 * math.pi * sweep * t) * math.exp(-t * decay)
        soft = noise[i] * math.exp(-t * decay * 1.4) * noise_amp
        buf[i] = (body + soft) * attack
    write_wav(path, [buf], normalize_to=level)


def make_motor() -> None:
    """4 s seamless motor loop: mains-hum fundamental, rotor harmonics,
    and a whisper of bearing noise. Pitch-shifted per machine."""
    duration = 4.0
    n = int(duration * SR)
    buf = [0.0] * n
    for freq, amp in ((60.0, 0.30), (120.0, 0.22), (180.0, 0.10),
                      (240.0, 0.07), (300.0, 0.035), (417.0, 0.03)):
        add_partial(buf, freq, amp, duration)
    # Slow loop-periodic load wobble.
    for i in range(n):
        buf[i] *= 1.0 + 0.10 * math.sin(2.0 * math.pi * 3.0 * i / n)
    noise = loop_crossfade(brown_noise(n + int(0.5 * SR), leak=0.95, gain=0.25), 0.5)
    alpha = 1.0 - math.exp(-2.0 * math.pi * 700.0 / SR)
    lp = 0.0
    for i in range(n):
        lp += alpha * (noise[i] - lp)
        buf[i] += lp * 0.18
    write_wav(OUT_DIR / "motor_loop.wav", [buf], normalize_to=0.5)


def make_steam() -> None:
    """4 s seamless steam hiss: bandpassed noise breathing slowly."""
    duration = 4.0
    n = int(duration * SR)
    noise = loop_crossfade(brown_noise(n + int(0.5 * SR), leak=0.6, gain=0.8), 0.5)
    # Highpass-ish: subtract a heavy lowpass to leave the hiss band.
    alpha = 1.0 - math.exp(-2.0 * math.pi * 900.0 / SR)
    lp = 0.0
    buf = [0.0] * n
    for i in range(n):
        lp += alpha * (noise[i] - lp)
        buf[i] = noise[i] - lp
    for i in range(n):
        buf[i] *= 1.0 + 0.18 * math.sin(2.0 * math.pi * 2.0 * i / n)
    write_wav(OUT_DIR / "steam_loop.wav", [buf], normalize_to=0.4)


def make_boiler() -> None:
    """4 s seamless boiler rumble: low rolling boil under a soft roar."""
    duration = 4.0
    n = int(duration * SR)
    buf = [0.0] * n
    for freq, amp in ((31.0, 0.28), (47.0, 0.20), (62.0, 0.14), (89.0, 0.08)):
        add_partial(buf, freq, amp, duration)
    noise = loop_crossfade(brown_noise(n + int(0.5 * SR), leak=0.985, gain=0.15), 0.5)
    for i in range(n):
        # Bubbling: amplitude ripple at a few loop-periodic rates.
        ripple = 1.0 + 0.25 * math.sin(2.0 * math.pi * 7.0 * i / n) \
            + 0.15 * math.sin(2.0 * math.pi * 13.0 * i / n)
        buf[i] = buf[i] * ripple + noise[i] * 0.5
    write_wav(OUT_DIR / "boiler_loop.wav", [buf], normalize_to=0.45)


def highpassed_noise(n: int, cutoff: float, leak: float = 0.6,
                     gain: float = 0.8) -> list[float]:
    """White-ish noise with the low band removed: the hiss register."""
    noise = brown_noise(n, leak=leak, gain=gain)
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / SR)
    lp = 0.0
    out = [0.0] * n
    for i in range(n):
        lp += alpha * (noise[i] - lp)
        out[i] = noise[i] - lp
    return out


def make_valve_air() -> None:
    """Pneumatic actuator stroke: a soft mechanical take-up thock, then
    an air burst that decays as the diaphragm chamber equalizes."""
    duration = 0.55
    n = int(duration * SR)
    buf = [0.0] * n
    hiss = highpassed_noise(n, 1200.0)
    for i in range(n):
        t = i / SR
        attack = min(1.0, t / 0.012)
        thock = math.sin(2.0 * math.pi * (170.0 * math.exp(-t * 9.0) + 60.0) * t) \
            * math.exp(-t * 26.0) * 0.7
        air = hiss[i] * math.exp(-t * 7.5) * attack
        buf[i] = thock + air
    write_wav(OUT_DIR / "valve_air.wav", [buf], normalize_to=0.40)


def make_clunk() -> None:
    """Contactor / motor starter clunk: low armature thump, a metallic
    tick, and one quieter mechanical bounce."""
    duration = 0.30
    n = int(duration * SR)
    buf = [0.0] * n
    tick = highpassed_noise(n, 2500.0, leak=0.4, gain=1.0)
    for i in range(n):
        t = i / SR
        thump = math.sin(2.0 * math.pi * 88.0 * t) * math.exp(-t * 34.0)
        ring = math.sin(2.0 * math.pi * 1380.0 * t) * math.exp(-t * 90.0) * 0.20
        buf[i] = thump + ring + tick[i] * math.exp(-t * 240.0) * 0.5
    bounce_at = int(0.055 * SR)
    for i in range(bounce_at, n):
        t = (i - bounce_at) / SR
        buf[i] += math.sin(2.0 * math.pi * 96.0 * t) * math.exp(-t * 60.0) * 0.35
    write_wav(OUT_DIR / "clunk.wav", [buf], normalize_to=0.48)


def make_relay_click() -> None:
    """Small ice-cube relay click: a 2 ms snap and a tiny ping."""
    duration = 0.09
    n = int(duration * SR)
    buf = [0.0] * n
    snap = highpassed_noise(n, 3000.0, leak=0.3, gain=1.0)
    for i in range(n):
        t = i / SR
        buf[i] = snap[i] * math.exp(-t * 420.0) \
            + math.sin(2.0 * math.pi * 2100.0 * t) * math.exp(-t * 160.0) * 0.25
    write_wav(OUT_DIR / "relay_click.wav", [buf], normalize_to=0.30)


def make_beep() -> None:
    """Annunciator beep: a clean 1.9 kHz tone with cosine ramps, dry
    and a little harsh on purpose — it has to read as an instrument,
    not music."""
    duration = 0.18
    n = int(duration * SR)
    buf = [0.0] * n
    ramp = 0.012
    for i in range(n):
        t = i / SR
        if t < ramp:
            env = 0.5 * (1.0 - math.cos(math.pi * t / ramp))
        elif t > duration - ramp:
            env = 0.5 * (1.0 - math.cos(math.pi * (duration - t) / ramp))
        else:
            env = 1.0
        buf[i] = (math.sin(2.0 * math.pi * 1900.0 * t)
                  + 0.20 * math.sin(2.0 * math.pi * 3800.0 * t)) * env
    write_wav(OUT_DIR / "beep.wav", [buf], normalize_to=0.32)


def make_trap_burst() -> None:
    """Steam trap discharge: hiss swells as the trap opens, chuffs
    while condensate flashes through, and dies as the seat closes."""
    duration = 1.3
    n = int(duration * SR)
    buf = [0.0] * n
    hiss = highpassed_noise(n, 900.0)
    for i in range(n):
        t = i / SR
        swell = min(1.0, t / 0.14)
        decay = math.exp(-max(0.0, t - 0.45) * 4.5)
        chuff = 1.0 + 0.45 * math.sin(2.0 * math.pi * 11.0 * t) \
            + 0.20 * math.sin(2.0 * math.pi * 23.0 * t)
        buf[i] = hiss[i] * swell * decay * chuff
    write_wav(OUT_DIR / "trap_burst.wav", [buf], normalize_to=0.38)


def make_vent_blast() -> None:
    """Main air valve burst: a hard valve pop, then a big rush of air
    that tails off as chamber pressure steps up. Bigger and rounder
    than the actuator's valve_air."""
    duration = 0.85
    n = int(duration * SR)
    buf = [0.0] * n
    rush = highpassed_noise(n, 700.0)
    for i in range(n):
        t = i / SR
        attack = min(1.0, t / 0.006)
        pop = math.sin(2.0 * math.pi * (140.0 * math.exp(-t * 12.0) + 45.0) * t) \
            * math.exp(-t * 30.0) * 0.9
        body = rush[i] * math.exp(-t * 4.2) * attack
        buf[i] = pop + body
    write_wav(OUT_DIR / "vent_blast.wav", [buf], normalize_to=0.46)


def make_gurgle() -> None:
    """3 s seamless condensate gurgle: a soft water-noise bed with
    upward-chirping bubble blips scattered through the loop (kept off
    the seam so it wraps cleanly)."""
    duration = 3.0
    n = int(duration * SR)
    buf = loop_crossfade(brown_noise(n + int(0.5 * SR), leak=0.92, gain=0.10), 0.5)
    for _ in range(46):
        start = rng.uniform(0.05, duration - 0.30)
        blip_len = rng.uniform(0.05, 0.16)
        f0 = rng.uniform(180.0, 420.0)
        sweep = rng.uniform(1.6, 3.2)
        amp = rng.uniform(0.25, 0.65)
        i0 = int(start * SR)
        for j in range(int(blip_len * SR)):
            t = j / SR
            frac = t / blip_len
            env = math.sin(math.pi * frac) ** 2
            buf[i0 + j] += amp * env * math.sin(
                2.0 * math.pi * f0 * (1.0 + sweep * frac) * t)
    write_wav(OUT_DIR / "gurgle_loop.wav", [buf[:n]], normalize_to=0.34)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("generating audio ->", OUT_DIR)
    make_music()
    make_hum()
    make_motor()
    make_steam()
    make_boiler()
    make_valve_air()
    make_clunk()
    make_relay_click()
    make_beep()
    make_trap_burst()
    make_vent_blast()
    make_gurgle()
    for idx, (f0, decay, noise_amp) in enumerate(
            [(72.0, 16.0, 0.50), (78.0, 18.0, 0.42), (66.0, 15.0, 0.55), (84.0, 17.0, 0.38)],
            start=1):
        make_step(OUT_DIR / f"step_{idx}.wav", f0, decay, noise_amp)
    make_step(OUT_DIR / "land.wav", 46.0, 7.0, 0.50, duration=0.55, level=0.42)
    print("done")


if __name__ == "__main__":
    main()
