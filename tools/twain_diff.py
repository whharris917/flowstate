"""Measure where the Mark Twain house model's outline differs from the survey.

For each front, the survey's elevation (HABS CT-359 sheets 8-11) and the
model's straight-on picture of surface directions (user://ortho_<front>_n.png
from world/twain_probe.tscn with FLOWSTATE_TW_ORTHO=all) are reduced to the
same thing: the sky round the house, found by flooding in from the top edge.
Where one has house and the other sky, the model is wrong:

  missing   the drawing has house there, the model has sky (red)
  extra     the model has house there, the drawing has sky (orange)

Regions smaller than --min square feet are ignored. The rest are listed
largest first with their extent in the sheet's feet (horizontal along the
front, heights over the first floor) and drawn over the sheet in
user://diff_<front>.png. A score per front (square feet of disagreement)
tracks progress.

    python tools/twain_diff.py <sheet dir> [front ...] [--min 2]
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None
USER = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "flowstate")
SHEETS = {"east": 8, "north": 9, "west": 10, "south": 11}
ORTHO_X = (10.0, 170.0)
ORTHO_Y = (-12.0, 52.0)
PX = 16
FF = 82.2
# Parts of each sheet that are not the house: titles, dimension strings,
# the level marks at the sides (sheet feet, heights over the first floor).
MASK_OUT = {
    "east": [(10, 22, -12, 52), (160, 170, -12, 52)],
    "north": [(10, 20, -12, 52), (140, 170, -12, 52)],
    "west": [(10, 16, -12, 52), (155, 170, -12, 52)],
    "south": [(10, 32, -12, 52), (135, 170, -12, 52)],
}


def sky_of_drawing(sheet_dir: str, front: str, shape: tuple[int, int]) -> np.ndarray:
    n = SHEETS[front]
    sheet = Image.open(os.path.join(sheet_dir, "m%02d.tif" % n)).convert("L")
    box = (int(ORTHO_X[0] * 100), int((FF - ORTHO_Y[1]) * 100), int(ORTHO_X[1] * 100), int((FF - ORTHO_Y[0]) * 100))
    d = np.asarray(sheet.crop(box).resize((shape[1], shape[0]), Image.LANCZOS))
    lines = d < 170
    # Close the gaps between strokes so the sky cannot leak through a
    # railing's open work or a hatched roof.
    lines = ndimage.binary_dilation(lines, iterations=2)
    return flood_from_top(~lines)


def flood_from_top(free: np.ndarray) -> np.ndarray:
    lab, _ = ndimage.label(free)
    top = np.unique(lab[0][lab[0] > 0])
    sky = np.isin(lab, top)
    # The sky reaches down to the ground on either side of the house.
    return sky


def sky_of_model(front: str, low: np.ndarray | None = None) -> np.ndarray:
    m = np.asarray(Image.open(os.path.join(USER, "ortho_%s_n.png" % front)).convert("RGB")).astype(int)
    bg = (np.abs(m - np.array([54, 54, 54])).sum(axis=2) < 12)
    # Railings, fret and posts are open work: close them as the drawing's
    # strokes are closed, then flood.
    house = ndimage.binary_dilation(~bg, iterations=2)
    # The drawing's ground closes the space under the porches: give the
    # model the same ground before flooding.
    if low is not None:
        rows = np.arange(house.shape[0])[:, None]
        house |= rows > low[None, :]
    return flood_from_top(~house)


def ground_line(sky_d: np.ndarray) -> np.ndarray:
    """Per column, the lowest row the drawing's sky reaches: below it is
    ground, compared nowhere."""
    rows = np.arange(sky_d.shape[0])[:, None]
    low = np.where(sky_d, rows, -1).max(axis=0)
    return low


def main() -> None:
    args = sys.argv[1:]
    min_ft2 = 2.0
    crops = 0
    if "--crops" in args:
        i = args.index("--crops")
        crops = int(args[i + 1])
        del args[i:i + 2]
    if "--min" in args:
        i = args.index("--min")
        min_ft2 = float(args[i + 1])
        del args[i:i + 2]
    sheet_dir = args[0]
    fronts = args[1:] or list(SHEETS)
    total = 0.0
    for front in fronts:
        shape = np.asarray(Image.open(os.path.join(USER, "ortho_%s_n.png" % front))).shape[:2]
        sky_d = sky_of_drawing(sheet_dir, front, shape)
        sky_m = sky_of_model(front, ground_line(sky_d))
        h, w = sky_m.shape
        cmp = np.ones_like(sky_m)
        # Compare only down to the drawing's ground, and not over its titles.
        low = ground_line(sky_d)
        rows = np.arange(h)[:, None]
        cmp &= rows <= low[None, :]
        for x0, x1, y0, y1 in MASK_OUT[front]:
            c0 = int((x0 - ORTHO_X[0]) * PX)
            c1 = int((x1 - ORTHO_X[0]) * PX)
            cmp[:, max(c0, 0):min(c1, w)] = False
        # How well the sheet is registered: the sideways shift of the
        # drawing that best fits the model's outline, above the ground.
        best = (1e18, 0)
        hard = cmp.copy()
        hard[: int(2 * PX), :] = False
        for sh in range(-6 * PX, 6 * PX + 1, 2):
            sd = np.roll(sky_d, sh, axis=1)
            bad = ((sd != sky_m) & hard).sum()
            if bad < best[0]:
                best = (bad, sh)
        print("%s: best fit with the drawing moved %+.1f ft along the front" % (front, best[1] / PX))
        missing = (~sky_d) & sky_m & cmp
        extra = sky_d & (~sky_m) & cmp
        img = Image.open(os.path.join(sheet_dir, "m%02d.tif" % SHEETS[front])).convert("L")
        box = (int(ORTHO_X[0] * 100), int((FF - ORTHO_Y[1]) * 100), int(ORTHO_X[1] * 100), int((FF - ORTHO_Y[0]) * 100))
        base = np.asarray(img.crop(box).resize((w, h), Image.LANCZOS))
        rgb = np.stack([base, base, base], axis=2).astype(float) * 0.55 + 110
        rgb[missing] = [215, 30, 30]
        rgb[extra] = [240, 150, 20]
        out = Image.fromarray(rgb.clip(0, 255).astype(np.uint8))
        dr = ImageDraw.Draw(out)
        try:
            font = ImageFont.truetype("arial.ttf", 16)
        except OSError:
            font = ImageFont.load_default()
        items = []
        for kind, mask in (("missing", missing), ("extra", extra)):
            lab, n = ndimage.label(mask)
            for idx, sl in enumerate(ndimage.find_objects(lab)):
                area = (lab[sl] == idx + 1).sum() / PX / PX
                if area < min_ft2:
                    continue
                ys, xs = sl
                x0 = ORTHO_X[0] + xs.start / PX
                x1 = ORTHO_X[0] + xs.stop / PX
                yb = ORTHO_Y[1] - ys.stop / PX
                yt = ORTHO_Y[1] - ys.start / PX
                items.append((area, kind, x0, x1, yb, yt))
        items.sort(reverse=True)
        score = sum(i[0] for i in items)
        total += score
        print("%s: %.0f sq ft of disagreement in %d regions" % (front, score, len(items)))
        for k, (area, kind, x0, x1, yb, yt) in enumerate(items):
            print("  %2d %-7s %6.1f sq ft   along %6.1f .. %6.1f   height %5.1f .. %5.1f" % (k + 1, kind, area, x0, x1, yb, yt))
            cx = (x0 - ORTHO_X[0]) * PX
            cy = (ORTHO_Y[1] - yt) * PX
            dr.rectangle([cx, cy, (x1 - ORTHO_X[0]) * PX, (ORTHO_Y[1] - yb) * PX], outline=(0, 0, 0))
            dr.text((cx + 2, cy + 2), str(k + 1), fill=(0, 0, 0), font=font)
        for fx in range(int(ORTHO_X[0]), int(ORTHO_X[1]) + 1, 10):
            dr.text(((fx - ORTHO_X[0]) * PX + 2, 2), str(fx), fill=(40, 80, 170), font=font)
        for fy in range(int(ORTHO_Y[0]), int(ORTHO_Y[1]) + 1, 10):
            dr.text((2, (ORTHO_Y[1] - fy) * PX + 2), "%+d" % fy, fill=(40, 80, 170), font=font)
        out.save(os.path.join(USER, "diff_%s.png" % front))
        # Each region as the drawing and the model side by side, with room
        # round it and a 1 ft grid: user://diff_<front>_<n>.png.
        if crops:
            model = Image.open(os.path.join(USER, "ortho_%s.png" % front)).convert("RGB")
            drawing = Image.fromarray(base).convert("RGB")
            for k, (area, kind, x0, x1, yb, yt) in enumerate(items[:crops]):
                pad = 4.0
                bx = (int((x0 - pad - ORTHO_X[0]) * PX), int((ORTHO_Y[1] - yt - pad) * PX),
                      int((x1 + pad - ORTHO_X[0]) * PX), int((ORTHO_Y[1] - yb + pad) * PX))
                bx = (max(bx[0], 0), max(bx[1], 0), min(bx[2], w), min(bx[3], h))
                a = drawing.crop(bx)
                b = model.crop(bx)
                sc = max(1, int(560 / max(a.width, 1)))
                if a.width * sc > 900:
                    sc = 1
                a = a.resize((a.width * sc, a.height * sc))
                b = b.resize((b.width * sc, b.height * sc))
                pair = Image.new("RGB", (a.width * 2 + 10, a.height + 24), (255, 255, 255))
                pair.paste(a, (0, 24))
                pair.paste(b, (a.width + 10, 24))
                pd = ImageDraw.Draw(pair)
                for im_x in (0, a.width + 10):
                    fx = int(np.ceil(bx[0] / PX + ORTHO_X[0]))
                    while (fx - ORTHO_X[0]) * PX < bx[2]:
                        X = im_x + ((fx - ORTHO_X[0]) * PX - bx[0]) * sc
                        pd.line([(X, 24), (X, pair.height)], fill=(90, 140, 230) if fx % 5 == 0 else (190, 210, 245))
                        if fx % 5 == 0:
                            pd.text((X + 2, 26), str(fx), fill=(20, 60, 180), font=font)
                        fx += 1
                    fy = int(np.floor(ORTHO_Y[1] - bx[1] / PX))
                    while (ORTHO_Y[1] - fy) * PX < bx[3]:
                        Y = 24 + ((ORTHO_Y[1] - fy) * PX - bx[1]) * sc
                        pd.line([(im_x, Y), (im_x + a.width, Y)], fill=(90, 140, 230) if fy % 5 == 0 else (190, 210, 245))
                        if fy % 5 == 0:
                            pd.text((im_x + 2, Y + 2), "%+d" % fy, fill=(20, 60, 180), font=font)
                        fy -= 1
                pd.text((4, 4), "%s %d: %s %.0f sq ft  (drawing | model)" % (front, k + 1, kind, area), fill=(0, 0, 0), font=font)
                pair.save(os.path.join(USER, "diff_%s_%02d.png" % (front, k + 1)))
    print("total: %.0f sq ft" % total)


if __name__ == "__main__":
    main()
