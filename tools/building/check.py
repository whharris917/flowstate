"""Check a building's data against the rules any building keeps.

Works on the data alone (no rendering, a few seconds), so a building can
be checked after every edit. Each finding names the rule, the space or
opening, and where it is in the building's feet:

  overlap     two spaces on one level cover the same floor
  gap         floor inside a level's outline that no space covers
  no-roof     part of an enclosed space with nothing over it (no roof, no
              space above)
  through-roof  part of a room's floor above the roof over it
  low-roof    a room most of whose floor has under 6 ft over it (attics
              and closets excepted)
  window-room a window between two enclosed spaces, or on no space's edge
  above-roof  an opening whose head stands above the roof over its wall
  no-level    an opening whose sill is on no level that has a space there
  chimney-room a chimney standing in a room's floor rather than in a wall
  chimney-low a chimney whose top does not clear the roof by 2 ft
  roof-over-nothing a roof body over no space
  sunk-gable  a gable whose eave is lower than the roof beside it on the
              same wall: the neighbouring eave runs across its face
  unsupported a roof body whose wall line runs where no wall or post is
  deck-headroom a porch or deck under a roof less than 6 ft over its floor
  window-ceiling / window-floor  an opening reaching over its room's
              ceiling or under its floor
  roof-crosses a roof crossing a window or door just outside it
  porch-over-room / porch-gap  a porch, deck or balcony over a room's floor,
              or with an edge standing short of the wall it runs along

    python tools/building/check.py <building> [--res 0.25]

Exits non-zero when anything is found, so it can stand in a script.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from model import Building, inside  # noqa: E402

OPEN = {"porch", "balcony", "deck", "canopy"}
LOW_OK = {"attic", "closet", "void"}


def blobs(mask: np.ndarray, xs, zs, res: float, min_area: float):
    lab, n = ndimage.label(mask)
    out = []
    for k in range(1, n + 1):
        cells = np.nonzero(lab == k)
        area = len(cells[0]) * res * res
        if area < min_area:
            continue
        out.append((area, xs[cells[0]].min(), xs[cells[0]].max(), zs[cells[1]].min(), zs[cells[1]].max()))
    return sorted(out, reverse=True)


def run(bname: str, res: float) -> int:
    b = Building.load(bname)
    found = []
    x0, x1, z0, z1 = 10.0, 170.0, 10.0, 125.0
    xs, zs, H, LB = b.roof_raster(x0, x1, z0, z1, res)
    X, Z = np.meshgrid(xs, zs, indexing="ij")
    masks = {}
    for s in b.spaces:
        masks[s["id"]] = inside(s["poly"], X, Z)
    levels = sorted(b.levels.values(), key=lambda lv: float(lv["floor"]))
    # Tiling of each level.
    for lv in levels:
        here = [s for s in b.spaces if s["level"] == lv["id"]]
        enclosed = [s for s in here if s["kind"] not in OPEN]
        count = np.zeros(X.shape, dtype=np.int32)
        for s in enclosed:
            count += masks[s["id"]]
        for area, ax0, ax1, az0, az1 in blobs(count > 1, xs, zs, res, 0.5):
            who = [s["id"] for s in enclosed if masks[s["id"]][(X >= ax0) & (X <= ax1) & (Z >= az0) & (Z <= az1)].any()]
            found.append(("overlap", "%s: %.1f sq ft covered twice over x %.1f-%.1f, z %.1f-%.1f (%s)"
                          % (lv["id"], area, ax0, ax1, az0, az1, ", ".join(who))))
        filled = ndimage.binary_fill_holes(count > 0)
        for area, ax0, ax1, az0, az1 in blobs(filled & (count == 0), xs, zs, res, 1.0):
            found.append(("gap", "%s: %.1f sq ft inside the outline in no space, over x %.1f-%.1f, z %.1f-%.1f"
                          % (lv["id"], area, ax0, ax1, az0, az1)))
    # What is over each space.
    for s in b.spaces:
        m = masks[s["id"]]
        fl = float(s["floor"])
        if s.get("top") == "roof" and s["kind"] not in OPEN:
            # The builder stops such a room at a knee wall where the roof
            # comes within 3 ft of its floor.
            m = m & ~(np.isfinite(H) & (H < fl + 3.0))
        over_space = np.full(X.shape, np.inf)
        for o in b.spaces:
            fo = float(o["floor"])
            if fo > fl + 1.5:
                over_space = np.where(masks[o["id"]], np.minimum(over_space, fo), over_space)
        # A roof counts over the space even where it comes down to the floor
        # at the eaves (headroom is the next rule).
        roof_over = np.where(H > fl - 1.0, H, np.inf)
        cover = np.minimum(over_space, roof_over)
        if s["kind"] in OPEN and "deck-headroom" in s.get("exempt", {}):
            continue
        if s["kind"] in OPEN:
            under_roof = m & np.isfinite(roof_over) & (roof_over < over_space)
            low = under_roof & (roof_over < fl + 6.0)
            for area, ax0, ax1, az0, az1 in blobs(low, xs, zs, res, 3.0):
                found.append(("deck-headroom", "%s: the roof %.1f sq ft of it stands under 6 ft over its floor, x %.1f-%.1f, z %.1f-%.1f"
                              % (s["id"], area, ax0, ax1, az0, az1)))
            continue
        for area, ax0, ax1, az0, az1 in blobs(m & ~np.isfinite(cover), xs, zs, res, 1.0):
            found.append(("no-roof", "%s: %.1f sq ft with nothing over it, x %.1f-%.1f, z %.1f-%.1f"
                          % (s["id"], area, ax0, ax1, az0, az1)))
        # The roof over a room coming down below its floor: the room would
        # stand out through the roof there.
        through = ndimage.binary_erosion(m, iterations=max(1, int(1.0 / res))) & np.isfinite(H) & (H > fl - 12.0) & (H < fl + 0.5) & ~np.isfinite(over_space)
        for area, ax0, ax1, az0, az1 in blobs(through, xs, zs, res, 2.0):
            found.append(("through-roof", "%s: %.1f sq ft of its floor stand above the roof there, x %.1f-%.1f, z %.1f-%.1f"
                          % (s["id"], area, ax0, ax1, az0, az1)))
        if s["kind"] not in LOW_OK:
            # Headroom: under the roof (or the floor above), inside the
            # walls (a foot in from the space's edge).
            # A room under slopes may be low at its sides; it is wrong when
            # most of it is.
            core = ndimage.binary_erosion(m, iterations=max(1, int(1.2 / res)))
            low = core & (cover < fl + 6.0)
            if core.sum() and low.sum() > 0.4 * core.sum():
                found.append(("low-roof", "%s: %.0f%% of its floor has under 6 ft over it"
                              % (s["id"], 100.0 * low.sum() / core.sum())))
    # Porches, decks and balconies against the house: their inner edges on
    # the walls' outer faces, never short of them (a strip no one owns, a
    # railing along the wall) nor over them.
    for s in b.spaces:
        if s["kind"] not in OPEN:
            continue
        fl = float(s["floor"])
        rooms = [o for o in b.spaces if o["kind"] not in OPEN and abs(float(o["floor"]) - fl) < 3.0]
        both = masks[s["id"]].copy()
        cover = np.zeros(X.shape, dtype=bool)
        for o in rooms:
            cover |= masks[o["id"]]
        for area, ax0, ax1, az0, az1 in blobs(both & cover, xs, zs, res, 1.0):
            found.append(("porch-over-room", "%s covers %.1f sq ft of a room's floor, x %.1f-%.1f, z %.1f-%.1f"
                          % (s["id"], area, ax0, ax1, az0, az1)))
        p = s["poly"]
        for i in range(len(p)):
            a0, c0 = p[i], p[(i + 1) % len(p)]
            if math.hypot(c0[0] - a0[0], c0[1] - a0[1]) < 0.5:
                continue
            def wall_gap(q):
                return min((min(_seg_dist(q, o["poly"][j], o["poly"][(j + 1) % len(o["poly"])]) for j in range(len(o["poly"])))
                            for o in rooms), default=99.0)
            # Along its whole length: an edge running beside a wall, not one
            # that ends at the wall.
            gaps = [wall_gap((a0[0] + (c0[0] - a0[0]) * t, a0[1] + (c0[1] - a0[1]) * t)) for t in (0.1, 0.5, 0.9)]
            gap = max(gaps)
            if all(0.15 < g < 2.0 for g in gaps):
                found.append(("porch-gap", "%s's edge (%.1f, %.1f)-(%.1f, %.1f) stands %.1f ft off a wall"
                              % (s["id"], a0[0], a0[1], c0[0], c0[1], gap)))
    # Openings.
    floors = sorted({float(s["floor"]) for s in b.spaces})
    for o in b.openings:
        at = o["at"]
        sill = float(o["sill"])
        kind = o.get("kind", "win")
        # The spaces whose edge it stands on, at its sill's level.
        near = []
        for s in b.spaces:
            fl = float(s["floor"])
            reach = 30.0 if s.get("top") == "roof" else 11.5
            if not (fl - 1.0 <= sill < fl + reach or (kind in ("idoor", "ishut", "door", "open", "shut", "french") and abs(sill - fl) < 1.0)):
                continue
            p = s["poly"]
            d = min(_seg_dist(at, p[i], p[(i + 1) % len(p)]) for i in range(len(p)))
            if d < 1.2:
                near.append(s)
        tag = "opening at (%.1f, %.1f), %s %.1f-%.1f" % (at[0], at[1], kind, sill, float(o["head"]))
        if not near:
            # A dormer's window: on a roof body's footprint edge, over a space.
            on_cheek = any(min(_seg_dist(at, bd.footprint[i], bd.footprint[(i + 1) % len(bd.footprint)])
                               for i in range(len(bd.footprint))) < 1.2 for bd in b.bodies)
            under = any(inside(s["poly"], np.array([at[0]]), np.array([at[1]]))[0] or
                        min(_seg_dist(at, s["poly"][i], s["poly"][(i + 1) % len(s["poly"])]) for i in range(len(s["poly"]))) < 3.0
                        for s in b.spaces if float(s["floor"]) < sill)
            if not (on_cheek and under):
                found.append(("no-level", tag + ": on no space's edge at its height"))
            continue
        enclosed = [s for s in near if s["kind"] not in OPEN]
        # Within the storey it lights: its head under the room's ceiling,
        # its sill over the floor.
        head = float(o["head"])
        dormer = any(min(_seg_dist(at, bd.footprint[i], bd.footprint[(i + 1) % len(bd.footprint)])
                         for i in range(len(bd.footprint))) < 1.2 and bd.kind == "gable" and float(bd.spec.get("eave", 0)) < head
                     for bd in b.bodies)
        for s in enclosed:
            fl = float(s["floor"])
            if not (fl - 1.0 <= sill <= fl + 9.0):
                continue
            if s["top"] != "roof" and head > float(s["top"]) + 0.2 and not dormer:
                found.append(("window-ceiling", tag + ": its head is above %s's ceiling (%.1f)" % (s["id"], float(s["top"]))))
            if sill < fl - 0.2 and kind not in ("idoor", "ishut"):
                found.append(("window-floor", tag + ": its sill is under %s's floor (%.1f)" % (s["id"], fl)))
        # No roof crosses it outside: the roof just outside the wall stands
        # under its sill or over its head.
        if kind not in ("idoor", "ishut"):
            best = None
            for s in b.spaces:
                p = s["poly"]
                for i in range(len(p)):
                    a0, c0 = p[i], p[(i + 1) % len(p)]
                    d0 = _seg_dist(at, a0, c0)
                    if best is None or d0 < best[0]:
                        best = (d0, a0, c0, s)
            if best is not None and best[0] < 1.2:
                _, a0, c0, s = best
                dx, dz = c0[0] - a0[0], c0[1] - a0[1]
                L = math.hypot(dx, dz) or 1.0
                nx, nz = dz / L, -dx / L
                # Outward: away from the space the edge belongs to.
                test = (np.array([at[0] + nx * 0.6]), np.array([at[1] + nz * 0.6]))
                if inside(s["poly"], *test)[0]:
                    nx, nz = -nx, -nz
                for u in (-0.35, 0.0, 0.35):
                    ex = at[0] + nx * 1.0 + (dx / L) * float(o["w"]) * u
                    ez = at[1] + nz * 1.0 + (dz / L) * float(o["w"]) * u
                    i = int((ex - x0) / res)
                    j = int((ez - z0) / res)
                    if 0 <= i < H.shape[0] and 0 <= j < H.shape[1] and np.isfinite(H[i, j]):
                        top_eff = head - (float(o["w"]) * 0.3 if o.get("shape") == "round" else 0.0)
                        if sill + 0.3 < H[i, j] < top_eff + 0.25:
                            found.append(("roof-crosses", tag + ": a roof (%.1f ft) crosses it just outside" % H[i, j]))
                            break
        # A space counts on the far side only where its cover stands above
        # the window's sill: a dormer's window looks out over the roof.
        def covers(s):
            i = int((at[0] - x0) / res)
            j = int((at[1] - z0) / res)
            r0 = int(1.0 / res)
            win = H[max(0, i - r0):i + r0 + 1, max(0, j - r0):j + r0 + 1]
            return not np.isfinite(win).any() or float(np.min(win)) > sill or s["top"] != "roof"
        enclosed = [s for s in enclosed if covers(s)]
        if kind == "win" and len(enclosed) >= 2 and len({s["group"] for s in enclosed}) == 1:
            found.append(("window-room", tag + ": a window between %s" % " and ".join(s["id"] for s in enclosed)))
        # Above the roof over its wall.
        i = int((at[0] - x0) / res)
        j = int((at[1] - z0) / res)
        r = int(1.0 / res)
        win = H[max(0, i - r):i + r + 1, max(0, j - r):j + r + 1]
        top_roof = np.max(win) if np.isfinite(win).any() else -np.inf
        if np.isfinite(top_roof) and float(o["head"]) > top_roof + 0.3 and kind not in ("idoor", "ishut"):
            found.append(("above-roof", tag + ": its head is above the roof over its wall (%.1f)" % top_roof))
    # Chimneys.
    for ch in b.chimneys:
        (cx, cz), (sx, sz) = ch["at"], ch["size"]
        base, top = float(ch.get("base", 0.0)), float(ch["top"])
        cm = (np.abs(X - cx) <= sx / 2) & (np.abs(Z - cz) <= sz / 2)
        for s in b.spaces:
            if s["kind"] in OPEN or s["kind"] in LOW_OK or not (base < float(s["floor"]) + 1.0 < top):
                continue
            # A breast may stand 2 ft into a room from its wall.
            core = ndimage.binary_erosion(masks[s["id"]], iterations=max(1, int(2.0 / res)))
            hit = (cm & core).sum() * res * res
            if hit > 3.0:
                found.append(("chimney-room", "chimney %s stands %.1f sq ft into %s's floor" % (ch["id"], hit, s["id"])))
        rt = np.max(np.where(cm, H, -np.inf))
        if np.isfinite(rt) and top < rt + 2.0:
            found.append(("chimney-low", "chimney %s tops out at %.1f, the roof round it at %.1f" % (ch["id"], top, rt)))
    # A gable or dormer stands out of the roof it rises from: at its front
    # the roof beside it on the same wall comes no higher than its own eave
    # (else the gable is sunk behind the neighbouring eave, which then runs
    # across its face).
    def h_at(x, z):
        i = int((x - x0) / res)
        j = int((z - z0) / res)
        if 0 <= i < H.shape[0] and 0 <= j < H.shape[1] and np.isfinite(H[i, j]):
            return float(H[i, j])
        return -np.inf
    for bd in b.bodies:
        if bd.kind != "gable" or bd.trim != "gable":
            continue
        e = float(bd.spec["eave"])
        fxs = [q[0] for q in bd.footprint]
        fzs = [q[1] for q in bd.footprint]
        exs = [q[0] for q in bd.extent]
        ezs = [q[1] for q in bd.extent]
        ax = bd.spec["axis"]
        # The ends of the ridge are the fronts; the sides run along it.
        ends = [(min(fzs), -1), (max(fzs), 1)] if ax == "z" else [(min(fxs), -1), (max(fxs), 1)]
        for pos, sgn in ends:
            # A front: just outside it is outside the building.
            mid = (pos + sgn * 0.8, (min(fzs) + max(fzs)) / 2) if ax == "x" else ((min(fxs) + max(fxs)) / 2, pos + sgn * 0.8)
            if any(inside(sp["poly"], np.array([mid[0]]), np.array([mid[1]]))[0] for sp in b.spaces if sp["kind"] not in OPEN):
                continue
            for side in (-1, 1):
                if ax == "z":
                    q = ((max(exs) + 0.8) if side > 0 else (min(exs) - 0.8), pos - sgn * 0.5)
                else:
                    q = (pos - sgn * 0.5, (max(ezs) + 0.8) if side > 0 else (min(ezs) - 0.8))
                on_wall = any(min(_seg_dist(q, sp["poly"][j], sp["poly"][(j + 1) % len(sp["poly"])]) for j in range(len(sp["poly"]))) < 1.2
                              for sp in b.spaces if sp["kind"] not in OPEN)
                hn = h_at(*q)
                i = int((q[0] - x0) / res)
                j = int((q[1] - z0) / res)
                who = b.bodies[LB[i, j] // 64] if 0 <= i < LB.shape[0] and 0 <= j < LB.shape[1] and LB[i, j] >= 0 else None
                if on_wall and who is not None and who.kind != "gable" and hn > e + 0.8:
                    found.append(("sunk-gable", "gable %s: beside its front the roof stands at %.1f, over its own eave (%.1f), at (%.1f, %.1f)"
                                  % (bd.id, hn, e, q[0], q[1])))
    # Every roof body is carried: each point of its footprint's outline
    # (its wall line) stands on a space's edge (a wall, or a porch's posts)
    # or inside a space; anything else hangs in the air.
    for bd in b.bodies:
        if bd.spec.get("exempt", {}).get("unsupported"):
            continue
        fp = bd.footprint
        loose = []
        for i in range(len(fp)):
            a0, c0 = fp[i], fp[(i + 1) % len(fp)]
            L = math.hypot(c0[0] - a0[0], c0[1] - a0[1])
            for k in range(max(1, int(L / 2.0)) + 1):
                t = k / max(1, int(L / 2.0))
                q = (a0[0] + (c0[0] - a0[0]) * t, a0[1] + (c0[1] - a0[1]) * t)
                carried = False
                for s in b.spaces:
                    p = s["poly"]
                    if inside(p, np.array([q[0]]), np.array([q[1]]))[0] or \
                            min(_seg_dist(q, p[j], p[(j + 1) % len(p)]) for j in range(len(p))) < 1.5:
                        carried = True
                        break
                if not carried:
                    loose.append(q)
        if loose:
            xs_ = [q[0] for q in loose]
            zs_ = [q[1] for q in loose]
            found.append(("unsupported", "roof %s: %d points of its wall line stand on nothing, x %.1f-%.1f, z %.1f-%.1f"
                          % (bd.id, len(loose), min(xs_), max(xs_), min(zs_), max(zs_))))
    # Roofs over nothing.
    anyspace = np.zeros(X.shape, dtype=bool)
    for s in b.spaces:
        anyspace |= masks[s["id"]]
    for bi, body in enumerate(b.bodies):
        mb = inside(body.footprint, X, Z)
        if not (mb & anyspace).any() and "roof-over-nothing" not in body.spec.get("exempt", {}):
            found.append(("roof-over-nothing", "roof %s stands over no space" % body.id))
    for rule, text in found:
        print("%-18s %s" % (rule, text))
    print("%d findings" % len(found))
    return 1 if found else 0


def _seg_dist(p, a, c) -> float:
    dx, dz = c[0] - a[0], c[1] - a[1]
    L2 = dx * dx + dz * dz or 1e-9
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / L2))
    return math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dz))


if __name__ == "__main__":
    args = sys.argv[1:]
    res = 0.25
    if "--res" in args:
        i = args.index("--res")
        res = float(args[i + 1])
        del args[i:i + 2]
    sys.exit(run(args[0], res))
