"""Find a building's chimneys on its roof plan and elevations.

On a roof plan a chimney is drawn as a small block of heavy, nested
lines: the densest ink on the sheet. Each dense blob of ink (density in a
0.5 ft window above --dens) between 1 and 60 square feet is listed with
its extent in the building's feet, next to the chimney in the data it
lies nearest. On each elevation, above every chimney's place along the
front, the topmost ink in a narrow band gives the drawn top.

    python tools/building/chimneys.py <building> [--dens 0.35]
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from model import Building  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
R = 20.0


def load(b: Building, spec: dict) -> np.ndarray:
    sd = b.data["sheets"]
    im = Image.open(os.path.join(sd["dir"], spec["file"])).convert("L")
    ppf = float(sd.get("px_per_ft", 100))
    return np.asarray(im.resize((int(im.width / ppf * R), int(im.height / ppf * R)), Image.LANCZOS)) < 150


def run(bname: str, dens_min: float) -> None:
    b = Building.load(bname)
    sheets = {s["id"]: s for s in b.data["sheets"]["list"]}
    roof = sheets.get("roof")
    chims = []
    for ch in b.chimneys:
        (cx, cz), (sx, sz) = ch["at"], ch["size"]
        chims.append((ch["id"], float(cx), float(cz), float(sx), float(sz), float(ch["top"])))
    if roof:
        ink = load(b, roof)
        dens = ndimage.uniform_filter(ink.astype(np.float32), size=int(0.5 * R))
        lab, n = ndimage.label(dens > dens_min)
        ox, oz = roof.get("offset", [0.0, 0.0])
        print("== dense blocks on the roof plan (building feet)")
        for k, sl in enumerate(ndimage.find_objects(lab), start=1):
            area = (lab[sl] == k).sum() / R / R
            if not 1.0 <= area <= 60.0:
                continue
            z0, z1 = sl[0].start / R + oz, sl[0].stop / R + oz
            x0, x1 = sl[1].start / R + ox, sl[1].stop / R + ox
            if not (40 < x0 < 170 and 10 < z0 < 125):
                continue
            mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
            near = min(chims, key=lambda c: (c[1] - mx) ** 2 + (c[2] - mz) ** 2)
            dist = ((near[1] - mx) ** 2 + (near[2] - mz) ** 2) ** 0.5
            print("  x %6.1f-%6.1f  z %5.1f-%5.1f  (%.1f x %.1f, centre %.1f, %.1f)   nearest: %s at (%.1f, %.1f) %.1f x %.1f, %.1f ft away"
                  % (x0, x1, z0, z1, x1 - x0, z1 - z0, mx, mz, near[0], near[1], near[2], near[3], near[4], dist))
    for sid in ("east", "west", "north", "south"):
        spec = sheets.get(sid)
        if not spec:
            continue
        ink = load(b, spec)
        axis = spec["view"][1]
        print("== %s: drawn top over each chimney" % sid)
        for cid, cx, cz, sx, sz, top in chims:
            along = cx if axis == "z" else cz
            half = (sx if axis == "z" else sz) / 2
            s0 = spec["sign"] * (along - half) + spec["offset"]
            s1 = spec["sign"] * (along + half) + spec["offset"]
            a, c = sorted((s0, s1))
            cols = ink[:, int(a * R):int(c * R) + 1]
            rows = np.nonzero(cols.mean(axis=1) > 0.3)[0]
            # The topmost row where the band is mostly ink, above the eaves.
            y = rows[(rows < (spec["ff"] - 15) * R) & (rows > (spec["ff"] - 55) * R)]
            drawn = spec["ff"] - y.min() / R if len(y) else float("nan")
            print("  %-18s top in data %5.1f, drawn %5.1f" % (cid, top, drawn))


if __name__ == "__main__":
    args = sys.argv[1:]
    dm = 0.35
    if "--dens" in args:
        i = args.index("--dens")
        dm = float(args[i + 1])
        del args[i:i + 2]
    run(args[0], dm)
