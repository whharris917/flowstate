"""Cut the rehearsal of The Four Faces into the film: whole beats kept or
dropped, never a word of the actors' changed; the cuts bridged by title
cards and by setting the cast on their marks for the next scene."""
import json, copy

SRC = r"C:\Users\wilha\AppData\Roaming\Godot\app_userdata\flowstate\takes\the_four_faces.json"
OUT = r"C:\Users\wilha\AppData\Roaming\Godot\app_userdata\flowstate\takes\the_four_faces_cut.json"
take = json.load(open(SRC))
ev = take["events"]


def strip(cmds, drop=("wait",)):
    """The commands with dead waits and failed seats taken out."""
    return [c for c in cmds if c.get("do") not in drop]


out = []
t = 0.0


def card(text, secs=3.5):
    global t
    out.append({"t": round(t, 2), "card": text, "secs": secs})
    t += secs + 0.3


VOICES = json.load(open(r"C:\Users\wilha\AppData\Roaming\Godot\app_userdata\flowstate\voices\voices.json"))
last_spoken = [0.0]


def put(i, gap, cmds=None, actor=None):
    """Event i of the rehearsal, gap seconds after the last. The clock
    waits while a recorded line is said, so the gap loses the time the
    last event's lines take."""
    global t
    t += max(0.9, gap - last_spoken[0])
    last_spoken[0] = 0.0
    e = copy.deepcopy(ev[i])
    if cmds is not None:
        e["commands"] = cmds
    if actor:
        e["actor"] = actor
    e["t"] = round(t, 2)
    out.append(e)
    for c in e.get("commands", []):
        if c.get("do") == "say":
            v = VOICES.get(e["actor"] + "|" + c.get("text", ""))
            if v:
                last_spoken[0] += v["secs"] + 0.35


def cmd(actor, commands, gap):
    global t
    t += gap
    out.append({"t": round(t, 2), "actor": actor, "commands": commands})


def cam(spec, gap=0.0):
    global t
    t += gap
    out.append({"t": round(t, 2), "camera": spec})


# -- Opening: the square, the tower, the title.
out.append({"t": 0.0, "camera": {"mode": "path", "points": [[-44, 3.5, 24], [-36, 6, 12]], "speed": 1.6, "look_at": [0, 24, 0], "cut": True}})
card("THE FOUR FACES", 4.0)
card("Monroe, North Carolina.  Four o'clock, give or take.", 3.2)
out.append({"t": round(t, 2), "camera": {"mode": "auto", "cut": True}})
# -- I. The wager.
put(0, 0.3)                                              # Wren: you came back
put(1, 2.1)                                              # Rosalind comes, flourish
put(3, 9.5, strip(ev[3]["commands"]))                    # the hill road tried
put(4, 3.2)                                              # north face drags
put(5, 6.6, strip(ev[5]["commands"]))                    # west face sulks
put(7, 6.8, [c for c in ev[7]["commands"] if c.get("do") != "shake_head"])  # clocks wear
put(8, 5.0, strip(ev[8]["commands"]))                    # a gallery; shall we
put(9, 5.8, [c for c in ev[9]["commands"] if c.get("do") != "go"])          # records
put(10, 4.2, [c for c in ev[10]["commands"] if c.get("do") != "go"])        # wear, then
# -- II. The porch: the cast on their marks before the clerk.
t += 5.0
out.append({"t": round(t, 2), "cast": [
    {"name": "wren", "at": [-12.7, 1.4, 0.9], "yaw_deg": -90},
    {"name": "rosalind", "at": [-12.7, 1.4, -0.9], "yaw_deg": -90},
    {"name": "clerk", "at": [-10.9, 1.4, 0.0], "yaw_deg": 90}]})
out.append({"t": round(t, 2), "camera": {"mode": "auto", "cut": True}})
put(11, 0.8, strip(ev[11]["commands"]))                  # bound for the gallery
put(13, 5.0, strip(ev[13]["commands"]))                  # two quarrelling witnesses
put(15, 5.5, [c for c in ev[15]["commands"] if c.get("do") != "wait"])      # the clerk's offer
put(14, 11.0, [c for c in ev[14]["commands"] if c.get("do") != "go"])       # my knees are older
put(16, 3.8, [c for c in ev[16]["commands"] if c.get("do") != "go"])        # you outrank it
# -- III. The court.
t += 4.0
card("Upstairs, the court was not sitting.  Until it was.", 3.4)
out.append({"t": round(t - 3.7, 2), "cast": [
    {"name": "rosalind", "at": [0.0, 6.9, -2.3], "yaw_deg": 180},
    {"name": "wren", "at": [-2.2, 6.9, -3.6], "yaw_deg": -60},
    {"name": "clerk", "at": [0.2, 6.9, 1.6], "yaw_deg": 0}]})
out.append({"t": round(t, 2), "camera": {"mode": "auto", "cut": True}})
put(27, 0.3, strip(ev[27]["commands"]))                  # members of the jury
put(30, 5.0, strip(ev[30]["commands"]))                  # the court calls the keeper
put(31, 3.8, strip(ev[31]["commands"]))                  # Wren: may I see it
put(35, 4.6, [c for c in ev[35]["commands"]])            # sworn: all four behind
put(36, 10.0, [c for c in ev[36]["commands"] if c.get("do") not in ("go", "wait")])  # which face
put(37, 4.4, strip(ev[37]["commands"]))                  # a conspiracy
put(43, 6.0)                                             # the carpenter
put(44, 9.5)                                             # I shall set it back; supper
put(45, 7.0, strip(ev[45]["commands"]))                  # the kindest thing
put(41, 7.5, strip(ev[41]["commands"]))                  # the verdict
put(46, 9.0)                                             # four minutes late
put(56, 9.5, strip(ev[56]["commands"]))                  # for the carpenter
put(54, 3.5, [c for c in ev[54]["commands"] if c.get("do") != "wait"])       # a bow for his town
# -- End.
cam({"mode": "path", "points": [[1.2, 8.2, 0.8], [0.6, 9.2, 2.4]], "speed": 0.45, "look_at": [0, 7.4, -3.6]}, 5.0)
# Outside, the tower, the clock four minutes behind.
cam({"mode": "path", "points": [[-18, 12, 26], [-14, 15, 19]], "speed": 0.9, "look_at": [0, 28.5, 0], "cut": True}, 4.5)
t += 2.0
card("The clock still runs four minutes slow.", 3.2)
card("On purpose.", 2.4)
out.append({"t": round(t + 0.6, 2), "end": True})

cut = {"title": "The Four Faces", "hour": take["hour"], "subtitles": True, "camera": {"mode": "path", "points": [[-44, 3.5, 24], [-36, 6, 12]], "speed": 1.6, "look_at": [0, 24, 0], "cut": True},
       "cast": take["cast"], "events": out}
json.dump(cut, open(OUT, "w"), indent=1)
print("length %.1f s, %d events" % (t, len(out)))
