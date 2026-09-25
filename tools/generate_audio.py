"""Generate the game's placeholder audio as WAV files, procedurally.

Run from the project root:

    .venv\\Scripts\\python.exe tools\\generate_audio.py

Writes to game/audio/:
  music_loop.wav  40 s seamless clockwork sequencer piece in D minor:
                  a tick on every beat, a sixteenth-note pluck arpeggio,
                  a pulsing sub bass, detuned pads, a sparse lead
  hum_loop.wav    8 s seamless ship hum — 55 Hz fundamental + harmonics
                  and a whisper of low noise
  step_1..4.wav   footstep thumps (pitch-swept sine + noise burst)
  land.wav        heavier landing thump
  surf_loop.wav   16 s seamless surf on a ledge, swells breaking as hiss
  wind_loop.wav   12 s seamless wind off the water, gusting
  gull_1..3.wav   herring gull cries: one long, a long call, a pair
  river_loop.wav  10 s seamless stream over stones: a low rush, a
                  chatter of eddies, bubbles now and then
  drip_1..3.wav   a water drop landing: the bubble plink, a rising
                  chirp that dies in a few hundredths of a second
  pour_loop.wav   3 s seamless trickle into a vessel: a thin splash
                  with bubbles under it
  dosing_loop.wav 2 s seamless metering-pump drive: a small motor with
                  the diaphragm's tick every half second
  rain_loop.wav   10 s seamless steady rain: hiss, run-off and near drops
  gale_loop.wav   14 s seamless gale, gusting hard, a moan on an edge
  thunder_near.wav, thunder_1..2.wav  a close stroke's crack and roll;
                  two distant rolls, darker with distance
  bell_1..2.wav   a bell buoy's bronze bell, struck hard and soft
  foghorn.wav     a diaphone blast and its falling grunt

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


# ---- music ----------------------------------------------------------------
# A clockwork sequencer piece (the vibe of
# Daniel Pemberton's "Clock Numbers" from Project Hail Mary — an
# original piece in that analog-sequencer lineage, not a copy). A tick
# on every beat, a sixteenth-note pluck arpeggio rolling through the
# chord with its filter opening across each four-bar phrase, a pulsing
# sub bass, soft detuned pads, and a sparse descending lead in the
# second half. 96 BPM makes a sixteenth exactly 5000 samples; 16 bars
# is 40 s, and every event that runs past the end wraps to the start,
# so the loop is seamless by construction.
MUSIC_BPM = 96
SIXTEENTH = int(SR * 60 / MUSIC_BPM / 4)   # 5000 samples
BAR = SIXTEENTH * 16
MUSIC_BARS = 16
MUSIC_N = BAR * MUSIC_BARS

# Chord slots: (first bar, bars, pad tones, arpeggio pitches, bass root).
# D minor throughout: i, VI, III, VII, v — the v pulls back to i at the seam.
MUSIC_CHORDS = [
    (0, 4, [146.83, 174.61, 220.00], [146.83, 174.61, 220.00, 293.66, 349.23], 73.42),   # Dm
    (4, 4, [116.54, 146.83, 174.61], [146.83, 174.61, 233.08, 293.66, 349.23], 58.27),   # Bb
    (8, 4, [174.61, 220.00, 261.63], [174.61, 220.00, 261.63, 349.23, 440.00], 87.31),   # F
    (12, 2, [130.81, 164.81, 196.00], [164.81, 196.00, 261.63, 329.63, 392.00], 65.41),  # C
    (14, 2, [110.00, 130.81, 164.81], [164.81, 220.00, 261.63, 329.63, 440.00], 55.00),  # Am
]
ARP_PATTERN = [0, 1, 2, 3, 4, 3, 2, 1, 0, 1, 2, 3, 4, 3, 2, 1]
# (bar, sixteenth, pitch Hz, sixteenths held): a lead that steps down
# from the fifth to the root over the second half and is gone by the seam.
MUSIC_LEAD = [
    (8, 0, 440.00, 30), (10, 0, 392.00, 14), (11, 0, 349.23, 14),
    (12, 0, 329.63, 30), (14, 0, 293.66, 26),
]


def _add_wrapped(buf: list[float], start: int, samples: list[float], gain: float) -> None:
    """Mix samples into the loop from start, wrapping past the seam."""
    n = len(buf)
    for j, v in enumerate(samples):
        buf[(start + j) % n] += v * gain


def _pluck(freq: float, length: int, bright: float) -> list[float]:
    """Sequencer pluck: four harmonics, the upper ones decaying faster
    so the note darkens as it rings; bright (0..1) is the filter."""
    out = [0.0] * length
    w = 2.0 * math.pi * freq / SR
    for k, base in ((1, 1.0), (2, 0.55), (3, 0.30), (4, 0.16)):
        amp = base if k == 1 else base * (0.25 + 0.75 * bright)
        tau = 0.26 / (k ** 0.9)
        wk = w * k
        for i in range(length):
            e = math.exp(-i / SR / tau)
            if i < 64:
                e *= i / 64.0
            out[i] += amp * e * math.sin(wk * i)
    return out


def _tick(freq: float, length: int, noise: float, r: random.Random) -> list[float]:
    """A clock escapement: a short ringing ping under a burst of noise."""
    out = [0.0] * length
    w = 2.0 * math.pi * freq / SR
    for i in range(length):
        t = i / SR
        out[i] = (0.7 * math.exp(-t / 0.0045) * math.sin(w * i)
                  + noise * math.exp(-t / 0.0012) * (r.random() * 2.0 - 1.0))
    return out


def _bass_pulse(freq: float, length: int) -> list[float]:
    out = [0.0] * length
    w = 2.0 * math.pi * freq / SR
    for i in range(length):
        e = math.exp(-i / SR / 0.22) * min(1.0, i / 160.0)
        out[i] = e * (math.sin(w * i) + 0.35 * math.sin(2.0 * w * i))
    return out


def _pad_voice(freq: float, length: int, edge: int, detune: float,
               harmonics: tuple[tuple[int, float], ...]) -> list[float]:
    """A sustained voice with raised-cosine edges of `edge` samples at
    both ends; two of these a slot apart cross at equal gain."""
    out = [0.0] * length
    w = 2.0 * math.pi * freq * (1.0 + detune) / SR
    for k, amp in harmonics:
        wk = w * k
        for i in range(length):
            out[i] += amp * math.sin(wk * i)
    for i in range(edge):
        g = 0.5 * (1.0 - math.cos(math.pi * i / edge))
        out[i] *= g
        out[length - 1 - i] *= g
    return out


def _lead_note(freq: float, length: int) -> list[float]:
    """A soft lead with vibrato that arrives after the note settles."""
    out = [0.0] * length
    attack = int(0.35 * SR)
    release = int(0.6 * SR)
    phase = 0.0
    for i in range(length):
        t = i / SR
        vib = 1.0 + 0.0035 * min(1.0, max(0.0, (t - 0.4) / 0.6)) * math.sin(2.0 * math.pi * 4.6 * t)
        phase += 2.0 * math.pi * freq * vib / SR
        v = math.sin(phase) + 0.35 * math.sin(2.0 * phase) + 0.12 * math.sin(3.0 * phase)
        if i < attack:
            v *= 0.5 * (1.0 - math.cos(math.pi * i / attack))
        if i > length - release:
            v *= 0.5 * (1.0 - math.cos(math.pi * (length - i) / release))
        out[i] = v
    return out


def make_music() -> None:
    n = MUSIC_N
    left = [0.0] * n
    right = [0.0] * n
    local = random.Random(20260902)   # own stream: the other files stay byte-identical

    # The clock: tock on beats 1 and 3 to the right, tick on 2 and 4 to
    # the left, 96 to the minute.
    tock = _tick(1900.0, int(0.03 * SR), 0.9, local)
    tick = _tick(2600.0, int(0.03 * SR), 0.7, local)
    for beat in range(MUSIC_BARS * 4):
        at = beat * SIXTEENTH * 4
        if beat % 2 == 0:
            _add_wrapped(right, at, tock, 0.085)
            _add_wrapped(left, at, tock, 0.045)
        else:
            _add_wrapped(left, at, tick, 0.065)
            _add_wrapped(right, at, tick, 0.035)

    pad_h = ((1, 1.0), (2, 0.42), (3, 0.16))
    edge = int(1.0 * SR)   # the crossfade: each slot starts a second early and ends a second late
    pluck_len = int(0.34 * SR)
    pulse_len = SIXTEENTH * 2
    for first_bar, bars, tones, arp, root in MUSIC_CHORDS:
        slot_start = first_bar * BAR
        slot_len = bars * BAR
        # Pads: chord tones detuned apart left and right, the root an
        # octave down in the middle.
        for f in tones:
            _add_wrapped(left, slot_start - edge,
                         _pad_voice(f, slot_len + 2 * edge, edge, -0.0025, pad_h), 0.075)
            _add_wrapped(right, slot_start - edge,
                         _pad_voice(f, slot_len + 2 * edge, edge, 0.0025, pad_h), 0.075)
        low = _pad_voice(root, slot_len + 2 * edge, edge, 0.0, ((1, 1.0), (2, 0.2)))
        _add_wrapped(left, slot_start - edge, low, 0.06)
        _add_wrapped(right, slot_start - edge, low, 0.06)
        # Bass: an eighth-note pulse on the root, leaning on the downbeat.
        for eighth in range(bars * 8):
            at = slot_start + eighth * SIXTEENTH * 2
            g = 0.30 if eighth % 8 == 0 else 0.22
            pulse = _bass_pulse(root, pulse_len)
            _add_wrapped(left, at, pulse, g)
            _add_wrapped(right, at, pulse, g)
        # Arpeggio: sixteenths through the pattern, ping-ponging left and
        # right, accented on the beat, the filter opening over each
        # four-bar phrase, and a breath at the end of every fourth bar.
        for bar in range(bars):
            phrase_pos = ((first_bar + bar) % 4 + 0.5) / 4.0
            for step in range(16):
                if (first_bar + bar) % 4 == 3 and step >= 14:
                    continue
                bright = 0.35 + 0.65 * (phrase_pos * 0.7 + 0.3 * step / 16.0)
                note = _pluck(arp[ARP_PATTERN[step]], pluck_len, bright)
                accent = 1.0 if step % 4 == 0 else (0.8 if step % 2 == 0 else 0.66)
                pan = 0.35 if step % 2 == 0 else -0.35
                at = slot_start + bar * BAR + step * SIXTEENTH
                _add_wrapped(left, at, note, 0.21 * accent * math.sqrt((1.0 - pan) / 2.0))
                _add_wrapped(right, at, note, 0.21 * accent * math.sqrt((1.0 + pan) / 2.0))

    for bar, step, freq, held in MUSIC_LEAD:
        note = _lead_note(freq, held * SIXTEENTH)
        at = bar * BAR + step * SIXTEENTH
        _add_wrapped(left, at, note, 0.13)
        _add_wrapped(right, at, note, 0.13)

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


def make_servo() -> None:
    """Servo index move: a quick rising whir that settles with a tiny
    detent tick — one conveyor step."""
    duration = 0.42
    n = int(duration * SR)
    buf = [0.0] * n
    move_s = 0.30
    for i in range(n):
        t = i / SR
        if t < move_s:
            frac = t / move_s
            f = 240.0 + 520.0 * math.sin(math.pi * frac)   # rev up, rev down
            env = math.sin(math.pi * frac) ** 0.7
            buf[i] = (math.sin(2.0 * math.pi * f * t)
                      + 0.35 * math.sin(2.0 * math.pi * 2.0 * f * t)) * env * 0.5
    tick_at = int((move_s + 0.02) * SR)
    for i in range(tick_at, n):
        t = (i - tick_at) / SR
        buf[i] += math.sin(2.0 * math.pi * 1600.0 * t) * math.exp(-t * 300.0) * 0.4
    write_wav(OUT_DIR / "servo.wav", [buf], normalize_to=0.30)


def make_milestone() -> None:
    """Milestone chime (campaign): three rising notes of a D
    major triad with a soft octave under each, bell-like decays, a
    touch under a second. Pure sines and no RNG, so every other file
    stays byte-identical."""
    duration = 1.1
    n = int(duration * SR)
    buf = [0.0] * n
    notes = [(587.33, 0.00), (739.99, 0.16), (880.00, 0.32), (1174.66, 0.50)]
    for freq, start in notes:
        start_i = int(start * SR)
        for i in range(start_i, n):
            t = (i - start_i) / SR
            attack = min(t / 0.012, 1.0)
            env = attack * math.exp(-t * 3.2)
            buf[i] += (math.sin(2.0 * math.pi * freq * t)
                       + 0.35 * math.sin(2.0 * math.pi * freq * 2.0 * t) * math.exp(-t * 6.0)
                       + 0.18 * math.sin(2.0 * math.pi * freq * 0.5 * t)) * env
    write_wav(OUT_DIR / "milestone.wav", [buf], normalize_to=0.36)


# ---- the coast --------------------------------------------------------------
# The Maine coast's ambience. Each has its own RNG so the
# files above stay byte-identical whatever is added here.

def _noise_r(r: random.Random, n: int) -> list[float]:
    return [r.random() * 2.0 - 1.0 for _ in range(n)]


def _lowpass(buf: list[float], alpha: float) -> list[float]:
    """One-pole low-pass; the cutoff is about alpha * SR / 2 pi."""
    out = [0.0] * len(buf)
    acc = 0.0
    for i, value in enumerate(buf):
        acc += alpha * (value - acc)
        out[i] = acc
    return out


def make_surf() -> None:
    """Surf on a ledge: the sea's low body under swells that break as a
    rising hiss and drag back. Two swell periods share the loop, so the
    seam falls where both are quiet."""
    r = random.Random(20260913)
    dur = 16.0
    n = int(SR * dur)
    fade = int(0.6 * SR)
    total = n + fade
    white = _noise_r(r, total)
    body = _lowpass(white, 0.012)
    high = _lowpass(white, 0.25)
    hiss = [w - h for w, h in zip(white, high)]
    out = [0.0] * total
    for i in range(total):
        t = i / SR
        s1 = math.sin(2.0 * math.pi * t * 2.0 / dur)
        s2 = math.sin(2.0 * math.pi * t * 3.0 / dur + 1.3)
        env = max(0.0, 0.55 * s1 + 0.45 * s2) ** 1.6
        out[i] = body[i] * (0.35 + 0.65 * env) * 4.0 + hiss[i] * env * 0.9
    out = loop_crossfade(out, 0.6)
    write_wav(OUT_DIR / "surf_loop.wav", [out], normalize_to=0.45)


def make_wind() -> None:
    """Wind off the water: filtered noise breathing in gusts, quiet."""
    r = random.Random(20260914)
    dur = 12.0
    n = int(SR * dur)
    fade = int(0.5 * SR)
    total = n + fade
    white = _noise_r(r, total)
    low = _lowpass(white, 0.05)
    mid = _lowpass(white, 0.18)
    out = [0.0] * total
    for i in range(total):
        t = i / SR
        gust = 0.5 + 0.3 * math.sin(2.0 * math.pi * t * 1.0 / dur + 0.4) \
            + 0.2 * math.sin(2.0 * math.pi * t * 3.0 / dur + 2.0)
        gust = max(0.0, gust)
        out[i] = low[i] * (0.4 + 0.6 * gust) * 3.0 + (mid[i] - low[i]) * gust * gust * 1.2
    out = loop_crossfade(out, 0.5)
    write_wav(OUT_DIR / "wind_loop.wav", [out], normalize_to=0.35)


def make_river() -> None:
    """A stream over stones: a low rush that never stops, a mid-band
    chatter of eddies breathing on several slow cycles that share the
    loop, and the odd bubble — a short falling chirp. Its own RNG, so
    the older files stay byte-identical."""
    r = random.Random(20260918)
    dur = 10.0
    n = int(SR * dur)
    fade = int(0.5 * SR)
    total = n + fade
    white = _noise_r(r, total)
    low = _lowpass(white, 0.04)
    mid = _lowpass(white, 0.16)
    high = _lowpass(white, 0.45)
    out = [0.0] * total
    for i in range(total):
        t = i / SR
        eddy = 0.55 + 0.25 * math.sin(2.0 * math.pi * t * 3.0 / dur + 0.9) \
            + 0.2 * math.sin(2.0 * math.pi * t * 7.0 / dur + 2.4)
        eddy = max(0.0, eddy)
        out[i] = low[i] * 2.2 + (mid[i] - low[i]) * (0.6 + 0.9 * eddy) * 1.6 \
            + (high[i] - mid[i]) * eddy * eddy * 0.9
    bubbles = int(dur * 6)
    for _b in range(bubbles):
        start = int(r.random() * n)
        f0 = r.uniform(900.0, 1600.0)
        length = int(SR * r.uniform(0.02, 0.05))
        phase = 0.0
        for k in range(length):
            tt = k / length
            f = f0 * (0.55 ** tt)
            phase += 2.0 * math.pi * f / SR
            env = math.sin(math.pi * tt) ** 2
            idx = (start + k) % total
            out[idx] += math.sin(phase) * env * 0.16
    out = loop_crossfade(out, 0.5)
    write_wav(OUT_DIR / "river_loop.wav", [out], normalize_to=0.40)


def make_gull(path: Path, calls: list[tuple[float, float, float, float]],
              r: random.Random) -> None:
    """A herring gull: a reedy descending cry — a stack of harmonics
    under a fast vibrato, with a scratch at the onset. calls are
    (start Hz, end Hz, length s, gap s), one per note."""
    out: list[float] = []
    phase = 0.0
    for f0, f1, length, gap in calls:
        m = int(SR * length)
        for i in range(m):
            t = i / m
            tt = i / SR
            f = f0 * (f1 / f0) ** t
            vib = 1.0 + 0.025 * math.sin(2.0 * math.pi * 38.0 * tt)
            phase += 2.0 * math.pi * f * vib / SR
            attack = min(1.0, tt / 0.015)
            release = min(1.0, (length - tt) / (0.3 * length))
            env = attack * release
            tone = (math.sin(phase) + 0.55 * math.sin(2.0 * phase) + 0.35 * math.sin(3.0 * phase)
                    + 0.2 * math.sin(4.0 * phase) + 0.12 * math.sin(5.0 * phase))
            scratch = (r.random() * 2.0 - 1.0) * 0.10 * (1.0 - t) ** 2
            out.append((tone * 0.5 + scratch) * env)
        out.extend([0.0] * int(SR * gap))
    write_wav(path, [out], normalize_to=0.40)


def make_gulls() -> None:
    r = random.Random(20260915)
    make_gull(OUT_DIR / "gull_1.wav", [(1250.0, 820.0, 0.75, 0.05)], r)
    make_gull(OUT_DIR / "gull_2.wav",
              [(1150.0, 950.0, 0.16, 0.08)] * 4 + [(1300.0, 800.0, 0.55, 0.05)], r)
    make_gull(OUT_DIR / "gull_3.wav",
              [(1380.0, 900.0, 0.45, 0.12), (1300.0, 880.0, 0.45, 0.05)], r)


def make_drip(path: Path, f0: float, rise: float, r: random.Random) -> None:
    """One water drop landing: a bubble resonance, a sine that chirps
    upward as the bubble shrinks and dies in a few hundredths of a
    second, with a whisper of splash at the instant it lands."""
    dur = 0.16
    n = int(SR * dur)
    buf = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        freq = f0 * (1.0 + rise * (1.0 - math.exp(-t / 0.018)))
        phase += 2.0 * math.pi * freq / SR
        env = math.exp(-t / 0.040) * min(1.0, t / 0.002)
        splash = (r.random() * 2.0 - 1.0) * 0.35 * math.exp(-t / 0.004)
        buf[i] = math.sin(phase) * env + splash
    write_wav(path, [buf], normalize_to=0.40)


def make_drips() -> None:
    r = random.Random(20260920)
    make_drip(OUT_DIR / "drip_1.wav", 760.0, 1.1, r)
    make_drip(OUT_DIR / "drip_2.wav", 940.0, 0.9, r)
    make_drip(OUT_DIR / "drip_3.wav", 1120.0, 1.3, r)


def make_pour() -> None:
    """A trickle into a vessel: a thin band of splash noise, bubbles
    under it now and then, seamless over three seconds."""
    r = random.Random(20260921)
    dur = 3.0
    n = int(SR * dur)
    fade = int(0.25 * SR)
    total = n + fade
    white = _noise_r(r, total)
    low = _lowpass(white, 0.08)
    high = _lowpass(white, 0.35)
    band = [h - l for h, l in zip(high, low)]
    out = [0.0] * total
    for i in range(total):
        t = i / SR
        swell = 0.75 + 0.25 * math.sin(2.0 * math.pi * t * 2.0 / dur + 0.7)
        out[i] = band[i] * swell * 1.6
    # Bubbles: short rising chirps, a few a second.
    for _ in range(int(dur * 4)):
        start = int(r.random() * n)
        f0 = 250.0 + r.random() * 500.0
        length = int(SR * 0.05)
        phase = 0.0
        for k in range(length):
            t = k / SR
            freq = f0 * (1.0 + 0.8 * (1.0 - math.exp(-t / 0.015)))
            phase += 2.0 * math.pi * freq / SR
            env = math.exp(-t / 0.014)
            idx = (start + k) % total
            out[idx] += math.sin(phase) * env * 0.5
    out = loop_crossfade(out, 0.25)
    write_wav(OUT_DIR / "pour_loop.wav", [out], normalize_to=0.38)


def make_dosing() -> None:
    """A metering pump running: a small motor, quiet, and the diaphragm
    tick every half second, four to the two-second loop."""
    r = random.Random(20260922)
    dur = 2.0
    n = int(SR * dur)
    out = [0.0] * n
    f_motor = quantize(95.0, dur)
    f_whine = quantize(1420.0, dur)
    for i in range(n):
        t = i / SR
        out[i] = 0.35 * math.sin(2.0 * math.pi * f_motor * t) \
            + 0.12 * math.sin(2.0 * math.pi * f_motor * 2.0 * t) \
            + 0.03 * math.sin(2.0 * math.pi * f_whine * t)
    for k in range(4):
        start = int(k * SR * 0.5)
        length = int(SR * 0.04)
        for j in range(length):
            t = j / SR
            click = (r.random() * 2.0 - 1.0) * math.exp(-t / 0.004) * 0.9 \
                + math.sin(2.0 * math.pi * 320.0 * t) * math.exp(-t / 0.012) * 0.6
            out[(start + j) % n] += click
    write_wav(OUT_DIR / "dosing_loop.wav", [out], normalize_to=0.34)


def make_clink() -> None:
    """A vial set down on steel (the filling line): a glass
    tap, a handful of inharmonic partials ringing out at their own rates
    over a click. Pure sines, no RNG, so no other file moves."""
    duration = 0.4
    n = int(duration * SR)
    buf = [0.0] * n
    partials = [(2630.0, 1.0, 22.0), (4180.0, 0.6, 30.0), (5870.0, 0.45, 38.0),
                (7340.0, 0.3, 46.0), (1190.0, 0.25, 60.0)]
    for i in range(n):
        t = i / SR
        v = 0.0
        for f, a_, d in partials:
            v += a_ * math.sin(2.0 * math.pi * f * t) * math.exp(-t * d)
        v += math.sin(2.0 * math.pi * 900.0 * t) * math.exp(-t * 400.0) * 0.6
        buf[i] = v
    write_wav(OUT_DIR / "clink.wav", [buf], normalize_to=0.30)


# The harbour town's weather and its harbour. Each has its own RNG, or
# none, so every file above stays byte-identical.

def make_rain() -> None:
    """Steady rain: a broad hiss of drops too many to count, a low
    body of water running off roofs and gutters, and the nearer drops
    as distinct ticks, a couple of hundred a second. Seamless over ten
    seconds."""
    r = random.Random(20260925)
    dur = 10.0
    n = int(SR * dur)
    fade = int(0.5 * SR)
    total = n + fade
    white = _noise_r(r, total)
    low = _lowpass(white, 0.03)
    mid = _lowpass(white, 0.30)
    hiss = [w - m for w, m in zip(white, mid)]
    body = [m - lo for m, lo in zip(mid, low)]
    out = [0.0] * total
    for i in range(total):
        t = i / SR
        swell = 0.85 + 0.15 * math.sin(2.0 * math.pi * t * 2.0 / dur + 0.3)
        out[i] = (hiss[i] * 0.55 + body[i] * 0.9 + low[i] * 1.2) * swell
    for _ in range(int(dur * 220)):
        start = int(r.random() * n)
        f0 = r.uniform(1800.0, 5200.0)
        amp = r.uniform(0.05, 0.35) ** 2
        length = int(SR * 0.012)
        for k in range(length):
            t = k / SR
            env = math.exp(-t / 0.0022)
            out[(start + k) % total] += (math.sin(2.0 * math.pi * f0 * t) * 0.6
                                         + (r.random() * 2.0 - 1.0) * 0.4) * env * amp
    out = loop_crossfade(out, 0.5)
    write_wav(OUT_DIR / "rain_loop.wav", [out], normalize_to=0.40)


def make_gale() -> None:
    """A gale: the wind loop's big brother, a roaring low band that
    gusts hard on slow cycles, and a thin moan where it finds an edge,
    rising and falling with the gusts."""
    r = random.Random(20260926)
    dur = 14.0
    n = int(SR * dur)
    fade = int(0.7 * SR)
    total = n + fade
    white = _noise_r(r, total)
    low = _lowpass(white, 0.035)
    mid = _lowpass(white, 0.20)
    out = [0.0] * total
    phase = 0.0
    for i in range(total):
        t = i / SR
        gust = 0.55 + 0.30 * math.sin(2.0 * math.pi * t * 2.0 / dur + 0.4) \
            + 0.25 * math.sin(2.0 * math.pi * t * 5.0 / dur + 1.9)
        gust = max(0.0, gust)
        phase += 2.0 * math.pi * (310.0 + 140.0 * gust) / SR
        moan = math.sin(phase) * max(0.0, gust - 0.55) ** 2 * 0.35
        out[i] = low[i] * (0.5 + 0.8 * gust) * 3.2 + (mid[i] - low[i]) * gust * gust * 1.6 + moan * 0.05
    out = loop_crossfade(out, 0.7)
    write_wav(OUT_DIR / "gale_loop.wav", [out], normalize_to=0.40)


def make_thunder(path: Path, r: random.Random, crack: float, length: float,
                 bumps: int, darkness: float) -> None:
    """Thunder: a crack (a split second of broadband tearing, several
    tears in a row) when the stroke is close, then the roll: brown
    noise under an envelope of rumbles, each a stretch of the channel
    heard later from further along it, decaying. darkness is the
    low-pass on the roll: distance takes the top off."""
    n = int(SR * length)
    white = _noise_r(r, n)
    roll_src = _lowpass(_lowpass(white, 0.012 * (1.0 - darkness) + 0.002), 0.05)
    env = [0.0] * n
    for b in range(bumps):
        at = r.uniform(0.05, 0.55) * length * (b + 1) / bumps
        width = r.uniform(0.4, 1.4)
        amp = r.uniform(0.5, 1.0) * math.exp(-at / (0.35 * length))
        for i in range(n):
            d = (i / SR - at) / width
            if -3.0 < d < 8.0:
                env[i] += amp * (math.exp(-d * d) if d < 0.0 else math.exp(-d * 0.7))
    out = [roll_src[i] * env[i] * 9.0 for i in range(n)]
    if crack > 0.0:
        tears = _lowpass(white, 0.6)
        for k in range(4):
            start = int(SR * (0.02 + 0.07 * k + r.uniform(0.0, 0.03)))
            m = int(SR * 0.18)
            for j in range(m):
                t = j / SR
                e = math.exp(-t / 0.045) * min(1.0, t / 0.002) * (1.0 - 0.18 * k)
                if start + j < n:
                    out[start + j] += tears[start + j] * e * crack * 1.4
    # Fade the last half second so nothing is cut off.
    tail = int(0.5 * SR)
    for i in range(tail):
        out[n - tail + i] *= 1.0 - i / tail
    write_wav(path, [out], normalize_to=0.55)


def make_thunders() -> None:
    r = random.Random(20260927)
    make_thunder(OUT_DIR / "thunder_near.wav", r, crack=1.0, length=9.0, bumps=5, darkness=0.2)
    make_thunder(OUT_DIR / "thunder_1.wav", r, crack=0.0, length=10.0, bumps=6, darkness=0.6)
    make_thunder(OUT_DIR / "thunder_2.wav", r, crack=0.0, length=12.0, bumps=7, darkness=0.85)


def make_bell(path: Path, f0: float, bright: float) -> None:
    """A bell buoy's bell: bronze, struck by a free clapper as the buoy
    rolls. The church-bell partials (the hum an octave under the
    strike, the minor third, the fifth, the octave and above) each ring
    at their own rate, the hum longest, each beating slowly as a real
    bell does. bright is how hard the clapper hit. Pure sines, no RNG."""
    duration = 6.0
    n = int(duration * SR)
    partials = [(0.5, 0.55, 0.45), (1.0, 1.0, 0.9), (1.183, 0.55, 1.3), (1.506, 0.35, 1.7),
                (2.0, 0.45 * bright, 2.2), (2.514, 0.25 * bright, 3.0), (2.662, 0.2 * bright, 3.4),
                (3.011, 0.18 * bright, 4.0), (4.166, 0.10 * bright, 6.0)]
    buf = [0.0] * n
    for i in range(n):
        t = i / SR
        v = 0.0
        for ratio, amp, decay in partials:
            beat = 1.0 + 0.08 * math.sin(2.0 * math.pi * 0.7 * ratio * t)
            v += amp * beat * math.sin(2.0 * math.pi * f0 * ratio * t) * math.exp(-t * decay)
        strike = math.sin(2.0 * math.pi * f0 * 5.4 * t) * math.exp(-t * 60.0) * 0.4 * bright
        buf[i] = (v + strike) * min(1.0, t / 0.002)
    tail = int(0.3 * SR)
    for i in range(tail):
        buf[n - tail + i] *= 1.0 - i / tail
    write_wav(path, [buf], normalize_to=0.45)


def make_bells() -> None:
    make_bell(OUT_DIR / "bell_1.wav", 392.0, 1.0)
    make_bell(OUT_DIR / "bell_2.wav", 392.0, 0.6)


def make_foghorn() -> None:
    """A diaphone foghorn: a reedy blast, the piston's buzz full of
    harmonics, then the grunt, the pitch dropping as the air runs out.
    The blast swells in over a fifth of a second. Pure sines, no RNG."""
    duration = 5.0
    n = int(duration * SR)
    blast = 2.6
    grunt = 0.9
    buf = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        if t < blast:
            f = 176.0
        else:
            u = min(1.0, (t - blast) / grunt)
            f = 176.0 - 70.0 * u ** 0.6
        phase += 2.0 * math.pi * f / SR
        on = min(1.0, t / 0.2) * (1.0 if t < blast + grunt else math.exp(-(t - blast - grunt) / 0.08))
        tone = 0.0
        for h in range(1, 14):
            tone += math.sin(h * phase) / h ** 1.1 * (1.0 if h < 6 else 0.7)
        buf[i] = tone * on
    write_wav(OUT_DIR / "foghorn.wav", [buf], normalize_to=0.55)


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
    make_servo()
    make_milestone()
    make_surf()
    make_wind()
    make_gulls()
    make_river()
    for idx, (f0, decay, noise_amp) in enumerate(
            [(72.0, 16.0, 0.50), (78.0, 18.0, 0.42), (66.0, 15.0, 0.55), (84.0, 17.0, 0.38)],
            start=1):
        make_step(OUT_DIR / f"step_{idx}.wav", f0, decay, noise_amp)
    make_step(OUT_DIR / "land.wav", 46.0, 7.0, 0.50, duration=0.55, level=0.42)
    make_drips()
    make_pour()
    make_dosing()
    make_clink()
    make_rain()
    make_gale()
    make_thunders()
    make_bells()
    make_foghorn()
    print("done")


if __name__ == "__main__":
    main()
