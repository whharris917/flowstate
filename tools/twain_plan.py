"""Draw the Mark Twain house audit's floor plans.

Reads user://twain_audit_geom.json (written by world/twain_audit.gd's reach
check) and draws one plan per floor in the survey's feet (north up, east
right): the rooms' outlines and names, each piece of furniture labelled,
the doorways, and where the player can walk (green: reached from the front
door; red: could stand there but never reached; grey: blocked).

    python tools/twain_plan.py [out_dir]

Needs Pillow.
"""
from __future__ import annotations

import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

USER = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "flowstate")
PX = 9.0          # pixels to the foot
X0, X1 = 15.0, 160.0   # survey x (north), drawn upward
Z0, Z1 = 15.0, 115.0   # survey z (east), drawn rightward
FLOORS = [("first", 0.0), ("second", 13.0), ("third", 24.0)]


def to_px(x: float, z: float) -> tuple[float, float]:
    return ((z - Z0) * PX, (X1 - x) * PX)


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else USER
    with open(os.path.join(USER, "twain_audit_geom.json"), encoding="utf-8") as f:
        geo = json.load(f)
    try:
        font = ImageFont.truetype("arial.ttf", 13)
        big = ImageFont.truetype("arialbd.ttf", 16)
    except OSError:
        font = big = ImageFont.load_default()
    w = int((Z1 - Z0) * PX)
    h = int((X1 - X0) * PX)
    colours = {0: (120, 200, 125), 1: (225, 80, 60), 2: (150, 140, 135)}
    for name, level in FLOORS:
        img = Image.new("RGB", (w, h), (250, 248, 242))
        d = ImageDraw.Draw(img)
        half = 0.35 / 0.3048 / 2.0
        for x, z, fl, state in geo["cells"]:
            if abs(fl - level) > 0.1:
                continue
            a = to_px(x + half, z - half)
            b = to_px(x - half, z + half)
            d.rectangle([a, b], fill=colours[state])
        # A foot grid every five feet.
        for gx in range(int(X0), int(X1) + 1, 5):
            d.line([to_px(gx, Z0), to_px(gx, Z1)], fill=(215, 212, 205) if gx % 10 else (190, 186, 178), width=1)
            if gx % 10 == 0:
                d.text(to_px(gx, Z0 + 0.3), str(gx), fill=(120, 120, 120), font=font)
        for gz in range(int(Z0), int(Z1) + 1, 5):
            d.line([to_px(X0, gz), to_px(X1, gz)], fill=(215, 212, 205) if gz % 10 else (190, 186, 178), width=1)
            if gz % 10 == 0:
                d.text(to_px(X1 - 1.5, gz), str(gz), fill=(120, 120, 120), font=font)
        for r in geo["rooms"]:
            if abs(r["y0"] - level) > 0.6:
                continue
            pts = [to_px(p[0], p[1]) for p in r["poly"]]
            d.polygon(pts, outline=(40, 40, 40), width=2)
            cx = sum(p[0] for p in pts) / len(pts)
            cy = sum(p[1] for p in pts) / len(pts)
            d.text((cx, cy - 30), r["name"], fill=(20, 20, 90), font=big, anchor="mm")
        for it in geo["items"]:
            if it["kind"] == "rug" or abs(it["y"] - level) > 3.0 and it["kind"] != "hanging":
                continue
            if it["kind"] == "hanging" and not (level < it["y"] < level + 11.0):
                continue
            pts = [to_px(p[0], p[1]) for p in it["corners"]]
            col = (140, 60, 20) if it["kind"] != "hanging" else (200, 150, 30)
            d.polygon(pts, outline=col, width=2)
            cx = sum(p[0] for p in pts) / 4
            cy = sum(p[1] for p in pts) / 4
            d.text((cx, cy), it["name"], fill=col, font=font, anchor="mm")
        for dr in geo["doors"]:
            if abs(dr["y"] - level) > 3.0:
                continue
            col = (30, 110, 200) if dr["open"] else (90, 90, 90)
            d.line([to_px(*dr["a"]), to_px(*dr["b"])], fill=col, width=5)
        d.text((10, 10), "%s floor  (survey feet: north up, east right)" % name, fill=(0, 0, 0), font=big)
        path = os.path.join(out, "twain_plan_%s.png" % name)
        img.save(path)
        print(path)


if __name__ == "__main__":
    main()
