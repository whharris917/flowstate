"""The boundary of a union of cells, exactly: every face of every cell less
where another cell's face lies against it. Its edges are matched end to
end (a vertex lying on another polygon's edge splits that edge), so the
surface either closes, every edge used once each way, or names the edges
where it does not.

Used for drawing (what is seen of a building: faces between cells that
touch are not drawn) and for checking (is a part a closed solid, does the
building's skin enclose its rooms).
"""
from __future__ import annotations

from collections import defaultdict
import math
from dataclasses import dataclass, field

import numpy as np

from solid import Cell, poly_less, poly_meet, poly_area, AREA_EPS

WELD = 5e-4         # feet: points this close are one point
NORMAL_TOL = 2e-5   # faces whose normals differ by less lie in one plane...
PLANE_TOL = 2e-4    # ...when their distances from the origin differ by less


@dataclass
class Poly:
    pts: list                    # np arrays, anticlockwise seen from outside
    n: np.ndarray
    owner: int                   # index of the cell it came from
    role: str
    loops: list = field(default_factory=list)   # the drawn outline, with split points


def _basis(n: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    a = np.array([1.0, 0.0, 0.0]) if abs(n[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    u = np.cross(n, a)
    u /= np.linalg.norm(u)
    v = np.cross(n, u)
    return u, v


def _canon(n: np.ndarray, d: float) -> tuple[np.ndarray, float, int]:
    """A plane's normal turned the one way of the two, decided by its
    largest component (a stray millionth elsewhere must not decide)."""
    k = int(np.argmax(np.abs(n)))
    if n[k] < 0:
        return -n, -d, -1
    return n, d, 1


def boundary(cells: list[Cell]) -> tuple[list[Poly], list[str]]:
    """The faces of the union of cells whose interiors do not overlap,
    and any faces found lying on another in the same direction (two
    cells overlapping, or drawn twice)."""
    groups: dict = defaultdict(list)
    recs = []
    # planes are one plane when their normals agree within NORMAL_TOL
    # (a plane reached by another route may tilt by a millionth)
    reps: dict = defaultdict(list)            # quantised normal -> [(rep normal, group key)]
    Q = 1e-4
    for ci, c in enumerate(cells):
        for f in c.faces:
            pl = c.planes[f.plane]
            n, d, s = _canon(np.array(pl.n), pl.d)
            qk = tuple(int(np.floor(v / Q)) for v in n)
            key = None
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for dz in (-1, 0, 1):
                        for rn, gk in reps.get((qk[0] + dx, qk[1] + dy, qk[2] + dz), ()):
                            if key is None and np.linalg.norm(rn - n) < NORMAL_TOL:
                                key = gk
            if key is None:
                key = len(reps) + len(groups) + 1
                key = ("g", len(groups), qk)
                reps[qk].append((n, key))
            recs.append((ci, f, pl, n, d, s))
            groups[key].append(len(recs) - 1)
    out: list[Poly] = []
    problems: list[str] = []
    for key, idxs in groups.items():
        # cluster by d
        idxs.sort(key=lambda i: recs[i][4])
        clusters, cur, last = [], [], None
        for i in idxs:
            d = recs[i][4]
            if last is not None and d - last > PLANE_TOL:
                clusters.append(cur)
                cur = []
            cur.append(i)
            last = d
        if cur:
            clusters.append(cur)
        for cl in clusters:
            n = recs[cl[0]][3]
            u, v = _basis(n)
            flat = {}
            for i in cl:
                ci, f, pl, _, _, s = recs[i]
                q = [(float(np.dot(p, u)), float(np.dot(p, v))) for p in map(np.array, f.pts)]
                if poly_area(q) < 0:
                    q = q[::-1]
                flat[i] = q
            dval = float(np.mean([recs[i][4] for i in cl]))
            for i in cl:
                ci, f, pl, _, _, s = recs[i]
                pieces = [flat[i]]
                for j in cl:
                    if j == i or recs[j][0] == ci:
                        continue
                    if recs[j][5] == s:
                        continue
                    nxt = []
                    for p in pieces:
                        nxt.extend(poly_less(p, flat[j]))
                    pieces = nxt
                    if not pieces:
                        break
                for p in pieces:
                    a_ = abs(poly_area(p))
                    if a_ < AREA_EPS:
                        continue
                    # a face narrower than points are welded at is rounding
                    longest = max(math.dist(p[k], p[(k + 1) % len(p)]) for k in range(len(p)))
                    if 2.0 * a_ / longest < 4e-4:
                        continue
                    pts = [u * a + v * b + n * dval for a, b in p]
                    # anticlockwise seen from outside: about the face's own normal
                    if s < 0:
                        pts = pts[::-1]
                    out.append(Poly(pts, n * s, ci, cells[ci].planes[f.plane].role))
            # Same-direction faces lying on each other.
            for a in range(len(cl)):
                for b in range(a + 1, len(cl)):
                    i, j = cl[a], cl[b]
                    if recs[i][5] != recs[j][5] or recs[i][0] == recs[j][0]:
                        continue
                    m = poly_meet(flat[i], flat[j])
                    if m and abs(poly_area(m)) > 1e-4:
                        problems.append((recs[i][0], recs[j][0], abs(poly_area(m))))
    return out, problems


# ---- edges ------------------------------------------------------------------

class Welder:
    def __init__(self) -> None:
        self.pts: list[np.ndarray] = []
        self.grid: dict = defaultdict(list)

    def id(self, p: np.ndarray) -> int:
        k = tuple(np.floor(p / WELD).astype(np.int64))
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for j in self.grid.get((k[0] + dx, k[1] + dy, k[2] + dz), ()):
                        if np.linalg.norm(self.pts[j] - p) < WELD:
                            return j
        self.pts.append(p)
        self.grid[k].append(len(self.pts) - 1)
        return len(self.pts) - 1


@dataclass
class EdgeReport:
    open_edges: list = field(default_factory=list)     # (a, b, forward, backward)
    shells: list = field(default_factory=list)         # [poly indices]
    shell_volume: list = field(default_factory=list)
    pairs: list = field(default_factory=list)          # (poly, poly, a, b) meeting along a -> b
    touching: list = field(default_factory=list)       # edges where parts touch along a line

    @property
    def closed(self) -> bool:
        return not self.open_edges


def analyse(polys: list[Poly]) -> EdgeReport:
    """Split every edge of the polygons at each vertex lying on it, then
    match each directed edge (i, j) with an edge (j, i): the surface is
    closed where every edge is met once each way. Fills each polygon's
    `loops` with its outline including the split points, and the report's
    `pairs` with the polygons meeting along each edge."""
    W = Welder()
    ids = [[W.id(np.asarray(p, dtype=float)) for p in poly.pts] for poly in polys]
    P = W.pts
    # a coarse grid of vertices, to find those lying on an edge
    G = 1.0
    grid: dict = defaultdict(list)
    for vid, p in enumerate(P):
        grid[tuple(np.floor(p / G).astype(np.int64))].append(vid)
    loops: list[list[int]] = []
    for loop in ids:
        out: list[int] = []
        n = len(loop)
        for k in range(n):
            a, b = loop[k], loop[(k + 1) % n]
            out.append(a)
            if a == b:
                continue
            pa, pb = P[a], P[b]
            d = pb - pa
            L2 = float(np.dot(d, d))
            lo = np.floor((np.minimum(pa, pb) - WELD) / G).astype(np.int64)
            hi = np.floor((np.maximum(pa, pb) + WELD) / G).astype(np.int64)
            on = []
            for gx in range(lo[0], hi[0] + 1):
                for gy in range(lo[1], hi[1] + 1):
                    for gz in range(lo[2], hi[2] + 1):
                        for vid in grid.get((gx, gy, gz), ()):
                            if vid == a or vid == b:
                                continue
                            t = float(np.dot(P[vid] - pa, d)) / L2
                            if t <= 1e-9 or t >= 1 - 1e-9:
                                continue
                            if np.linalg.norm(pa + d * t - P[vid]) < WELD:
                                on.append((t, vid))
            on.sort()
            for t, vid in on:
                if out[-1] != vid:
                    out.append(vid)
        # drop a repeated closing point
        while len(out) > 1 and out[-1] == out[0]:
            out.pop()
        loops.append(out)
    directed: dict = defaultdict(list)
    for pi, loop in enumerate(loops):
        n = len(loop)
        for k in range(n):
            a, b = loop[k], loop[(k + 1) % n]
            if a != b:
                directed[(a, b)].append(pi)
    parent = list(range(len(polys)))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def join(x: int, y: int) -> None:
        rx, ry = find(x), find(y)
        if rx != ry:
            parent[rx] = ry

    rep = EdgeReport()
    for (a, b), fw in directed.items():
        bw = directed.get((b, a), [])
        if not (a < b or not bw):
            continue
        if len(fw) != len(bw):
            rep.open_edges.append((P[a], P[b], len(fw), len(bw)))
            for x in fw + bw:
                join(x, fw[0])
            continue
        if len(fw) == 1:
            rep.pairs.append((fw[0], bw[0], P[a], P[b]))
            join(fw[0], bw[0])
            continue
        # more than two faces on one edge: parts touching along a line. Round
        # the edge, faces that bound the same wedge of air belong to one
        # surface; a wedge of solid between them does not join them.
        rep.touching.append((P[a], P[b], len(fw), len(bw)))
        e = P[b] - P[a]
        e = e / np.linalg.norm(e)
        mid = (P[a] + P[b]) / 2.0
        ref = None
        items = []
        for pi in fw + bw:
            pts = polys[pi].pts
            c = sum(pts) / len(pts)
            dvec = c - mid
            dvec = dvec - e * float(np.dot(dvec, e))
            L = float(np.linalg.norm(dvec))
            if L < 1e-9:
                continue
            dvec /= L
            if ref is None:
                ref = dvec
            th = math.atan2(float(np.dot(np.cross(ref, dvec), e)), float(np.dot(ref, dvec)))
            # which way round the edge the face's outside lies
            s = float(np.dot(polys[pi].n, np.cross(e, dvec)))
            items.append((th, pi, s))
        # two faces at the same angle facing the same way are one surface
        # (chips of a face split twice): keep one, join the other to it
        kept = []
        for it in sorted(items):
            dup = next((q for q in kept if abs(q[0] - it[0]) < 1e-6 and (q[2] > 0) == (it[2] > 0)), None)
            if dup is not None:
                join(it[1], dup[1])
                continue
            kept.append(it)
        items = kept
        # faces at the same angle (one plane, one side) may go in either
        # order: take the order in which the wedges alternate consistently
        k = len(items)
        best = None
        for sign in (1, -1):
            order = sorted(items, key=lambda it: (round(it[0], 6), sign * it[2]))
            bad = 0
            for i in range(k):
                s0, s1 = order[i][2], order[(i + 1) % k][2]
                if (s0 > 0) != (s1 < 0):
                    bad += 1
            if best is None or bad < best[0]:
                best = (bad, order)
        order = best[1]
        for i in range(k):
            t0, p0, s0 = order[i]
            t1, p1, s1 = order[(i + 1) % k]
            if s0 > 0 and s1 < 0:
                join(p0, p1)
                rep.pairs.append((p0, p1, P[a], P[b]))
            elif (s0 > 0) != (s1 < 0):
                rep.open_edges.append((P[a], P[b], len(fw), len(bw)))
    for pi, loop in enumerate(loops):
        polys[pi].loops = [P[v] for v in loop]
    shells: dict = defaultdict(list)
    for pi in range(len(polys)):
        shells[find(pi)].append(pi)
    for sh in shells.values():
        vol = 0.0
        for pi in sh:
            pts = polys[pi].pts
            for i in range(1, len(pts) - 1):
                vol += float(np.dot(pts[0], np.cross(pts[i], pts[i + 1])))
        rep.shells.append(sh)
        rep.shell_volume.append(vol / 6.0)
    return rep


def triangles(poly: Poly) -> list:
    """A polygon's outline (with its split points) as triangles fanned
    from its centre, so a vertex on an edge is never a crack."""
    loop = poly.loops or poly.pts
    c = sum(loop) / len(loop)
    out = []
    for i in range(len(loop)):
        a, b = loop[i], loop[(i + 1) % len(loop)]
        if np.linalg.norm(np.cross(a - c, b - c)) > 1e-10:
            out.append((c, a, b))
    return out
