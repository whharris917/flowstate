class_name SmallBoreUtil
## What the small-line family shares (director, 2026-09-20: "what would
## exist in a real processing plant on small-diameter lines"): the
## fitting a little line meets a device with, and the body's proportions
## at its bore. A line of DN15 and under is tubing, and tubing joins
## with compression fittings -- a hex nut over a ferrule on a threaded
## boss -- never a flange. Larger, the device wears a flange the mate
## of the line's own, like every other inline fitting.

## Bores at or under this (DN15, radius 0.021) are tube.
const TUBE_BORE := 0.0215


static func is_tube(bore_r: float) -> bool:
	return bore_r <= TUBE_BORE


## The fitting at one port face of an inline device, its face at
## `face_x` along the device's own x axis (the line meets it there),
## built into `parent` at the line's height. The compression nut is a
## six-sided cylinder, the boss under it round and threaded-looking.
static func port_end(parent: Node3D, face_x: float, line_y: float, bore_r: float,
		steel: Material) -> void:
	var side := signf(face_x)
	if is_tube(bore_r):
		var nut_r := maxf(bore_r * 2.2, 0.014)
		var nut_h := maxf(bore_r * 2.4, 0.016)
		var nut := ViewUtil.cylinder(parent, nut_r, nut_h, Vector3(face_x - side * nut_h / 2.0, line_y, 0), steel)
		(nut.mesh as CylinderMesh).radial_segments = 6
		nut.rotation_degrees = Vector3(0, 0, 90)
		var boss_h := maxf(bore_r * 1.6, 0.012)
		var boss := ViewUtil.cylinder(parent, nut_r * 0.7, boss_h,
			Vector3(face_x - side * (nut_h + boss_h / 2.0), line_y, 0), steel)
		boss.rotation_degrees = Vector3(0, 0, 90)
	else:
		var flange := ViewUtil.cylinder(parent, bore_r * 1.8, 0.045, Vector3(face_x - side * 0.0225, line_y, 0), steel)
		flange.rotation_degrees = Vector3(0, 0, 90)


## A short run of the line's bore between two faces, on the axis.
static func spool(parent: Node3D, x0: float, x1: float, line_y: float, bore_r: float,
		mat: Material) -> MeshInstance3D:
	var run := ViewUtil.cylinder(parent, bore_r, absf(x1 - x0), Vector3((x0 + x1) / 2.0, line_y, 0), mat)
	run.rotation_degrees = Vector3(0, 0, 90)
	return run


## The size the body is drawn at: the line's bore against DN50, but a
## little machine never shrinks below a quarter of its full size, or a
## DN1 valve would be a speck nobody could click.
static func body_scale(bore_r: float) -> float:
	return clampf(bore_r / 0.07, 0.25, 1.0)
