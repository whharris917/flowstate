"""Lay the Mark Twain house model over the survey's elevation drawings.

Reads the model's straight-on pictures (user://ortho_<front>.png, written by
world/twain_probe.tscn with FLOWSTATE_TW_ORTHO=all) and the survey's sheet
masters (HABS CT-359 sheets 8-11, 100 px to the foot), and writes for each
front user://overlay_<front>.png: the model faded, the drawing's lines over
it in dark red, a grid every five feet. Where a red line has no model under
it, the model is missing something; where model stands clear of the lines,
it has something the house does not.

    python tools/twain_overlay.py <sheet dir> [front ...] [--crop x0 x1 y0 y1]

<sheet dir> holds m08.tif .. m11.tif (the sheets' master TIFFs from
tile.loc.gov). --crop limits the output to sheet feet x0..x1 and heights
y0..y1 over the first floor, drawn larger.
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

Image.MAX_IMAGE_PIXELS = None
USER = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "flowstate")
# Kept in step with twain_probe.gd's SHEETS / ORTHO_*.
SHEETS = {"east": 8, "north": 9, "west": 10, "south": 11}
ORTHO_X = (10.0, 170.0)
ORTHO_Y = (-12.0, 52.0)
PX = 16
FF = {8: 82.2, 9: 82.2, 10: 82.2, 11: 82.2}   # the first floor's line on each sheet, sheet feet


def overlay(sheet_dir: str, front: str, crop: tuple[float, float, float, float] | None) -> str:
    n = SHEETS[front]
    model = Image.open(os.path.join(USER, "ortho_%s.png" % front)).convert("RGB")
    sheet = Image.open(os.path.join(sheet_dir, "m%02d.tif" % n)).convert("L")
    ff = FF[n]
    box = (int(ORTHO_X[0] * 100), int((ff - ORTHO_Y[1]) * 100), int(ORTHO_X[1] * 100), int((ff - ORTHO_Y[0]) * 100))
    draw = sheet.crop(box).resize(model.size, Image.LANCZOS)
    lines = ImageOps.invert(draw).point(lambda v: 255 if v > 70 else int(v * 3.6))
    # The model in warm grey, its sky white, so the drawing's lines read.
    grey = ImageOps.autocontrast(model.convert("L"), cutoff=1)
    sky = model.split()[2].point(lambda v: 255 if v > 200 else 0)
    grey = Image.composite(Image.new("L", model.size, 255), grey, ImageChops.multiply(sky, model.split()[0].point(lambda v: 255 if v < 190 else 0)))
    faded = Image.merge("RGB", [grey.point(lambda v: 90 + v * 0.62), grey.point(lambda v: 80 + v * 0.62), grey.point(lambda v: 70 + v * 0.62)])
    ink = Image.new("RGB", model.size, (0, 40, 190))
    out = Image.composite(ink, faded, lines)
    d = ImageDraw.Draw(out)
    try:
        font = ImageFont.truetype("arial.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    for fx in range(int(ORTHO_X[0]), int(ORTHO_X[1]) + 1, 5):
        x = (fx - ORTHO_X[0]) * PX
        d.line([(x, 0), (x, out.height)], fill=(60, 110, 200) if fx % 10 == 0 else (170, 195, 235), width=1)
        if fx % 10 == 0:
            d.text((x + 3, 3), str(fx), fill=(40, 80, 170), font=font)
    for fy in range(int(ORTHO_Y[0]), int(ORTHO_Y[1]) + 1, 5):
        y = (ORTHO_Y[1] - fy) * PX
        d.line([(0, y), (out.width, y)], fill=(60, 110, 200) if fy % 10 == 0 else (170, 195, 235), width=1)
        if fy % 10 == 0:
            d.text((3, y + 3), "%+d" % fy, fill=(40, 80, 170), font=font)
    if crop:
        x0, x1, y0, y1 = crop
        c = out.crop((int((x0 - ORTHO_X[0]) * PX), int((ORTHO_Y[1] - y1) * PX), int((x1 - ORTHO_X[0]) * PX), int((ORTHO_Y[1] - y0) * PX)))
        out = c.resize((c.width * 2, c.height * 2), Image.LANCZOS) if c.width < 1000 else c
    path = os.path.join(USER, "overlay_%s%s.png" % (front, "_crop" if crop else ""))
    out.save(path)
    return path


def main() -> None:
    args = sys.argv[1:]
    crop = None
    if "--crop" in args:
        i = args.index("--crop")
        crop = tuple(float(v) for v in args[i + 1:i + 5])
        del args[i:i + 5]
    sheet_dir = args[0]
    fronts = args[1:] or list(SHEETS)
    for f in fronts:
        print(overlay(sheet_dir, f, crop))


if __name__ == "__main__":
    main()
