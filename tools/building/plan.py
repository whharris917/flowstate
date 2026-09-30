"""Plan geometry for the generator: convex pieces of any simple polygon,
and the edges where tiled polygons meet or face nothing.

Points are (x, z) tuples in feet; polygons are lists of points.
"""
from __future__ import annotations

import math

from solid import ccw, poly_area, is_convex

TOL = 5e-3          # feet: points closer than this are one point


def _cross(o, a, b) -> float:
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _in_tri(p, a, b, c) -> bool:
    return _cross(a, b, p) > 1e-12 and _cross(b, c, p) > 1e-12 and _cross(c, a, p) > 1e-12


def simplify(p: list) -> list:
    """Drop repeated and collinear points."""
    out = []
    for q in p:
        if not out or math.dist(q, out[-1]) > TOL:
            out.append(q)
    if len(out) > 1 and math.dist(out[0], out[-1]) < TOL:
        out.pop()
    changed = True
    while changed and len(out) > 3:
        changed = False
        for i in range(len(out)):
            a, b, c = out[i - 1], out[i], out[(i + 1) % len(out)]
            if abs(_cross(a, b, c)) < 1e-9 * max(1.0, math.dist(a, c)) and \
                    (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1]) > 0:
                out.pop(i)
                changed = True
                break
    return out


def triangulate(p: list) -> list[list]:
    """Ear clipping of a simple anticlockwise polygon."""
    pts = list(p)
    tris = []
    guard = 0
    while len(pts) > 3 and guard < 10000:
        guard += 1
        n = len(pts)
        for i in range(n):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
            if _cross(a, b, c) <= 1e-12:
                continue
            if any(_in_tri(q, a, b, c) for q in pts if q not in (a, b, c)):
                continue
            tris.append([a, b, c])
            pts.pop(i)
            break
        else:
            raise ValueError("polygon is not simple")
    tris.append(pts)
    return tris


def convex_parts(p: list) -> list[list]:
    """A simple polygon as convex pieces (Hertel-Mehlhorn: triangles
    merged across diagonals while the union stays convex)."""
    p = simplify(ccw(p))
    if is_convex(p):
        return [p]
    parts = triangulate(p)
    merged = True
    while merged:
        merged = False
        for i in range(len(parts)):
            for j in range(i + 1, len(parts)):
                m = _merge(parts[i], parts[j])
                if m is not None and is_convex(m):
                    parts[i] = simplify(m)
                    parts.pop(j)
                    merged = True
                    break
            if merged:
                break
    return [simplify(q) for q in parts]


def _merge(a: list, b: list):
    """Two anticlockwise polygons sharing an edge, as one."""
    for i in range(len(a)):
        p0, p1 = a[i], a[(i + 1) % len(a)]
        for j in range(len(b)):
            q0, q1 = b[j], b[(j + 1) % len(b)]
            if math.dist(p0, q1) < TOL and math.dist(p1, q0) < TOL:
                # a up to p0, then b from q1 (= p0) round to q0 (= p1)
                out = [a[(i + 1 + k) % len(a)] for k in range(len(a))]   # starts at p1, ends at p0
                rest = [b[(j + 2 + k) % len(b)] for k in range(len(b) - 2)]  # after q1 ... before q0
                return out + rest
    return None


# ---- edges of tiled polygons ------------------------------------------------

def _line_key(a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dz)
    ux, uz = dx / L, dz / L
    if ux < -1e-9 or (abs(ux) <= 1e-9 and uz < 0):
        ux, uz = -ux, -uz
    off = -uz * a[0] + ux * a[1]
    return (ux, uz, off)


def _same_line(k1, k2) -> bool:
    return abs(k1[0] - k2[0]) < 1e-6 and abs(k1[1] - k2[1]) < 1e-6 and abs(k1[2] - k2[2]) < 2e-3


def edge_parts(polys: dict) -> list[dict]:
    """Every edge of every polygon (anticlockwise, {id: poly}) cut where
    it meets other polygons' edges running the other way along the same
    line: [{a, b, of (id), other (id or None)}], a -> b along the owner's
    boundary, the owner on the left."""
    edges = []
    for pid, p in polys.items():
        p = ccw(p)
        for i in range(len(p)):
            a, b = p[i], p[(i + 1) % len(p)]
            if math.dist(a, b) < TOL:
                continue
            edges.append((pid, a, b, _line_key(a, b)))
    out = []
    for pid, a, b, key in edges:
        ux, uz = key[0], key[1]
        ta, tb = a[0] * ux + a[1] * uz, b[0] * ux + b[1] * uz
        lo, hi = min(ta, tb), max(ta, tb)
        cuts = {lo, hi}
        others = []
        for qid, c, d, k2 in edges:
            if qid == pid or not _same_line(key, k2):
                continue
            # running the other way
            if ((d[0] - c[0]) * (b[0] - a[0]) + (d[1] - c[1]) * (b[1] - a[1])) >= 0:
                continue
            tc, td = c[0] * ux + c[1] * uz, d[0] * ux + d[1] * uz
            o0, o1 = max(lo, min(tc, td)), min(hi, max(tc, td))
            if o1 - o0 > TOL:
                others.append((o0, o1, qid))
                cuts.add(o0)
                cuts.add(o1)
        ts = sorted(cuts)
        merged = []
        for t in ts:
            if not merged or t - merged[-1] > TOL:
                merged.append(t)
        ts = merged
        dirn = 1.0 if tb > ta else -1.0
        segs = []
        for k in range(len(ts) - 1):
            t0, t1 = ts[k], ts[k + 1]
            mid = (t0 + t1) / 2.0
            other = None
            for o0, o1, qid in others:
                if o0 - TOL <= mid <= o1 + TOL:
                    other = qid
            segs.append((t0, t1, other))
        if dirn < 0:
            segs = [(t1, t0, o) for (t0, t1, o) in reversed(segs)]
        # back to points: the line through a with direction u
        def pt(t):
            s = (t - ta)
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            f = s / (tb - ta)
            return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
        for t0, t1, other in segs:
            out.append({"a": pt(t0), "b": pt(t1), "of": pid, "other": other})
    return out


def chain(segs: list[dict]) -> list[list[dict]]:
    """Directed segments (each {a, b, ...}) joined end to start into
    closed loops. Consecutive collinear segments with the same labels are
    kept apart; the caller merges what it wants."""
    left = list(segs)
    loops = []
    while left:
        loop = [left.pop(0)]
        guard = 0
        while guard < 100000:
            guard += 1
            end = loop[-1]["b"]
            if math.dist(end, loop[0]["a"]) < 1e-3:
                break
            nxt = None
            for i, s in enumerate(left):
                if math.dist(s["a"], end) < 1e-3:
                    nxt = i
                    break
            if nxt is None:
                raise ValueError("an outline does not close at (%.2f, %.2f)" % end)
            loop.append(left.pop(nxt))
        loops.append(loop)
    return loops


def point_in(p, poly) -> bool:
    inside = False
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        if (a[1] > p[1]) != (b[1] > p[1]):
            x = a[0] + (p[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            if p[0] < x:
                inside = not inside
    return inside


def seg_dist(p, a, b) -> float:
    dx, dz = b[0] - a[0], b[1] - a[1]
    L2 = dx * dx + dz * dz
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / L2))
    return math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dz * t)


def area(p) -> float:
    return abs(poly_area(p))
