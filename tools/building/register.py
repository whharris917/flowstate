"""Register a plan sheet to the building's frame.

Each floor of a survey is drawn on its own sheet, placed where it fitted
the paper: the same wall stands at different sheet coordinates on each.
This finds, for a plan sheet, the offset (in feet) that lays the
building's outer walls on that level (the edges of its spaces with no
other enclosed space beyond them) onto the sheet's drawn lines best:
the share of the walls' length with ink within 0.15 ft, searched over
+-6 ft in x and z, coarse then fine. The first floor's plan is the frame,
so its offset should come out near zero; any sheet whose best offset is
not clearly better than its neighbours is reported as doubtful.

    python tools/building/register.py <building> [sheet ...] [--write]

--write stores the offsets found in the building file's sheet table.
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from model import Building, building_path, inside  # noqa: E402
from overlay import Sheet, OPEN_KINDS, R  # noqa: E402


def outer_samples(b: Building, level: str, step: float = 0.3) -> np.ndarray:
    spaces = [s for s in b.spaces_on(level) if s["kind"] not in OPEN_KINDS]
    pts = []
    for s in spaces:
        p = s["poly"]
        area = sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))
        for i in range(len(p)):
            a, c = p[i], p[(i + 1) % len(p)]
            L = math.hypot(c[0] - a[0], c[1] - a[1])
            if L < 1.0:
                continue
            ux, uz = (c[0] - a[0]) / L, (c[1] - a[1]) / L
            n = (-uz, ux) if area > 0 else (uz, -ux)
            mid = ((a[0] + c[0]) / 2 - n[0] * 0.6, (a[1] + c[1]) / 2 - n[1] * 0.6)
            if any(inside(o["poly"], np.array([mid[0]]), np.array([mid[1]]))[0] for o in spaces if o is not s):
                continue
            k = int(L / step)
            for j in range(k + 1):
                t = j / max(k, 1)
                pts.append((a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t, n[0], n[1]))
    return np.array(pts)


def roof_outline_samples(b: Building) -> np.ndarray:
    """The roof's outer edge (its eaves and rakes as a roof plan draws
    them), with outward normals."""
    xs, zs, H, L = b.roof_raster(10.0, 170.0, 10.0, 125.0, 0.25)
    has = np.isfinite(H)
    pts = []
    for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nb = np.roll(has, (-di, -dj), axis=(0, 1))
        edge = has & ~nb
        for i, j in zip(*np.nonzero(edge)):
            # (di, dj) points outward; the normal kept is the inward one.
            pts.append((xs[i], zs[j], -di, -dj))
    return np.array(pts[::2])


def _look(arr: np.ndarray, x: np.ndarray, z: np.ndarray, ox: float, oz: float, fill: float) -> np.ndarray:
    sx = ((x - ox) * R).astype(int)
    sy = ((z - oz) * R).astype(int)
    ok = (sx >= 0) & (sy >= 0) & (sx < arr.shape[1]) & (sy < arr.shape[0])
    out = np.full(len(x), fill, dtype=float)
    out[ok] = arr[sy[ok], sx[ok]]
    return out


def score(sheet: Sheet, pts: np.ndarray, ox: float, oz: float, tol: float = 0.15) -> float:
    """The share of the outer walls drawn as an outer face would be: a
    line on it, the wall's drawn body just inside, bare paper outside."""
    x, z, nx, nz = pts[:, 0], pts[:, 1], pts[:, 2], pts[:, 3]
    on = _look(sheet.dist, x, z, ox, oz, 99.0) <= tol
    inner = _look(sheet.dens, x + nx * 0.5, z + nz * 0.5, ox, oz, 0.0) > 0.12
    outer = _look(sheet.dens, x - nx * 0.6, z - nz * 0.6, ox, oz, 1.0) < 0.08
    return float(np.mean(on & inner & outer))


def register(bname: str, only: list, write: bool) -> None:
    b = Building.load(bname)
    found = {}
    for spec in b.data["sheets"]["list"]:
        if spec["kind"] not in ("plan", "roofplan") or (only and spec["id"] not in only):
            continue
        level = spec.get("level", "roof")
        pts = outer_samples(b, level) if spec["kind"] == "plan" else roof_outline_samples(b)
        if len(pts) == 0:
            print("%s: no outer walls on level %s" % (spec["id"], level))
            continue
        sheet = Sheet(b, dict(spec, offset=[0.0, 0.0]))
        sheet.dens = ndimage.uniform_filter(sheet.ink.astype(np.float32), size=int(0.3 * R))
        best = (-1.0, 0.0, 0.0)
        grid = {}
        for ox in np.arange(-6.0, 6.01, 0.25):
            for oz in np.arange(-6.0, 6.01, 0.25):
                sc = score(sheet, pts, ox, oz)
                grid[(round(ox, 2), round(oz, 2))] = sc
                if sc > best[0]:
                    best = (sc, ox, oz)
        _, bx, bz = best
        for ox in np.arange(bx - 0.3, bx + 0.301, 0.05):
            for oz in np.arange(bz - 0.3, bz + 0.301, 0.05):
                sc = score(sheet, pts, ox, oz)
                if sc > best[0]:
                    best = (sc, ox, oz)
        sc, bx, bz = best
        # The best offset away from this one, for how sure the fit is.
        rival = max(v for (ox, oz), v in grid.items() if math.hypot(ox - bx, oz - bz) > 1.0)
        cur = spec.get("offset", [0.0, 0.0])
        print("%-9s level %-9s offset (%+.2f, %+.2f)  %.0f%% of outer walls on a line (next best %.0f%%)%s  [was (%+.2f, %+.2f)]"
              % (spec["id"], level, bx, bz, 100 * sc, 100 * rival, "  DOUBTFUL" if sc < rival * 1.3 else "", cur[0], cur[1]))
        found[spec["id"]] = [round(bx, 2), round(bz, 2)]
    if write and found:
        path = building_path(bname)
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for spec in data["sheets"]["list"]:
            if spec["id"] in found:
                spec["offset"] = found[spec["id"]]
        with open(path, "w", encoding="utf-8") as f:
            f.write(json.dumps(data, indent=1))
        print("written")


if __name__ == "__main__":
    args = sys.argv[1:]
    w = "--write" in args
    if w:
        args.remove("--write")
    register(args[0], args[1:], w)
