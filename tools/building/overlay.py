"""Lay a building's data over its survey sheets and list where they disagree.

For each sheet the building's own lines are drawn in the sheet's frame
(see the "sheets" table in the building file): on a plan, the spaces of
its level (walls on their edges), the openings and chimneys; on the roof
plan, the roof's eaves, ridges, hips and valleys as the roof bodies make
them; on an elevation, the roof's skyline, its visible edges and the
openings facing that way. Each line is then checked against the sheet's
ink: a run of line with no ink within the tolerance is a finding, listed
with where it is in the building's feet, longest first. A score per
sheet (the share of the building's lines the drawing supports) tracks
progress.

    python tools/building/overlay.py <building> [sheet ...] [--tol 0.5] [--out dir] [--crop x0 x1 y0 y1]

Writes <out>/overlay_<building>_<sheet>.png (the sheet in grey, the data
in colour: supported in blue, unsupported in red) and prints the
findings. --crop limits the picture to a window of the sheet (sheet
feet).
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from model import Building  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
R = 20.0                     # pixels to the foot the comparison works at
OUT = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "flowstate")
OPEN_KINDS = {"porch", "balcony", "deck"}


class Sheet:
    def __init__(self, b: Building, spec: dict):
        self.spec = spec
        sd = b.data["sheets"]
        path = os.path.join(sd["dir"], spec["file"])
        im = Image.open(path).convert("L")
        ppf = float(sd.get("px_per_ft", 100))
        self.w_ft = im.width / ppf
        self.h_ft = im.height / ppf
        self.img = np.asarray(im.resize((int(self.w_ft * R), int(self.h_ft * R)), Image.LANCZOS))
        self.ink = self.img < 150
        # Distance (feet) from every pixel to the nearest ink.
        self.dist = ndimage.distance_transform_edt(~self.ink) / R

    # The sheet's feet for a building point: a plan point (x, z), or on an
    # elevation a point along the front and a height.
    def plan_to_sheet(self, x: float, z: float) -> tuple[float, float]:
        ox, oz = self.spec.get("offset", [0.0, 0.0])
        return (x - ox, z - oz)

    def elev_to_sheet(self, along: float, y: float) -> tuple[float, float]:
        return (self.spec["sign"] * along + self.spec["offset"], self.spec["ff"] - y)

    def px(self, sx: float, sy: float) -> tuple[float, float]:
        return (sx * R, sy * R)

    def dist_at(self, sx: float, sy: float) -> float:
        i, j = int(sy * R), int(sx * R)
        if 0 <= i < self.dist.shape[0] and 0 <= j < self.dist.shape[1]:
            return float(self.dist[i, j])
        return 99.0


# ---- the building's lines, per kind of sheet ------------------------------------

def plan_lines(b: Building, level: str) -> list:
    """[(label, [(x, z), ...] polyline, kind)] for a plan of `level`."""
    out = []
    spaces = b.spaces_on(level)
    for s in spaces:
        p = s["poly"]
        kind = "open" if s["kind"] in OPEN_KINDS else "wall"
        for i in range(len(p)):
            out.append((s["id"], [p[i], p[(i + 1) % len(p)]], kind))
    fl = float(b.levels[level]["floor"]) if level in b.levels else 0.0
    nxt = sorted(float(lv["floor"]) for lv in b.levels.values() if float(lv["floor"]) > fl + 1.0)
    top = nxt[0] if nxt else fl + 12.0
    for o in b.openings:
        if not (fl - 0.5 <= float(o["sill"]) < top - 0.5):
            continue
        # Across the nearest space edge, its width along it.
        best = None
        for s in spaces:
            p = s["poly"]
            for i in range(len(p)):
                a, c = p[i], p[(i + 1) % len(p)]
                d = _seg_dist(o["at"], a, c)
                if best is None or d < best[0]:
                    best = (d, a, c)
        if best is None or best[0] > 1.5:
            out.append(("opening %s" % (o["at"],), [o["at"], o["at"]], "orphan"))
            continue
        _, a, c = best
        dx, dz = c[0] - a[0], c[1] - a[1]
        L = math.hypot(dx, dz)
        ux, uz = dx / L, dz / L
        hw = float(o["w"]) / 2.0
        at = o["at"]
        out.append(("opening %.1f,%.1f" % at, [(at[0] - ux * hw, at[1] - uz * hw), (at[0] + ux * hw, at[1] + uz * hw)], "opening"))
    for ch in b.chimneys:
        if float(ch.get("base", 0)) <= fl + 1.0 <= float(ch["top"]):
            (cx, cz), (sx, sz) = ch["at"], ch["size"]
            r = [(cx - sx / 2, cz - sz / 2), (cx + sx / 2, cz - sz / 2), (cx + sx / 2, cz + sz / 2), (cx - sx / 2, cz + sz / 2)]
            for i in range(4):
                out.append(("chimney " + ch["id"], [r[i], r[(i + 1) % 4]], "chimney"))
    return out


def _seg_dist(p, a, c) -> float:
    dx, dz = c[0] - a[0], c[1] - a[1]
    L2 = dx * dx + dz * dz or 1e-9
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / L2))
    return math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dz))


def roof_edges(b: Building, res: float = 0.2):
    """The roof as drawn on a roof plan: cells where the roof changes face
    (ridges, hips, valleys) or ends (eaves, rakes)."""
    x0, x1, z0, z1 = 10.0, 170.0, 10.0, 125.0
    xs, zs, H, L = b.roof_raster(x0, x1, z0, z1, res)
    has = np.isfinite(H)
    edge = np.zeros(H.shape, dtype=bool)
    for ax in (0, 1):
        dL = np.diff(L, axis=ax) != 0
        if ax == 0:
            edge[:-1, :] |= dL
        else:
            edge[:, :-1] |= dL
    edge &= has | np.roll(has, 1, 0) | np.roll(has, 1, 1)
    return xs, zs, H, L, edge


def elevation_view(b: Building, view: str, res: float = 0.2):
    """What an elevation sees of the roof: for each position along the
    front the highest point of the roof or chimney (the skyline), and the
    roof's visible edges as (along, height) points."""
    xs, zs, H, L, edge = roof_edges(b, res)
    # Chimneys stand as blocks in the height field.
    X, Z = np.meshgrid(xs, zs, indexing="ij")
    Hc = H.copy()
    for ch in b.chimneys:
        (cx, cz), (sx, sz) = ch["at"], ch["size"]
        m = (np.abs(X - cx) <= sx / 2) & (np.abs(Z - cz) <= sz / 2)
        Hc = np.where(m, np.maximum(Hc, float(ch["top"])), Hc)
    axis = view[1]
    toward = 1 if view[0] == "+" else -1
    # along: the coordinate across the view; depth: along the view.
    if axis == "z":
        along, grid, E = xs, Hc, edge          # rows x, columns z
    else:
        along, grid, E = zs, Hc.T, edge.T      # rows z, columns x
    sky = np.max(np.where(np.isfinite(grid), grid, -1e9), axis=1)
    # Visible edge points: nothing nearer the viewer stands higher.
    g = np.where(np.isfinite(grid), grid, -1e9)
    order = slice(None, None, -1) if toward > 0 else slice(None)
    gg = g[:, order]
    ee = E[:, order]
    front = np.maximum.accumulate(gg, axis=1)
    prev = np.concatenate([np.full((gg.shape[0], 1), -1e9), front[:, :-1]], axis=1)
    vis = ee & (gg >= prev - 0.05)
    pts = [(along[i], gg[i, j]) for i, j in zip(*np.nonzero(vis))]
    return along, sky, pts


# ---- checking lines against ink --------------------------------------------------

def check_polyline(sheet: Sheet, pts_sheet: list, tol: float, step: float = 0.25):
    """Sample a polyline in sheet feet: [(sx, sy, ok)]."""
    out = []
    for i in range(len(pts_sheet) - 1):
        (ax, ay), (bx, by) = pts_sheet[i], pts_sheet[i + 1]
        L = math.hypot(bx - ax, by - ay)
        n = max(1, int(L / step))
        for k in range(n + 1):
            t = k / n
            sx, sy = ax + (bx - ax) * t, ay + (by - ay) * t
            out.append((sx, sy, sheet.dist_at(sx, sy) <= tol))
    return out


def runs_unsupported(samples, min_len: float):
    """Stretches of consecutive unsupported samples at least min_len long."""
    runs, cur = [], []
    for s in samples:
        if not s[2]:
            cur.append(s)
        else:
            if cur:
                runs.append(cur)
            cur = []
    if cur:
        runs.append(cur)
    out = []
    for r in runs:
        L = math.hypot(r[-1][0] - r[0][0], r[-1][1] - r[0][1])
        if L >= min_len:
            out.append((L, r[0], r[-1]))
    return out


def run(bname: str, only: list, tol: float, out_dir: str, crop):
    b = Building.load(bname)
    try:
        font = ImageFont.truetype("arial.ttf", 16)
    except OSError:
        font = ImageFont.load_default()
    summary = []
    for spec in b.data["sheets"]["list"]:
        if only and spec["id"] not in only:
            continue
        kind = spec["kind"]
        if kind not in ("plan", "roofplan", "elevation"):
            continue
        sheet = Sheet(b, spec)
        pic = Image.fromarray(sheet.img).convert("RGB")
        pic = Image.eval(pic, lambda v: 150 + v // 2.6)
        d = ImageDraw.Draw(pic)
        findings = []
        n_ok = n_all = 0
        if kind == "plan":
            for label, pl, lk in plan_lines(b, spec["level"]):
                sp = [sheet.plan_to_sheet(*q) for q in pl]
                if lk == "orphan":
                    x, y = sheet.px(*sp[0])
                    d.ellipse([x - 8, y - 8, x + 8, y + 8], outline=(255, 0, 255), width=3)
                    findings.append((99.0, "%s stands on no space's edge" % label))
                    continue
                if lk == "open":
                    d.line([sheet.px(*q) for q in sp], fill=(0, 160, 0), width=2)
                    continue
                samples = check_polyline(sheet, sp, tol)
                if lk == "opening":
                    # A door is a gap in the drawn wall, a window lines across
                    # it: openings are drawn, not scored.
                    d.line([sheet.px(*q) for q in sp], fill=(0, 170, 170), width=5)
                    continue
                n_all += len(samples)
                n_ok += sum(1 for s in samples if s[2])
                for (sx, sy, ok) in samples:
                    x, y = sheet.px(sx, sy)
                    col = ((0, 70, 230) if ok else (230, 0, 0)) if lk != "opening" else ((0, 170, 170) if ok else (255, 120, 0))
                    d.rectangle([x - 1, y - 1, x + 1, y + 1], fill=col)
                for L, a, c in runs_unsupported(samples, 1.0):
                    findings.append((L, "%s: %.1f ft with no line drawn, from (%.1f, %.1f) to (%.1f, %.1f)"
                                     % (label, L, a[0] + spec["offset"][0], a[1] + spec["offset"][1],
                                        c[0] + spec["offset"][0], c[1] + spec["offset"][1])))
        elif kind == "roofplan":
            xs, zs, H, L, edge = roof_edges(b)
            ii, jj = np.nonzero(edge)
            for i, j in zip(ii, jj):
                sx, sy = sheet.plan_to_sheet(xs[i], zs[j])
                ok = sheet.dist_at(sx, sy) <= tol
                n_all += 1
                n_ok += ok
                x, y = sheet.px(sx, sy)
                d.point((x, y), fill=(0, 70, 230) if ok else (230, 0, 0))
            # Unsupported roof lines, gathered into blobs.
            bad = np.zeros(edge.shape, dtype=bool)
            for i, j in zip(ii, jj):
                sx, sy = sheet.plan_to_sheet(xs[i], zs[j])
                bad[i, j] = sheet.dist_at(sx, sy) > tol
            lab, n = ndimage.label(ndimage.binary_dilation(bad, iterations=2))
            for k in range(1, n + 1):
                cells = np.nonzero((lab == k) & bad)
                if len(cells[0]) < 10:
                    continue
                x0, x1 = xs[cells[0].min()], xs[cells[0].max()]
                z0, z1 = zs[cells[1].min()], zs[cells[1].max()]
                bodies = sorted({b.bodies[v // 64].id for v in L[cells] if v >= 0})
                findings.append((len(cells[0]) * 0.2, "roof line with none drawn over x %.1f-%.1f, z %.1f-%.1f (%s)"
                                 % (x0, x1, z0, z1, ", ".join(bodies))))
        else:
            along, sky, pts = elevation_view(b, spec["view"])
            prev = None
            sky_samples = []
            for a, h in zip(along, sky):
                if h < -1e8:
                    prev = None
                    continue
                s = sheet.elev_to_sheet(a, h)
                ok = sheet.dist_at(*s) <= tol
                sky_samples.append((s[0], s[1], ok, a, h))
                x, y = sheet.px(*s)
                d.rectangle([x - 1, y - 1, x + 1, y + 1], fill=(0, 70, 230) if ok else (230, 0, 0))
            n_all += len(sky_samples)
            n_ok += sum(1 for s in sky_samples if s[2])
            for L_, a0, a1 in runs_unsupported([(s[3], s[4], s[2]) for s in sky_samples], 1.5):
                findings.append((L_, "skyline %.1f ft long with none drawn at %.1f-%.1f along, height %.1f-%.1f"
                                 % (L_, a0[0], a1[0], a0[1], a1[1])))
            for a, h in pts:
                s = sheet.elev_to_sheet(a, h)
                x, y = sheet.px(*s)
                d.point((x, y), fill=(0, 150, 255) if sheet.dist_at(*s) <= tol else (255, 140, 0))
        summary.append((spec["id"], n_ok, n_all))
        findings.sort(key=lambda f: -f[0])
        print("== %s (%s): %d of %d samples on a drawn line (%.0f%%), %d findings"
              % (spec["id"], kind, n_ok, n_all, 100.0 * n_ok / max(1, n_all), len(findings)))
        for f in findings[:40]:
            print("   ", f[1])
        if crop:
            x0, x1, y0, y1 = crop
            pic = pic.crop((int(x0 * R), int(y0 * R), int(x1 * R), int(y1 * R)))
        path = os.path.join(out_dir, "overlay_%s_%s.png" % (bname, spec["id"]))
        pic.save(path)
    return summary


def main() -> None:
    args = sys.argv[1:]
    tol, out_dir, crop = 0.5, OUT, None
    if "--tol" in args:
        i = args.index("--tol")
        tol = float(args[i + 1])
        del args[i:i + 2]
    if "--out" in args:
        i = args.index("--out")
        out_dir = args[i + 1]
        del args[i:i + 2]
    if "--crop" in args:
        i = args.index("--crop")
        crop = tuple(float(v) for v in args[i + 1:i + 5])
        del args[i:i + 5]
    run(args[0], args[1:], tol, out_dir, crop)


if __name__ == "__main__":
    main()
