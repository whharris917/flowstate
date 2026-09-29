"""Find parts of a building that pass through each other.

Every triangle the builder draws carries a tag naming the part it belongs
to (FLOWSTATE_BLD_EXPORT=1): "roof <body>", "eave <body>" (fascia and
trim along a roof's edges), "gable end <body>" (bargeboards, king post,
finial), "brackets <body>", "cheek <body>", "wall <kind> <space>",
"dress <opening>", "chimney <id>", "porch <space>" (posts, rails, plates,
skirts), "floor <space>", "steps", and the rooms' finishes. Two parts
penetrate when an edge of one crosses a face of the other and runs on
more than DEPTH beyond it on both sides: parts that only touch, or meet
along a shared line (two roof faces in a valley, a wall under a roof),
do not count.

Not every penetration is a fault: a wall's top runs into its roof's
thickness, walls overlap at their corners, a window's casing stands in
its wall, a chimney rises through the roof. So each pair of kinds of
part is ruled allowed or not (ALLOWED below); everything else found is
listed, grouped by the pair of parts, with where it is:

  trim through another body's roof or trim (gutters and bargeboards of
  two gables crossing), trim through a chimney, a window, a porch;
  a roof through another body's roof (not meeting along a valley), a
  window, a porch's rails; a rail or post through a wall's face or a
  window; anything outside through a room's finish.

    python tools/building/penetration.py <building> [--depth 0.03]
"""
from __future__ import annotations

import json
import os
import sys
from collections import defaultdict

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from validity import load, plan_of, ft_y  # noqa: E402

DEPTH = 0.03       # metres an edge must run on past a face, both sides
CELL = 0.5


def kind_of(name: str) -> tuple[str, str]:
    """(kind, owner) of a tag: the kind of part and whose it is."""
    for k in ("gable end", "roof", "eave", "brackets", "cheek", "chimney", "porch", "floor", "dress", "finish"):
        if name.startswith(k + " "):
            return k, name[len(k) + 1:]
    if name.startswith("wall "):
        return "wall", name.split(" ", 2)[-1]
    if name == "steps":
        return "steps", ""
    if name == "glass":
        return "glass", ""
    if name.startswith("inner "):
        return "inner", name[6:]
    return "other", name


TRIM = {"eave", "gable end", "brackets"}


def allowed(ka: str, oa: str, kb: str, ob: str) -> bool:
    """Whether parts of kinds ka (of owner oa) and kb (of ob) may pass into
    each other."""
    pair = {ka, kb}
    if ka == kb and oa == ob:
        return True
    # Masonry and the things built into it.
    if pair <= {"wall", "cheek", "chimney", "floor", "steps"}:
        return True
    if "dress" in pair and pair & {"wall", "cheek"}:
        return True
    # A wall's or cheek's top runs into the roof's thickness; a chimney
    # rises through it.
    if "roof" in pair and pair & {"wall", "cheek", "chimney"}:
        return True
    # Trim and roof of the same body are made together; trim is fixed to
    # the wall under it.
    if pair & TRIM and "roof" in pair and oa == ob:
        return True
    if pair <= TRIM and oa == ob:
        return True
    if pair & TRIM and pair & {"wall", "cheek"}:
        return True
    # A porch's posts stand on its floor and carry its roof; its plate and
    # rails run to the house's walls.
    if "porch" in pair and pair & {"wall", "floor", "steps", "roof", "eave"}:
        return True
    if "inner" in pair and pair & {"wall", "floor", "inner", "cheek", "dress"}:
        return True
    # A window's panes sit in its sash, in the wall's opening; the casings
    # of windows set close together share their mullions.
    if "glass" in pair and pair & {"dress", "wall", "cheek", "glass"}:
        return True
    if pair == {"dress"}:
        return True
    return False


def tri_edge_cross(A: np.ndarray, B: np.ndarray, depth: float) -> np.ndarray:
    """For pairs (A[i], B[i]) of triangles (n, 3, 3): whether an edge of A
    crosses the face of B, running on past it by `depth` on both sides."""
    n0 = np.cross(B[:, 1] - B[:, 0], B[:, 2] - B[:, 0])
    nl = np.linalg.norm(n0, axis=1)
    ok = nl > 1e-9
    nrm = n0 / np.where(ok, nl, 1.0)[:, None]
    hit = np.zeros(len(A), dtype=bool)
    for e0, e1 in ((0, 1), (1, 2), (2, 0)):
        p = A[:, e0]
        q = A[:, e1]
        dp = np.einsum("ij,ij->i", p - B[:, 0], nrm)
        dq = np.einsum("ij,ij->i", q - B[:, 0], nrm)
        cross = (dp * dq < 0) & (np.abs(dp) > depth) & (np.abs(dq) > depth)
        t = dp / np.where(cross, dp - dq, 1.0)
        x = p + (q - p) * t[:, None]
        # Inside B, and not within `depth` of its edges.
        inside = np.ones(len(A), dtype=bool)
        for f0, f1 in ((0, 1), (1, 2), (2, 0)):
            ed = B[:, f1] - B[:, f0]
            c = np.cross(ed, x - B[:, f0])
            s = np.einsum("ij,ij->i", c, nrm)
            el = np.linalg.norm(ed, axis=1)
            inside &= s > depth * el
        hit |= cross & inside & ok
    return hit


def run(name: str, depth: float) -> int:
    tris, tags, meta = load(name)
    names = meta["tags"]

    def tag_name(t: int) -> str:
        if t <= -1000000:
            return "glass"
        if t < 0:
            return "inner " + names[-t - 1]
        return names[t] if t < len(names) else "other"

    uniq = np.unique(tags)
    kinds = {int(t): kind_of(tag_name(int(t))) for t in uniq}
    # Bin triangles by the grid cells their bounding boxes touch.
    lo = tris.min(axis=1)
    hi = tris.max(axis=1)
    base = tris.reshape(-1, 3).min(axis=0)
    ilo = np.floor((lo - base) / CELL).astype(np.int64)
    ihi = np.floor((hi - base) / CELL).astype(np.int64)
    cells = defaultdict(list)
    for i in range(len(tris)):
        for x in range(ilo[i, 0], ihi[i, 0] + 1):
            for y in range(ilo[i, 1], ihi[i, 1] + 1):
                for z in range(ilo[i, 2], ihi[i, 2] + 1):
                    cells[(x, y, z)].append(i)
    pa, pb = [], []
    for members in cells.values():
        if len(members) < 2:
            continue
        m = np.array(members)
        tg = tags[m]
        if len(np.unique(tg)) < 2:
            continue
        ii, jj = np.triu_indices(len(m), 1)
        diff = tg[ii] != tg[jj]
        pa.append(m[ii[diff]])
        pb.append(m[jj[diff]])
    if not pa:
        print("0 findings")
        return 0
    pa = np.concatenate(pa)
    pb = np.concatenate(pb)
    key = np.unique(np.minimum(pa, pb) * len(tris) + np.maximum(pa, pb))
    pa = key // len(tris)
    pb = key % len(tris)
    # Only pairs of kinds not allowed to pass into each other.
    keep = np.array([not allowed(*kinds[int(tags[a])], *kinds[int(tags[b])]) for a, b in zip(pa, pb)], dtype=bool)
    pa, pb = pa[keep], pb[keep]
    # Bounding boxes overlap.
    ov = np.all((lo[pa] <= hi[pb]) & (lo[pb] <= hi[pa]), axis=1)
    pa, pb = pa[ov], pb[ov]
    hits = np.zeros(len(pa), dtype=bool)
    step = 200000
    for s in range(0, len(pa), step):
        A = tris[pa[s:s + step]]
        B = tris[pb[s:s + step]]
        hits[s:s + step] = tri_edge_cross(A, B, depth) | tri_edge_cross(B, A, depth)
    pa, pb = pa[hits], pb[hits]
    groups = defaultdict(list)
    for a, b in zip(pa, pb):
        ta, tb = tag_name(int(tags[a])), tag_name(int(tags[b]))
        k = tuple(sorted((ta, tb)))
        groups[k].append((tris[a].mean(axis=0) + tris[b].mean(axis=0)) / 2)
    out = []
    for (ta, tb), pts in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        c = np.mean(pts, axis=0)
        px, pz = plan_of(meta, c)
        y = ft_y(meta, c[1])
        out.append({"rule": "penetrates", "size": len(pts), "at": [float(px), float(pz), float(y)],
                    "text": "%s passes through %s round (%.1f, %.1f) %.1f ft up (%d crossings)" % (ta, tb, px, pz, y, len(pts))})
        print("%-11s %s" % ("penetrates", out[-1]["text"]))
    print("%d findings" % len(out))
    user = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "flowstate")
    with open(os.path.join(user, "penetration_%s.json" % name), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    return 1 if out else 0


if __name__ == "__main__":
    args = sys.argv[1:]
    dp = DEPTH
    if "--depth" in args:
        i = args.index("--depth")
        dp = float(args[i + 1])
        del args[i:i + 2]
    sys.exit(run(args[0], dp))
