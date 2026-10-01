"""Read each roof's eaves off the roof plan: how far the drawn eave line
stands from the generated one.

For every eave edge of every roof (a footprint edge with its overhang),
the roof plan's ink is sampled across the eave line at stations along its
middle: the drawn lines found between 3 ft inside and 4 ft outside are
listed as offsets in feet (outward positive), pooled over the stations.
The outermost line is usually the cornice's edge, the one the model's
eave should stand on; an inner one may be the gutter's back or the wall
drawn dashed under the roof.

    .venv/Scripts/python.exe tools/building/eaves.py <building> [roof ...]
"""
from __future__ import annotations

import math
import os
import sys
from collections import Counter

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import arch  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
R = 20.0


def main(argv: list[str]) -> int:
    name = argv[1]
    only = set(argv[2:])
    m = arch.load(os.path.join(arch.M.ROOT, "game", "data", "buildings", name + ".json"))
    m._roofs()
    sd = m.data["sheets"]
    spec = next(s for s in sd["list"] if s["kind"] == "roofplan")
    im = Image.open(os.path.join(sd["dir"], spec["file"])).convert("L")
    ppf = float(sd.get("px_per_ft", 100))
    img = np.asarray(im.resize((int(im.width / ppf * R), int(im.height / ppf * R)), Image.LANCZOS))
    ink = img < 170
    ox, oz = spec.get("offset", [0.0, 0.0])

    def inked(x, z) -> bool:
        i, j = int(round((z - oz) * R)), int(round((x - ox) * R))
        return 0 <= i < ink.shape[0] and 0 <= j < ink.shape[1] and bool(ink[i, j])

    for rid, r in m.roofs.items():
        if only and rid not in only:
            continue
        fp = r.footprint
        n = len(fp)
        for i, e in enumerate(r.edges):
            if e["kind"] != "eave":
                continue
            a, b = fp[i], fp[(i + 1) % n]
            L = math.dist(a, b)
            if L < 2.0:
                continue
            tx, tz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
            nx, nz = tz, -tx                       # outward of an anticlockwise footprint
            over = float(e["over"])
            hits: Counter = Counter()
            stations = 0
            for k in range(1, 10):
                s = L * (0.2 + 0.6 * k / 10.0)
                px_, pz_ = a[0] + tx * s + nx * over, a[1] + tz * s + nz * over
                stations += 1
                prev = False
                for step in range(-60, 81):
                    d = step * 0.05
                    on = inked(px_ + nx * d, pz_ + nz * d)
                    if on and not prev:
                        hits[round(d * 4) / 4] += 1
                    prev = on
            lines = sorted((d for d, c in hits.items() if c >= stations * 0.5), key=lambda d: d)
            side = {"x0": None}
            print("%-22s edge %d (%5.1f,%5.1f)-(%5.1f,%5.1f) %4.1f ft  over %.2f  drawn lines at %s"
                  % (rid, i, a[0], a[1], b[0], b[1], L, over,
                     ", ".join("%+.2f" % d for d in lines) or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
