"""Is the generated building a building? Checks on the solids alone, with
no reference to any drawing or photograph.

    .venv/Scripts/python.exe tools/building/validate.py <name> [--quiet]

A building that fails any check is broken, not a draft. The invariants:

  closed        every part is a closed solid: each edge of its surface is
                met once by an edge running the other way, none shared by
                more than two faces
  overlap       no two parts share any volume (where one part meets
                another by design, the generator has already cut it)
  fitted        every face that must rest on something does, wholly: a
                wall's top on a floor or roof, its foot on a floor; a
                frame in its reveal, glass and doors in their frames;
                casings, sills and hoods backed by their wall; a post
                between floor and roof; a bracket between wall and soffit
  sealed        with windows and doors shut, no face of the inside (a
                wall's inner face, a floor, a ceiling, the roof's
                underside over rooms, a partition) can be reached from
                outside: no gap anywhere between walls, floors and roofs
  roof edges    every edge of the roof's surface is an eave (level, over a
                fascia), a rake (over a bargeboard), a ridge, a hip, a
                valley, a deck's edge, an abutment (against a wall or
                chimney) or a well's edge; anything else is a step or a
                slot and is listed
  openings      every opening lies in its wall with its casing on the
                wall's face, clear of the roof above it and of the other
                openings beside it, and glazed windows see out
  chimneys      every chimney clears the roof within 10 ft of it by 2 ft
  headroom      every enclosed room has at least 6.5 ft of it somewhere
  carried       every roof rests on walls, posts or another roof
  generation    whatever the generator could not honour (a wall with
                nothing over it)
"""
from __future__ import annotations

import math
import os
import sys
import time
from collections import defaultdict

sys.path.insert(0, os.path.dirname(__file__))

import arch
import plan as P
from solid import Cell, overlap, boxes_apart, Plane, cell, prism_planes
from surface import boundary, analyse

VOL_TOL = 2e-4          # cubic feet (about 6 cm3): smaller is not a finding
AREA_TOL = 2e-3         # square feet of face left unsupported


INTERIOR = {"inner", "floor", "ceiling", "attic", "partition"}


class Finding:
    def __init__(self, check: str, what: str, where=None):
        self.check = check
        self.what = what
        self.where = where

    def __str__(self) -> str:
        w = "" if self.where is None else " at (%s)" % ", ".join("%.1f" % v for v in self.where)
        return "%-11s %s%s" % (self.check, self.what, w)


class Validator:
    def __init__(self, m: arch.Model):
        self.m = m
        self.findings: list[Finding] = []
        self.edge_classes: list = []          # (kind, a, b) for every roof edge classified
        self.stats: dict = {}
        self.cells: list[Cell] = []
        self.owner: list[str] = []
        for e in m.elements.values():
            for c in e.cells:
                self.cells.append(c)
                self.owner.append(e.id)

    def add(self, check: str, what: str, where=None) -> None:
        self.findings.append(Finding(check, what, where))

    def run(self) -> list[Finding]:
        t = time.time()
        for n in self.m.notes:
            self.add("generation", n)
        self.closed()
        self.overlaps()
        self.surface()
        self.openings()
        self.chimneys()
        self.headroom()
        self.carried()
        self.stats["seconds"] = round(time.time() - t, 1)
        return self.findings

    # ---- closed -----------------------------------------------------------

    def closed(self) -> None:
        for e in self.m.elements.values():
            if not e.cells:
                continue
            polys, probs = boundary(e.cells)
            if probs:
                self.add("closed", "%s: two of its pieces lie on each other" % e.id, e.cells[probs[0][0]].centroid())
            rep = analyse(polys)
            for a, b, fw, bw in (rep.open_edges + rep.touching)[:3]:
                self.add("closed", "%s: an edge met %d/%d times" % (e.id, fw, bw), tuple((a + b) / 2.0))

    # ---- overlap ----------------------------------------------------------

    def _pairs(self):
        grid = defaultdict(list)
        G = 4.0
        boxes = [c.aabb() for c in self.cells]
        for i, (lo, hi) in enumerate(boxes):
            for gx in range(int(math.floor(lo[0] / G)), int(math.floor(hi[0] / G)) + 1):
                for gy in range(int(math.floor(lo[1] / G)), int(math.floor(hi[1] / G)) + 1):
                    for gz in range(int(math.floor(lo[2] / G)), int(math.floor(hi[2] / G)) + 1):
                        grid[(gx, gy, gz)].append(i)
        seen = set()
        for ids in grid.values():
            for a in range(len(ids)):
                for b in range(a + 1, len(ids)):
                    i, j = ids[a], ids[b]
                    k = (i, j) if i < j else (j, i)
                    if k in seen:
                        continue
                    seen.add(k)
                    yield k

    def overlaps(self) -> None:
        worst = {}
        n = 0
        for i, j in self._pairs():
            a, b = self.cells[i], self.cells[j]
            if boxes_apart(a, b, 1e-4):
                continue
            n += 1
            x = overlap(a, b)
            if x is None:
                continue
            v = x.volume()
            if v < VOL_TOL:
                continue
            key = tuple(sorted((self.owner[i], self.owner[j])))
            if key not in worst or v > worst[key][0]:
                worst[key] = (v, x.centroid())
        self.stats["pairs tested"] = n
        for (ea, eb), (v, at) in sorted(worst.items(), key=lambda kv: -kv[1][0]):
            self.add("overlap", "%s and %s share %.3f cu ft" % (ea, eb, v), at)

    # ---- the whole surface ------------------------------------------------

    def _role(self, poly) -> str:
        """What a face of the surface is: its plane's role, refined by what
        it belongs to."""
        eid = self.owner[poly.owner]
        e = self.m.elements[eid]
        r = poly.role
        c = poly.pts
        cx = sum(p[0] for p in c) / len(c)
        cz = sum(p[2] for p in c) / len(c)
        if e.kind == "roof":
            if r == "underside":
                R = self.m.roofs[eid.split(":", 1)[1]]
                cy = sum(p[1] for p in c) / len(c)
                if any(P.point_in((cx, cz), q) for q in R.parts) and self.m.enclosed_at(cx, cz, cy):
                    return "attic"
                return "soffit"
            return r
        if e.kind in ("wall", "cheek"):
            if r == "inner":
                # a room behind it, or only a porch or the air
                n = poly.n
                cy = sum(p[1] for p in c) / len(c)
                if not self.m.enclosed_at(cx + n[0] * 0.3, cz + n[2] * 0.3, cy):
                    return "inner_open"
            return r
        if e.kind == "partition":
            return "partition"
        if e.kind == "slab":
            sp = self.m.space.get(e.info.get("space"), {})
            if sp.get("open"):
                if r in ("bottom", "underside"):
                    cy = sum(p[1] for p in c) / len(c)
                    return "ceiling" if self.m.enclosed_at(cx, cz, cy - 0.5) else "deck_under"
                return {"top": "deck_top"}.get(r, "deck_edge")
            if r == "top":
                # a doorway's threshold, under the wall's thickness, is neither
                cx_, cz_ = cx, cz
                for run in self.m.runs:
                    if run.kind != "wall":
                        continue
                    u, sv = run.uv((cx_, cz_))
                    if -run.thick - 1e-3 <= sv <= 1e-3 and -1e-3 <= u <= run.length + 1e-3:
                        return "threshold"
                return "floor"
            if r in ("bottom", "underside"):
                return "ceiling"
            return "slab_edge"
        return e.kind + ":" + r

    def surface(self) -> None:
        polys, probs = boundary(self.cells)
        seen = set()
        for ci, cj, a in probs:
            key = tuple(sorted((self.owner[ci], self.owner[cj])))
            if key in seen:
                continue
            seen.add(key)
            self.add("overlap", "%s and %s have faces lying on each other (%.2f sq ft)" % (key[0], key[1], a),
                     self.cells[ci].centroid())
        rep = analyse(polys)
        self.polys, self.rep = polys, rep
        self.stats["surface faces"] = len(polys)
        for a, b, fw, bw in rep.open_edges[:10]:
            self.add("closed", "the building's surface is open along an edge (%d/%d)" % (fw, bw), tuple((a + b) / 2.0))
        # fitted: faces that must rest on something
        must = {
            "wall": {"top", "bottom", "underside"},
            "partition": {"top", "bottom", "underside"},
            "frame": {"fit"}, "glass": {"side"},
            "casing": {"back"}, "hood": {"back"}, "sill": {"back"},
            "bracket": {"back", "seat"},
            "post": {"underside"},
        }
        loose = defaultdict(float)
        where = {}
        for poly in polys:
            eid = self.owner[poly.owner]
            e = self.m.elements[eid]
            req = must.get(e.kind)
            if not req or poly.role not in req:
                continue
            a = _area(poly.pts)
            if a > AREA_TOL:
                key = (eid, poly.role)
                loose[key] += a
                where.setdefault(key, tuple(sum(p) / len(poly.pts) for p in zip(*poly.pts)))
        for (eid, role), a in sorted(loose.items(), key=lambda kv: -kv[1]):
            if a < 0.01:
                continue
            self.add("fitted", "%s: %.2f sq ft of its %s rests on nothing" % (eid, a, role), where[(eid, role)])
        # sealed: no room's floor can be reached from outside; finish: no
        # inside face shows to the weather. The way in is traced from the
        # roof's top faces along the surface to the first inside faces.
        vols = rep.shell_volume
        if vols:
            outer = max(range(len(vols)), key=lambda k: vols[k])
            oset = set(rep.shells[outer])
            self.stats["shells"] = len(vols)
            roles = {pi: self._role(polys[pi]) for pi in oset}
            floors = [pi for pi in oset if roles[pi] == "floor"]
            inside = [pi for pi in oset if roles[pi] in INTERIOR]
            adj = defaultdict(list)
            for pi, pj, a, b in rep.pairs:
                if pi in oset and pj in oset:
                    adj[pi].append((pj, (a + b) / 2.0))
                    adj[pj].append((pi, (a + b) / 2.0))
            start = [pi for pi in oset if roles[pi] in ("slope", "deck") and
                     self.m.elements[self.owner[polys[pi].owner]].kind == "roof"]
            import collections
            # breadth first from the roof; each face remembers where its
            # path last crossed from an outside face to an inside one
            seen = {pi: None for pi in start}
            door = {pi: None for pi in start}
            dq = collections.deque(start)
            first = []
            while dq:
                i = dq.popleft()
                if roles[i] in INTERIOR and not floors:
                    first.append(i)
                    continue
                for j, at in adj[i]:
                    if j not in seen:
                        seen[j] = at
                        door[j] = door[i] if roles[i] in INTERIOR else (at, j)
                        dq.append(j)
            if floors:
                first = [i for i in floors if i in door]
            spots = []
            for i in first:
                d_ = door.get(i) if floors else (seen[i], i)
                if d_ is None or d_[0] is None:
                    continue
                at, j = d_
                if any(sum((at[k] - q[0][k]) ** 2 for k in range(3)) < 9.0 for q in spots):
                    continue
                spots.append((at, j))
            check = "sealed" if floors else "finish"
            what = ("the rooms are open to the outside here: %s meets the outside"
                    if floors else "an inside finish shows to the weather: %s")
            for at, i in spots[:30]:
                self.add(check, what % ("%s's %s" % (self.owner[polys[i].owner], roles[i])), tuple(at))
            self.stats["floors reached from outside"] = len(floors)
        self.roof_edges(polys, rep)

    def _opening_part(self, pi) -> bool:
        return self.m.elements[self.owner[self.polys[pi].owner]].kind in ("frame", "glass", "door")

    # ---- roof edges -------------------------------------------------------

    def roof_edges(self, polys, rep) -> None:
        import numpy as np
        counts = defaultdict(int)
        bad = []
        for pi, pj, a, b in rep.pairs:
            ri, rj = self._role(polys[pi]), self._role(polys[pj])
            ei, ej = self.m.elements[self.owner[polys[pi].owner]], self.m.elements[self.owner[polys[pj].owner]]
            top_i = ei.kind == "roof" and ri in ("slope", "deck")
            top_j = ej.kind == "roof" and rj in ("slope", "deck")
            if not (top_i or top_j):
                continue
            if not top_i:
                pi, pj, ri, rj, ei, ej, top_i, top_j = pj, pi, rj, ri, ej, ei, top_j, top_i
            d = b - a
            L = float(np.linalg.norm(d))
            if L < 1e-4:
                continue
            level = abs(d[1]) / L < 1e-3
            if top_j:
                ni, nj = polys[pi].n, polys[pj].n
                if float(np.dot(ni, nj)) > 1 - 1e-9:
                    kind = "seam"
                else:
                    cj = sum(polys[pj].pts) / len(polys[pj].pts)
                    convex = float(np.dot(ni, cj - a)) < 0
                    flat_i = ri == "deck" or abs(ni[1]) > 1 - 1e-6
                    flat_j = rj == "deck" or abs(nj[1]) > 1 - 1e-6
                    if flat_i or flat_j:
                        kind = "deck edge" if level else None
                    elif level:
                        kind = "ridge" if convex else None
                    else:
                        kind = "hip" if convex else "valley"
                    if kind is None:
                        bad.append(("a level trough between two roof faces", (a + b) / 2.0))
                        continue
            elif ej.kind == "roof" and ej is not ei and rj in ("fascia", "rake"):
                kind = "abutment"
            elif ej.kind == "roof" and ej is not ei and rj == "soffit":
                kind = "tuck"
            elif rj == "fascia":
                kind = "eave" if level else None
                if kind is None:
                    bad.append(("an eave that is not level", (a + b) / 2.0))
                    continue
            elif rj == "rake":
                kind = "rake"
            elif rj == "hole":
                kind = "well"
            elif ej.kind in ("wall", "cheek", "chimney", "slab") or rj in ("chimney_joint",):
                kind = "abutment"
            elif rj == "soffit" or rj == "underside" or rj == "attic":
                bad.append(("a roof face meets the underside of %s" % ej.id, (a + b) / 2.0))
                continue
            else:
                bad.append(("a roof face of %s meets %s of %s" % (ei.id, rj, ej.id), (a + b) / 2.0))
                continue
            counts[kind] += 1
            self.edge_classes.append((kind, a, b))
        self.stats["roof edges"] = dict(counts)
        seen = set()
        for what, at in bad:
            key = (what, tuple(round(v, 0) for v in at))
            if key in seen:
                continue
            seen.add(key)
            self.add("roof edges", what, tuple(at))

    # ---- openings ---------------------------------------------------------

    def openings(self) -> None:
        m = self.m
        idx = defaultdict(list)
        for i, o in enumerate(self.owner):
            idx[o].append(i)
        roofs = [i for i, o in enumerate(self.owner) if m.elements[o].kind == "roof"]
        for op in m.openings:
            oid = op["id"]
            run = op["run"]
            if run.kind == "partition":
                continue
            own = {oid + s for s in (":frame", ":glass", ":leaf", ":casing", ":hood", ":sill", ":rail")}
            # clear of the roof: 0.2 ft over the hood
            hood = m.elements.get(oid + ":hood")
            if hood and hood.cells:
                hc = hood.cells[0]
                lo, hi = hc.aabb()
                probe = cell(prism_planes([(lo[0], lo[2]), (hi[0], lo[2]), (hi[0], hi[2]), (lo[0], hi[2])], hi[1], hi[1] + 0.2))
                for i in roofs:
                    if overlap(probe, self.cells[i]) is not None:
                        self.add("openings", "%s (at %s): its hood is within 0.2 ft of %s" % (oid, _at(op), self.owner[i]),
                                 hc.centroid())
                        break
            # sees out: 1.5 ft in front of the glass
            if op["kind"] not in ("door", "idoor", "ishut"):
                s1 = run.s_range()[1]
                us = [q[0] for q in op["prof"]]
                ys = [q[1] for q in op["prof"]]
                probe = arch.run_cell(run, arch.rect(min(us) + 0.3, max(us) - 0.3, min(ys) + 0.3, max(ys) - 0.3), s1 + 0.15, s1 + 0.5)
                if probe is not None:
                    for i, c in enumerate(self.cells):
                        if self.owner[i] in own or boxes_apart(probe, c):
                            continue
                        x = overlap(probe, c)
                        if x is not None and x.volume() > 0.01:
                            self.add("openings", "%s (at %s): %s stands in front of it" % (oid, _at(op), self.owner[i]),
                                     x.centroid())
                            break

    # ---- chimneys ---------------------------------------------------------

    def chimneys(self) -> None:
        for ch in self.m.data.get("chimneys", []):
            import model as M
            cx, cz = M.expand_point(ch["at"])
            top = float(ch["top"])
            sx, sz = ch["size"]
            worst = -1e9
            for R in self.m.roofs.values():
                for i in range(5):
                    for j in range(5):
                        p = (cx - sx / 2 + sx * i / 4, cz - sz / 2 + sz * j / 4)
                        if any(P.point_in(p, q) for q in R.extent_parts):
                            worst = max(worst, R.top(*p))
            if worst > -1e8 and top < worst + 2.0:
                self.add("chimneys", "chimney %s: top %.1f is %.1f ft over the roof it passes through (needs 2)"
                         % (ch["id"], top, top - worst), (cx, top, cz))

    # ---- headroom ---------------------------------------------------------

    def headroom(self) -> None:
        m = self.m
        for s in m.spaces:
            if s["open"]:
                continue
            poly = s["poly"]
            xs = [q[0] for q in poly]
            zs = [q[1] for q in poly]
            best = -1e9
            for i in range(9):
                for j in range(9):
                    p = (min(xs) + (max(xs) - min(xs)) * (i + 0.5) / 9, min(zs) + (max(zs) - min(zs)) * (j + 0.5) / 9)
                    if not P.point_in(p, poly):
                        continue
                    over = 1e9
                    for (q, bottom, top, lv, sid) in m.slab_plan:
                        if bottom > s["floor"] + 0.5 and P.point_in(p, q):
                            over = min(over, bottom)
                    rtop = -1e9
                    for R in m.roofs.values():
                        if any(P.point_in(p, q) for q in R.parts):
                            rtop = max(rtop, R.top(*p) - R.t)
                    h = min(over, rtop) - s["floor"]
                    best = max(best, h)
            if best < 6.5:
                self.add("headroom", "%s: at most %.1f ft of headroom" % (s["id"], best))

    # ---- carried ----------------------------------------------------------

    def carried(self) -> None:
        polys = self.polys
        touching = defaultdict(set)
        for pi, pj, a, b in self.rep.pairs:
            oi, oj = self.owner[polys[pi].owner], self.owner[polys[pj].owner]
            if oi != oj:
                touching[oi].add(oj)
                touching[oj].add(oi)
        # contact through faces removed from the surface: any two cells
        # whose faces lie on each other
        for i, j in self._pairs():
            oi, oj = self.owner[i], self.owner[j]
            if oi == oj or oj in touching[oi]:
                continue
            if _touch(self.cells[i], self.cells[j]):
                touching[oi].add(oj)
                touching[oj].add(oi)
        for e in self.m.elements.values():
            if e.kind != "roof" or not e.cells:
                continue
            ok = any(self.m.elements[o].kind in ("wall", "cheek", "post", "roof", "chimney") for o in touching[e.id])
            if not ok:
                self.add("carried", "%s rests on nothing" % e.id)

    # ---- slivers ----------------------------------------------------------

    def slivers(self) -> None:
        for i, c in enumerate(self.cells):
            e = self.m.elements[self.owner[i]]
            if e.kind in ("glass",):
                continue
            vs = c.vset()
            thin = min(max(pl.d - (pl.n[0] * p[0] + pl.n[1] * p[1] + pl.n[2] * p[2]) for p in vs) for pl in c.planes)
            if thin < 0.03:
                self.add("slivers", "%s: a piece %.3f ft thick" % (e.id, thin), c.centroid())

    def report(self, quiet: bool = False) -> str:
        lines = []
        by = defaultdict(list)
        for f in self.findings:
            by[f.check].append(f)
        for check in ("generation", "closed", "overlap", "fitted", "sealed", "finish", "roof edges", "openings", "chimneys",
                      "headroom", "carried"):
            fs = by.get(check, [])
            lines.append("%-11s %s" % (check, "ok" if not fs else "%d finding%s" % (len(fs), "s" if len(fs) > 1 else "")))
            if not quiet:
                for f in fs[:25]:
                    lines.append("    " + str(f))
                if len(fs) > 25:
                    lines.append("    ... %d more" % (len(fs) - 25))
        lines.append("stats: %s" % self.stats)
        return "\n".join(lines)


def _area(pts) -> float:
    import numpy as np
    s = np.zeros(3)
    for i in range(len(pts)):
        s += np.cross(pts[i], pts[(i + 1) % len(pts)])
    return float(np.linalg.norm(s)) / 2.0


def _touch(a: Cell, b: Cell) -> bool:
    if boxes_apart(a, b, -1e-4):
        return False
    for f in a.faces:
        pl = a.planes[f.plane]
        for g in b.faces:
            ql = b.planes[g.plane]
            if pl.n[0] * ql.n[0] + pl.n[1] * ql.n[1] + pl.n[2] * ql.n[2] < -1 + 1e-9 and abs(pl.d + ql.d) < 1e-5:
                return True
    return False


def _at(op) -> str:
    run = op["run"]
    p = run.plan(op["u"], 0.0)
    return "%.1f, %.1f, sill %.1f" % (p[0], p[1], op["sill"])


def main(argv: list[str]) -> int:
    name = argv[1] if len(argv) > 1 else "twain"
    path = name if name.endswith(".json") else os.path.join(arch.M.ROOT, "game", "data", "buildings", name + ".json")
    t = time.time()
    m = arch.load(path).generate()
    gen = time.time() - t
    v = Validator(m)
    v.run()
    v.stats["generate seconds"] = round(gen, 1)
    v.stats["cells"] = len(v.cells)
    v.stats["parts"] = len(m.elements)
    print(v.report("--quiet" in argv))
    return 1 if v.findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
