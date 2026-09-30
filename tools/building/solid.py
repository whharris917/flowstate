"""Convex solids as intersections of half-spaces: the kernel every
generated building is made of.

A building's parts are unions of convex cells. A cell is the intersection
of half-spaces n.x <= d, each plane carrying the role of the face it makes
(a wall's outer face, a roof's slope, its underside, an eave's end). Cells
are built by clipping, subtracted from one another by splitting into
convex pieces, and tested for overlap exactly, so a generated part is a
closed solid by construction and two parts either touch face to face or
overlap by a measurable volume.

Coordinates are feet: x and z in plan, y up. Points are tuples.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

EPS = 1e-7          # distance from a plane that counts as on it, feet
VOL_EPS = 1e-6      # cubic feet: smaller is numerical noise, not a solid
AREA_EPS = 1e-6     # square feet
THIN = 1e-4         # feet: a piece thinner than this across a face is no piece
BOUND = 1.0e4       # the box every cell starts from


def dot(a, b) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def mul(a, k: float):
    return (a[0] * k, a[1] * k, a[2] * k)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a) -> float:
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def unit(a):
    L = norm(a)
    return (a[0] / L, a[1] / L, a[2] / L)


@dataclass
class Plane:
    """The half-space n.x <= d, n a unit vector. `role` names the face the
    plane makes on a cell (what it is and so how it is finished:
    "outer", "slope", "soffit", ...)."""
    n: tuple
    d: float
    role: str = ""

    @staticmethod
    def of(n, d: float, role: str = "") -> "Plane":
        L = norm(n)
        return Plane((n[0] / L, n[1] / L, n[2] / L), float(d) / L, role)

    @staticmethod
    def through(n, p, role: str = "") -> "Plane":
        """The plane with outward normal n through point p."""
        n = unit(n)
        return Plane(n, dot(n, p), role)

    def side(self, p) -> float:
        n = self.n
        return n[0] * p[0] + n[1] * p[1] + n[2] * p[2] - self.d

    def flipped(self, role: str | None = None) -> "Plane":
        return Plane((-self.n[0], -self.n[1], -self.n[2]), -self.d, self.role if role is None else role)

    def shifted(self, dist: float, role: str | None = None) -> "Plane":
        """Moved outward along its normal by dist."""
        return Plane(self.n, self.d + dist, self.role if role is None else role)

    def with_role(self, role: str) -> "Plane":
        return Plane(self.n, self.d, role)


def below_y(a: float, b: float, c: float, role: str = "") -> Plane:
    """The half-space under the surface y = a x + b z + c."""
    return Plane.of((-a, 1.0, -b), c, role)


def above_y(a: float, b: float, c: float, role: str = "") -> Plane:
    return Plane.of((a, -1.0, b), -c, role)


def floor_at(y: float, role: str = "bottom") -> Plane:
    return Plane((0.0, -1.0, 0.0), -y, role)


def ceiling_at(y: float, role: str = "top") -> Plane:
    return Plane((0.0, 1.0, 0.0), y, role)


def vertical(p0, p1, role: str = "") -> Plane:
    """The half-space to the left of the plan line p0 -> p1 (x, z): the
    inside of an anticlockwise polygon's edge."""
    dx, dz = p1[0] - p0[0], p1[1] - p0[1]
    return Plane.through((dz, 0.0, -dx), (p0[0], 0.0, p0[1]), role)


def prism_planes(poly, y0: float | None, y1: float | None, side_role: str = "side",
                 bottom_role: str = "bottom", top_role: str = "top") -> list[Plane]:
    """A vertical prism over a convex anticlockwise plan polygon."""
    out = [vertical(poly[i], poly[(i + 1) % len(poly)], side_role) for i in range(len(poly))
           if abs(poly[i][0] - poly[(i + 1) % len(poly)][0]) + abs(poly[i][1] - poly[(i + 1) % len(poly)][1]) > 1e-9]
    if y0 is not None:
        out.append(floor_at(y0, bottom_role))
    if y1 is not None:
        out.append(ceiling_at(y1, top_role))
    return out


def prism_roles(poly, roles, y0: float | None, y1: float | None, bottom_role: str = "bottom",
                top_role: str = "top") -> list[Plane]:
    """A vertical prism over a convex anticlockwise plan polygon, each side
    with its own role (roles[i] for the edge from poly[i])."""
    if poly_area(poly) <= 0:
        raise ValueError("prism_roles needs an anticlockwise polygon")
    out = [vertical(poly[i], poly[(i + 1) % len(poly)], roles[i]) for i in range(len(poly))]
    if y0 is not None:
        out.append(floor_at(y0, bottom_role))
    if y1 is not None:
        out.append(ceiling_at(y1, top_role))
    return out


@dataclass
class Face:
    plane: int                  # index into the cell's planes
    pts: list                   # points, anticlockwise seen from outside


@dataclass
class Cell:
    """A convex solid: its planes and the faces they make."""
    planes: list
    faces: list = field(default_factory=list)
    mat: str = ""               # material of its faces unless a plane says
    color: tuple = (1.0, 1.0, 1.0)
    _vs: list | None = None
    _box: tuple | None = None

    def vset(self) -> list:
        """The distinct corners."""
        if self._vs is None:
            seen = {}
            for f in self.faces:
                for p in f.pts:
                    seen[(round(p[0], 7), round(p[1], 7), round(p[2], 7))] = p
            self._vs = list(seen.values())
        return self._vs

    def aabb(self) -> tuple:
        if self._box is None:
            v = self.vset()
            self._box = (tuple(min(p[k] for p in v) for k in range(3)), tuple(max(p[k] for p in v) for k in range(3)))
        return self._box

    def volume(self) -> float:
        s = 0.0
        for f in self.faces:
            p0 = f.pts[0]
            for i in range(1, len(f.pts) - 1):
                s += dot(p0, cross(f.pts[i], f.pts[i + 1]))
        return s / 6.0

    def centroid(self):
        v = self.vset()
        return tuple(sum(p[k] for p in v) / len(v) for k in range(3))

    def with_planes(self, extra: list[Plane]) -> "Cell | None":
        return make_cell(self.planes + extra, self.mat, self.color, start=self)

    def recolored(self, mat: str | None = None, color=None) -> "Cell":
        return Cell(self.planes, self.faces, self.mat if mat is None else mat,
                    self.color if color is None else color)


def _clip_face(pts: list, pl: Plane) -> tuple[list, list]:
    """Sutherland-Hodgman: the part of a face inside pl, and the points
    where its boundary meets pl."""
    out, cut = [], []
    n = len(pts)
    sides = [pl.side(p) for p in pts]
    for i in range(n):
        p, q = pts[i], pts[(i + 1) % n]
        sp, sq = sides[i], sides[(i + 1) % n]
        if sp <= EPS:
            out.append(p)
            if sp >= -EPS:
                cut.append(p)
        if (sp < -EPS and sq > EPS) or (sp > EPS and sq < -EPS):
            t = sp / (sp - sq)
            x = (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t)
            out.append(x)
            cut.append(x)
    return out, cut


def _order_loop(pts: list, n) -> list:
    """Distinct points on a plane, anticlockwise about its normal n."""
    uniq: list = []
    for p in pts:
        if not any(norm(sub(p, q)) < 1e-6 for q in uniq):
            uniq.append(p)
    if len(uniq) < 3:
        return []
    k = len(uniq)
    c = (sum(p[0] for p in uniq) / k, sum(p[1] for p in uniq) / k, sum(p[2] for p in uniq) / k)
    u = sub(uniq[0], c)
    if norm(u) < 1e-12:
        u = sub(uniq[1], c)
    u = unit(u)
    v = cross(n, u)
    uniq.sort(key=lambda p: math.atan2(dot(sub(p, c), v), dot(sub(p, c), u)))
    return uniq


def _clean(pts: list) -> list:
    """Drop repeated and collinear points."""
    out = []
    for p in pts:
        if not out or norm(sub(p, out[-1])) > 1e-6:
            out.append(p)
    while len(out) > 1 and norm(sub(out[0], out[-1])) < 1e-6:
        out.pop()
    changed = True
    while changed and len(out) >= 3:
        changed = False
        for i in range(len(out)):
            a, b, c = out[i - 1], out[i], out[(i + 1) % len(out)]
            if norm(cross(sub(b, a), sub(c, b))) < 1e-9 * max(1.0, norm(sub(c, a))):
                out.pop(i)
                changed = True
                break
    return out


def area3(pts: list) -> float:
    sx = sy = sz = 0.0
    for i in range(len(pts)):
        c = cross(pts[i], pts[(i + 1) % len(pts)])
        sx += c[0]
        sy += c[1]
        sz += c[2]
    return math.sqrt(sx * sx + sy * sy + sz * sz) / 2.0


def _box_faces(planes: list) -> list:
    B = BOUND
    c = [(float(x), float(y), float(z)) for x in (-B, B) for y in (-B, B) for z in (-B, B)]

    def idx(x, y, z):
        return x * 4 + y * 2 + z

    quads = [
        ((-1.0, 0.0, 0.0), [idx(0, 0, 0), idx(0, 0, 1), idx(0, 1, 1), idx(0, 1, 0)]),
        ((1.0, 0.0, 0.0), [idx(1, 0, 0), idx(1, 1, 0), idx(1, 1, 1), idx(1, 0, 1)]),
        ((0.0, -1.0, 0.0), [idx(0, 0, 0), idx(1, 0, 0), idx(1, 0, 1), idx(0, 0, 1)]),
        ((0.0, 1.0, 0.0), [idx(0, 1, 0), idx(0, 1, 1), idx(1, 1, 1), idx(1, 1, 0)]),
        ((0.0, 0.0, -1.0), [idx(0, 0, 0), idx(0, 1, 0), idx(1, 1, 0), idx(1, 0, 0)]),
        ((0.0, 0.0, 1.0), [idx(0, 0, 1), idx(1, 0, 1), idx(1, 1, 1), idx(0, 1, 1)]),
    ]
    faces = []
    for n, q in quads:
        planes.append(Plane(n, B, "unbounded"))
        faces.append(Face(len(planes) - 1, [c[i] for i in q]))
    return faces


class Unbounded(ValueError):
    pass


def make_cell(planes: list, mat: str = "", color=(1.0, 1.0, 1.0), start: Cell | None = None) -> Cell | None:
    """The cell cut from space by the planes, or None when it has no
    volume. Raises Unbounded when the planes leave it open."""
    if start is not None:
        all_planes = list(start.planes)
        faces = [Face(f.plane, list(f.pts)) for f in start.faces]
        new = planes[len(start.planes):]
    else:
        all_planes = []
        faces = _box_faces(all_planes)
        new = planes
    for pl in new:
        sides_all = [pl.side(p) for f in faces for p in f.pts]
        if max(sides_all) <= EPS:
            continue            # wholly inside: the plane makes no face
        if min(sides_all) >= -EPS:
            return None         # wholly outside
        k = len(all_planes)
        all_planes.append(pl)
        kept, cuts = [], []
        for f in faces:
            pts, cut = _clip_face(f.pts, pl)
            cuts.extend(cut)
            pts = _clean(pts)
            if len(pts) >= 3 and area3(pts) > AREA_EPS * 1e-3:
                kept.append(Face(f.plane, pts))
        faces = kept
        if not faces:
            return None
        loop = _order_loop(cuts, pl.n)
        if len(loop) >= 3 and area3(loop) > AREA_EPS * 1e-3:
            faces.append(Face(k, loop))
    c = Cell(all_planes, faces, mat, color)
    if c.volume() < VOL_EPS:
        return None
    # a piece thinner than THIN across any of its faces is a cut's rounding,
    # not a solid, however long it is
    vs = c.vset()
    for f in c.faces:
        pl = all_planes[f.plane]
        if max(pl.d - (pl.n[0] * p[0] + pl.n[1] * p[1] + pl.n[2] * p[2]) for p in vs) < THIN:
            return None
    for f in c.faces:
        if all_planes[f.plane].role == "unbounded":
            raise Unbounded("a cell is open to infinity")
    used = sorted({f.plane for f in c.faces})
    remap = {old: i for i, old in enumerate(used)}
    c.planes = [all_planes[i] for i in used]
    for f in c.faces:
        f.plane = remap[f.plane]
    return c


def cell(planes: list, mat: str = "", color=(1.0, 1.0, 1.0)) -> Cell | None:
    return make_cell(planes, mat, color)


def separated(a: Cell, b: Cell) -> bool:
    """Whether a face plane of one leaves the other wholly outside (so the
    two touch at most)."""
    va, vb = a.vset(), b.vset()
    for pl in a.planes:
        if all(pl.side(p) >= -1e-6 for p in vb):
            return True
    for pl in b.planes:
        if all(pl.side(p) >= -1e-6 for p in va):
            return True
    return False


def boxes_apart(a: Cell, b: Cell, gap: float = 1e-6) -> bool:
    lo_a, hi_a = a.aabb()
    lo_b, hi_b = b.aabb()
    for k in range(3):
        if hi_a[k] < lo_b[k] + gap or hi_b[k] < lo_a[k] + gap:
            return True
    return False


def overlap(a: Cell, b: Cell) -> Cell | None:
    """The solid two cells share, or None when they only touch."""
    if boxes_apart(a, b) or separated(a, b):
        return None
    return make_cell(a.planes + b.planes, a.mat, a.color, start=a)


def subtract(a: Cell, b: Cell, role: str | None = None) -> list[Cell]:
    """a less b, as convex pieces. The faces cut along b keep b's roles
    (or take `role`)."""
    if overlap(a, b) is None:
        return [a]
    out = []
    cur: Cell | None = a
    for pl in b.planes:
        if cur is None:
            break
        if all(pl.side(p) <= 1e-9 for p in cur.vset()):
            continue
        piece = cur.with_planes([pl.flipped(role)])
        if piece is not None:
            out.append(piece)
        cur = cur.with_planes([pl])
    return out


def subtract_all(pieces: list[Cell], cutters: list[Cell], role: str | None = None) -> list[Cell]:
    for c in cutters:
        nxt = []
        for p in pieces:
            nxt.extend(subtract(p, c, role))
        pieces = nxt
    return pieces


def clip_all(pieces: list[Cell], planes: list[Plane]) -> list[Cell]:
    out = []
    for p in pieces:
        q = p.with_planes(planes)
        if q is not None:
            out.append(q)
    return out


# ---- convex plan polygons ---------------------------------------------------

def poly_area(p) -> float:
    s = 0.0
    for i in range(len(p)):
        a, b = p[i], p[(i + 1) % len(p)]
        s += a[0] * b[1] - b[0] * a[1]
    return s / 2.0


def ccw(p) -> list:
    p = [(float(q[0]), float(q[1])) for q in p]
    return p if poly_area(p) > 0 else p[::-1]


def is_convex(p, tol: float = 1e-9) -> bool:
    p = ccw(p)
    for i in range(len(p)):
        a, b, c = p[i - 1], p[i], p[(i + 1) % len(p)]
        cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if cr < -tol:
            return False
    return True


def clip_poly(p, a, b) -> list:
    """The part of a plan polygon left of the line a -> b."""
    out = []

    def s(q):
        return (b[0] - a[0]) * (q[1] - a[1]) - (b[1] - a[1]) * (q[0] - a[0])

    n = len(p)
    for i in range(n):
        u, v = p[i], p[(i + 1) % n]
        su, sv = s(u), s(v)
        if su >= -1e-12:
            out.append(u)
        if (su < -1e-12 < sv) or (sv < -1e-12 < su):
            t = su / (su - sv)
            out.append((u[0] + (v[0] - u[0]) * t, u[1] + (v[1] - u[1]) * t))
    return out


def poly_meet(p, q) -> list:
    """Convex p within convex q (both anticlockwise)."""
    out = list(p)
    for i in range(len(q)):
        a, b = q[i], q[(i + 1) % len(q)]
        if abs(a[0] - b[0]) + abs(a[1] - b[1]) < 1e-12:
            continue
        out = clip_poly(out, a, b)
        if len(out) < 3:
            return []
    return out if abs(poly_area(out)) > AREA_EPS else []


def poly_less(p, q) -> list[list]:
    """Convex p less convex q, as convex pieces."""
    if not poly_meet(p, q):
        return [list(p)]
    out = []
    cur = list(p)
    for i in range(len(q)):
        a, b = q[i], q[(i + 1) % len(q)]
        if abs(a[0] - b[0]) + abs(a[1] - b[1]) < 1e-12:
            continue
        piece = clip_poly(cur, b, a)
        if len(piece) >= 3 and abs(poly_area(piece)) > AREA_EPS:
            out.append(piece)
        cur = clip_poly(cur, a, b)
        if len(cur) < 3:
            break
    return out


def line_hit(p0, t0, p1, t1):
    """Where the plan lines p0 + s t0 and p1 + s t1 cross, or None."""
    det = t0[0] * (-t1[1]) - (-t1[0]) * t0[1]
    if abs(det) < 1e-12:
        return None
    rx, rz = p1[0] - p0[0], p1[1] - p0[1]
    s = (rx * (-t1[1]) - (-t1[0]) * rz) / det
    return (p0[0] + t0[0] * s, p0[1] + t0[1] * s)


def offset_poly(p, d) -> list:
    """An anticlockwise polygon with edge i moved outward by d[i] (or d
    for all), corners mitred."""
    p = ccw(p)
    n = len(p)
    ds = [float(d)] * n if isinstance(d, (int, float)) else [float(x) for x in d]
    lines = []
    for i in range(n):
        a, b = p[i], p[(i + 1) % n]
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        t = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
        o = (t[1], -t[0])
        lines.append(((a[0] + o[0] * ds[i], a[1] + o[1] * ds[i]), t))
    res = []
    for i in range(n):
        (q0, t0), (q1, t1) = lines[i - 1], lines[i]
        h = line_hit(q0, t0, q1, t1)
        res.append(q1 if h is None else h)
    return res
