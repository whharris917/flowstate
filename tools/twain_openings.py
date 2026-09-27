"""Draw the Mark Twain house model's windows and doors over the survey's elevations.

Reads user://twain_openings.json (every opening as built, written by
world/twain_probe.tscn with FLOWSTATE_TW_ORTHO) and the sheet masters, and for
each front draws, over the drawing, a box for each opening of the model that
faces the viewer: green for a window, blue for a door. An opening drawn in the
survey with no box on it is missing from the model; a box on bare wall is one
the house does not have. Written as user://openings_<front>_<n>.png, the front
in tiles for reading at full size.

    python tools/twain_openings.py <sheet dir> [front ...]
"""
from __future__ import annotations

import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

Image.MAX_IMAGE_PIXELS = None
USER = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "flowstate")
# sheet, the survey direction the viewer looks from (nx, nz), and how the
# sheet's horizontal maps: sheet = sign * (survey x or z) + offset.
FRONTS = {
    "east": (8, (0.0, 1.0), "x", 1.0, -1.7),
    "north": (9, (1.0, 0.0), "z", -1.0, 155.8),
    "west": (10, (0.0, -1.0), "x", -1.0, 176.5),
    "south": (11, (-1.0, 0.0), "z", 1.0, 23.0),
}
FF = 82.2
PX = 40        # pixels to the foot in the output
X_RANGE = (15.0, 165.0)
Y_RANGE = (-12.0, 50.0)
TILES = 3


def main() -> None:
    sheet_dir = sys.argv[1]
    fronts = sys.argv[2:] or list(FRONTS)
    with open(os.path.join(USER, "twain_openings.json"), encoding="utf-8") as f:
        ops = json.load(f)
    try:
        font = ImageFont.truetype("arial.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    for front in fronts:
        n, (vx, vz), axis, sign, off = FRONTS[front]
        sheet = Image.open(os.path.join(sheet_dir, "m%02d.tif" % n)).convert("L")
        span = (X_RANGE[1] - X_RANGE[0]) / TILES
        for t in range(TILES):
            x0 = X_RANGE[0] + t * span - 2.0
            x1 = x0 + span + 4.0
            box = (int(x0 * 100), int((FF - Y_RANGE[1]) * 100), int(x1 * 100), int((FF - Y_RANGE[0]) * 100))
            img = sheet.crop(box).resize((int((x1 - x0) * PX), int((Y_RANGE[1] - Y_RANGE[0]) * PX)), Image.LANCZOS).convert("RGB")
            d = ImageDraw.Draw(img)
            for fx in range(int(x0), int(x1) + 1):
                if fx % 5 == 0:
                    X = (fx - x0) * PX
                    d.line([(X, 0), (X, img.height)], fill=(150, 180, 235))
                    d.text((X + 3, 3), str(fx), fill=(20, 60, 180), font=font)
            for fy in range(int(Y_RANGE[0]), int(Y_RANGE[1]) + 1, 5):
                Y = (Y_RANGE[1] - fy) * PX
                d.line([(0, Y), (img.width, Y)], fill=(150, 180, 235))
                d.text((3, Y + 3), "%+d" % fy, fill=(20, 60, 180), font=font)
            for o in ops:
                if o["nx"] * vx + o["nz"] * vz < 0.5:
                    continue
                along = o[axis] * sign + off
                a = along - o["w"] / 2.0
                b = along + o["w"] / 2.0
                if b < x0 or a > x1:
                    continue
                col = (0, 160, 60) if o["kind"] == "win" else (20, 80, 230)
                d.rectangle([(a - x0) * PX, (Y_RANGE[1] - o["yt"]) * PX, (b - x0) * PX, (Y_RANGE[1] - o["y0"]) * PX], outline=col, width=4)
            path = os.path.join(USER, "openings_%s_%d.png" % (front, t + 1))
            img.save(path)
            print(path)


if __name__ == "__main__":
    main()
