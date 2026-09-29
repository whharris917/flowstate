"""A building generated from architectural parameters.

The building file gives what an architect would: the plan of every level
(spaces tiling it), floor heights, wall thicknesses, and for each roof its
footprint, plate heights, pitches and overhangs; dormers by their host
roof, position and size; porches by the space they cover; openings by the
wall they are in, their width, sill and head; chimneys by plan position,
base and top. Everything else is derived, as convex cells (solid.py):

- walls stand on the outline of each level's enclosed spaces, on the outer
  face, inset by their thickness, mitred at corners; partitions on the
  lines rooms share. Each rises from its floor to whatever is over it:
  the floor above, else the underside of the highest roof whose
  footprint it stands inside. Nothing gives a wall a height.
- floors fill each level's outline between the walls' faces; where no
  level lies below, the floor is a plinth down to the foundation.
- a roof's surface is, over its footprint, the lowest of the planes its
  eaves define (each through its eave line at the plate, rising inward at
  its pitch): ridges, hips and the deck's edges are where planes meet. A
  gable edge makes no plane: the wall under it rises to the rakes. The
  covering is the surface less a thickness, over the footprint grown by
  the overhangs; its ends are the fascia and the bargeboards.
- where roofs overlap, the higher is the roof within its footprint and a
  lower roof's covering stops at the vertical through their meeting
  (valleys and abutments meet exactly); a roof over rooms runs on under
  another's overhang, an overhang yields to a roof it would dip into.
- a roof edge standing over another roof carries a wall (a dormer's
  cheek, a gable's end over a lower roof) from the lower roof's
  underside to its own.
- openings are cut from their host wall; frames, glass, doors, casings,
  sills and hoods are fitted to the cut.
- chimneys pass through floors, walls and roofs, which yield to them.

Parameters are checked as they are read (GenError): a roof over a
footprint that is not convex (unless it is a single plane), a pitch out of
range, an overhang too deep, a dormer taller than its host, an opening on
no wall. Where one part yields to another the pair is recorded as a
designed joint (`Model.joints`); validate.py checks the result.

Coordinates: feet, plan (x, z) as the building file's frame, y up from
the building's datum.
"""
from __future__ import annotations

import json
import math
import os
from dataclasses import dataclass, field

import model as M                 # grid names and polygon shorthands
import plan as P
from solid import (Cell, Plane, cell, make_cell, subtract, subtract_all, overlap, clip_all,
                   vertical, floor_at, ceiling_at, below_y, above_y, prism_planes,
                   ccw, is_convex, poly_area, poly_less, poly_meet, offset_poly, boxes_apart, prism_roles)

LO, HI = -500.0, 1000.0          # the far floor and sky every open column stops at

PITCH_MAX = 30.0                  # rise per foot (a spire's steepest face)
OVERHANG_MAX = 8.0


class GenError(ValueError):
    pass


@dataclass
class Element:
    id: str
    kind: str                      # wall, partition, cheek, slab, plinth, roof, chimney,
                                   # frame, glass, door, casing, sill, hood, post, rail,
                                   # baluster, skirt, step, bracket
    cells: list
    mat: str = ""
    info: dict = field(default_factory=dict)


@dataclass
class Run:
    """A straight wall: its outer face (a partition's centre) from a to b,
    the inside to its left; thickness; the element holding it."""
    a: tuple
    b: tuple
    thick: float
    element: str
    kind: str                      # wall, partition, cheek
    level: str = ""
    centred: bool = False

    @property
    def length(self) -> float:
        return math.dist(self.a, self.b)

    @property
    def dir(self) -> tuple:
        L = self.length
        return ((self.b[0] - self.a[0]) / L, (self.b[1] - self.a[1]) / L)

    @property
    def out(self) -> tuple:
        d = self.dir
        return (d[1], -d[0])

    def s_range(self) -> tuple:
        return (-self.thick / 2.0, self.thick / 2.0) if self.centred else (-self.thick, 0.0)

    def plan(self, u: float, s: float) -> tuple:
        d, o = self.dir, self.out
        return (self.a[0] + d[0] * u + o[0] * s, self.a[1] + d[1] * u + o[1] * s)

    def uv(self, p) -> tuple:
        d, o = self.dir, self.out
        dx, dz = p[0] - self.a[0], p[1] - self.a[1]
        return (dx * d[0] + dz * d[1], dx * o[0] + dz * o[1])


def run_cell(run: Run, prof: list, s0: float, s1: float, mat: str = "", color=(1, 1, 1),
             roles: tuple = ("side", "back", "face"), edge_roles: list | None = None) -> Cell | None:
    """A prism in a wall's frame: a convex anticlockwise profile in (u, y)
    extruded across the wall from s0 (inward) to s1 (outward). The
    profile's edges take roles[0], or edge_roles[i] each."""
    d, o = run.dir, run.out
    planes = []
    n = len(prof)
    for i in range(n):
        (ua, ya), (ub, yb) = prof[i], prof[(i + 1) % n]
        du, dy = ub - ua, yb - ya
        # outward normal of a ccw profile edge in (u, y): (dy, -du)
        nu, ny = dy, -du
        nrm = (d[0] * nu, ny, d[1] * nu)
        pa = run.plan(ua, 0.0)
        planes.append(Plane.through(nrm, (pa[0], ya, pa[1]), edge_roles[i] if edge_roles else roles[0]))
    pa = run.plan(0.0, s1)
    planes.append(Plane.through((o[0], 0.0, o[1]), (pa[0], 0.0, pa[1]), roles[2]))
    pb = run.plan(0.0, s0)
    planes.append(Plane.through((-o[0], 0.0, -o[1]), (pb[0], 0.0, pb[1]), roles[1]))
    return cell(planes, mat, color)


def rect(u0, u1, y0, y1) -> list:
    return [(u0, y0), (u1, y0), (u1, y1), (u0, y1)]


def disjoint(cells: list) -> list:
    out: list = []
    for c in cells:
        out.extend(subtract_all([c], out))
    return out


def prism(poly, y0=LO, y1=HI, role="side", mat="", color=(1, 1, 1)) -> Cell | None:
    return cell(prism_planes(ccw(poly), y0, y1, role, "bottom", "top"), mat, color)


def contains(c: Cell, p, tol: float = 1e-6) -> bool:
    return all(pl.side(p) <= tol for pl in c.planes)


# ---- roofs ------------------------------------------------------------------

@dataclass
class Roof:
    id: str
    spec: dict
    footprint: list                # anticlockwise
    parts: list                    # convex pieces of the footprint
    edges: list                    # per footprint edge: {kind, plate, pitch, over}
    extent: list                   # footprint grown by the overhangs
    extent_parts: list
    planes: list                   # (a, b, c, edge index or -1 for the deck)
    t: float                       # the covering's depth, measured vertically
    cover: str
    order: int
    infield: list = field(default_factory=list)    # covering cells over the footprint
    eave: list = field(default_factory=list)       # covering cells over the overhangs
    under: list = field(default_factory=list)      # below the covering, within the footprint
    solid: list = field(default_factory=list)      # below the surface, within the footprint

    def top(self, x: float, z: float) -> float:
        return min(a * x + b * z + c for a, b, c, _ in self.planes)

    def peak(self) -> float:
        return max(self.top(*q) for q in self._corners())

    def _corners(self) -> list:
        # the surface's highest point is at a vertex of the plan cells
        pts = list(self.footprint)
        for i in range(len(self.planes)):
            for j in range(i + 1, len(self.planes)):
                for k in range(j + 1, len(self.planes)):
                    a = self.planes[i]
                    b = self.planes[j]
                    c = self.planes[k]
                    # solve a.x = b.x = c.x in plan
                    m11, m12 = a[0] - b[0], a[1] - b[1]
                    m21, m22 = a[0] - c[0], a[1] - c[1]
                    det = m11 * m22 - m12 * m21
                    if abs(det) < 1e-12:
                        continue
                    r1, r2 = b[2] - a[2], c[2] - a[2]
                    x = (r1 * m22 - m12 * r2) / det
                    z = (m11 * r2 - r1 * m21) / det
                    if any(P.point_in((x, z), q) or P.seg_dist((x, z), q[0], q[1]) < 1e-6 for q in self.parts):
                        pts.append((x, z))
        return pts


def _edge_plane(a, b, plate: float, pitch: float):
    """y = plate + pitch * (distance inward from the line a -> b)."""
    L = math.dist(a, b)
    tx, tz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
    mx, mz = -tz, tx                       # left of travel: inward
    return (pitch * mx, pitch * mz, plate - pitch * (mx * a[0] + mz * a[1]))


def _same_plane(p, q) -> bool:
    return abs(p[0] - q[0]) < 1e-9 and abs(p[1] - q[1]) < 1e-9 and abs(p[2] - q[2]) < 1e-6


# ---- the model --------------------------------------------------------------

class Model:
    def __init__(self, data: dict):
        self.data = data
        self.name = data.get("name", "building")
        M.GRID["x"] = dict(data.get("grid", {}).get("x", {}))
        M.GRID["z"] = dict(data.get("grid", {}).get("z", {}))
        d = data.get("defaults", {})
        self.WALL = float(d.get("wall", 1.0))
        self.PART = float(d.get("partition", 0.5))
        self.SLAB = float(d.get("slab", 1.0))
        self.ROOF_T = float(d.get("roof_depth", 0.6))
        self.FOUNDATION = float(data.get("site", {}).get("foundation", -10.0))
        self.levels = {lv["id"]: lv for lv in data.get("levels", [])}
        self.groups = {g["id"]: dict(g, order=i) for i, g in enumerate(data.get("groups", []))}
        self.elements: dict[str, Element] = {}
        self.joints: set = set()              # (a, b): a yields to b by design
        self.runs: list[Run] = []
        self.roofs: dict[str, Roof] = {}
        self.notes: list[str] = []            # what the generator could not honour
        self.slab_plan: list = []             # (convex poly, bottom, top, level)
        self.outlines: dict = {}              # level -> [segments {a, b, on, group}]
        self.openings: list = []
        self._read_spaces()

    # ---- reading --------------------------------------------------------

    def y(self, v) -> float:
        if isinstance(v, str):
            if v not in self.levels:
                raise GenError("no level named %r" % v)
            return float(self.levels[v]["floor"])
        return float(v)

    def _poly(self, spec) -> list:
        if isinstance(spec, dict) and "space" in spec:
            if spec["space"] not in self.space:
                raise GenError("no space named %r" % spec["space"])
            return list(self.space[spec["space"]]["poly"])
        return P.simplify(ccw(M.expand_poly(spec)))

    def _read_spaces(self) -> None:
        self.spaces = []
        self.space = {}
        for s in self.data.get("spaces", []):
            s = dict(s)
            s["poly"] = P.simplify(ccw(M.expand_poly(s["poly"])))
            if s["level"] not in self.levels:
                raise GenError("space %s is on no level (%r)" % (s["id"], s["level"]))
            s["floor"] = float(s.get("floor", self.levels[s["level"]]["floor"]))
            s["open"] = s["kind"] in ("porch", "balcony", "deck", "canopy")
            self.spaces.append(s)
            self.space[s["id"]] = s

    def add(self, eid: str, kind: str, cells: list, mat: str = "", **info) -> Element:
        cells = [c for c in cells if c is not None]
        if eid in self.elements:
            e = self.elements[eid]
            e.cells.extend(cells)
            return e
        e = Element(eid, kind, cells, mat, info)
        self.elements[eid] = e
        return e

    def yield_to(self, eid: str, cutters: list, host: str, role: str | None = None) -> None:
        """Element eid gives way to cells of host: a designed joint."""
        e = self.elements.get(eid)
        if e is None or not cutters:
            return
        before = len(e.cells)
        vol0 = sum(c.volume() for c in e.cells)
        cut = subtract_all(e.cells, cutters, role)
        if abs(sum(c.volume() for c in cut) - vol0) > 1e-5 or len(cut) != before:
            self.joints.add((eid, host))
        e.cells = cut

    # ---- generation -----------------------------------------------------

    def generate(self) -> "Model":
        self._roofs()
        self._compose_roofs()
        self._covering_elements()
        self._outlines()
        self._slabs()
        self._walls()
        self._partitions()
        self._cheeks()
        self._chimneys()
        self._openings()
        self._porches()
        self._brackets()
        return self

    # ---- roofs --------------------------------------------------------------

    def _roofs(self) -> None:
        specs = list(self.data.get("roofs", []))
        # dormers first get their footprints from their hosts
        for order, spec in enumerate(specs):
            rid = spec["id"]
            if "dormer" in spec:
                fp, edges = self._dormer_footprint(spec)
            else:
                fp = self._poly(spec["footprint"])
                edges = self._edge_specs(spec, fp)
            self.roofs[rid] = self._make_roof(rid, spec, fp, edges, order)

    def _edge_specs(self, spec: dict, fp: list) -> list:
        """Per footprint edge: {kind: eave | gable | abut, plate, pitch, over}.
        `sides` names a rectangle's sides x0, x1, z0, z1 (the edges on
        those lines); `edges` gives them by index; `at` finds an edge by a
        point on it."""
        base = {
            "kind": spec.get("edge", "eave"),
            "plate": spec.get("plate"),
            "pitch": spec.get("pitch"),
            "over": spec.get("overhang", 0.0),
            "rake": spec.get("rake", spec.get("overhang", 0.0)),
        }
        out = [dict(base) for _ in fp]
        xs = [q[0] for q in fp]
        zs = [q[1] for q in fp]
        bounds = {"x0": min(xs), "x1": max(xs), "z0": min(zs), "z1": max(zs)}
        for name, e in spec.get("sides", {}).items():
            hit = False
            for i in range(len(fp)):
                a, b = fp[i], fp[(i + 1) % len(fp)]
                ax = 0 if name[0] == "x" else 1
                if abs(a[ax] - bounds[name]) < 1e-6 and abs(b[ax] - bounds[name]) < 1e-6:
                    out[i].update(e)
                    hit = True
            if not hit:
                raise GenError("roof %s: no edge on side %s" % (spec["id"], name))
        for key, e in spec.get("edges", {}).items():
            out[int(key)].update(e)
        for e in spec.get("edges_at", []):
            p = M.expand_point(e["at"])
            best = min(range(len(fp)), key=lambda i: P.seg_dist(p, fp[i], fp[(i + 1) % len(fp)]))
            if P.seg_dist(p, fp[best], fp[(best + 1) % len(fp)]) > 0.5:
                raise GenError("roof %s: no edge at %s" % (spec["id"], e["at"]))
            out[best].update({k: v for k, v in e.items() if k != "at"})
        return out

    def _make_roof(self, rid: str, spec: dict, fp: list, edges: list, order: int) -> Roof:
        fp = ccw(fp)
        planes = []
        overs = []
        for i, e in enumerate(edges):
            kind = e["kind"]
            if kind not in ("eave", "gable", "abut"):
                raise GenError("roof %s edge %d: kind %r" % (rid, i, kind))
            if kind == "eave":
                if e.get("plate") is None or e.get("pitch") is None:
                    raise GenError("roof %s edge %d: an eave needs a plate and a pitch" % (rid, i))
                pitch = float(e["pitch"])
                if not (0.0 <= pitch <= PITCH_MAX):
                    raise GenError("roof %s edge %d: pitch %.2f out of range" % (rid, i, pitch))
                pl = _edge_plane(fp[i], fp[(i + 1) % len(fp)], self.y(e["plate"]), pitch)
                if not any(_same_plane(pl, q) for q in planes):
                    planes.append(pl + (i,))
                over = float(e["over"])
            elif kind == "gable":
                over = float(e.get("rake", e["over"]))
            else:
                over = 0.0
            if not (0.0 <= over <= OVERHANG_MAX):
                raise GenError("roof %s edge %d: overhang %.2f out of range" % (rid, i, over))
            overs.append(over)
        if "deck" in spec:
            planes.append((0.0, 0.0, float(spec["deck"]), -1))
        if not planes:
            raise GenError("roof %s has no eave: nothing makes its surface" % rid)
        single = len(planes) == 1
        if not single and not is_convex(fp):
            raise GenError("roof %s: a roof of several planes needs a convex footprint "
                           "(compose it from convex roofs)" % rid)
        parts = [fp] if is_convex(fp) else P.convex_parts(fp)
        extent = offset_poly(fp, overs)
        if not is_convex(extent) and not single:
            raise GenError("roof %s: its overhangs make its outline concave" % rid)
        extent_parts = [extent] if is_convex(extent) else P.convex_parts(extent)
        r = Roof(rid, spec, fp, parts, edges, extent, extent_parts, planes,
                 float(spec.get("depth", self.ROOF_T)), spec.get("cover", "slate"), order)
        # the surface must close over the footprint
        for q in r.footprint:
            for (a, b, c, _) in planes:
                pass
        try:
            r.under = self._under(r)
        except Exception as ex:          # an open surface
            raise GenError("roof %s: its planes do not close over its footprint (%s)" % (rid, ex))
        pk = r.peak()
        for i, e in enumerate(edges):
            if e["kind"] == "eave" and pk < self.y(e["plate"]) - 1e-6:
                raise GenError("roof %s: peak under its plate" % rid)
        return r

    def _under(self, r: Roof) -> list:
        out, sol = [], []
        for part in r.parts:
            base = prism_planes(part, LO, None, "wallline")
            under = [below_y(a, b, c - r.t, "underside") for a, b, c, _ in r.planes]
            top = [below_y(a, b, c, "slope") for a, b, c, _ in r.planes]
            u = cell(base + under)
            s = cell(base + top)
            if u is not None:
                out.append(u)
            if s is not None:
                sol.append(s)
        r.solid = sol
        return out

    def _dormer_footprint(self, spec: dict):
        dm = spec["dormer"]
        host = self.roofs.get(dm["host"])
        if host is None:
            raise GenError("dormer %s: host roof %r must come before it" % (spec["id"], dm["host"]))
        # the host edge it stands on
        side = dm["side"]
        fp = host.footprint
        if isinstance(side, str):
            xs = [q[0] for q in fp]
            zs = [q[1] for q in fp]
            bounds = {"x0": min(xs), "x1": max(xs), "z0": min(zs), "z1": max(zs)}
            ax = 0 if side[0] == "x" else 1
            idx = [i for i in range(len(fp)) if abs(fp[i][ax] - bounds[side]) < 1e-6
                   and abs(fp[(i + 1) % len(fp)][ax] - bounds[side]) < 1e-6]
            if not idx:
                raise GenError("dormer %s: host %s has no side %s" % (spec["id"], host.id, side))
            i = idx[0]
        else:
            i = int(side)
        he = host.edges[i]
        if he["kind"] != "eave":
            raise GenError("dormer %s: host edge is not an eave" % spec["id"])
        a, b = fp[i], fp[(i + 1) % len(fp)]
        L = math.dist(a, b)
        t = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
        m = (-t[1], t[0])                                  # inward
        c = float(M.gx(dm["center"])) if side in ("z0", "z1") else float(M.gz(dm["center"])) \
            if side in ("x0", "x1") else float(dm["center"])
        # along-edge coordinate of the centre
        if isinstance(side, str):
            u = (c - (a[0] if side[0] == "z" else a[1])) / (t[0] if side[0] == "z" else t[1])
        else:
            u = c
        w = float(dm["width"])
        setback = float(dm.get("setback", 0.0))
        plate = self.y(spec["plate"])
        pitch = float(spec["pitch"])
        ridge = plate + pitch * w / 2.0
        hp, hpitch = self.y(he["plate"]), float(he["pitch"])
        if hpitch <= 0:
            raise GenError("dormer %s: its host slope is flat" % spec["id"])
        if ridge >= host.peak():
            raise GenError("dormer %s: its ridge (%.2f) stands above its host's (%.2f)" % (spec["id"], ridge, host.peak()))
        reach = (ridge - hp) / hpitch                      # where its ridge dies into the host
        depth = float(dm.get("depth", reach - setback + 1.0))
        if depth <= 0.5:
            raise GenError("dormer %s: no depth (its ridge is under the host's eave)" % spec["id"])
        if u - w / 2.0 < 0 or u + w / 2.0 > L:
            raise GenError("dormer %s: wider than its host's edge allows" % spec["id"])
        p0 = (a[0] + t[0] * (u - w / 2.0) + m[0] * setback, a[1] + t[1] * (u - w / 2.0) + m[1] * setback)
        p1 = (a[0] + t[0] * (u + w / 2.0) + m[0] * setback, a[1] + t[1] * (u + w / 2.0) + m[1] * setback)
        p2 = (p1[0] + m[0] * depth, p1[1] + m[1] * depth)
        p3 = (p0[0] + m[0] * depth, p0[1] + m[1] * depth)
        fpd = [p0, p1, p2, p3]
        over = float(spec.get("overhang", 0.5))
        rake = float(spec.get("rake", over))
        edges = [
            {"kind": "gable", "over": rake, "rake": rake},          # front
            {"kind": "eave", "plate": plate, "pitch": pitch, "over": over},
            {"kind": "gable", "over": 0.0, "rake": 0.0},             # back, inside the host
            {"kind": "eave", "plate": plate, "pitch": pitch, "over": over},
        ]
        spec.setdefault("host", dm["host"])
        return fpd, edges

    def _higher(self, B: Roof, pl, A: Roof, within: list, above: float | None = None) -> list:
        """Where roof B's surface stands above plane pl of roof A, within
        the plan polygons `within` (B's footprint or extent parts), as
        vertical prisms. Ties go to the roof listed first."""
        out = []
        extra = []
        for (a, b, c, _) in B.planes:
            # pl - B_j < 0 : (pa - a) x + (pb - b) z < c - pc
            nx, nz = pl[0] - a, pl[1] - b
            rhs = c - pl[2]
            if abs(nx) < 1e-12 and abs(nz) < 1e-12:
                if rhs > 1e-6:
                    continue
                if rhs < -1e-6:
                    return []
                if B.order < A.order:
                    continue
                return []
            extra.append(Plane.of((nx, 0.0, nz), rhs, "meet"))
        if above is not None:
            # and only where plane pl stands above the height `above`
            if abs(pl[0]) < 1e-12 and abs(pl[1]) < 1e-12:
                if pl[2] <= above:
                    return []
            else:
                extra.append(Plane.of((-pl[0], 0.0, -pl[1]), pl[2] - above, "meet"))
        for poly in within:
            c_ = cell(prism_planes(poly, LO, HI, "meet") + extra)
            if c_ is not None:
                out.append(c_)
        return out

    def _compose_roofs(self) -> None:
        roofs = list(self.roofs.values())
        for A in roofs:
            fields, eaves = [], []
            for i, pl in enumerate(A.planes):
                a, b, c, ei = pl
                others = [Plane.of((a - q[0], 0.0, b - q[1]), q[2] - c, "hip") for q in A.planes if q is not pl
                          and not (abs(a - q[0]) < 1e-12 and abs(b - q[1]) < 1e-12)]
                top = below_y(a, b, c, "deck" if ei < 0 else "slope")
                bot = above_y(a, b, c - A.t, "underside")
                for part in A.extent_parts:
                    ends = self._extent_planes(A, part)
                    cc = cell(ends + others + [top, bot], A.id, (1, 1, 1))
                    if cc is None:
                        continue
                    cc.plane = i
                    fp_cells = [cell(prism_planes(fpp, LO, HI, "wallline")) for fpp in A.parts]
                    inside = []
                    for f in fp_cells:
                        x = overlap(cc, f)
                        if x is not None:
                            x.plane = i
                            inside.append(x)
                    outside = subtract_all([cc], fp_cells)
                    for x in outside:
                        x.plane = i
                    fields.extend(inside)
                    eaves.extend(outside)
            A.infield, A.eave = fields, eaves
        # meetings
        for A in roofs:
            nf, ne = [], []
            for c_ in A.infield:
                pl = A.planes[c_.plane]
                cut = [c_]
                for B in roofs:
                    if B is A or boxes_apart(c_, self._bbox_cell(B)):
                        continue
                    hi = self._higher(B, pl, A, B.parts)
                    if hi:
                        n0 = len(cut)
                        cut = subtract_all(cut, hi, "meet")
                        self.joints.add(("roof:" + A.id, "roof:" + B.id))
                for x in cut:
                    x.plane = c_.plane
                nf.extend(cut)
            for c_ in A.eave:
                pl = A.planes[c_.plane]
                cut = [c_]
                for B in roofs:
                    if B is A or boxes_apart(c_, self._bbox_cell(B)):
                        continue
                    # an eave meets an eave where they cross; one far below the
                    # other's lowest edge runs on under it
                    lowest = min(B.top(*q) for q in B.extent) - B.t
                    hi = self._higher(B, pl, A, B.extent_parts, above=lowest)
                    if hi:
                        cut = subtract_all(cut, hi, "meet")
                    cut = subtract_all(cut, B.solid, "meet")
                    self.joints.add(("roof:" + A.id, "roof:" + B.id))
                for x in cut:
                    x.plane = c_.plane
                ne.extend(cut)
            A.infield, A.eave = nf, ne
        # holes
        for A in roofs:
            holes = [self._poly(h) for h in A.spec.get("holes", [])]
            for h in holes:
                cutters = [prism(q, LO, HI, "hole") for q in P.convex_parts(h)]
                A.infield = self._keep_plane(subtract_all, A.infield, cutters, "hole")
                A.eave = self._keep_plane(subtract_all, A.eave, cutters, "hole")
                A.under = subtract_all(A.under, cutters)

    def _keep_plane(self, fn, cells, cutters, role):
        out = []
        for c_ in cells:
            for x in fn([c_], cutters, role):
                x.plane = c_.plane
                out.append(x)
        return out

    def _bbox_cell(self, B: Roof) -> Cell:
        if not hasattr(B, "_bb"):
            xs = [q[0] for q in B.extent]
            zs = [q[1] for q in B.extent]
            B._bb = cell(prism_planes([(min(xs), min(zs)), (max(xs), min(zs)), (max(xs), max(zs)), (min(xs), max(zs))], LO, HI))
        return B._bb

    def _extent_planes(self, A: Roof, part: list) -> list:
        """The vertical faces of a covering's outline: an eave's fascia or a
        gable's bargeboard where the outline follows the roof's own edge,
        a seam elsewhere."""
        out = []
        n = len(A.footprint)
        for k in range(len(part)):
            a, b = part[k], part[(k + 1) % len(part)]
            role = "seam"
            for i in range(n):
                # the grown edge i runs parallel to footprint edge i
                ga, gb = A.extent[i], A.extent[(i + 1) % n]
                if P.seg_dist(a, ga, gb) < 1e-4 and P.seg_dist(b, ga, gb) < 1e-4:
                    kind = A.edges[i]["kind"]
                    role = "fascia" if kind == "eave" else "rake" if kind == "gable" else "abut"
            out.append(vertical(a, b, role))
        return out

    def enclosed_at(self, x: float, z: float, below: float) -> bool:
        """Whether an enclosed space lies at a plan point under a height."""
        for s in self.spaces:
            if not s["open"] and s["floor"] < below and P.point_in((x, z), s["poly"]):
                return True
        return False

    def _covering_elements(self) -> None:
        for A in self.roofs.values():
            self.add("roof:" + A.id, "roof", A.infield + A.eave, A.cover,
                     footprint=A.footprint, host=A.spec.get("host"))

    # ---- outlines, floors ---------------------------------------------------

    def _outlines(self) -> None:
        """Each level's walls: where an enclosed space meets the outside, an
        open space or a part of the building listed later."""
        for lv in self.levels:
            enclosed = {s["id"]: s["poly"] for s in self.spaces if s["level"] == lv and not s["open"]}
            if not enclosed:
                continue
            parts = P.edge_parts(enclosed)
            segs = []
            for e in parts:
                s = self.space[e["of"]]
                g = self.groups.get(s.get("group"), {"order": 99, "wall": self.WALL})
                o = self.space.get(e["other"]) if e["other"] else None
                if o is None:
                    on = True
                elif o.get("group") == s.get("group"):
                    on = None                     # a partition
                else:
                    go = self.groups.get(o.get("group"), {"order": 99})
                    on = g["order"] < go["order"]
                segs.append(dict(e, on=on, group=s.get("group"), level=lv))
            self.outlines[lv] = segs

    def _group_loops(self, lv: str, group: str) -> list:
        """The group's region at a level as loops of segments (inside on
        the left), with runs of collinear segments of the same kind merged."""
        segs = [s for s in self.outlines.get(lv, []) if s["group"] == group and s["on"] is not None]
        loops = P.chain(segs)
        out = []
        for loop in loops:
            merged = []
            for s in loop:
                if merged:
                    m = merged[-1]
                    if m["on"] == s["on"] and self._collinear(m, s) and m.get("mat") == s.get("mat"):
                        m["b"] = s["b"]
                        continue
                merged.append(dict(s))
            if len(merged) > 1 and merged[0]["on"] == merged[-1]["on"] and self._collinear(merged[-1], merged[0]):
                merged[0]["a"] = merged[-1]["a"]
                merged.pop()
            out.append(merged)
        return out

    @staticmethod
    def _collinear(s, t) -> bool:
        a, b, c = s["a"], s["b"], t["b"]
        cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        dt = (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1])
        return abs(cr) < 1e-6 * max(1.0, math.dist(a, c)) ** 2 and dt > 0

    def _level_region(self, lv: str) -> list:
        """The level's enclosed spaces as convex plan pieces."""
        out = []
        for s in self.spaces:
            if s["level"] == lv and not s["open"]:
                out.extend(P.convex_parts(s["poly"]))
        return out

    def grade(self, x: float, z: float) -> float:
        site = self.data.get("site", {})
        pts = site.get("grade_points", [])
        g0 = float(site.get("grade", -2.0))
        if not pts:
            return g0
        s = w = 0.0
        for px, pz, py in pts:
            d2 = (x - px) ** 2 + (z - pz) ** 2
            wt = 1.0 / (d2 + 4.0)
            s += wt * py
            w += wt
        return s / w

    def _slabs(self) -> None:
        lv_sorted = sorted(self.levels, key=lambda k: self.y(k))
        for lv in lv_sorted:
            f = self.y(lv)
            below = [q for l2 in lv_sorted if self.y(l2) < f - 0.5 for q in self._level_region(l2)]
            for s in self.spaces:
                if s["level"] != lv or s["kind"] == "canopy":
                    continue
                fl = s["floor"]
                t = float(s.get("slab", self.SLAB))
                for part in P.convex_parts(s["poly"]):
                    pieces = [part]
                    ground = []
                    if not s["open"]:
                        for q in below:
                            nxt = []
                            for p in pieces:
                                nxt.extend(poly_less(p, q))
                            pieces = nxt
                        # a floor over no level below that stands near the ground
                        # is a plinth down to the foundation
                        for p in pieces:
                            cx = sum(q[0] for q in p) / len(p)
                            cz = sum(q[1] for q in p) / len(p)
                            if fl - self.grade(cx, cz) < 6.0:
                                ground.append(p)
                    cells = []
                    for p in pieces:
                        bottom = self.FOUNDATION if p in ground else fl - t
                        c_ = cell(prism_planes(ccw(p), bottom, fl, "slab_edge",
                                               "footing" if p in ground else "bottom", "top"), "floor")
                        cells.append(c_)
                    covered = [prism(p, fl - t, fl) for p in (poly_less_all(part, pieces))]
                    cells.extend(covered)
                    cells = [c for c in cells if c is not None]
                    if not s["open"]:
                        cells = self._under_roofs(cells, keep_uncovered=True)
                    kind = "plinth" if ground else "slab"
                    self.add("floor:" + s["id"], "slab", cells, "floor", level=lv, space=s["id"])
                    self.slab_plan.append((part, fl - t, fl, lv, s["id"]))

    def _under_roofs(self, cells: list, keep_uncovered: bool) -> list:
        """Cells cut to the underside of the highest roof over them; parts
        under no roof's footprint kept or dropped."""
        out = []
        for c_ in cells:
            parts = []
            for R in self.roofs.values():
                for u in R.under:
                    x = overlap(c_, u)
                    if x is not None:
                        parts.append(x)
            parts = disjoint(parts)
            out.extend(parts)
            if keep_uncovered:
                cov = [prism(q) for R in self.roofs.values() for q in R.parts]
                out.extend(subtract_all([c_], [q for q in cov if q is not None]))
        return out

    def _cap(self, quad: list, y0: float, label: str, roles=None) -> list:
        """A wall's column over a plan quad from y0 to whatever is over it:
        the lowest floor above (its underside), else the highest roof's
        underside."""
        if roles is None:
            col = prism(quad, y0, HI)
        else:
            col = cell(prism_roles(quad, roles, y0, HI))
        if col is None:
            return []
        remaining = [col]
        capped = []
        for (poly, bottom, top, lv, sid) in sorted(self.slab_plan, key=lambda s: s[1]):
            if bottom <= y0 + 0.05:
                continue
            sp = prism(poly)
            nxt = []
            for r in remaining:
                x = overlap(r, sp)
                if x is not None:
                    y = x.with_planes([ceiling_at(bottom, "top")])
                    if y is not None:
                        capped.append(y)
                nxt.extend(subtract(r, sp))
            remaining = nxt
        out = self._under_roofs(capped, keep_uncovered=True)
        roofed = self._under_roofs(remaining, keep_uncovered=False)
        out.extend(roofed)
        # what is under nothing
        cov = [prism(q) for R in self.roofs.values() for q in R.parts]
        for r in remaining:
            for x in subtract_all([r], [q for q in cov if q is not None]):
                self.notes.append("%s: part of it has nothing over it (at %s)"
                                  % (label, tuple(round(v, 1) for v in x.centroid())))
                break
        return out

    # ---- walls --------------------------------------------------------------

    def _wall_mat(self, group: str, a, b, lv: str) -> str:
        for w in self.data.get("walls", []):
            if w.get("level") != lv:
                continue
            fa, fb = M.expand_point(w["from"]), M.expand_point(w["to"])
            if P.seg_dist(a, fa, fb) < 0.2 and P.seg_dist(b, fa, fb) < 0.2:
                return w.get("material", "brick")
        return self.groups.get(group, {}).get("material", "brick")

    def _walls(self) -> None:
        for lv, segs in self.outlines.items():
            groups = []
            for s in segs:
                if s["group"] not in groups:
                    groups.append(s["group"])
            for g in groups:
                gd = self.groups.get(g, {"wall": self.WALL})
                t = float(gd.get("wall", self.WALL))
                if t <= 0:
                    continue
                for loop in self._group_loops(lv, g):
                    self._loop_walls(loop, t, lv, g)

    def _loop_walls(self, loop: list, t: float, lv: str, group: str) -> None:
        n = len(loop)
        f = self.y(lv)

        def inset(s, d):
            a, b = s["a"], s["b"]
            L = math.dist(a, b)
            tx, tz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
            mx, mz = -tz, tx
            return (a[0] + mx * d, a[1] + mz * d), (tx, tz)

        for i, s in enumerate(loop):
            if not s["on"]:
                continue
            prev, nxt = loop[i - 1], loop[(i + 1) % n]
            q0, t0 = inset(s, t)
            # the inner corner at the start
            if prev["on"]:
                pq, pt = inset(prev, t)
            else:
                pq, pt = inset(prev, 0.0)
            h0 = _hit(pq, pt, q0, t0)
            nq, nt = inset(nxt, t if nxt["on"] else 0.0)
            h1 = _hit(q0, t0, nq, nt)
            if h0 is None or h1 is None:
                raise GenError("wall at level %s: corner at %s does not close" % (lv, s["a"]))
            quad = [s["a"], s["b"], h1, h0]
            if poly_area(quad) <= 1e-6 or not is_convex(quad):
                raise GenError("wall at level %s from %s to %s: shorter than its thickness allows at a corner"
                               % (lv, _r(s["a"]), _r(s["b"])))
            mat = self._wall_mat(group, s["a"], s["b"], lv)
            eid = "wall:%s:%s:%d" % (lv, group, len(self.runs))
            cells = self._cap(quad, f, eid, ("outer", "end", "inner", "end"))
            for c_ in cells:
                c_.mat = mat
            self.add(eid, "wall", cells, mat, level=lv, group=group)
            self.runs.append(Run(s["a"], s["b"], t, eid, "wall", lv))

    def _partitions(self) -> None:
        for lv, segs in self.outlines.items():
            done = set()
            for s in segs:
                if s["on"] is not None:
                    continue
                key = tuple(sorted([(round(s["a"][0], 3), round(s["a"][1], 3)), (round(s["b"][0], 3), round(s["b"][1], 3))]))
                if key in done:
                    continue
                done.add(key)
                a, b = s["a"], s["b"]
                L = math.dist(a, b)
                if L < 0.2:
                    continue
                tx, tz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
                mx, mz = -tz, tx
                h = self.PART / 2.0
                quad = [(a[0] - mx * h, a[1] - mz * h), (b[0] - mx * h, b[1] - mz * h),
                        (b[0] + mx * h, b[1] + mz * h), (a[0] + mx * h, a[1] + mz * h)]
                eid = "part:%s:%d" % (lv, len(self.runs))
                cells = self._cap(quad, self.y(lv), eid)
                for c_ in cells:
                    c_.mat = "partition"
                self.add(eid, "partition", cells, "partition", level=lv)
                # it stops at the outer walls and at partitions built before it
                for e in list(self.elements.values()):
                    if e.kind == "wall" and e.info.get("level") == lv:
                        self.yield_to(eid, e.cells, e.id)
                    elif e.kind == "partition" and e.id != eid and e.info.get("level") == lv:
                        self.yield_to(eid, e.cells, e.id)
                self.runs.append(Run(a, b, self.PART, eid, "partition", lv, centred=True))

    def _cheeks(self) -> None:
        """A roof's edge standing over another roof, where no level's wall
        rises under it, carries a wall from the lower roof's underside."""
        walls = [r for r in self.runs if r.kind == "wall"]
        for B in self.roofs.values():
            fp = B.footprint
            n = len(fp)
            mat = B.spec.get("cheek", self._host_mat(B))
            for i in range(n):
                if B.edges[i]["kind"] == "abut":
                    continue
                a, b = fp[i], fp[(i + 1) % n]
                L = math.dist(a, b)
                d = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
                # the parts of the edge no wall rises under
                covered = []
                for w in walls:
                    wd = w.dir
                    if abs(wd[0] * d[1] - wd[1] * d[0]) > 1e-6 or wd[0] * d[0] + wd[1] * d[1] < 0:
                        continue
                    if P.seg_dist(w.a, a, (a[0] + d[0], a[1] + d[1])) > 1e3:
                        pass
                    # same line?
                    off = (w.a[0] - a[0]) * (-d[1]) + (w.a[1] - a[1]) * d[0]
                    if abs(off) > 0.02:
                        continue
                    u0 = (w.a[0] - a[0]) * d[0] + (w.a[1] - a[1]) * d[1]
                    u1 = (w.b[0] - a[0]) * d[0] + (w.b[1] - a[1]) * d[1]
                    covered.append((min(u0, u1), max(u0, u1)))
                free = _free_intervals(0.0, L, covered)
                t = float(B.spec.get("cheek_wall", 0.5))
                for (u0, u1) in free:
                    if u1 - u0 < 0.05:
                        continue
                    run = Run((a[0] + d[0] * u0, a[1] + d[1] * u0), (a[0] + d[0] * u1, a[1] + d[1] * u1), t,
                              "cheek:%s:%d" % (B.id, i), "cheek")
                    quad = [run.a, run.b, run.plan(run.length, -t), run.plan(0.0, -t)]
                    col = cell(prism_roles(quad, ("outer", "end", "inner", "end"), LO, HI))
                    if col is None:
                        continue
                    tops = [x for u in B.under for x in [overlap(col, u)] if x is not None]
                    pieces = []
                    for A in self.roofs.values():
                        if A is B:
                            continue
                        for k, (pa, pb, pc, _) in enumerate(A.planes):
                            others = [Plane.of((pa - q[0], 0.0, pb - q[1]), q[2] - pc) for q in A.planes
                                      if q is not A.planes[k] and not (abs(pa - q[0]) < 1e-12 and abs(pb - q[1]) < 1e-12)]
                            for part in A.parts:
                                region = prism_planes(part, None, None, "side") + others + [above_y(pa, pb, pc - A.t, "seat")]
                                for tp in tops:
                                    x = tp.with_planes(region)
                                    if x is not None:
                                        pieces.append(x)
                    pieces = disjoint(pieces)
                    if not pieces:
                        continue
                    for c_ in pieces:
                        c_.mat = mat
                    self.add(run.element, "cheek", pieces, mat, roof=B.id)
                    self.runs.append(run)
                    # at a corner it stops against the roof's cheeks built before it
                    for e in list(self.elements.values()):
                        if e.kind == "cheek" and e.info.get("roof") == B.id and e.id != run.element:
                            self.yield_to(run.element, e.cells, e.id)
                    # partitions under it stop at it
                    for e in list(self.elements.values()):
                        if e.kind == "partition":
                            self.yield_to(e.id, self.elements[run.element].cells, run.element)
                    # the lower roof's covering yields to it
                    for A in self.roofs.values():
                        if A is not B:
                            self.yield_to("roof:" + A.id, pieces, run.element)

    def _host_mat(self, B: Roof) -> str:
        return "brick"

    # ---- chimneys -----------------------------------------------------------

    def _chimneys(self) -> None:
        for ch in self.data.get("chimneys", []):
            cx, cz = M.expand_point(ch["at"])
            sx, sz = ch["size"]
            base, top = float(ch["base"]), float(ch["top"])
            poly = [(cx - sx / 2, cz - sz / 2), (cx + sx / 2, cz - sz / 2), (cx + sx / 2, cz + sz / 2), (cx - sx / 2, cz + sz / 2)]
            cap = float(ch.get("cap", 0.35))
            big = offset_poly(poly, cap)
            stack = prism(poly, base, top - 1.0, "chimney", "chimney")
            band = prism(big, top - 1.0, top - 0.5, "chimney", "chimney")
            crown = prism(poly, top - 0.5, top, "chimney", "chimney")
            eid = "chimney:" + ch["id"]
            self.add(eid, "chimney", [stack, band, crown], "chimney", top=top)
            shaft = [prism(poly, base, top), prism(big, top - 1.0, top - 0.5)]
            for e in list(self.elements.values()):
                if e.kind in ("roof", "slab", "wall", "partition", "cheek") and e.id != eid:
                    self.yield_to(e.id, [c for c in shaft if c is not None], eid, "chimney_joint")

    # ---- openings -----------------------------------------------------------

    def _find_run(self, o: dict) -> tuple:
        p = M.expand_point(o["at"])
        sill, head = float(o["sill"]), float(o["head"])
        best = None
        for r in self.runs:
            u, s = r.uv(p)
            s0, s1 = r.s_range()
            face = s1 if not r.centred else 0.0
            if abs(s - face) > 0.35 and not (r.centred and abs(s) < 0.35):
                continue
            if u < -0.01 or u > r.length + 0.01:
                continue
            e = self.elements.get(r.element)
            if e is None or not e.cells:
                continue
            lo = min(c.aabb()[0][1] for c in e.cells)
            hi = max(c.aabb()[1][1] for c in e.cells)
            if lo - 0.01 <= sill and head <= hi + 0.01:
                score = abs(s - face)
                if best is None or score < best[0]:
                    best = (score, r, u)
        if best is None:
            raise GenError("opening at %s (sill %.2f, head %.2f) is in no wall" % (o["at"], sill, head))
        return best[1], best[2]

    def _profile(self, u: float, w: float, sill: float, head: float, shape: str, rise: float) -> list:
        u0, u1 = u - w / 2.0, u + w / 2.0
        if shape == "flat" or rise <= 0.01:
            return rect(u0, u1, sill, head)
        # the head is an arc from (u0, head - rise) through (u, head)
        spring = head - rise
        r = (w * w / 4.0 + rise * rise) / (2.0 * rise)
        yc = head - r
        a0 = math.atan2(spring - yc, -w / 2.0)
        a1 = math.atan2(spring - yc, w / 2.0)
        n = 8
        pts = [(u0, sill), (u1, sill)]
        for k in range(n + 1):
            a = a1 + (a0 - a1) * k / n
            pts.append((u + r * math.cos(a), yc + r * math.sin(a)))
        return P.simplify(pts)

    def _openings(self) -> None:
        FR = float(self.data.get("defaults", {}).get("frame", 0.25))
        CW = float(self.data.get("defaults", {}).get("casing", 0.4))
        for k, o in enumerate(self.data.get("openings", [])):
            kind = o.get("kind", "window")
            run, u = self._find_run(o)
            w = float(o["w"])
            sill, head = float(o["sill"]), float(o["head"])
            shape = o.get("head_shape", "flat")
            rise = float(o.get("rise", w / 2.0 if shape == "round" else w * 0.16 if shape == "segment" else 0.0))
            prof = self._profile(u, w, sill, head, shape, rise)
            s0, s1 = run.s_range()
            oid = "opening:%d" % k
            cutter = run_cell(run, prof, s0 - 0.5, s1 + 0.5)
            self.openings.append({"id": oid, "run": run, "u": u, "w": w, "sill": sill, "head": head,
                                  "kind": kind, "prof": prof, "index": k, "spec": o})
            self.yield_to(run.element, [cutter], oid, "reveal")
            door = kind in ("door", "idoor")
            shut = kind == "ishut"
            inner = offset_poly(prof, [0.0 if door else -FR] + [-FR] * (len(prof) - 1)) if not door else \
                offset_poly(prof, [0.0] + [-FR] * (len(prof) - 1))
            mid = (s0 + s1) / 2.0
            fd = min(0.35, s1 - s0)
            # the frame: a board along each edge of the hole, mitred at the
            # corners, its back against the reveal
            frame = []
            for i in range(len(prof)):
                q = [prof[i], prof[(i + 1) % len(prof)], inner[(i + 1) % len(prof)], inner[i]]
                if poly_area(q) < 1e-4:
                    continue
                frame.append(run_cell(run, q, mid - fd / 2.0, mid + fd / 2.0, "frame",
                                      edge_roles=["fit", "mitre", "inside", "mitre"]))
            self.add(oid + ":frame", "frame", frame, "frame", opening=oid)
            if door or shut:
                lt = 0.15
                leaf = run_cell(run, ccw(inner), mid - fd / 2.0, mid - fd / 2.0 + lt, "door")
                self.add(oid + ":leaf", "door", [leaf], "door", opening=oid, hinge=True, closed_only=door)
            else:
                ys = [q[1] for q in inner]
                us = [q[0] for q in inner]
                split = (min(ys) + max(ys)) / 2.0 if max(ys) - min(ys) > 3.0 else None
                panes = [ccw(inner)]
                rail = []
                if split is not None:
                    band = rect(min(us) - 1, max(us) + 1, split - 0.08, split + 0.08)
                    rail = [q for q in [poly_meet(ccw(inner), band)] if q]
                    panes = poly_less(ccw(inner), band)
                glass = [run_cell(run, q, mid - 0.02, mid + 0.02, "glass") for q in panes]
                self.add(oid + ":glass", "glass", glass, "glass", opening=oid)
                if rail:
                    self.add(oid + ":rail", "frame", [run_cell(run, q, mid - 0.06, mid + 0.06, "frame") for q in rail],
                             "frame", opening=oid)
            if run.kind == "partition":
                continue
            # outside: casing, sill, hood
            grown = offset_poly(prof, [0.0] + [CW] * (len(prof) - 1))
            casing = [run_cell(run, q, s1, s1 + 0.12, "casing") for q in poly_less(ccw(grown), ccw(prof))]
            self.add(oid + ":casing", "casing", casing, "trim", opening=oid, host=run.element)
            ytop = max(q[1] for q in grown)
            hood = run_cell(run, rect(u - w / 2 - CW - 0.2, u + w / 2 + CW + 0.2, ytop, ytop + 0.3), s1, s1 + 0.3, "hood")
            self.add(oid + ":hood", "hood", [hood], "trim", opening=oid, host=run.element)
            if not door:
                sl = run_cell(run, rect(u - w / 2 - CW - 0.15, u + w / 2 + CW + 0.15, sill - 0.3, sill), s1, s1 + 0.3, "sill")
                self.add(oid + ":sill", "sill", [sl], "stone", opening=oid, host=run.element)

    # ---- porches ------------------------------------------------------------

    def _porches(self) -> None:
        porch_roof = {}
        for R in self.roofs.values():
            sp = R.spec.get("porch")
            if sp:
                porch_roof[sp] = R
        enclosed_edges = {}
        for lv, segs in self.outlines.items():
            enclosed_edges[lv] = segs
        for s in self.spaces:
            if not s["open"]:
                continue
            R = porch_roof.get(s["id"])
            poly = s["poly"]
            fl = s["floor"]
            canopy = s["kind"] == "canopy"
            open_edges = self._open_edges(s)
            # posts on the open edges' corners and along them
            spots = []
            if R is not None:
                ins = 0.4
                for (a, b) in open_edges:
                    L = math.dist(a, b)
                    d = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
                    m = (-d[1], d[0])
                    k = max(1, math.ceil(L / 9.0))
                    for j in range(k + 1):
                        uu = ins + (L - 2 * ins) * j / k
                        p = (a[0] + d[0] * uu + m[0] * ins, a[1] + d[1] * uu + m[1] * ins)
                        if not any(math.dist(p, q) < 1.0 for q in spots):
                            spots.append(p)
                posts = []
                for p in spots:
                    y0 = self.grade(*p) - 0.5 if canopy else fl
                    sq = [(p[0] - 0.25, p[1] - 0.25), (p[0] + 0.25, p[1] - 0.25), (p[0] + 0.25, p[1] + 0.25), (p[0] - 0.25, p[1] + 0.25)]
                    col = prism(sq, y0, HI)
                    parts = [x for u in R.under for x in [overlap(col, u)] if x is not None]
                    posts.extend(disjoint(parts))
                self.add("posts:" + s["id"], "post", posts, "trim", space=s["id"])
            if canopy:
                continue
            # railings between posts, on open edges
            rails = []
            ins = 0.4
            for (a, b) in open_edges:
                L = math.dist(a, b)
                if L < 0.9:
                    continue
                d = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
                run = Run(a, b, 0.25, "rail", "rail")
                stops = sorted([run.uv(p)[0] for p in spots if abs(run.uv(p)[1] + ins) < 0.05])
                cuts = [0.0] + stops + [L]
                for j in range(len(cuts) - 1):
                    u0 = cuts[j] + (0.25 if j > 0 else ins + 0.25 if self._post_at(spots, run, cuts[j]) else 0.0)
                    u1 = cuts[j + 1] - (0.25 if j + 1 < len(cuts) - 1 else 0.0)
                    if u1 - u0 < 0.5:
                        continue
                    s0, s1 = -ins - 0.12, -ins + 0.12
                    rails.append(run_cell(run, rect(u0, u1, fl + 2.7, fl + 3.0), s0 - 0.04, s1 + 0.04, "rail"))
                    rails.append(run_cell(run, rect(u0, u1, fl + 0.25, fl + 0.45), s0, s1, "rail"))
                    nb = max(1, int((u1 - u0) / 0.45))
                    for q in range(nb):
                        uc = u0 + (u1 - u0) * (q + 0.5) / nb
                        rails.append(run_cell(run, rect(uc - 0.06, uc + 0.06, fl + 0.45, fl + 2.7), -ins - 0.06, -ins + 0.06, "rail"))
            self.add("rail:" + s["id"], "rail", rails, "trim", space=s["id"])
            # a skirt from the ground to a porch floor standing clear of it
            if s["level"] == self._lowest_level():
                sk = []
                for (a, b) in open_edges:
                    L = math.dist(a, b)
                    if L < 0.5:
                        continue
                    g = min(self.grade(*a), self.grade(*b), self.grade((a[0] + b[0]) / 2, (a[1] + b[1]) / 2))
                    top = fl - float(s.get("slab", self.SLAB))
                    if top - g < 0.5:
                        continue
                    run = Run(a, b, 0.1, "skirt", "skirt")
                    sk.append(run_cell(run, rect(0.3, L - 0.3, g - 0.5, top), -0.4, -0.3, "skirt"))
                self.add("skirt:" + s["id"], "skirt", sk, "lattice", space=s["id"])

    def _post_at(self, spots, run, u) -> bool:
        return False

    def _lowest_level(self) -> str:
        return min(self.levels, key=lambda k: abs(self.y(k)))

    def _open_edges(self, s: dict) -> list:
        """The edges of an open space that meet no enclosed space and no
        wall at its level."""
        polys = {x["id"]: x["poly"] for x in self.spaces if not x["open"] and abs(x["floor"] - s["floor"]) < 8.0}
        polys[s["id"]] = s["poly"]
        out = []
        for e in P.edge_parts(polys):
            if e["of"] != s["id"] or e["other"] is not None:
                continue
            out.append((e["a"], e["b"]))
        # merge collinear
        merged = []
        for a, b in out:
            if merged and math.dist(merged[-1][1], a) < 1e-3 and self._collinear({"a": merged[-1][0], "b": merged[-1][1]}, {"a": a, "b": b}):
                merged[-1] = (merged[-1][0], b)
            else:
                merged.append((a, b))
        return merged

    # ---- brackets -----------------------------------------------------------

    def _brackets(self) -> None:
        for R in self.roofs.values():
            sp = R.spec.get("brackets")
            if not sp:
                continue
            sp = float(sp)
            cells = []
            n = len(R.footprint)
            for i in range(n):
                e = R.edges[i]
                if e["kind"] != "eave" or float(e["over"]) < 0.9:
                    continue
                a, b = R.footprint[i], R.footprint[(i + 1) % n]
                run = Run(a, b, 1.0, "bracket", "bracket")
                L = run.length
                k = max(1, int((L - 1.0) / sp))
                pl = next(p for p in R.planes if p[3] == i)
                for j in range(k + 1):
                    uc = 0.5 + (L - 1.0) * j / max(1, k)
                    # the soffit over it and the wall behind it must be there
                    pout = run.plan(uc, float(e["over"]) / 2.0)
                    ysoff = pl[0] * pout[0] + pl[1] * pout[1] + pl[2] - R.t
                    probe = (pout[0], ysoff + 0.02, pout[1])
                    if not any(contains(c_, probe, 1e-4) for c_ in self.elements["roof:" + R.id].cells):
                        continue
                    pin = run.plan(uc, -0.2)
                    wprobe = (pin[0], ysoff - 1.2, pin[1])
                    if not any(contains(c_, wprobe, 1e-4) for ee in self.elements.values() if ee.kind in ("wall", "cheek")
                               for c_ in ee.cells):
                        continue
                    depth = float(e["over"]) - 0.25
                    prof = rect(uc - 0.18, uc + 0.18, ysoff - 1.2, ysoff + 3.0)
                    c_ = run_cell(run, prof, 0.0, depth, "bracket")
                    if c_ is None:
                        continue
                    c_ = c_.with_planes([below_y(pl[0], pl[1], pl[2] - R.t, "seat")])
                    if c_ is not None:
                        cells.append(c_)
            self.add("brackets:" + R.id, "bracket", cells, "trim", roof=R.id)


def poly_less_all(p, qs) -> list:
    pieces = [p]
    for q in qs:
        nxt = []
        for x in pieces:
            nxt.extend(poly_less(x, q))
        pieces = nxt
    return pieces


def _hit(p0, t0, p1, t1):
    det = t0[0] * (-t1[1]) - (-t1[0]) * t0[1]
    if abs(det) < 1e-9:
        # parallel: continue straight
        return p1
    rx, rz = p1[0] - p0[0], p1[1] - p0[1]
    s = (rx * (-t1[1]) - (-t1[0]) * rz) / det
    return (p0[0] + t0[0] * s, p0[1] + t0[1] * s)


def _free_intervals(lo, hi, covered):
    covered = sorted(covered)
    out = []
    cur = lo
    for a, b in covered:
        if b <= cur + 1e-6:
            continue
        if a > cur + 1e-6:
            out.append((cur, min(a, hi)))
        cur = max(cur, b)
        if cur >= hi:
            break
    if cur < hi - 1e-6:
        out.append((cur, hi))
    return out


def _r(p):
    return tuple(round(v, 2) for v in p)


def load(path: str) -> Model:
    with open(path, encoding="utf-8") as f:
        return Model(json.load(f))
