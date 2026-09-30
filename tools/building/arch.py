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
        if abs(du) + abs(dy) < 1e-9:
            continue
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
        """The surface's highest point over the footprint."""
        return max(c.aabb()[1][1] for c in self.solid)


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
            "kind": spec.get("edge", "gable" if "shed" in spec else "eave"),
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
        apex = None
        if "apex" in spec:
            # a pyramid or cone: every eave rises to one point
            apex = M.expand_point(spec["apex"])
            on_edge = any(P.seg_dist(apex, fp[i], fp[(i + 1) % len(fp)]) < 1e-3 for i in range(len(fp)))
            if not P.point_in(apex, fp) and not on_edge:
                raise GenError("roof %s: its apex stands outside its footprint" % rid)
            if spec.get("peak") is None:
                raise GenError("roof %s: an apex needs a peak height" % rid)
        for i, e in enumerate(edges):
            if apex is not None and e["kind"] == "eave" and e.get("pitch") is None:
                a, b = fp[i], fp[(i + 1) % len(fp)]
                dist = abs((b[0] - a[0]) * (apex[1] - a[1]) - (b[1] - a[1]) * (apex[0] - a[0])) / math.dist(a, b)
                if dist < 1e-3:
                    raise GenError("roof %s: edge %d runs through its apex (make it abut)" % (rid, i))
                rise = float(spec["peak"]) - self.y(e["plate"])
                if rise <= 0:
                    raise GenError("roof %s: its peak is under its plate" % rid)
                e = dict(e, pitch=rise / dist)
                edges[i] = e
            kind = e["kind"]
            if kind not in ("eave", "gable", "abut"):
                raise GenError("roof %s edge %d: kind %r" % (rid, i, kind))
            if kind == "eave" and "shed" in spec:
                over = float(e["over"])
            elif kind == "eave":
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
        if "shed" in spec:
            # one plane, rising from a line (inward to its left) at a pitch
            sh = spec["shed"]
            p0, p1 = M.expand_point(sh["from"][0]), M.expand_point(sh["from"][1])
            pitch = float(sh["pitch"])
            if not (0.0 <= pitch <= PITCH_MAX):
                raise GenError("roof %s: pitch %.2f out of range" % (rid, pitch))
            planes.append(_edge_plane(p0, p1, self.y(sh["plate"]), pitch) + (-2,))
        if "deck" in spec:
            planes.append((0.0, 0.0, float(spec["deck"]), -1))
        if not planes:
            raise GenError("roof %s has no eave: nothing makes its surface" % rid)
        single = len(planes) == 1
        if not single and not is_convex(fp):
            raise GenError("roof %s: a roof of several planes needs a convex footprint "
                           "(compose it from convex roofs)" % rid)
        parts = [fp] if is_convex(fp) else P.convex_parts(fp)
        if is_convex(fp):
            ext = offset_poly(fp, overs)
            if not is_convex(ext):
                raise GenError("roof %s: its overhangs make its outline concave" % rid)
            extent_parts = [ext]
        else:
            extent_parts = _grown_pieces(fp, parts, overs)
        extent = [q for p in extent_parts for q in p]
        r = Roof(rid, spec, fp, parts, edges, extent, extent_parts, planes,
                 float(spec.get("depth", self.ROOF_T)), spec.get("cover", "slate"), order)
        r.lines = []
        for i in range(len(fp)):
            a, b = fp[i], fp[(i + 1) % len(fp)]
            L = math.dist(a, b)
            t = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
            n_ = (t[1], -t[0])
            r.lines.append(((a[0] + n_[0] * overs[i], a[1] + n_[1] * overs[i]), t))
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
            if e["kind"] == "eave" and "shed" not in spec and pk < self.y(e["plate"]) - 1e-6:
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
        return subtract_all(out, self._hole_cells(B))

    def _hole_cells(self, R: Roof) -> list:
        if getattr(R, "_holes", None) is None:
            R._holes = [prism(q, LO, HI, "hole") for h in R.spec.get("holes", []) for q in P.convex_parts(self._poly(h))]
        return R._holes

    def _compose_roofs(self) -> None:
        roofs = list(self.roofs.values())
        for A in roofs:
            fields, eaves = [], []
            for i, pl in enumerate(A.planes):
                a, b, c, ei = pl
                others = [Plane.of((a - q[0], 0.0, b - q[1]), q[2] - c, "hip") for q in A.planes if q is not pl
                          and not (abs(a - q[0]) < 1e-12 and abs(b - q[1]) < 1e-12)]
                top = below_y(a, b, c, "deck" if ei == -1 else "slope")
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
                    # where B's front rises from A's wall, A's eave stops across
                    # the width of that front, however high B stands
                    for face in self._same_wall_line(A, B):
                        b0, b1 = face
                        L = math.dist(b0, b1)
                        t = ((b1[0] - b0[0]) / L, (b1[1] - b0[1]) / L)
                        span = []
                        for part in B.extent_parts:
                            q = poly_meet(ccw(part), ccw([(b0[0] - t[1] * 50, b0[1] + t[0] * 50), (b0[0] + t[1] * 50, b0[1] - t[0] * 50),
                                                          (b1[0] + t[1] * 50, b1[1] - t[0] * 50), (b1[0] - t[1] * 50, b1[1] + t[0] * 50)]))
                            if q:
                                span.append(q)
                        hi = hi + self._higher(B, pl, A, span)
                    if hi:
                        cut = subtract_all(cut, hi, "meet")
                    cut = subtract_all(cut, subtract_all(B.solid, self._hole_cells(B)), "meet")
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

    def _above_underside(self, R: Roof) -> list:
        """Everything over a roof's underside within its outline, as cells."""
        if getattr(R, "_above", None) is None:
            out = []
            for i, (a, b, c, _) in enumerate(R.planes):
                others = [Plane.of((a - q[0], 0.0, b - q[1]), q[2] - c) for q in R.planes if q is not R.planes[i]
                          and not (abs(a - q[0]) < 1e-12 and abs(b - q[1]) < 1e-12)]
                for part in R.extent_parts:
                    x = cell(prism_planes(part, None, HI) + others + [above_y(a, b, c - R.t)])
                    if x is not None:
                        out.append(x)
            R._above = subtract_all(out, self._hole_cells(R))
        return R._above

    @staticmethod
    def _same_wall_line(A: Roof, B: Roof):
        """Whether an edge of B's footprint runs along an edge of A's, the
        same way (B's front rises from A's wall, as a wall dormer's or a
        gable's end does): every such edge of B."""
        out = []
        for i in range(len(B.footprint)):
            b0, b1 = B.footprint[i], B.footprint[(i + 1) % len(B.footprint)]
            for j in range(len(A.footprint)):
                a0, a1 = A.footprint[j], A.footprint[(j + 1) % len(A.footprint)]
                L = math.dist(a0, a1)
                t = ((a1[0] - a0[0]) / L, (a1[1] - a0[1]) / L)
                off0 = (b0[0] - a0[0]) * t[1] - (b0[1] - a0[1]) * t[0]
                off1 = (b1[0] - a0[0]) * t[1] - (b1[1] - a0[1]) * t[0]
                if abs(off0) > 0.05 or abs(off1) > 0.05:
                    continue
                if (b1[0] - b0[0]) * t[0] + (b1[1] - b0[1]) * t[1] <= 0:
                    continue
                u0 = (b0[0] - a0[0]) * t[0] + (b0[1] - a0[1]) * t[1]
                u1 = (b1[0] - a0[0]) * t[0] + (b1[1] - a0[1]) * t[1]
                if min(u1, L) - max(u0, 0.0) > 0.1:
                    out.append((b0, b1))
        return out

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
        for k in range(len(part)):
            a, b = part[k], part[(k + 1) % len(part)]
            if math.dist(a, b) < 1e-9:
                continue
            role = "seam"
            for i, (q, t) in enumerate(A.lines):
                # on the line footprint edge i is grown to
                da = abs((a[0] - q[0]) * t[1] - (a[1] - q[1]) * t[0])
                db = abs((b[0] - q[0]) * t[1] - (b[1] - q[1]) * t[0])
                if da < 1e-4 and db < 1e-4:
                    kind = A.edges[i]["kind"]
                    role = "fascia" if kind == "eave" else "rake" if kind == "gable" else "abut"
                    break
            out.append(vertical(a, b, role))
        return out

    def enclosed_at(self, x: float, z: float, below: float) -> bool:
        """Whether the space nearest under a point (at a plan point, the one
        with the highest floor under the height) is enclosed."""
        best = None
        for s in self.spaces:
            if s["floor"] < below and P.point_in((x, z), s["poly"]):
                if best is None or s["floor"] > best["floor"]:
                    best = s
        return best is not None and not best["open"]

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
                    if m["on"] == s["on"] and self._collinear(m, s) and m.get("mat") == s.get("mat") and                             self.space[m["of"]]["floor"] == self.space[s["of"]]["floor"]:
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
        dt = (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1])
        off = P.seg_dist(b, a, c)
        if dt > 0 and 1e-5 < off < 0.02:
            # a point a hair off a wall's line would tilt the whole wall
            raise GenError("a wall bends by %.4f ft at (%.3f, %.3f): put the point on the line"
                           % (off, b[0], b[1]))
        return dt > 0 and off <= 1e-5 and math.dist(a, c) > 1e-6

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
        caps = [(poly, bottom) for (poly, bottom, top, lv, sid) in self.slab_plan] + \
            [(ccw(q), f) for (q, f) in getattr(self, "wall_plan", [])]
        for (poly, bottom) in sorted(caps, key=lambda s: s[1]):
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
        self.wall_plan = []
        self._dry = True
        self._each_wall()
        self._partitions()
        self._dry = False
        self._each_wall()

    def _each_wall(self) -> None:
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
            # it stands on the floor of the room it closes
            f = self.space[s["of"]]["floor"] if s.get("of") in self.space else self.y(lv)
            if self._dry:
                self.wall_plan.append((quad, f))
                continue
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
                pf = min(self.space[s["of"]]["floor"], self.space[s["other"]]["floor"])                     if s.get("other") in self.space else self.y(lv)
                if getattr(self, "_dry", False):
                    self.wall_plan.append((quad, pf))
                    continue
                eid = "part:%s:%d" % (lv, len(self.runs))
                cells = self._cap(quad, pf, eid)
                rooms = [prism(q) for s2 in self.spaces if s2["level"] == lv and not s2["open"]
                         for q in P.convex_parts(s2["poly"])]
                cells = disjoint([x for c_ in cells for r_ in rooms if r_ is not None for x in [overlap(c_, r_)] if x is not None])
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
                        # the lower roof's covering as it stands (a part of it cut
                        # away under a higher roof carries nothing)
                        for cov in self.elements["roof:" + A.id].cells:
                            topf = [cov.planes[f.plane] for f in cov.faces if cov.planes[f.plane].role in ("slope", "deck")]
                            if not topf:
                                continue
                            tn = topf[0]
                            if tn.n[1] < 1e-6:
                                continue
                            pa, pb, pc = -tn.n[0] / tn.n[1], -tn.n[2] / tn.n[1], tn.d / tn.n[1]
                            others = []
                            clear = []
                            empty = False
                            for (qa, qb, qc, _) in B.planes:
                                nx, nz = pa - qa, pb - qb
                                rhs = qc - B.t - pc
                                if abs(nx) < 1e-12 and abs(nz) < 1e-12:
                                    if rhs <= 1e-6:
                                        empty = True
                                    continue
                                clear.append(Plane.of((nx, 0.0, nz), rhs, "end"))
                            if empty:
                                continue
                            # the lower roof's covering, and a cheek's width beyond
                            # its edge: a step between two roofs is closed by a
                            # wall standing at the lower one's edge
                            hull = _swept([(q[0], q[2]) for q in cov.vset()], (-d[1] * (t + 0.02), d[0] * (t + 0.02)))
                            for part in [hull]:
                                if len(part) < 3:
                                    continue
                                region = prism_planes(part, None, None, "side") + others + clear + \
                                    [above_y(pa, pb, pc - A.t, "seat")]
                                for tp in tops:
                                    x = tp.with_planes(region)
                                    if x is not None:
                                        pieces.append(x)
                    pieces = disjoint(pieces)
                    # it stops at the walls, floors and cheeks already there
                    for e in list(self.elements.values()):
                        if e.kind in ("wall", "slab", "cheek") and pieces:
                            n0 = sum(c.volume() for c in pieces)
                            pieces = subtract_all(pieces, e.cells)
                            if abs(sum(c.volume() for c in pieces) - n0) > 1e-5:
                                self.joints.add((run.element, e.id))
                    if not pieces:
                        continue
                    for c_ in pieces:
                        c_.mat = mat
                    self.add(run.element, "cheek", pieces, mat, roof=B.id)
                    self.runs.append(run)
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
            for e in list(self.elements.values()):
                if e.kind == "chimney" and e.id != eid:
                    self.yield_to(eid, e.cells, e.id)
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
            # the wall that stands at the opening's middle
            q = r.plan(u, (s0 + s1) / 2.0)
            ym = (sill + head) / 2.0
            if any(contains(c_, (q[0], ym, q[1]), 1e-6) for c_ in e.cells):
                score = abs(s - face)
                if best is None or score < best[0]:
                    best = (score, r, u)
        if best is None:
            raise GenError("opening at %s (sill %.2f, head %.2f) is in no wall" % (o["at"], sill, head))
        return best[1], best[2]

    def _face_runs(self, run: Run) -> list:
        """The walls whose faces lie in one plane with this one, the same
        way: one facade, however its storeys divide it."""
        out = []
        for r2 in self.runs:
            if r2.kind != run.kind or r2.centred != run.centred:
                continue
            d1, d2 = run.dir, r2.dir
            if d1[0] * d2[0] + d1[1] * d2[1] < 1 - 1e-6:
                continue
            if abs(run.uv(r2.a)[1]) > 0.02 or abs(run.uv(r2.b)[1]) > 0.02:
                continue
            out.append(r2)
        return out

    def _profile(self, u: float, w: float, sill: float, head: float, shape: str, rise: float) -> list:
        u0, u1 = u - w / 2.0, u + w / 2.0
        if shape == "flat" or rise <= 0.01:
            return rect(u0, u1, sill, head)
        # an arch taller than the opening makes a lunette: all arch
        rise = min(rise, head - sill)
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
        errors = []
        self._uncut = {}
        self._placed = []
        for k, o in enumerate(self.data.get("openings", [])):
            try:
                run, u = self._find_run(o)
                w = float(o["w"])
                # the face it is in: every wall on the same line, the same way
                spans = sorted((min(a_, b_), max(a_, b_)) for r2 in self._face_runs(run)
                               for a_, b_ in [(run.uv(r2.a)[0], run.uv(r2.b)[0])])
                lo_, hi_ = u - w / 2.0 - 0.15, u + w / 2.0 + 0.15
                cover = lo_
                for a_, b_ in spans:
                    if a_ <= cover + 1e-6:
                        cover = max(cover, b_)
                if cover < hi_ - 1e-6 or not any(a_ <= lo_ + 1e-6 for a_, b_ in spans):
                    raise GenError("opening at %s: %.2f ft wide, it runs off its wall" % (o["at"], w))
                self._placed.append((run, u, w, k))
            except GenError as ex:
                errors.append(str(ex))
                self._placed.append(None)
        if not errors:
            for k, o in enumerate(self.data.get("openings", [])):
                try:
                    self._opening(k, o, FR, CW)
                except GenError as ex:
                    errors.append(str(ex))
        if errors:
            raise GenError("%d openings cannot be made:\n  " % len(errors) + "\n  ".join(errors))

    def _opening(self, k: int, o: dict, FR: float, CW: float) -> None:
        if True:
            kind = o.get("kind", "window")
            run, u, w, _ = self._placed[k]
            sill, head = float(o["sill"]), float(o["head"])
            shape = o.get("head_shape", "flat")
            rise = float(o.get("rise", w / 2.0 if shape == "round" else w * 0.16 if shape == "segment" else 0.0))
            prof = self._profile(u, w, sill, head, shape, rise)
            s0, s1 = run.s_range()
            oid = "opening:%d" % k
            cutter = run_cell(run, prof, s0 - 0.5, s1 + 0.5)
            if cutter is None or head - sill < 0.5 or w < 0.5:
                raise GenError("opening at %s: no opening (width %.2f, sill %.2f, head %.2f)" % (o["at"], w, sill, head))
            # the wall must stand all round the hole: a band 0.15 ft wide
            # outside the opening (the foot of a door excepted) is wall
            door_foot = kind in ("door", "idoor", "shut", "ishut", "open", "french")
            ring = offset_poly(prof, [0.0 if door_foot else 0.15] + [0.15] * (len(prof) - 1))
            face = self._face_runs(run)
            host = [c_ for r2 in face for c_ in self._uncut.setdefault(r2.element, list(self.elements[r2.element].cells))]
            # a chimney's brick is wall enough round an opening beside it
            host += [c_ for e_ in self.elements.values() if e_.kind == "chimney" for c_ in e_.cells]
            for i in range(len(ring)):
                pa, pb = ring[i], ring[(i + 1) % len(ring)]
                if door_foot and i == 0:
                    continue
                n_ = max(2, int(math.dist(pa, pb) / 0.25))
                for j in range(n_):
                  uu = pa[0] + (pb[0] - pa[0]) * j / n_
                  yy = pa[1] + (pb[1] - pa[1]) * j / n_
                  for ss in (s0 + 0.02, (s0 + s1) / 2.0, s1 - 0.02):
                    q = run.plan(uu, ss)
                    if not any(contains(c_, (q[0], yy, q[1]), 1e-6) for c_ in host):
                        raise GenError("opening at %s (sill %.2f, head %.2f): its wall does not stand round it "
                                       "(nothing at u %.2f, height %.2f)" % (o["at"], sill, head, uu, yy))
            self.openings.append({"id": oid, "run": run, "u": u, "w": w, "sill": sill, "head": head,
                                  "kind": kind, "prof": prof, "index": k, "spec": o})
            for r2 in face:
                self.yield_to(r2.element, [cutter], oid, "reveal")
            if kind not in ("window", "french", "door", "idoor", "shut", "ishut", "open"):
                raise GenError("opening at %s: no kind %r" % (o["at"], kind))
            leaf = kind in ("door", "idoor", "shut", "ishut")
            door = leaf or kind == "open"           # no frame across the foot
            swung = kind in ("door", "idoor")
            inner = offset_poly(prof, [0.0 if door else -FR] + [-FR] * (len(prof) - 1))
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
            if kind == "open":
                pass
            elif leaf:
                lt = 0.15
                lc = run_cell(run, ccw(inner), mid - fd / 2.0, mid - fd / 2.0 + lt, "door")
                self.add(oid + ":leaf", "door", [lc], "door", opening=oid, swung=swung)
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
                return
            # outside: casing, sill, hood, as wide as the wall and the
            # openings beside it leave room for
            trim = o.get("trim", ["casing", "hood", "sill"])
            if not o.get("hood", True) and "hood" in trim:
                trim = [t_ for t_ in trim if t_ != "hood"]
            left, right, up, down = self._room_around(k, run, u, w, sill, head)
            cl, cr_ = min(CW, left), min(CW, right)
            xl, xr = min(0.2, left - cl), min(0.2, right - cr_)
            ytop_prof = max(q[1] for q in prof)
            up = self._clear_above(run, u - w / 2 - cl, u + w / 2 + cr_, ytop_prof, s1, min(up, 1.2))
            ct = min(CW, up)
            n_ = len(prof)
            widths = [0.0] + [ct] * (n_ - 1)
            widths[1] = cr_
            widths[n_ - 1] = cl
            grown = offset_poly(prof, widths)
            ytop = max(q[1] for q in grown)
            if "casing" in trim:
                casing = [run_cell(run, q, s1, s1 + 0.12, "casing") for q in poly_less(ccw(grown), ccw(prof))]
                self.add(oid + ":casing", "casing", casing, "trim", opening=oid, host=run.element)
            # a hood where the wall rises clear over the casing; a sill board
            # where it stands clear under the opening
            if "hood" in trim and up >= ct + 0.35:
                hood = run_cell(run, rect(u - w / 2 - cl - xl, u + w / 2 + cr_ + xr, ytop, ytop + 0.3), s1, s1 + 0.3, "hood")
                self.add(oid + ":hood", "hood", [hood], "trim", opening=oid, host=run.element)
            if "sill" in trim and not door and kind != "french":
                dn = self._clear_below(run, u - w / 2 - cl - min(0.15, xl), u + w / 2 + cr_ + min(0.15, xr), sill, s1, min(down, 0.6))
                if dn >= 0.35:
                    sl = run_cell(run, rect(u - w / 2 - cl - min(0.15, xl), u + w / 2 + cr_ + min(0.15, xr), sill - 0.3, sill),
                                  s1, s1 + 0.3, "sill")
                    self.add(oid + ":sill", "sill", [sl], "stone", opening=oid, host=run.element)

    def _under_covering(self, col: Cell, p) -> list:
        """A column cut to the underside of the lowest roof covering over
        its middle (as the roofs stand, not as their planes run)."""
        best = None
        for e in self.elements.values():
            if e.kind != "roof":
                continue
            for c_ in e.cells:
                lo, hi = c_.aabb()
                if not (lo[0] - 1e-6 <= p[0] <= hi[0] + 1e-6 and lo[2] - 1e-6 <= p[1] <= hi[2] + 1e-6):
                    continue
                for f in c_.faces:
                    pl = c_.planes[f.plane]
                    if pl.n[1] > -1e-6:
                        continue
                    # the underside plane: n.x <= d with n pointing down
                    y = (pl.d - pl.n[0] * p[0] - pl.n[2] * p[1]) / pl.n[1]
                    q = (p[0], y + 0.01, p[1])
                    if contains(c_, q, 1e-5):
                        if best is None or y < best[0]:
                            best = (y, e.id)
        if best is None:
            return []
        R = self.roofs[best[1].split(":", 1)[1]]
        return disjoint([x for u in R.under for x in [overlap(col, u)] if x is not None])

    def _obstacles(self, lo, hi) -> list:
        """Every solid but the walls within a box, for trim to keep clear of."""
        out = []
        for e in self.elements.values():
            if e.kind in ("wall", "partition", "frame", "glass", "door"):
                continue
            for c_ in e.cells:
                a, b = c_.aabb()
                if all(a[i] <= hi[i] and b[i] >= lo[i] for i in range(3)):
                    out.append(c_)
        return out

    def _clear_above(self, run: Run, u0: float, u1: float, y: float, s1: float, limit: float) -> float:
        """How far above height y the face stays clear (nothing in front of
        it, the wall behind it) across u0..u1, up to limit."""
        pts = [run.plan(u0 + (u1 - u0) * i / 6.0, 0.0) for i in range(7)]
        back = [run.plan(u0 + (u1 - u0) * i / 6.0, s1 - 0.02) for i in range(7)]
        front = [run.plan(u0 + (u1 - u0) * i / 6.0, s1 + 0.1) for i in range(7)]
        xs = [p[0] for p in pts]
        zs = [p[1] for p in pts]
        obs = self._obstacles((min(xs) - 1, y - 1, min(zs) - 1), (max(xs) + 1, y + limit + 1, max(zs) + 1))
        walls = [c_ for e in self.elements.values() if e.kind in ("wall", "cheek", "chimney") for c_ in e.cells]
        h = 0.0
        while h < limit:
            yy = y + h + 0.05
            if any(contains(c_, (q[0], yy, q[1]), 1e-6) for q in front for c_ in obs):
                break
            if not all(any(contains(c_, (q[0], yy, q[1]), 1e-6) for c_ in walls) for q in back):
                break
            h += 0.05
        return max(0.0, h - 0.05)

    def _clear_below(self, run: Run, u0: float, u1: float, y: float, s1: float, limit: float) -> float:
        pts = [run.plan(u0 + (u1 - u0) * i / 6.0, 0.0) for i in range(7)]
        front = [run.plan(u0 + (u1 - u0) * i / 6.0, s1 + 0.15) for i in range(7)]
        xs = [p[0] for p in pts]
        zs = [p[1] for p in pts]
        obs = self._obstacles((min(xs) - 1, y - limit - 1, min(zs) - 1), (max(xs) + 1, y + 1, max(zs) + 1))
        h = 0.0
        while h < limit:
            yy = y - h - 0.05
            if any(contains(c_, (q[0], yy, q[1]), 1e-6) for q in front for c_ in obs):
                break
            h += 0.05
        return max(0.0, h - 0.05)

    def _room_around(self, k: int, run: Run, u: float, w: float, sill: float, head: float) -> tuple:
        """How far the trim of opening k may reach on its wall's face: along
        it to the wall's end or half way to the next opening beside it, and
        up or down half way to an opening above or below it."""
        left, right = u - w / 2.0, run.length - (u + w / 2.0)
        up, down = 9.0, 9.0
        ops = self.data.get("openings", [])
        for pl in self._placed:
            if pl is None or pl[3] == k:
                continue
            r2, u2, w2, k2 = pl
            if r2.kind == "partition":
                continue
            c = r2.plan(u2, 0.0)
            uu, ss = run.uv(c)
            d2 = r2.dir
            if abs(ss) > 0.05 or d2[0] * run.dir[0] + d2[1] * run.dir[1] < 0.99:
                continue
            s2, h2 = float(ops[k2]["sill"]), float(ops[k2]["head"])
            side_by_side = s2 < head and h2 > sill
            if side_by_side:
                if uu > u:
                    right = min(right, ((uu - w2 / 2.0) - (u + w / 2.0)) / 2.0)
                else:
                    left = min(left, ((u - w / 2.0) - (uu + w2 / 2.0)) / 2.0)
            elif abs(uu - u) < (w + w2) / 2.0 + 0.8:
                if s2 >= head:
                    up = min(up, (s2 - head) / 2.0)
                elif h2 <= sill:
                    down = min(down, (sill - h2) / 2.0)
        return max(0.0, left - 0.02), max(0.0, right - 0.02), max(0.0, up - 0.02), max(0.0, down - 0.02)

    def _room_beside(self, k: int, run: Run, u: float, w: float) -> tuple:
        """How far the trim of opening k may reach along its wall's face,
        each side: to the wall's end, or half way to the next opening on the
        same face."""
        left, right = u - w / 2.0, run.length - (u + w / 2.0)
        for pl in self._placed:
            if pl is None or pl[3] == k:
                continue
            r2, u2, w2, _ = pl
            if r2.kind == "partition":
                continue
            # the same face: the same line, the same way
            c = r2.plan(u2, 0.0)
            uu, ss = run.uv(c)
            d2 = r2.dir
            if abs(ss) > 0.05 or d2[0] * run.dir[0] + d2[1] * run.dir[1] < 0.99:
                continue
            if uu > u:
                right = min(right, ((uu - w2 / 2.0) - (u + w / 2.0)) / 2.0)
            else:
                left = min(left, ((u - w / 2.0) - (uu + w2 / 2.0)) / 2.0)
        return max(0.0, left - 0.02), max(0.0, right - 0.02)

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
            gaps = self._entries(s, open_edges)
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
                        in_gap = any(P.seg_dist(p, g0, g1) < 0.6 for g0, g1 in gaps)
                        if not in_gap and not any(math.dist(p, q) < 1.0 for q in spots):
                            spots.append(p)
                posts = []
                for p in spots:
                    y0 = self.grade(*p) - 0.5 if canopy else fl
                    sq = [(p[0] - 0.25, p[1] - 0.25), (p[0] + 0.25, p[1] - 0.25), (p[0] + 0.25, p[1] + 0.25), (p[0] - 0.25, p[1] + 0.25)]
                    col = prism(sq, y0, HI)
                    parts = self._under_covering(col, p)
                    walls_ = [c_ for e_ in self.elements.values() if e_.kind in ("wall", "cheek", "chimney")
                              for c_ in e_.cells]
                    if any(overlap(pc_, wc_) is not None for pc_ in parts for wc_ in walls_):
                        continue
                    posts.extend(parts)
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
                pieces = []
                for j in range(len(cuts) - 1):
                    u0 = cuts[j] + (0.25 if j > 0 else 0.0)
                    u1 = cuts[j + 1] - (0.25 if j + 1 < len(cuts) - 1 else 0.0)
                    free = [(u0, u1)]
                    for g0, g1 in gaps:
                        ga, gb = run.uv(g0)[0], run.uv(g1)[0]
                        if abs(run.uv(g0)[1]) > 0.05 or abs(run.uv(g1)[1]) > 0.05:
                            continue
                        ga, gb = min(ga, gb), max(ga, gb)
                        nxt = []
                        for f0, f1 in free:
                            if gb <= f0 or ga >= f1:
                                nxt.append((f0, f1))
                                continue
                            if ga > f0:
                                nxt.append((f0, ga))
                            if gb < f1:
                                nxt.append((gb, f1))
                        free = nxt
                    pieces.extend(free)
                for u0, u1 in pieces:
                    if u1 - u0 < 0.5:
                        continue
                    s0, s1 = -ins - 0.12, -ins + 0.12
                    rails.append(run_cell(run, rect(u0, u1, fl + 2.7, fl + 3.0), s0 - 0.04, s1 + 0.04, "rail"))
                    rails.append(run_cell(run, rect(u0, u1, fl + 0.25, fl + 0.45), s0, s1, "rail"))
                    nb = max(1, int((u1 - u0) / 0.45))
                    for q in range(nb):
                        uc = u0 + (u1 - u0) * (q + 0.5) / nb
                        rails.append(run_cell(run, rect(uc - 0.06, uc + 0.06, fl + 0.45, fl + 2.7), -ins - 0.06, -ins + 0.06, "rail"))
            self.add("rail:" + s["id"], "rail", disjoint([r_ for r_ in rails if r_ is not None]), "trim", space=s["id"])
            for R2 in self.roofs.values():
                self.yield_to("rail:" + s["id"], self._above_underside(R2), "roof:" + R2.id)
            # and stop at the walls they meet
            for e_ in list(self.elements.values()):
                if e_.kind in ("wall", "cheek", "chimney", "post"):
                    self.yield_to("rail:" + s["id"], e_.cells, e_.id)
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
                self.add("skirt:" + s["id"], "skirt", disjoint([c_ for c_ in sk if c_ is not None]), "lattice",
                         space=s["id"])

    def _entries(self, s: dict, open_edges: list) -> list:
        """An open space's entries: gaps in its railing, each with steps
        down to the ground in front of it. [(a, b)] along the edges."""
        out = []
        for k, en in enumerate(s.get("entries", [])):
            p = M.expand_point(en["at"])
            w = float(en["w"])
            best = None
            for a, b in open_edges:
                dd = P.seg_dist(p, a, b)
                if dd < 0.3 and (best is None or dd < best[0]):
                    best = (dd, a, b)
            if best is None:
                raise GenError("%s: entry at %s is on no open edge" % (s["id"], en["at"]))
            _, a, b = best
            run = Run(a, b, 0.0, "steps", "steps")
            u = run.uv(p)[0]
            u0, u1 = max(0.0, u - w / 2.0), min(run.length, u + w / 2.0)
            out.append((run.plan(u0, 0.0), run.plan(u1, 0.0)))
            if s["kind"] == "canopy":
                continue
            g = self.grade(*run.plan(u, 2.0))
            drop = s["floor"] - g
            if drop < 0.4:
                continue
            n = max(1, math.ceil(drop / 0.6))
            h = drop / n
            steps = []
            for i in range(1, n + 1):
                top = s["floor"] - i * h
                if top - (g - 0.5) < 0.05:
                    continue
                steps.append(run_cell(run, rect(u0, u1, g - 0.5, top), float(i - 1), float(i), "step"))
            self.add("steps:%s:%d" % (s["id"], k), "step", steps, "stone", space=s["id"])
        return out

    def _lowest_level(self) -> str:
        return min(self.levels, key=lambda k: abs(self.y(k)))

    def _open_edges(self, s: dict) -> list:
        """The edges of an open space that meet no enclosed space and no
        wall at its level."""
        # a canopy has no floor: a porch's edge under one is still open
        polys = {x["id"]: x["poly"] for x in self.spaces if abs(x["floor"] - s["floor"]) < 8.0
                 and (x["kind"] != "canopy" or x is s)}
        polys[s["id"]] = s["poly"]
        encl = [x["poly"] for x in self.spaces if not x["open"] and abs(x["floor"] - s["floor"]) < 8.0]
        out = []
        for e in P.edge_parts(polys):
            if e["of"] != s["id"] or e["other"] is not None:
                continue
            a, b = e["a"], e["b"]
            # along a room's wall though drawn with other points
            against = True
            for f in (0.0, 0.25, 0.5, 0.75, 1.0):
                p = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
                if not any(P.seg_dist(p, q[i], q[(i + 1) % len(q)]) < 0.35 for q in encl for i in range(len(q))):
                    against = False
                    break
            if against:
                continue
            out.append((a, b))
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
                pl = _edge_plane(a, b, self.y(e["plate"]), float(e["pitch"]))
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
                    if c_ is None:
                        continue
                    clash = False
                    for ee in self.elements.values():
                        for d_ in ee.cells:
                            if not boxes_apart(c_, d_, 1e-4) and overlap(c_, d_) is not None and overlap(c_, d_).volume() > 1e-5:
                                clash = True
                                break
                        if clash:
                            break
                    if clash or any(overlap(c_, d_) is not None for d_ in cells):
                        continue
                    bears = True
                    for uu in (uc - 0.15, uc + 0.15):
                        for ss in (0.1, depth - 0.1):
                            pt = run.plan(uu, ss)
                            ys = pl[0] * pt[0] + pl[1] * pt[1] + pl[2] - R.t
                            if not any(contains(d_, (pt[0], ys + 0.02, pt[1]), 1e-4) for d_ in self.elements["roof:" + R.id].cells):
                                bears = False
                        for yy in (ysoff - 1.1, ysoff - 0.1):
                            pt = run.plan(uu, -0.05)
                            if not any(contains(d_, (pt[0], yy, pt[1]), 1e-4) for ee in self.elements.values()
                                       if ee.kind in ("wall", "cheek") for d_ in ee.cells):
                                bears = False
                    if bears:
                        cells.append(c_)
            self.add("brackets:" + R.id, "bracket", cells, "trim", roof=R.id)


def _grown_pieces(fp: list, parts: list, overs: list) -> list:
    """A concave footprint grown by each edge's overhang, as disjoint
    convex pieces: the footprint's own pieces, a strip outside each edge,
    and at each outward corner the mitre between two strips."""
    n = len(fp)
    pieces = [list(p) for p in parts]
    norms = []
    for i in range(n):
        a, b = fp[i], fp[(i + 1) % n]
        L = math.dist(a, b)
        t = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
        norms.append(((t[1], -t[0]), t))
    for i in range(n):
        d = overs[i]
        if d <= 1e-9:
            continue
        a, b = fp[i], fp[(i + 1) % n]
        o = norms[i][0]
        pieces.append(ccw([a, b, (b[0] + o[0] * d, b[1] + o[1] * d), (a[0] + o[0] * d, a[1] + o[1] * d)]))
    for j in range(n):
        i = (j - 1) % n
        v = fp[j]
        a = fp[i]
        c = fp[(j + 1) % n]
        cr = (v[0] - a[0]) * (c[1] - v[1]) - (v[1] - a[1]) * (c[0] - v[0])
        if cr <= 1e-9 or (overs[i] <= 1e-9 and overs[j] <= 1e-9):
            continue
        (oi, ti), (oj, tj) = norms[i], norms[j]
        pi = (v[0] + oi[0] * overs[i], v[1] + oi[1] * overs[i])
        pj = (v[0] + oj[0] * overs[j], v[1] + oj[1] * overs[j])
        m = _hit(pi, ti, pj, tj)
        if math.dist(m, v) > 4.0 * max(overs[i], overs[j]):
            q = [v, pi, pj]
        else:
            q = [v, pi, m, pj]
        q = P.simplify(ccw(q))
        if len(q) >= 3 and abs(poly_area(q)) > 1e-6 and is_convex(q):
            pieces.append(q)
    out: list = []
    for p in pieces:
        pp = [p]
        for q in out:
            nxt = []
            for x in pp:
                nxt.extend(poly_less(x, q))
            pp = nxt
        out.extend(pp)
    out = [P.simplify(ccw(p)) for p in out if abs(poly_area(p)) > 1e-6]
    return [p for p in out if len(p) >= 3]


def _swept(p: list, v: tuple) -> list:
    """A convex polygon swept along a vector: the hull of it and its copy
    moved by v."""
    pts = [tuple(q) for q in p] + [(q[0] + v[0], q[1] + v[1]) for q in p]
    pts = sorted(set((round(x, 9), round(z, 9)) for x, z in pts))

    def cr(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lo, up = [], []
    for q in pts:
        while len(lo) >= 2 and cr(lo[-2], lo[-1], q) <= 1e-12:
            lo.pop()
        lo.append(q)
    for q in reversed(pts):
        while len(up) >= 2 and cr(up[-2], up[-1], q) <= 1e-12:
            up.pop()
        up.append(q)
    return lo[:-1] + up[:-1]


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
