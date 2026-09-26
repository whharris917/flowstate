class_name StageCamera
extends Camera3D
## The director's camera. Told what to do in plain terms, it takes over
## the screen from the player's eyes until it is released:
##   {"mode": "follow", "actor": "clerk", "distance": 4, "height": 1.8, "angle": 0}
##       behind (angle 0), beside (90 left, -90 right) or before (180) the actor
##   {"mode": "two_shot", "actors": ["a", "b"], "side": 1}
##       both in frame, from one side of the line between them
##   {"mode": "fixed", "at": [x, y, z], "look_at": "<actor, affordance or [x, y, z]>"}
##   {"mode": "orbit", "target": "<...>", "radius": 8, "height": 3, "deg_per_s": 10}
##   {"mode": "path", "points": [[x, y, z], ...], "speed": 1.5, "look_at": "<...>", "loop": false}
##       a dolly along the points at speed metres a second
##   {"mode": "player"}                                back to the player's eyes
## Any mode takes "fov" (degrees) and "cut": true to jump there at once;
## otherwise the camera glides to its new place.

var stage: Stage
var player_cam: Camera3D
var mode := "player"
var spec: Dictionary = {}
var _path_s := 0.0
var _orbit_a := 0.0
var _glide := true


func direct(s: Dictionary) -> String:
	spec = s
	mode = str(s.get("mode", "player"))
	_path_s = 0.0
	_orbit_a = deg_to_rad(float(s.get("start_deg", 0.0)))
	_glide = not bool(s.get("cut", false))
	if s.has("fov"):
		fov = clampf(float(s["fov"]), 10.0, 110.0)
	# The game's own panels stay off the director's picture.
	for layer in stage.world.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = mode == "player"
	if mode == "player":
		if player_cam != null:
			player_cam.make_current()
		return "the player's eyes"
	if not mode in ["follow", "two_shot", "fixed", "orbit", "path"]:
		mode = "player"
		return "no camera mode called '%s'" % s.get("mode", "")
	make_current()
	_update(1.0, true)
	return mode


func _process(delta: float) -> void:
	if mode != "player":
		_update(delta, false)


func _update(delta: float, first: bool) -> void:
	var goal := global_position
	var look := global_position - global_basis.z
	match mode:
		"follow":
			var a := _actor(str(spec.get("actor", "")))
			if a == null:
				return
			var back := a.global_transform.basis.z
			var ang := deg_to_rad(float(spec.get("angle", 0.0)))
			var dir := back.rotated(Vector3.UP, ang)
			goal = a.global_position + dir * float(spec.get("distance", 4.0)) + Vector3(0, float(spec.get("height", 1.8)), 0)
			look = a.global_position + Vector3(0, 1.3, 0)
		"two_shot":
			var names: Array = spec.get("actors", [])
			if names.size() < 2:
				return
			var a := _actor(str(names[0]))
			var b := _actor(str(names[1]))
			if a == null or b == null:
				return
			var mid := (a.global_position + b.global_position) / 2.0
			var line := b.global_position - a.global_position
			line.y = 0.0
			var side := Vector3.UP.cross(line).normalized() * float(spec.get("side", 1.0))
			var dist := maxf(2.8, line.length() * 1.2) * float(spec.get("distance", 1.0))
			goal = mid + side * dist + Vector3(0, 1.6, 0)
			look = mid + Vector3(0, 1.35, 0)
		"fixed":
			goal = _point(spec.get("at", [0, 5, 20]))
			look = _point(spec.get("look_at", [0, 5, 0]))
		"orbit":
			var c := _point(spec.get("target", [0, 0, 0]))
			_orbit_a += deg_to_rad(float(spec.get("deg_per_s", 10.0))) * delta
			var r := float(spec.get("radius", 8.0))
			goal = c + Vector3(cos(_orbit_a) * r, float(spec.get("height", 3.0)), sin(_orbit_a) * r)
			look = c + Vector3(0, 1.2, 0)
		"path":
			var pts: Array = spec.get("points", [])
			if pts.size() < 2:
				return
			_path_s += float(spec.get("speed", 1.5)) * (0.0 if first else delta)
			goal = _on_path(pts, _path_s, bool(spec.get("loop", false)))
			look = _point(spec.get("look_at", pts[pts.size() - 1]))
	var k := 1.0 if (first and not _glide) else 1.0 - exp(-(3.0 if mode != "path" else 12.0) * delta)
	global_position = global_position.lerp(goal, k)
	if global_position.distance_to(look) > 0.05:
		var want := global_transform.looking_at(look, Vector3.UP)
		global_basis = global_basis.slerp(want.basis, k)


func _actor(n: String) -> Actor:
	if stage != null and stage.actors.has(n):
		return stage.actors[n]
	return null


## A point from a name (an actor, an affordance, a place) or [x, y, z].
func _point(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	var n := str(v)
	var a := _actor(n)
	if a != null:
		return a.global_position + Vector3(0, 1.3, 0)
	var af := CourthouseAffordances.find(n)
	if not af.is_empty():
		return af["at"]
	var pl := CourthousePlaces.resolve(n)
	if pl != "":
		return (CourthousePlaces.NODES[pl] as Vector3) + Vector3(0, 1.5, 0)
	return Vector3.ZERO


func _on_path(pts: Array, s: float, loop: bool) -> Vector3:
	var v: Array[Vector3] = []
	for p in pts:
		v.append(_point(p))
	var total := 0.0
	for i in range(1, v.size()):
		total += v[i].distance_to(v[i - 1])
	if loop and total > 0.0:
		s = fmod(s, total)
	for i in range(1, v.size()):
		var seg := v[i].distance_to(v[i - 1])
		if s <= seg:
			return v[i - 1].lerp(v[i], s / maxf(seg, 0.001))
		s -= seg
	return v[v.size() - 1]
