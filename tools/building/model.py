"""A building as data: the reader and the geometry every check shares.

A building file (game/data/buildings/<name>.json) describes a real
building in the survey's own feet: its sheets and how each registers to
the building's frame, its levels, its spaces (rooms, halls, stairs,
porches, balconies, decks, attics) as plan polygons, its openings, its
roof bodies and chimneys. Everything else (walls, gable ends, the roof's
surface where bodies meet, eaves, railings) is derived from these, in the
game by world/building/ and here, rasterised, for comparing the data with
the drawings.

Coordinates: plan points are [x, z] in feet (for the Mark Twain house x
runs north, z east, as the survey's plans do); heights y in feet over the
building's datum (the first floor).

Grid lines: "grid": {"x": {name: value}, "z": {name: value}} names the
lines walls stand on (an outer face, a partition's centre); any plan
coordinate may be a name instead of a number, so one measurement moves
every wall that shares it.

Shorthands inside a polygon's point list:
    {"arc": [cx, cz, r, a0, a1, n]}   n+1 points on a circle, angles in
                                       degrees from +x toward +z
    {"arc_at": [cx, cz, r, [a, ...]]} points on a circle at given angles
    {"rect": [x0, z0, x1, z1]}        a whole polygon given as a rectangle

Roof bodies (the roof's surface over a point is the highest body there;
a body's own surface is the lowest of its planes, as a hip is):
    {"kind": "planes", "planes": [[a, b, c], ...]}   y = a*x + b*z + c
    {"kind": "hip", "eave": e, "pitch": s | [sx0, sx1, sz0, sz1], "top": t}
    {"kind": "gable", "axis": "x" | "z", "eave": e, "peak": p}
    {"kind": "pyramid", "apex": [x, z], "eave": e, "peak": p}   eave at the
                                       overhang's edge, one plane per edge
    {"kind": "flat", "y": h}
    {"kind": "shed", "low": [[x, z], y], "high": [[x, z], y]}
each with "footprint" (the wall line, a polygon), "overhang" (feet, a
number or per side [x0, x1, z0, z1] for a rectangle), optional "holes"
(polygons the body leaves open) and "trim" (what its edges carry).
"""
from __future__ import annotations

import json
import math
import os
from dataclasses import dataclass, field

import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


def building_path(name: str) -> str:
    return os.path.join(ROOT, "game", "data", "buildings", name + ".json")


# ---- polygons ---------------------------------------------------------------

GRID: dict = {"x": {}, "z": {}}


def gx(v) -> float:
    """A plan x: a number, or the name of a grid line across x."""
    return float(GRID["x"][v]) if isinstance(v, str) else float(v)


def gz(v) -> float:
    return float(GRID["z"][v]) if isinstance(v, str) else float(v)


def expand_poly(spec) -> list[tuple[float, float]]:
    """A polygon from its data: a list of points and arcs, or a rect."""
    if isinstance(spec, dict) and "rect" in spec:
        x0, z0, x1, z1 = spec["rect"]
        x0, z0, x1, z1 = gx(x0), gz(z0), gx(x1), gz(z1)
        return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    pts: list[tuple[float, float]] = []
    for item in spec:
        if isinstance(item, dict) and "arc" in item:
            cx, cz, r, a0, a1, n = item["arc"]
            cx, cz = gx(cx), gz(cz)
            for i in range(int(n) + 1):
                a = math.radians(a0 + (a1 - a0) * i / n)
                pts.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
        elif isinstance(item, dict) and "arc_at" in item:
            cx, cz, r, angles = item["arc_at"]
            cx, cz = gx(cx), gz(cz)
            for a in angles:
                a = math.radians(a)
                pts.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
        else:
            pts.append((gx(item[0]), gz(item[1])))
    # Drop repeated points.
    out: list[tuple[float, float]] = []
    for p in pts:
        if not out or abs(p[0] - out[-1][0]) > 1e-6 or abs(p[1] - out[-1][1]) > 1e-6:
            out.append(p)
    if len(out) > 2 and abs(out[0][0] - out[-1][0]) < 1e-6 and abs(out[0][1] - out[-1][1]) < 1e-6:
        out.pop()
    return out


def expand_point(spec) -> tuple[float, float]:
    if isinstance(spec, dict) and "arc_pt" in spec:
        cx, cz, r, a = spec["arc_pt"]
        cx, cz = gx(cx), gz(cz)
        a = math.radians(a)
        return (cx + math.cos(a) * r, cz + math.sin(a) * r)
    return (gx(spec[0]), gz(spec[1]))


def signed_area(p) -> float:
    s = 0.0
    for i in range(len(p)):
        a, b = p[i], p[(i + 1) % len(p)]
        s += a[0] * b[1] - b[0] * a[1]
    return s / 2.0


def offset_poly(p, d: float) -> list[tuple[float, float]]:
    """The polygon grown outward by d (mitred corners, capped at 3 d)."""
    if abs(d) < 1e-9:
        return list(p)
    n = len(p)
    ccw = signed_area(p) > 0.0
    out = []
    for i in range(n):
        a, b, c = p[i - 1], p[i], p[(i + 1) % n]
        def normal(u, v):
            dx, dz = v[0] - u[0], v[1] - u[1]
            L = math.hypot(dx, dz) or 1.0
            # outward normal: right of travel for ccw
            return (dz / L, -dx / L) if ccw else (-dz / L, dx / L)
        n1, n2 = normal(a, b), normal(b, c)
        m = (n1[0] + n2[0], n1[1] + n2[1])
        ml = math.hypot(*m)
        if ml < 1e-9:
            out.append((b[0] + n1[0] * d, b[1] + n1[1] * d))
            continue
        m = (m[0] / ml, m[1] / ml)
        cosh = m[0] * n1[0] + m[1] * n1[1]
        k = d / max(cosh, 1.0 / 3.0)
        out.append((b[0] + m[0] * k, b[1] + m[1] * k))
    return out


def rect_overhang(p, over) -> list[tuple[float, float]]:
    """A rectangle's footprint grown by [x0, x1, z0, z1] feet per side."""
    xs = [q[0] for q in p]
    zs = [q[1] for q in p]
    x0, x1, z0, z1 = min(xs) - over[0], max(xs) + over[1], min(zs) - over[2], max(zs) + over[3]
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]


def inside(poly, X: np.ndarray, Z: np.ndarray) -> np.ndarray:
    """Even-odd point in polygon over arrays of points."""
    res = np.zeros(X.shape, dtype=bool)
    n = len(poly)
    for i in range(n):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % n]
        cond = (z1 > Z) != (z2 > Z)
        with np.errstate(divide="ignore", invalid="ignore"):
            xi = x1 + (Z - z1) * (x2 - x1) / (z2 - z1)
        res ^= cond & (X < xi)
    return res


# ---- the building -------------------------------------------------------------

@dataclass
class Body:
    id: str
    kind: str
    footprint: list
    extent: list            # the footprint with its overhang
    planes: list            # [(a, b, c)], surface = min over planes
    holes: list = field(default_factory=list)
    trim: str = "eave"
    spec: dict = field(default_factory=dict)
    # A pyramid or cone: each plane owns its sector (the triangle from its
    # eave edge to the apex), which holds whatever the footprint's shape.
    sectors: list = field(default_factory=list)

    def height(self, X: np.ndarray, Z: np.ndarray) -> np.ndarray:
        if self.sectors:
            h = np.full(X.shape, -np.inf)
            for (a, b, c), tri in zip(self.planes, self.sectors):
                m = inside(tri, X, Z)
                h = np.where(m, a * X + b * Z + c, h)
            return h
        h = np.full(X.shape, np.inf)
        for a, b, c in self.planes:
            h = np.minimum(h, a * X + b * Z + c)
        return h

    def plane_index(self, X: np.ndarray, Z: np.ndarray) -> np.ndarray:
        if self.sectors:
            idx = np.zeros(X.shape, dtype=np.int64)
            for k, tri in enumerate(self.sectors):
                idx = np.where(inside(tri, X, Z), k, idx)
            return idx
        stack = np.stack([a * X + b * Z + c for a, b, c in self.planes])
        return np.argmin(stack, axis=0)


def _planes_for(spec: dict, fp, ext) -> list:
    kind = spec["kind"]
    if kind == "planes":
        return [tuple(p) for p in spec["planes"]]
    if kind == "flat":
        return [(0.0, 0.0, float(spec["y"]))]
    xs = [q[0] for q in fp]
    zs = [q[1] for q in fp]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    if kind == "hip":
        e = float(spec["eave"])
        s = spec["pitch"]
        sx0, sx1, sz0, sz1 = (s, s, s, s) if isinstance(s, (int, float)) else s
        pl = [(sx0, 0.0, e - sx0 * x0), (-sx1, 0.0, e + sx1 * x1), (0.0, sz0, e - sz0 * z0), (0.0, -sz1, e + sz1 * z1)]
        if "top" in spec:
            pl.append((0.0, 0.0, float(spec["top"])))
        return pl
    if kind == "gable":
        e, p = float(spec["eave"]), float(spec["peak"])
        if spec["axis"] == "x":        # ridge runs along x, slopes fall to z0 and z1
            zc = (z0 + z1) / 2.0
            s = (p - e) / ((z1 - z0) / 2.0)
            return [(0.0, s, p - s * zc), (0.0, -s, p + s * zc)]
        xc = (x0 + x1) / 2.0
        s = (p - e) / ((x1 - x0) / 2.0)
        return [(s, 0.0, p - s * xc), (-s, 0.0, p + s * xc)]
    if kind == "pyramid":
        ax, az = gx(spec["apex"][0]), gz(spec["apex"][1])
        e, p = float(spec["eave"]), float(spec["peak"])
        # Through the eave line: the footprint grown by its overhang.
        pl = []
        n = len(ext)
        for i in range(n):
            (xa, za), (xb, zb) = ext[i], ext[(i + 1) % n]
            # The plane through the edge at the eave and the apex at the peak.
            v1 = np.array([xb - xa, 0.0, zb - za])
            v2 = np.array([ax - xa, p - e, az - za])
            nrm = np.cross(v1, v2)
            if abs(nrm[1]) < 1e-9:
                continue
            a = -nrm[0] / nrm[1]
            b = -nrm[2] / nrm[1]
            c = e - a * xa - b * za
            pl.append((a, b, c))
        return pl
    if kind == "shed":
        (xl, zl), yl = spec["low"]
        (xh, zh), yh = spec["high"]
        dx, dz = xh - xl, zh - zl
        L2 = dx * dx + dz * dz
        a, b = (yh - yl) * dx / L2, (yh - yl) * dz / L2
        return [(a, b, yl - a * xl - b * zl)]
    raise ValueError("unknown roof kind " + kind)


class Building:
    def __init__(self, data: dict):
        self.data = data
        self.name = data.get("name", "")
        GRID["x"] = dict(data.get("grid", {}).get("x", {}))
        GRID["z"] = dict(data.get("grid", {}).get("z", {}))
        self.levels = {lv["id"]: lv for lv in data.get("levels", [])}
        self.spaces = []
        for s in data.get("spaces", []):
            s = dict(s)
            s["poly"] = expand_poly(s["poly"])
            if "floor" not in s:
                s["floor"] = float(self.levels[s["level"]]["floor"])
            self.spaces.append(s)
        self.openings = []
        for o in data.get("openings", []):
            o = dict(o)
            o["at"] = expand_point(o["at"])
            self.openings.append(o)
        self.bodies: list[Body] = []
        by_id = {sp["id"]: sp for sp in self.spaces}
        for r in data.get("roofs", []):
            # A roof over a space may take the space's outline.
            fps = r["footprint"]
            fp = list(by_id[fps["space"]]["poly"]) if isinstance(fps, dict) and "space" in fps else expand_poly(fps)
            over = r.get("overhang", 0.0)
            ext = rect_overhang(fp, over) if isinstance(over, list) else offset_poly(fp, float(over))
            holes = [list(by_id[h["space"]]["poly"]) if isinstance(h, dict) and "space" in h else expand_poly(h)
                     for h in r.get("holes", [])]
            if "clear_rooms" in r:
                holes += [s["poly"] for s in self.spaces
                          if s["level"] == r["clear_rooms"] and s["kind"] not in ("porch", "balcony", "deck")]
            body = Body(r["id"], r["kind"], fp, ext, _planes_for(r, fp, ext), holes, r.get("trim", "eave"), r)
            if r["kind"] == "pyramid":
                ax, az = gx(r["apex"][0]), gz(r["apex"][1])
                body.planes, body.sectors = [], []
                n = len(ext)
                for i in range(n):
                    a, c = ext[i], ext[(i + 1) % n]
                    pl = _planes_for({"kind": "pyramid", "apex": r["apex"], "eave": r["eave"], "peak": r["peak"]}, [a, c], [a, c])
                    if pl:
                        body.planes.append(pl[0])
                        body.sectors.append([a, c, (ax, az)])
            self.bodies.append(body)
        self.chimneys = data.get("chimneys", [])

    @staticmethod
    def load(name_or_path: str) -> "Building":
        path = name_or_path if name_or_path.endswith(".json") else building_path(name_or_path)
        with open(path, encoding="utf-8") as f:
            return Building(json.load(f))

    def spaces_on(self, level: str) -> list:
        return [s for s in self.spaces if s["level"] == level]

    # ---- the roof's surface, rasterised --------------------------------------

    def roof_raster(self, x0: float, x1: float, z0: float, z1: float, res: float = 0.2):
        """The roof over a plan window: H (feet, -inf where there is none)
        and the id of the (body, plane) that is the roof at each cell."""
        xs = np.arange(x0, x1, res) + res / 2.0
        zs = np.arange(z0, z1, res) + res / 2.0
        X, Z = np.meshgrid(xs, zs, indexing="ij")
        H = np.full(X.shape, -np.inf)
        L = np.full(X.shape, -1, dtype=np.int32)
        for bi, b in enumerate(self.bodies):
            m = inside(b.extent, X, Z)
            for h in b.holes:
                m &= ~inside(h, X, Z)
            if not m.any():
                continue
            h = np.where(m, b.height(X, Z), -np.inf)
            pi = b.plane_index(X, Z)
            up = h > H + 1e-6
            H = np.where(up, h, H)
            L = np.where(up, bi * 64 + pi, L)
        return xs, zs, H, L
