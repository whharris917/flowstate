"""The film's soundtrack: each line in its character's voice, laid at the
frame it was said; a music box under the titles; mixed with the game's
own sound and put to the picture.

    python soundtrack.py <render.log> <render.avi> <out.mp4>
"""
import sys, os, re, subprocess, math, wave, struct, array, json

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pylib"))
import imageio_ffmpeg  # noqa: E402
FF = imageio_ffmpeg.get_ffmpeg_exe()
FPS = 30.0
RATE = 48000
TRIM = 0.0          # set from the [play] mark, less a little lead-in

log, avi, out = sys.argv[1], sys.argv[2], sys.argv[3]
work = os.path.join(HERE, "voice")
os.makedirs(work, exist_ok=True)

lines, cards, play, end = [], [], None, None
for raw in open(log, encoding="utf-8", errors="replace"):
    raw = raw.rstrip("\n")
    m = re.match(r"\[said\] (\d+)\t(\w+)\t(.*)", raw)
    if m:
        lines.append((int(m.group(1)) / FPS, m.group(2), m.group(3)))
    m = re.match(r"\[card\] (\d+)\t(.*)", raw)
    if m:
        cards.append((int(m.group(1)) / FPS, m.group(2)))
    m = re.match(r"\[play\] (\d+)", raw)
    if m:
        play = int(m.group(1)) / FPS
    m = re.match(r"\[end\] (\d+)", raw)
    if m:
        end = int(m.group(1)) / FPS
TRIM = max((play or 0.0) - 0.2, 0.0)
print("play at %.2f s, end at %s, %d lines" % (play or -1, end, len(lines)))

# Each character's voice: the speech engine's voice, its rate (-10..10),
# then a pitch shift (semitones) keeping the length.
VOICES = {
    "wren": ("Microsoft Zira Desktop", -1, -3.0),
    "rosalind": ("Microsoft Zira Desktop", 2, 1.5),
    "clerk": ("Microsoft David Desktop", 1, -1.5),
}


def speak(i, who, text):
    voice, rate, semis = VOICES.get(who, VOICES["clerk"])
    raw = os.path.join(work, "raw_%02d.wav" % i)
    txt = os.path.join(work, "line_%02d.txt" % i)
    open(txt, "w", encoding="utf-8").write(text)
    ps = (
        "Add-Type -AssemblyName System.Speech; "
        "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
        f"$s.SelectVoice('{voice}'); $s.Rate = {rate}; "
        f"$s.SetOutputToWaveFile('{raw}'); "
        f"$s.Speak([IO.File]::ReadAllText('{txt}')); $s.Dispose()"
    )
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], check=True)
    shifted = os.path.join(work, "line_%02d.wav" % i)
    f = 2.0 ** (semis / 12.0)
    # asetrate shifts the pitch and the pace; atempo puts the pace back.
    af = f"aresample={RATE},asetrate={int(RATE * f)},aresample={RATE},atempo={1.0 / f:.4f},highpass=f=90,volume=1.6"
    subprocess.run([FF, "-y", "-loglevel", "error", "-i", raw, "-af", af, "-ac", "1", "-ar", str(RATE), shifted], check=True)
    with wave.open(shifted) as w:
        return shifted, w.getnframes() / w.getframerate()


# The music box: a small waltz in D under the title cards and the end.
def music_box(path, secs, seed_notes):
    n = int(secs * RATE)
    buf = array.array("f", [0.0]) * n
    beat = 0.42
    for k, note in enumerate(seed_notes * 8):
        t0 = k * beat
        if t0 >= secs - 1.0 or note is None:
            continue
        f = 440.0 * 2 ** ((note - 69) / 12.0)
        i0 = int(t0 * RATE)
        for j in range(int(2.4 * RATE)):
            if i0 + j >= n:
                break
            t = j / RATE
            env = math.exp(-t * 2.2) * min(1.0, t * 300)
            s = (math.sin(2 * math.pi * f * t) + 0.35 * math.sin(2 * math.pi * 2.01 * f * t) + 0.12 * math.sin(2 * math.pi * 3.98 * f * t))
            buf[i0 + j] += 0.16 * env * s
    fade = int(1.5 * RATE)
    for j in range(fade):
        buf[n - 1 - j] *= j / fade
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack("<%dh" % n, *[int(max(-1, min(1, x)) * 32000) for x in buf]))


tune = [74, 78, 81, 79, 78, 76, 74, None, 73, 76, 79, 78, 76, 74, 73, None]
music_box(os.path.join(work, "music_open.wav"), 9.5, tune)
music_box(os.path.join(work, "music_end.wav"), 12.0, [81, 79, 78, 76, 74, None, 76, 78, 74, None, None, None])

# The voices, placed; a line never starts before the last has finished.
placed = []
free_at = 0.0
for i, (t, who, text) in enumerate(lines if os.environ.get("VOICES_IN_GAME") != "1" else []):
    path, dur = speak(i, who, text)
    at = max(t - TRIM + 0.15, free_at + 0.12)
    placed.append((path, at, dur, who, text))
    free_at = at + dur
json.dump([(p[1], p[2], p[3], p[4]) for p in placed], open(os.path.join(work, "placed.json"), "w"), indent=1)

length = ((end or (lines[-1][0] + 8)) - TRIM) + 1.5
inputs = ["-ss", f"{TRIM:.3f}", "-i", avi]
filters = []
mix = ["[0:a]volume=%s[a0]" % ("1.0" if os.environ.get("VOICES_IN_GAME") == "1" else "0.55")]
labels = ["[a0]"]
k = 1
open_at = max((cards[0][0] - TRIM) if cards else 0.0, 0.0)
end_at = max((cards[-2][0] - TRIM) if len(cards) >= 2 else length - 12, 0.0)
for path, at in [(os.path.join(work, "music_open.wav"), open_at), (os.path.join(work, "music_end.wav"), end_at)]:
    inputs += ["-i", path]
    mix.append(f"[{k}:a]adelay={int(at * 1000)}|{int(at * 1000)},volume=0.9[a{k}]")
    labels.append(f"[a{k}]")
    k += 1
for path, at, dur, who, text in placed:
    inputs += ["-i", path]
    mix.append(f"[{k}:a]adelay={int(at * 1000)}|{int(at * 1000)}[a{k}]")
    labels.append(f"[a{k}]")
    k += 1
mix.append("".join(labels) + f"amix=inputs={len(labels)}:normalize=0:duration=first,alimiter=limit=0.9[aout]")
cmd = [FF, "-y", "-loglevel", "error"] + inputs + ["-filter_complex", ";".join(mix), "-map", "0:v", "-map", "[aout]",
       "-t", f"{length:.2f}", "-c:v", "libx264", "-preset", "slow", "-crf", "20", "-pix_fmt", "yuv420p",
       "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", out]
subprocess.run(cmd, check=True)
print("wrote %s, %.1f s, %d voiced lines" % (out, length, len(placed)))
