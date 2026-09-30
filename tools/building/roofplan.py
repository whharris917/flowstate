"""Lay the generated roof over the survey's roof plan.

    .venv/Scripts/python.exe tools/building/roofplan.py <name> [--crop x0 x1 z0 z1]

Draws every edge of the generated roof's surface, coloured by what it is
(eave blue, rake cyan, ridge green, hip dark green, valley purple, deck
edge orange, abutment grey, well brown), and each roof-edge finding of the
validator as a red ring, over the roof plan sheet in grey. Writes
roofplan_<name>.png to the user data folder (next to the probes' pictures)
and lists the findings.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import arch  # noqa: E402
from validate import Validator  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
OUT = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "flowstate")
COL = {"eave": (0, 70, 230), "rake": (0, 170, 200), "ridge": (0, 160, 0), "hip": (0, 100, 40),
       "valley": (140, 0, 170), "deck edge": (240, 130, 0), "abutment": (110, 110, 110),
       "tuck": (170, 170, 170), "well": (140, 80, 20), "seam": None}


def main(argv: list[str]) -> int:
    name = argv[1] if len(argv) > 1 and not argv[1].startswith("--") else "twain"
    crop = None
    if "--crop" in argv:
        i = argv.index("--crop")
        crop = [float(v) for v in argv[i + 1:i + 5]]
    path = os.path.join(arch.M.ROOT, "game", "data", "buildings", name + ".json")
    m = arch.load(path).generate()
    v = Validator(m)
    v.run()
    spec = next(s for s in m.data["sheets"]["list"] if s["kind"] == "roofplan")
    sd = m.data["sheets"]
    im = Image.open(os.path.join(sd["dir"], spec["file"])).convert("L")
    ppf = float(sd.get("px_per_ft", 100))
    R = 20.0
    im = im.resize((int(im.width / ppf * R), int(im.height / ppf * R)), Image.LANCZOS)
    pic = Image.eval(im.convert("RGB"), lambda c: 170 + c // 3)
    d = ImageDraw.Draw(pic)
    ox, oz = spec.get("offset", [0.0, 0.0])

    def px(x, z):
        return ((x - ox) * R, (z - oz) * R)

    edges = v.edge_classes if hasattr(v, "edge_classes") else []
    for kind, a, b in edges:
        c = COL.get(kind)
        if c is None:
            continue
        d.line([px(a[0], a[2]), px(b[0], b[2])], fill=c, width=3)
    try:
        font = ImageFont.truetype("arial.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    n = 0
    for f in v.findings:
        if f.check != "roof edges" or f.where is None:
            continue
        n += 1
        x, y = px(f.where[0], f.where[2])
        d.ellipse([x - 10, y - 10, x + 10, y + 10], outline=(230, 0, 0), width=3)
        d.text((x + 12, y - 12), str(n), fill=(230, 0, 0), font=font)
        print("%3d %s" % (n, f))
    if crop:
        x0, y0 = px(crop[0], crop[2])
        x1, y1 = px(crop[1], crop[3])
        pic = pic.crop((int(min(x0, x1)), int(min(y0, y1)), int(max(x0, x1)), int(max(y0, y1))))
    out = os.path.join(OUT, "roofplan_%s.png" % name)
    pic.save(out)
    print("wrote", out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
