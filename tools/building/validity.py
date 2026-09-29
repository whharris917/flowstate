"""Check a building as built: is it a sound, weathertight, livable shell?

Works on the geometry the game actually draws (exported by the builder
with FLOWSTATE_BLD_EXPORT=1: every triangle, tagged with what drew it),
not on the data or the drawings, so it finds what a visitor would find.
The triangles are sampled into a grid of 0.1 m cells; then:

  gap         where outside air gets inside the house's shell (over its
              plan, under its roof) with every window and door shut
  leak        with every window and door shut, outside air still reaches
              deep into a room or attic: a gap in a wall or roof that
              would let rain and wind in. Listed where the outside air
              gets in, with what is drawn round the gap.
  blocked     a window's view out is blocked close in front of it by the
              building's own parts (a roof, a wall), within 1.2 m
  intrudes    a roof, eave, cheek, gable trim, chimney or porch part
              standing inside a room's or attic's airspace
  exposed     a room's inner finish showing to the outside air
  above-roof  a wall standing up clear of any roof over it
  floating    a piece of the building joined to nothing else
  no-footing  an outer door with neither a floor, a step nor the ground
              under its threshold outside

    python tools/building/validity.py <building> [--cell 0.1] [--out dir]

Writes <out>/validity_<building>.json with every finding and its place
(plan feet and height over the datum) for photographing.
"""
from __future__ import annotations

import json
import math
import os
import sys
from collections import Counter

import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from model import Building, inside  # noqa: E402

USER = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "flowstate")
SEAL = 0
INTRUDERS = ("roof", "eave", "cheek", "gable end", "brackets", "chimney", "porch")


class Grid:
    def __init__(self, lo, hi, h):
        self.lo = np.array(lo, float)
        self.h = h
        self.shape = tuple(int(math.ceil((hi[i] - lo[i]) / h)) + 1 for i in range(3))

    def idx(self, p):
        return np.floor((np.asarray(p) - self.lo) / self.h).astype(np.int64)

    def centre(self, ijk):
        return self.lo + (np.asarray(ijk) + 0.5) * self.h

    def ok(self, ijk):
        return np.all((ijk >= 0) & (ijk < np.array(self.shape)), axis=-1)


def load(name: str):
    base = os.path.join(USER, "bld_" + name)
    tris = np.fromfile(base + "_tris.bin", dtype=np.float32).reshape(-1, 3, 3).astype(np.float64)
    tags = np.fromfile(base + "_tags.bin", dtype=np.int32)
    with open(base + ".json", encoding="utf-8") as f:
        meta = json.load(f)
    return tris, tags, meta


def sample(tris: np.ndarray, h: float):
    """Points over every triangle, no two more than h/2 apart; the index of
    the triangle each came from."""
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    longest = np.max(np.stack([np.linalg.norm(b - a, axis=1), np.linalg.norm(c - b, axis=1), np.linalg.norm(a - c, axis=1)]), axis=0)
    m = np.maximum(1, np.ceil(longest / (h * 0.45))).astype(int)
    pts, src = [], []
    for mm in np.unique(m):
        sel = np.nonzero(m == mm)[0]
        uv = [(i / mm, j / mm) for i in range(mm + 1) for j in range(mm + 1 - i)]
        uv = np.array(uv)
        A, B, C = a[sel], b[sel], c[sel]
        P = A[:, None, :] + uv[None, :, 0:1] * (B - A)[:, None, :] + uv[None, :, 1:2] * (C - A)[:, None, :]
        pts.append(P.reshape(-1, 3))
        src.append(np.repeat(sel, len(uv)))
    return np.concatenate(pts), np.concatenate(src)


def plan_of(meta, p):
    ox, oz = meta["origin"]
    ft = meta["ft"]
    return ox - p[..., 2] / ft, oz + p[..., 0] / ft


def world_y(meta, y_ft):
    return meta["datum_m"] + y_ft * meta["ft"]


def ft_y(meta, y_m):
    return (y_m - meta["datum_m"]) / meta["ft"]


def run(name: str, h: float, out_dir: str) -> int:
    tris, tags, meta = load(name)
    names = meta["tags"]
    b = Building.load(name)

    def tag_name(t: int) -> str:
        if t <= -1000000:
            return "glass"
        if t < 0:
            return "inner " + names[-t - 1]
        return names[t] if t < len(names) else "?"

    lo = tris.reshape(-1, 3).min(axis=0) - 1.0
    hi = tris.reshape(-1, 3).max(axis=0) + 1.0
    g = Grid(lo, hi, h)
    pts, src = sample(tris, h)
    ijk = g.idx(pts)
    solid = np.zeros(g.shape, dtype=bool)
    tagv = np.zeros(g.shape, dtype=np.int32)
    solid[ijk[:, 0], ijk[:, 1], ijk[:, 2]] = True
    # Exterior geometry wins a cell over an inner finish.
    order = np.argsort(tags[src] >= 0)
    tagv[ijk[order, 0], ijk[order, 1], ijk[order, 2]] = tags[src][order]
    finish = np.zeros(g.shape, dtype=bool)
    fin = tags[src] < 0
    fin &= tags[src] > -1000000
    finish[ijk[fin, 0], ijk[fin, 1], ijk[fin, 2]] = True
    exterior = solid & (tagv >= 0)

    # The ground is solid.
    gr = meta["ground"]
    G = np.array(gr["ft"], float).reshape(gr["nx"], gr["nz"])
    xs0 = g.lo[0] + (np.arange(g.shape[0]) + 0.5) * h
    zs0 = g.lo[2] + (np.arange(g.shape[2]) + 0.5) * h
    PX0, PZ0 = np.meshgrid(xs0, zs0, indexing="ij")
    gx_ = np.clip(np.round(meta["origin"][0] - PZ0 / meta["ft"] - gr["x0"]).astype(int), 0, gr["nx"] - 1)
    gz_ = np.clip(np.round(meta["origin"][1] + PX0 / meta["ft"] - gr["z0"]).astype(int), 0, gr["nz"] - 1)
    ground_m = world_y(meta, G[gx_, gz_])
    ys0 = g.lo[1] + (np.arange(g.shape[1]) + 0.5) * h
    earth = ys0[None, :, None] < ground_m[:, None, :]
    # Shut every opening on an outer wall: its rectangle, in the wall's face.
    # With --seal n the drawn surfaces are thickened by n cells first, so a
    # slope sampled onto the grid cannot let the flood through between its
    # cells: only gaps wider than about 2n+1 cells are then found.
    shut = (ndimage.binary_dilation(solid, iterations=SEAL) if SEAL else solid) | earth
    near_open = np.zeros(g.shape, dtype=bool)
    for o in meta["openings"]:
        if not o["outer"]:
            continue
        c = np.array(o["c"])
        n = np.array(o["n"])
        al = np.array(o["along"])
        w = float(o["w"])
        us = np.arange(-w / 2, w / 2 + 1e-9, h / 2)
        ys = np.arange(float(o["y0"]), float(o["yt"]) + 1e-9, h / 2)
        for depth in (-0.05, -0.15):
            P = c[None, None, :] + us[:, None, None] * al[None, None, :] + n[None, None, :] * depth
            P = np.broadcast_to(P, (len(us), len(ys), 3)).copy()
            P[..., 1] = ys[None, :]
            q = g.idx(P.reshape(-1, 3))
            q = q[g.ok(q)]
            shut[q[:, 0], q[:, 1], q[:, 2]] = True
        # The reveal and dressing round it, to leave out of the leak search.
        for depth in np.arange(-0.6, 0.61, h):
            P = c[None, None, :] + us[:, None, None] * al[None, None, :] + n[None, None, :] * depth
            P = np.broadcast_to(P, (len(us), len(ys), 3)).copy()
            P[..., 1] = ys[None, :]
            q = g.idx(P.reshape(-1, 3))
            q = q[g.ok(q)]
            near_open[q[:, 0], q[:, 1], q[:, 2]] = True
    near_open = ndimage.binary_dilation(near_open, iterations=3)

    air = ~shut
    lab, _ = ndimage.label(air)
    edge_labels = set(np.unique(np.concatenate([lab[0].ravel(), lab[-1].ravel(), lab[:, 0].ravel(), lab[:, -1].ravel(),
                                                lab[:, :, 0].ravel(), lab[:, :, -1].ravel()])))
    edge_labels.discard(0)
    outside = np.isin(lab, list(edge_labels))

    # Each cell's plan point and height over the datum.
    xs = g.lo[0] + (np.arange(g.shape[0]) + 0.5) * h
    ys = g.lo[1] + (np.arange(g.shape[1]) + 0.5) * h
    zs = g.lo[2] + (np.arange(g.shape[2]) + 0.5) * h
    PX, PZ = np.meshgrid(xs, zs, indexing="ij")
    ox, oz = meta["origin"]
    ft = meta["ft"]
    plan_x = ox - PZ / ft
    plan_z = oz + PX / ft
    yft = ft_y(meta, ys)
    # The roof over each column (feet), from the same data the builder used.
    # The roof that covers each column: a body over its own footprint, or
    # over its eaves where they stand outside every room (over a room a
    # lower roof runs on under a higher one's eaves).
    rooms_m = np.zeros(PX.shape, dtype=bool)
    for s in meta["spaces"]:
        if not s["open"]:
            rooms_m |= inside([tuple(q) for q in s["poly"]], plan_x, plan_z)
    roofH = np.full(PX.shape, -np.inf)
    for body in b.bodies:
        m = inside(body.footprint, plan_x, plan_z) | (inside(body.extent, plan_x, plan_z) & ~rooms_m)
        for hole in body.holes:
            m &= ~inside(hole, plan_x, plan_z)
        if m.any():
            roofH = np.where(m, np.maximum(roofH, body.height(plan_x, plan_z)), roofH)

    # The rooms' airspace: each enclosed space, a foot and a half in from
    # its walls, from a foot over its floor to a foot under its ceiling,
    # the floor above or the roof.
    envelope = np.zeros(g.shape, dtype=bool)
    owner = np.full(g.shape, -1, dtype=np.int32)
    spaces = [s for s in meta["spaces"] if not s["open"]]
    for si, s in enumerate(spaces):
        poly = [tuple(q) for q in s["poly"]]
        m2 = inside(poly, plan_x, plan_z)
        m2 = ndimage.binary_erosion(m2, iterations=max(1, int(1.5 * ft / h)))
        if not m2.any():
            continue
        fl = float(s["floor"])
        top = float(s["top"]) if not isinstance(s["top"], str) else 1e9
        above = np.full(PX.shape, np.inf)
        for o2 in meta["spaces"]:
            f2 = float(o2["floor"])
            if f2 > fl + 1.5:
                mo = inside([tuple(q) for q in o2["poly"]], plan_x, plan_z)
                above = np.where(mo, np.minimum(above, f2 - 1.0), above)
        ceil = np.minimum(np.minimum(above, roofH - 1.0), top - 1.0)
        for j, y in enumerate(yft):
            if y < fl + 1.0:
                continue
            mj = m2 & (y < ceil)
            if mj.any():
                envelope[:, j, :] |= mj
                owner[:, j, :] = np.where(mj, si, owner[:, j, :])

    envelope = ndimage.binary_erosion(envelope, iterations=3)
    # What stands well inside a room: half a metre clear of its bounds.
    deep = ndimage.binary_erosion(envelope, iterations=3)
    findings = []

    def place(cells):
        c = g.centre(np.mean(cells, axis=0))
        px, pz = plan_of(meta, c)
        return float(px), float(pz), float(ft_y(meta, c[1]))

    def around(cells, r=3):
        cnt = Counter()
        for q in cells[:: max(1, len(cells) // 60)]:
            sl = tuple(slice(max(0, q[i] - r), q[i] + r + 1) for i in range(3))
            for t in tagv[sl][solid[sl]].ravel():
                cnt[tag_name(int(t))] += 1
        return ", ".join(k for k, _ in cnt.most_common(4))

    # Leaks: the outside air is flooded from the grid's edge through every
    # cell that is not a room's air (the rooms' whole prisms, a little in
    # from their walls and under their roofs); a room's air cell touching
    # it is where the weather gets in.
    full = np.zeros(g.shape, dtype=bool)
    for s in spaces:
        poly = [tuple(q) for q in s["poly"]]
        m2 = inside(poly, plan_x, plan_z)
        m2 = ndimage.binary_erosion(m2, iterations=max(1, int(0.3 * ft / h)))
        fl = float(s["floor"])
        top = float(s["top"]) if not isinstance(s["top"], str) else 1e9
        above = np.full(PX.shape, np.inf)
        for o2 in meta["spaces"]:
            f2 = float(o2["floor"])
            if f2 > fl + 1.5:
                mo = inside([tuple(q) for q in o2["poly"]], plan_x, plan_z)
                above = np.where(mo, np.minimum(above, f2), above)
        ceil = np.minimum(np.minimum(above, roofH - 0.5), top - 0.2)
        for j, y in enumerate(yft):
            if y > fl - 0.5:
                full[:, j, :] |= m2 & (y < ceil)
    free = ~shut & ~full
    lab_o, _ = ndimage.label(free)
    edge_o = set(np.unique(np.concatenate([lab_o[0].ravel(), lab_o[-1].ravel(), lab_o[:, 0].ravel(), lab_o[:, -1].ravel(),
                                          lab_o[:, :, 0].ravel(), lab_o[:, :, -1].ravel()])))
    edge_o.discard(0)
    out_air = np.isin(lab_o, list(edge_o))
    leak = full & ~shut & ndimage.binary_dilation(out_air, iterations=1) & ~near_open
    # Where the outside air gets into the building: outside air inside the
    # house's shell (over its plan, under its roof) next to outside air
    # beyond the shell. One finding per gap, with what is drawn round it.
    # The shell: over the rooms' plan and under a roof's own footprint (the
    # air under an eave's overhang is outside).
    roofFP = np.full(PX.shape, -np.inf)
    for body in b.bodies:
        m = inside(body.footprint, plan_x, plan_z)
        for hole in body.holes:
            m &= ~inside(hole, plan_x, plan_z)
        if m.any():
            roofFP = np.where(m, np.maximum(roofFP, body.height(plan_x, plan_z)), roofFP)
    shell = rooms_m[:, None, :] & (yft[None, :, None] < roofFP[:, None, :] - 0.3) & ~earth
    # Over a deck, a balcony or a porch it is open air.
    for s in meta["spaces"]:
        if s["open"]:
            mo = inside([tuple(q) for q in s["poly"]], plan_x, plan_z)
            shell &= ~(mo[:, None, :] & (yft[None, :, None] > float(s["floor"]) - 0.5))
    gaps = out_air & shell & ndimage.binary_dilation(out_air & ~shell, iterations=1) & ~near_open
    lab_g, n_g = ndimage.label(gaps, structure=np.ones((3, 3, 3)))
    gap_found = []
    for k in range(1, n_g + 1):
        cells = np.argwhere(lab_g == k)
        if len(cells) < 3:
            continue
        gap_found.append(cells)
    lab2, n2 = ndimage.label(leak)
    for k in range(1, n2 + 1):
        cells = np.argwhere(lab2 == k)
        if len(cells) < 4:
            continue
        who = Counter(spaces[owner[tuple(q)]]["id"] for q in cells if owner[tuple(q)] >= 0) or Counter(["a room"])
        x, z, y = place(cells)
        findings.append({"rule": "leak", "size": int(len(cells)), "at": [x, z, y],
                         "text": "outside air reaches %d cells of %s round (%.1f, %.1f) %.1f ft up; drawn round it: %s"
                                 % (len(cells), ", ".join(w for w, _ in who.most_common(3)), x, z, y, around(cells))})

    for cells in gap_found:
        x, z, y = place(cells)
        findings.append({"rule": "gap", "size": int(len(cells)), "at": [x, z, y],
                         "text": "the outside air gets into the house round (%.1f, %.1f) %.1f ft up (%d cells); drawn round it: %s"
                                 % (x, z, y, len(cells), around(cells))})

    # Intruders into rooms' airspace.
    for t_id, tname in enumerate(names):
        if not tname.startswith(INTRUDERS):
            continue
        m = exterior & (tagv == t_id) & deep
        if tname.startswith("chimney"):
            # A chimney may rise through an attic.
            att = np.zeros(g.shape, dtype=bool)
            for si, s in enumerate(spaces):
                if s["kind"] == "attic":
                    att |= owner == si
            m &= ~att
        if m.sum() < 6:
            continue
        lab3, n3 = ndimage.label(m, structure=np.ones((3, 3, 3)))
        for k in range(1, n3 + 1):
            cells = np.argwhere(lab3 == k)
            if len(cells) < 6:
                continue
            who = Counter(spaces[owner[tuple(q)]]["id"] for q in cells)
            x, z, y = place(cells)
            findings.append({"rule": "intrudes", "size": int(len(cells)), "at": [x, z, y],
                             "text": "%s stands inside %s at (%.1f, %.1f) %.1f ft up (%d cells)"
                                     % (tname, ", ".join(w for w, _ in who.most_common(2)), x, z, y, len(cells))})

    # Inner finish exposed to the outside air.
    exposed = finish & ndimage.binary_dilation(out_air & ~near_open, iterations=1)
    lab4, n4 = ndimage.label(exposed, structure=np.ones((3, 3, 3)))
    for k in range(1, n4 + 1):
        cells = np.argwhere(lab4 == k)
        if len(cells) < 10:
            continue
        x, z, y = place(cells)
        findings.append({"rule": "exposed", "size": int(len(cells)), "at": [x, z, y],
                         "text": "a room's finish (%s) shows to the outside round (%.1f, %.1f) %.1f ft up (%d cells)"
                                 % (around(cells, 1), x, z, y, len(cells))})

    # Walls standing above every roof over them.
    for t_id, tname in enumerate(names):
        if not tname.startswith("wall "):
            continue
        m = exterior & (tagv == t_id)
        # A fin: outside air on both sides, along x or along z.
        oa = out_air
        both = np.zeros(g.shape, dtype=bool)
        for ax in (0, 2):
            fwd = np.roll(oa, 3, axis=ax)
            bwd = np.roll(oa, -3, axis=ax)
            both |= fwd & bwd
        above = m & both & ~near_open
        if above.sum() < 10:
            continue
        cells = np.argwhere(above)
        x, z, y = place(cells)
        findings.append({"rule": "above-roof", "size": int(len(cells)), "at": [x, z, y],
                         "text": "%s stands free, outside air on both sides, round (%.1f, %.1f) %.1f ft up (%d cells)" % (tname, x, z, y, len(cells))})

    # Floating pieces.
    ext = ndimage.binary_dilation(exterior, iterations=1)
    lab5, n5 = ndimage.label(ext, structure=np.ones((3, 3, 3)))
    sizes = ndimage.sum(np.ones_like(lab5), lab5, index=range(1, n5 + 1))
    main = int(np.argmax(sizes)) + 1
    for k in range(1, n5 + 1):
        if k == main or sizes[k - 1] < 4:
            continue
        cells = np.argwhere((lab5 == k) & exterior)
        if len(cells) == 0:
            continue
        # Resting on the ground is standing, not floating.
        low = g.centre(cells[np.argmin(cells[:, 1])])
        x, z, y = place(cells)
        if ft_y(meta, low[1]) < -1.5:
            continue
        findings.append({"rule": "floating", "size": int(len(cells)), "at": [x, z, y],
                         "text": "%s floats, joined to nothing, round (%.1f, %.1f) %.1f ft up (%d cells)"
                                 % (around(cells, 0), x, z, y, len(cells))})

    # Windows' views out, and doors' footing.
    for o in meta["openings"]:
        if not o["outer"]:
            continue
        c = np.array(o["c"])
        n = np.array(o["n"])
        al = np.array(o["along"])
        w = float(o["w"])
        px, pz = plan_of(meta, c)
        kind = o["kind"]
        if kind in ("win", "french"):
            hits = Counter()
            total = blocked = 0
            for u in np.linspace(-w * 0.35, w * 0.35, 3):
                for yy in np.linspace(float(o["y0"]) + 0.3, float(o["ys"]) - 0.2, 3):
                    start = c + al * u + n * 0.45
                    start[1] = yy
                    for yaw in range(-40, 41, 20):
                        for pitch in (-5, 5):
                            dvec = (n * math.cos(math.radians(yaw)) + al * math.sin(math.radians(yaw))) * math.cos(math.radians(pitch))
                            dvec = dvec + np.array([0, math.sin(math.radians(pitch)), 0])
                            total += 1
                            for step in np.arange(0.0, 1.2, h * 0.7):
                                q = g.idx(start + dvec * step)
                                if not g.ok(q) or not exterior[tuple(q)]:
                                    continue
                                tn = tag_name(int(tagv[tuple(q)]))
                                # A porch's own rails and posts, and the
                                # window's own dressing, are its view.
                                if tn.startswith("porch") or tn.startswith("dress"):
                                    continue
                                blocked += 1
                                hits[tag_name(int(tagv[tuple(q)]))] += 1
                                break
            if total and blocked / total > 0.2:
                findings.append({"rule": "blocked", "size": int(100 * blocked / total), "at": [float(px), float(pz), ft_y(meta, c[1] + 1.0)],
                                 "text": "window %d at (%.1f, %.1f), sill %.1f ft: %d%% of its view out blocked within 1.2 m by %s"
                                         % (o["id"], px, pz, ft_y(meta, float(o["y0"])), 100 * blocked / total,
                                            ", ".join(k for k, _ in hits.most_common(3)))})
        if kind in ("door", "french", "open", "shut"):
            foot = c + n * 0.8
            foot[1] = float(o["y0"]) + 0.02
            found_floor = False
            foot = c + n * 0.35
            foot[1] = float(o["y0"]) + 0.02
            for step in np.arange(0.0, 0.45, h * 0.5):
                q = g.idx(foot - np.array([0, step, 0]))
                if g.ok(q) and shut[tuple(q)]:
                    found_floor = True
                    break
            drop = float(o["y0"]) - float(o.get("ground_out", -99))
            if not found_floor and drop > 0.45:
                findings.append({"rule": "no-footing", "size": int(drop * 100), "at": [float(px), float(pz), ft_y(meta, float(o["y0"]))],
                                 "text": "door %d at (%.1f, %.1f) opens onto a drop of %.1f ft, with no floor or step outside"
                                         % (o["id"], px, pz, drop / ft)})

    # A viewpoint for each finding: outside air about 4 m from it, with a
    # clear line to it.
    oa_pts = np.argwhere(out_air[::5, ::5, ::5]) * 5
    oa_w = g.lo + (oa_pts + 0.5) * h
    for f in findings:
        x, z, y = f["at"]
        tgt = np.array([(z - meta["origin"][1]) * meta["ft"], world_y(meta, y), -(x - meta["origin"][0]) * meta["ft"]])
        dd = np.linalg.norm(oa_w - tgt, axis=1)
        order = np.argsort(np.abs(dd - 4.5))
        for k2 in order[:200]:
            e = oa_w[k2]
            if e[1] < tgt[1]:
                continue
            ok = True
            for t in np.linspace(0.1, 0.85, 12):
                q = g.idx(e + (tgt - e) * t)
                if g.ok(q) and shut[tuple(q)]:
                    ok = False
                    break
            if ok:
                px_, pz_ = plan_of(meta, e)
                f["from"] = [float(px_), float(pz_), float(ft_y(meta, e[1]))]
                break
    findings.sort(key=lambda f: (f["rule"], -f["size"]))
    for f in findings:
        print("%-11s %s" % (f["rule"], f["text"]))
    counts = Counter(f["rule"] for f in findings)
    print("%d findings: %s" % (len(findings), ", ".join("%s %d" % kv for kv in sorted(counts.items()))))
    with open(os.path.join(out_dir, "validity_%s.json" % name), "w", encoding="utf-8") as f:
        json.dump(findings, f, indent=1)
    return 1 if findings else 0


if __name__ == "__main__":
    args = sys.argv[1:]
    global_seal = 0
    h, out = 0.1, USER
    if "--cell" in args:
        i = args.index("--cell")
        h = float(args[i + 1])
        del args[i:i + 2]
    if "--seal" in args:
        i = args.index("--seal")
        SEAL = int(args[i + 1])
        del args[i:i + 2]
    if "--out" in args:
        i = args.index("--out")
        out = args[i + 1]
        del args[i:i + 2]
    sys.exit(run(args[0], h, out))
