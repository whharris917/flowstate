"""Find where a photograph was taken, and lay the built model over it.

A photograph's camera is solved from a few points seen in it whose place
in the building is known (a gable's peak, a chimney's top, a corner of a
porch): given at least five (pixel x, pixel y) -> (x, z, y in the
building's feet), the camera's position, heading, tilt, roll and focal
length are fitted by least squares, the eye held above the ground when
the photograph was taken from it. The result is a probe view string for
FLOWSTATE_TW_VIEWS ("cam_<name>:<vfov>:<pos>:<target>"), and the error at
each point, which says whether the points agree.

    python tools/building/camera.py <building> <points.json> [--eye 1.6]

points.json: {"photo": path, "name": "se", "points": [[px, py, x, z, y], ...]}

With --compare after a probe run, writes <name>_side.png (photograph and
render side by side) and <name>_over.png (the render's edges in yellow
over the photograph) to the output directory, for reading by eye where
the model and the building part.
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter, ImageOps
from scipy.optimize import least_squares

sys.path.insert(0, os.path.dirname(__file__))
from model import Building  # noqa: E402

USER = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "flowstate")


def world(b: Building, x: float, z: float, y: float) -> np.ndarray:
    w = b.data["world"]
    ox, oz = w["origin"]
    ft = w.get("ft_to_m", 0.3048)
    return np.array([(z - oz) * ft, w.get("first_floor_m", 0.0) + y * ft, -(x - ox) * ft])


def rot(yaw: float, pitch: float, roll: float) -> np.ndarray:
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    cr, sr = math.cos(roll), math.sin(roll)
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    rz = np.array([[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]])
    return ry @ rx @ rz


def solve(b: Building, spec: dict, eye: float | None):
    im = Image.open(spec["photo"])
    W, H = im.size
    pts = np.array([[p[0], p[1]] for p in spec["points"]], float)
    P = np.array([world(b, p[2], p[3], p[4]) for p in spec["points"]])
    cx = W / 2.0

    def project(v):
        x, y, z, yaw, pitch, roll, f, cy = v
        R = rot(yaw, pitch, roll)
        q = (P - np.array([x, y, z])) @ R
        return np.stack([cx + f * q[:, 0] / -q[:, 2], cy - f * q[:, 1] / -q[:, 2]], 1)

    # The optical centre is the image's centre (a shifted lens is not
    # modelled): the render is square to it.
    lo = [-150, -5, -150, -10, -1, -0.3, 100, H / 2 - 0.5]
    hi = [150, 40, 150, 10, 1, 0.3, 8000, H / 2 + 0.5]
    if eye is not None:
        lo[1], hi[1] = eye - 0.01, eye + 0.01
    best = None
    centre = P.mean(axis=0)
    for ang in np.linspace(0, 2 * math.pi, 16, endpoint=False):
        start = centre + np.array([math.sin(ang) * 40, 0, math.cos(ang) * 40])
        yaw0 = math.atan2(start[0] - centre[0], start[2] - centre[2])
        v0 = [start[0], eye if eye is not None else 1.6, start[2], yaw0, 0.1, 0.0, W, H / 2]
        v0 = [min(max(a, l + 1e-3), h - 1e-3) for a, l, h in zip(v0, lo, hi)]
        r = least_squares(lambda v: (project(v) - pts).ravel(), v0, bounds=(lo, hi))
        if best is None or r.cost < best.cost:
            best = r
    v = best.x
    err = np.hypot(*(project(v) - pts).T)
    R = rot(v[3], v[4], v[5])
    C = v[:3]
    tgt = C - R[:, 2] * 20.0
    # The render is square to the image's centre line; the fitted optical
    # centre's height is carried by tilting and cropping in compare().
    vfov = 2 * math.degrees(math.atan(H / 2 / v[6]))
    view = "cam_%s:%.2f:%.2f,%.2f,%.2f:%.2f,%.2f,%.2f" % (spec["name"], vfov, *C, *tgt)
    return view, err, v, (W, H)


def compare(spec: dict, v, size, out_dir: str) -> None:
    W, H = size
    name = spec["name"]
    r = Image.open(os.path.join(USER, "probe_tw_cam_%s.png" % name)).convert("RGB")
    p = Image.open(spec["photo"]).convert("RGB")
    s = r.height / H
    x0 = r.width / 2 - (W / 2) * s
    y0 = r.height / 2 - v[7] * s
    c = r.crop((int(x0), int(y0), int(x0 + W * s), int(y0 + H * s))).resize((W, H))
    side = Image.new("RGB", (W * 2, H))
    side.paste(p, (0, 0))
    side.paste(c, (W, 0))
    side.save(os.path.join(out_dir, "%s_side.png" % name))
    edges = ImageOps.autocontrast(c.convert("L").filter(ImageFilter.FIND_EDGES)).point(lambda q: 255 if q > 60 else 0)
    o = p.copy()
    o.paste(Image.new("RGB", (W, H), (255, 255, 0)), (0, 0), edges)
    o.save(os.path.join(out_dir, "%s_over.png" % name))


def main() -> None:
    args = sys.argv[1:]
    eye = 1.6
    out = USER
    do_compare = "--compare" in args
    if do_compare:
        args.remove("--compare")
    if "--eye" in args:
        i = args.index("--eye")
        eye = None if args[i + 1] == "free" else float(args[i + 1])
        del args[i:i + 2]
    if "--out" in args:
        i = args.index("--out")
        out = args[i + 1]
        del args[i:i + 2]
    b = Building.load(args[0])
    with open(args[1], encoding="utf-8") as f:
        spec = json.load(f)
    view, err, v, size = solve(b, spec, eye)
    print(view)
    print("error at each point (px):", " ".join("%.0f" % e for e in err))
    if do_compare:
        compare(spec, v, size, out)


if __name__ == "__main__":
    main()
