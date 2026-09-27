"""Voice every line of a take before it is filmed: each actor's lines in
its own voice, written to user://voices/ with an index the stage reads
(actor|text -> file, seconds).

    python voices.py <take.json>
"""
import sys, os, json, subprocess, wave, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "pylib"))
import imageio_ffmpeg  # noqa: E402
FF = imageio_ffmpeg.get_ffmpeg_exe()
USER = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\flowstate")
OUT = os.path.join(USER, "voices")
os.makedirs(OUT, exist_ok=True)
RATE = 44100

VOICES = {
    "wren": ("Microsoft Zira Desktop", 0, -3.0),
    "rosalind": ("Microsoft Zira Desktop", 2, 1.5),
    "clerk": ("Microsoft David Desktop", 1, -1.5),
}

take = json.load(open(sys.argv[1], encoding="utf-8"))
lines = []
for e in take["events"]:
    for c in e.get("commands", []):
        if c.get("do") == "say" and c.get("text"):
            lines.append((e["actor"], c["text"]))

index_path = os.path.join(OUT, "voices.json")
index = json.load(open(index_path)) if os.path.exists(index_path) else {}
for who, text in lines:
    key = who + "|" + text
    if key in index and os.path.exists(os.path.join(OUT, index[key]["file"])):
        continue
    voice, rate, semis = VOICES.get(who, VOICES["clerk"])
    h = hashlib.sha1(key.encode()).hexdigest()[:12]
    raw = os.path.join(OUT, "raw_" + h + ".wav")
    txt = os.path.join(OUT, "t_" + h + ".txt")
    open(txt, "w", encoding="utf-8").write(text)
    ps = ("Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
          f"$s.SelectVoice('{voice}'); $s.Rate = {rate}; $s.SetOutputToWaveFile('{raw}'); "
          f"$s.Speak([IO.File]::ReadAllText('{txt}')); $s.Dispose()")
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], check=True)
    f = 2.0 ** (semis / 12.0)
    name = h + ".wav"
    af = (f"aresample={RATE},asetrate={int(RATE * f)},aresample={RATE},atempo={1.0 / f:.4f},highpass=f=90,"
          "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,volume=1.5")
    subprocess.run([FF, "-y", "-loglevel", "error", "-i", raw, "-af", af, "-ac", "1", "-ar", str(RATE),
                    "-c:a", "pcm_s16le", os.path.join(OUT, name)], check=True)
    os.remove(raw)
    os.remove(txt)
    with wave.open(os.path.join(OUT, name)) as w:
        secs = w.getnframes() / w.getframerate()
    index[key] = {"file": name, "secs": round(secs, 3)}
    print("%-8s %4.1fs %s" % (who, secs, text[:60]))
json.dump(index, open(index_path, "w"), indent=1)
print(len(index), "lines voiced")
