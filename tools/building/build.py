"""Generate a building, validate it, and write what the game draws.

    .venv/Scripts/python.exe tools/building/build.py <name> [--force]

Reads game/data/buildings/<name>.json, generates it (arch.py), checks it
(validate.py) and, only if every check passes, writes
game/data/buildings/<name>.bld: the building's visible surface in world
metres, finished by the file's "style". --force writes a failing building
for looking at its faults; the game prints that it is broken.

The .bld format (little-endian): "BLD1", u32 flags (1 = failed its
checks), u32 polygon count, then per polygon: u8 surface (0 solid, 1 glass,
2 a door leaf, drawn open and not solid), 4 u8 colour (alpha = the wall
shader's kind / 20), 3 f32 normal, u16 point count, points as 3 f32.
"""
from __future__ import annotations

import json
import math
import os
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))

import numpy as np

import arch
import plan as P
from surface import boundary, analyse
from validate import Validator

K = {"paint": 0, "clapboard": 1, "brick": 2, "shingle": 3, "stone": 4, "roof": 5, "plank": 6,
     "timber": 7, "tar": 8, "plaster": 12, "enamel": 14, "wood": 16, "slate": 17, "beaded": 18}

DEFAULT_STYLE = {
    "brick": {"color": [0.60, 0.26, 0.17], "kind": "brick"},
    "clapboard": {"color": [0.55, 0.45, 0.35], "kind": "clapboard"},
    "timber": {"color": [0.33, 0.14, 0.09], "kind": "timber"},
    "stone": {"color": [0.44, 0.34, 0.29], "kind": "stone"},
    "plaster": {"color": [0.84, 0.79, 0.68], "kind": "plaster"},
    "ceiling": {"color": [0.86, 0.82, 0.72], "kind": "plaster"},
    "floor": {"color": [0.52, 0.34, 0.18], "kind": "wood"},
    "attic": {"color": [0.45, 0.33, 0.22], "kind": "beaded"},
    "trim": {"color": [0.33, 0.14, 0.09], "kind": "paint"},
    "sash": {"color": [0.22, 0.10, 0.07], "kind": "paint"},
    "door": {"color": [0.30, 0.17, 0.09], "kind": "wood"},
    "deck": {"color": [0.36, 0.34, 0.31], "kind": "plank"},
    "slate": {"color": [0.37, 0.42, 0.40], "kind": "slate"},
    "tin": {"color": [0.38, 0.47, 0.41], "kind": "paint"},
    "glass": {"color": [0.5, 0.56, 0.58], "kind": "paint"},
    "lattice": {"color": [0.33, 0.14, 0.09], "kind": "paint"},
    "chimney": {"color": [0.60, 0.26, 0.17], "kind": "brick"},
}


class Style:
    def __init__(self, spec: dict):
        self.mats = dict(DEFAULT_STYLE)
        self.mats.update(spec.get("materials", {}))
        self.bands = spec.get("bands", [])            # [y0, y1, material] on outer brick
        self.courses = spec.get("courses")            # {"height": ft, "materials": [...]} on slate

    def color(self, mat: str) -> tuple:
        m = self.mats.get(mat) or self.mats["trim"]
        c = m["color"]
        return (c[0], c[1], c[2], K.get(m.get("kind", "paint"), 0) / 20.0)


def finish(v: Validator, poly) -> str:
    """The material a face of the surface is finished in."""
    m = v.m
    e = m.elements[v.owner[poly.owner]]
    role = v._role(poly)
    k = e.kind
    if k == "roof":
        R = m.roofs[e.id.split(":", 1)[1]]
        if role in ("slope", "deck"):
            return R.cover
        if role == "attic":
            return "attic"
        return "trim"
    if k in ("wall", "cheek"):
        if role in ("inner",):
            return "plaster"
        return v.cells[poly.owner].mat or e.mat or "brick"
    if k == "partition":
        return "plaster"
    if k == "slab":
        if role in ("floor", "threshold"):
            return "floor"
        if role == "ceiling":
            return "ceiling"
        if role in ("deck_top",):
            return "deck"
        if role in ("deck_under", "deck_edge"):
            return "trim"
        # a floor's edge between two storeys shows as the wall
        return "stone" if poly.role in ("footing",) or _below(poly, 0.0) else "brick"
    if k == "frame":
        return "sash"
    if k == "glass":
        return "glass"
    if k == "door":
        return "door"
    if k == "sill":
        return "stone"
    if k == "chimney":
        return "chimney"
    if k == "skirt":
        return "lattice"
    return "trim"


def _below(poly, y: float) -> bool:
    return max(p[1] for p in poly.pts) <= y + 1e-6


def clip_y(loop: list, y: float, keep_below: bool) -> list:
    out = []
    n = len(loop)
    for i in range(n):
        a, b = loop[i], loop[(i + 1) % n]
        sa, sb = a[1] - y, b[1] - y
        ina = sa <= 0 if keep_below else sa >= 0
        inb = sb <= 0 if keep_below else sb >= 0
        if ina:
            out.append(a)
        if ina != inb and abs(sa - sb) > 1e-12:
            t = sa / (sa - sb)
            out.append(a + (b - a) * t)
    return out


def bands_of(loop: list, cuts: list) -> list:
    """A convex loop cut into horizontal bands at heights `cuts` (sorted):
    [(y0, y1, loop)]."""
    out = []
    ys = [p[1] for p in loop]
    lo, hi = min(ys), max(ys)
    edges = [lo - 1] + [c for c in cuts if lo < c < hi] + [hi + 1]
    for i in range(len(edges) - 1):
        q = clip_y(loop, edges[i], keep_below=False)
        if len(q) >= 3:
            q = clip_y(q, edges[i + 1], keep_below=True)
        if len(q) >= 3:
            out.append((edges[i], edges[i + 1], q))
    return out


def write(v: Validator, path: str, failed: bool) -> int:
    m = v.m
    st = Style(m.data.get("style", {}))
    w = m.data.get("world", {})
    ox, oz = w.get("origin", [0.0, 0.0])
    ft = float(w.get("ft_to_m", 0.3048))
    datum = float(w.get("first_floor_m", 0.0))
    # the surface without door leaves, which are drawn open
    solid_ids = [i for i, o in enumerate(v.owner) if m.elements[o].kind != "door"]
    leaf_ids = [i for i, o in enumerate(v.owner) if m.elements[o].kind == "door"]
    cells = [v.cells[i] for i in solid_ids]
    sub = Validator.__new__(Validator)
    sub.m, sub.cells, sub.owner = m, cells, [v.owner[i] for i in solid_ids]
    polys, _ = boundary(cells)
    analyse(polys)
    recs = []

    def emit(surface: int, col: tuple, n, loop):
        pts = [((p[2] - oz) * ft, datum + p[1] * ft, -(p[0] - ox) * ft) for p in loop]
        nn = (float(n[2]), float(n[1]), -float(n[0]))
        recs.append((surface, col, nn, pts))

    band_cuts = sorted({float(b[0]) for b in st.bands} | {float(b[1]) for b in st.bands})
    for poly in polys:
        mat = finish(sub, poly)
        loop = [np.asarray(p, dtype=float) for p in (poly.loops or poly.pts)]
        surface = 1 if mat == "glass" else 0
        role = sub._role(poly)
        if mat in ("brick",) and role in ("outer", "slab_edge") and band_cuts:
            for y0, y1, q in bands_of(loop, band_cuts):
                ym = (y0 + y1) / 2.0
                bm = mat
                for b in st.bands:
                    if b[0] <= ym <= b[1]:
                        bm = b[2]
                emit(surface, st.color(bm), poly.n, q)
            continue
        if mat == "slate" and st.courses and role == "slope":
            hgt = float(st.courses["height"])
            ys = [p[1] for p in loop]
            cuts = [hgt * k for k in range(int(math.floor(min(ys) / hgt)), int(math.ceil(max(ys) / hgt)) + 1)]
            for y0, y1, q in bands_of(loop, cuts):
                k = int(math.floor((y0 + y1) / 2.0 / hgt))
                names = st.courses["materials"]
                emit(surface, st.color(names[k % len(names)]), poly.n, q)
            continue
        emit(surface, st.color(mat), poly.n, loop)
    # door leaves, swung open into the room
    leaves = {}
    for i in leaf_ids:
        leaves.setdefault(v.owner[i], []).append(v.cells[i])
    for eid, lc in leaves.items():
        op = next(o for o in m.openings if o["id"] + ":leaf" == eid)
        run = op["run"]
        lpolys, _ = boundary(lc)
        analyse(lpolys)
        us = [q[0] for q in op["prof"]]
        s0, s1 = run.s_range()
        mid = (s0 + s1) / 2.0
        hinge = run.plan(min(us) + 0.25, mid - 0.175)
        ang = math.radians(80.0)
        o = run.out
        # swing so the free edge moves inward (against the outward normal)
        test = run.plan(max(us), mid - 0.175)
        def rot(p, a):
            dx, dz = p[0] - hinge[0], p[2] - hinge[1]
            c, s = math.cos(a), math.sin(a)
            return np.array([hinge[0] + dx * c - dz * s, p[1], hinge[1] + dx * s + dz * c])
        t1 = rot(np.array([test[0], 0.0, test[1]]), ang)
        if (t1[0] - hinge[0]) * o[0] + (t1[2] - hinge[1]) * o[1] > 0:
            ang = -ang
        for poly in lpolys:
            loop = [rot(np.asarray(p, dtype=float), ang) for p in (poly.loops or poly.pts)]
            nrm = rot(np.asarray(poly.n) + np.array([hinge[0], 0.0, hinge[1]]), ang) - np.array([hinge[0], 0.0, hinge[1]])
            emit(2, st.color("door"), nrm, loop)
    with open(path, "wb") as f:
        f.write(b"BLD1")
        f.write(struct.pack("<II", 1 if failed else 0, len(recs)))
        for surface, col, nn, pts in recs:
            f.write(struct.pack("<B4B3fH", surface, *[max(0, min(255, int(round(c * 255)))) for c in col], *nn, len(pts)))
            f.write(struct.pack("<%df" % (3 * len(pts)), *[x for p in pts for x in p]))
    return len(recs)


def main(argv: list[str]) -> int:
    name = argv[1] if len(argv) > 1 else "twain"
    path = name if name.endswith(".json") else os.path.join(arch.M.ROOT, "game", "data", "buildings", name + ".json")
    out = os.path.splitext(path)[0] + ".bld"
    t = time.time()
    m = arch.load(path).generate()
    v = Validator(m)
    v.run()
    print(v.report("--quiet" in argv))
    failed = bool(v.findings)
    if failed and "--force" not in argv:
        print("not written: the building fails its checks (--force writes it marked broken)")
        return 1
    n = write(v, out, failed)
    print("wrote %s: %d faces%s, %.1f s" % (os.path.relpath(out, arch.M.ROOT), n, " (BROKEN)" if failed else "", time.time() - t))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
