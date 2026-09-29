"""Measure a building's walls off its plan sheets.

For every edge of every space on a plan's level, the sheet's ink is
sampled across the edge (along its normal, 3 ft either way, averaged
over the middle of the edge): a drawn wall shows as a band of ink (the
hatched brick, or a partition's pair of lines). The band nearest the
edge gives where the edge should be: an outer wall's outer face on the
band's outer boundary, a partition's centre line in the band's middle.
Edges that stand on a named grid line pool their measurements into one
proposal per grid line.

    python tools/building/measure.py <building> <plan sheet> [--min 0.2]

Prints, per grid line and per edge not on one, the measured position
where it differs from the data by more than --min feet, with how many
edges agree and the wall's drawn thickness.
"""
from __future__ import annotations

import math
import os
import sys
from collections import defaultdict

import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from model import Building, GRID, inside  # noqa: E402
from overlay import Sheet, OPEN_KINDS, R  # noqa: E402

SPAN = 3.0
STEP = 0.05


def density(sheet: Sheet) -> np.ndarray:
    """Ink density in a 0.3 ft window: walls (hatch, paired lines) stand
    out as bands."""
    return ndimage.uniform_filter(sheet.ink.astype(np.float32), size=int(0.3 * R))


def profile(sheet: Sheet, dens: np.ndarray, a, c, n) -> tuple[np.ndarray, np.ndarray]:
    ts = np.arange(-SPAN, SPAN + 1e-9, STEP)
    L = math.hypot(c[0] - a[0], c[1] - a[1])
    k = max(3, int(L / 0.25))
    rows = np.zeros((k, ts.size))
    for i in range(k):
        f = 0.1 + 0.8 * i / (k - 1)
        px, pz = a[0] + (c[0] - a[0]) * f, a[1] + (c[1] - a[1]) * f
        for j, t in enumerate(ts):
            sx, sy = sheet.plan_to_sheet(px + n[0] * t, pz + n[1] * t)
            ii, jj = int(sy * R), int(sx * R)
            if 0 <= ii < dens.shape[0] and 0 <= jj < dens.shape[1]:
                rows[i, j] = dens[ii, jj]
    # The wall as most of its length draws it: windows and doors, which
    # break the band, take up the smaller part of a wall.
    return ts, np.percentile(rows, 70, axis=0)


def bands(ts, prof, thr=0.18):
    on = prof > thr
    out, start = [], None
    for i, v in enumerate(on):
        if v and start is None:
            start = i
        if not v and start is not None:
            out.append((ts[start], ts[i - 1]))
            start = None
    if start is not None:
        out.append((ts[start], ts[-1]))
    return out


def measure(bname: str, sheet_id: str, min_shift: float):
    b = Building.load(bname)
    spec = next(s for s in b.data["sheets"]["list"] if s["id"] == sheet_id)
    sheet = Sheet(b, spec)
    dens = density(sheet)
    level = spec["level"]
    spaces = [s for s in b.spaces_on(level) if s["kind"] not in OPEN_KINDS]
    rank = {g["id"]: i for i, g in enumerate(b.data.get("groups", []))}
    per_grid = defaultdict(list)
    loose = []
    for s in spaces:
        p = s["poly"]
        area = sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))
        for i in range(len(p)):
            a, c = p[i], p[(i + 1) % len(p)]
            L = math.hypot(c[0] - a[0], c[1] - a[1])
            if L < 1.5:
                continue
            ux, uz = (c[0] - a[0]) / L, (c[1] - a[1]) / L
            # The inward normal: left of travel on an anticlockwise polygon.
            n = (-uz, ux) if area > 0 else (uz, -ux)
            mid = ((a[0] + c[0]) / 2, (a[1] + c[1]) / 2)
            out_pt = (np.array([mid[0] - n[0] * 0.6]), np.array([mid[1] - n[1] * 0.6]))
            other = next((o for o in spaces if o is not s and inside(o["poly"], *out_pt)[0]), None)
            shared = other is not None and other.get("group") == s.get("group")
            ts, prof = profile(sheet, dens, a, c, n)
            bs = bands(ts, prof)
            if not bs:
                continue
            if other is not None and not shared and rank.get(other.get("group"), 99) < rank.get(s.get("group"), 99):
                # Against a part built first (the main block): the edge stands
                # on that part's outer face, the band outside this space.
                t0, t1 = min(bs, key=lambda q: abs(q[1]))
                shift = t1
            elif shared:
                # A partition: the middle of the band nearest the line.
                t0, t1 = min(bs, key=lambda q: abs((q[0] + q[1]) / 2))
                shift = (t0 + t1) / 2
            else:
                # An outer wall: the outer face of the band that holds or
                # lies nearest the wall's expected place just inside the line.
                t0, t1 = min(bs, key=lambda q: 0.0 if q[0] <= 0.5 <= q[1] else min(abs(q[0] - 0.5), abs(q[1] - 0.5)))
                shift = t0
            thick = t1 - t0
            # Which grid line the edge stands on, if any.
            name = None
            if abs(ux) < 1e-6:
                name = next((("x", k) for k, v in GRID["x"].items() if abs(v - a[0]) < 1e-6), None)
            elif abs(uz) < 1e-6:
                name = next((("z", k) for k, v in GRID["z"].items() if abs(v - a[1]) < 1e-6), None)
            # The shift in the grid's own axis.
            item = (s["id"], i, a, c, shift, thick, shared)
            if name:
                axis_shift = shift * (n[0] if name[0] == "x" else n[1])
                per_grid[name].append((axis_shift, item))
            elif abs(shift) > min_shift:
                loose.append(item)
    print("== grid lines (%s)" % sheet_id)
    for (ax, k), vals in sorted(per_grid.items()):
        shifts = np.array([v[0] for v in vals])
        med = float(np.median(shifts))
        cur = GRID[ax][k]
        flag = "  <-- move" if abs(med) > min_shift else ""
        print("  %s %-14s %7.2f  measured %7.2f  (%d edges, spread %.2f)%s"
              % (ax, k, cur, cur + med, len(vals), float(shifts.max() - shifts.min()), flag))
    print("== edges not on a grid line, off by more than %.2f ft" % min_shift)
    for sid, i, a, c, shift, thick, shared in sorted(loose, key=lambda q: -abs(q[4])):
        print("  %-12s edge %d (%.1f, %.1f)-(%.1f, %.1f): %s off by %+.2f ft (drawn wall %.2f thick)"
              % (sid, i, a[0], a[1], c[0], c[1], "partition" if shared else "outer face", shift, thick))


if __name__ == "__main__":
    args = sys.argv[1:]
    mn = 0.2
    if "--min" in args:
        i = args.index("--min")
        mn = float(args[i + 1])
        del args[i:i + 2]
    measure(args[0], args[1], mn)
