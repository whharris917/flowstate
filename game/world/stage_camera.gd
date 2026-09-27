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
##   {"mode": "auto"}   a camera operator of its own: on whoever speaks,
##       over the listener's shoulder or facing them; on whoever walks,
##       following; the group wide when all are still. It cuts, holding
##       each shot at least a few seconds.
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
## The auto operator's shot: {kind, a, b}, how long held, and whether the
## last one ended in a cut.
var _shot: Dictionary = {}
var _held := 0.0
var _cut_now := false
const MIN_SHOT := 2.6
const SPEECH_LAYER := 1 << 19


## Lines over heads off the picture (a take's subtitles carry them).
func hide_speech(on: bool) -> void:
	if on:
		cull_mask &= ~SPEECH_LAYER
	else:
		cull_mask |= SPEECH_LAYER


func direct(s: Dictionary) -> String:
	spec = s
	mode = str(s.get("mode", "player"))
	_path_s = 0.0
	_orbit_a = deg_to_rad(float(s.get("start_deg", 0.0)))
	_glide = not bool(s.get("cut", false))
	if s.has("fov"):
		fov = clampf(float(s["fov"]), 10.0, 110.0)
	# The game's own panels stay off the director's picture (a take's
	# subtitles and cards excepted).
	for layer in stage.world.find_children("*", "CanvasLayer", true, false):
		if layer.name != "Subtitles":
			(layer as CanvasLayer).visible = mode == "player"
	if mode == "player":
		if player_cam != null:
			player_cam.make_current()
		return "the player's eyes"
	if not mode in ["follow", "two_shot", "fixed", "orbit", "path", "auto"]:
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
		"auto":
			var r := _auto(delta)
			if r.is_empty():
				return
			goal = r["at"]
			look = r["look"]
			if _cut_now:
				_cut_now = false
				global_position = goal
				if goal.distance_to(look) > 0.05:
					look_at_from_position(goal, look, Vector3.UP)
				return
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


## The auto operator: decide what to look at, then where to stand.
func _auto(delta: float) -> Dictionary:
	_held += delta
	var cast: Array[Actor] = []
	for a: Actor in stage.actors.values():
		if a.visible:
			cast.append(a)
	if cast.is_empty():
		return {}
	var now := stage.clock
	var want := {}
	var sp := stage.last_speaker
	var speaking := sp != null and is_instance_valid(sp) and sp.visible and (sp._say_left > 0.0 or now - stage.last_said_at < 1.5)
	if speaking:
		var listener := _nearest(sp, cast)
		if listener != null and listener.global_position.distance_to(sp.global_position) < 7.0:
			want = {"kind": "over" if randi() % 3 != 0 else "two", "a": sp, "b": listener}
		else:
			want = {"kind": "single", "a": sp}
	else:
		for a in cast:
			if a._doing_words() == "walking":
				want = {"kind": "follow", "a": a}
				break
		# Someone performing an action: a medium shot on them, facing.
		if want.is_empty():
			for a in cast:
				if a.figure.busy() and a.sitting == "" and str(a.figure.action.get("name", "")) != "sit":
					want = {"kind": "medium", "a": a}
					break
		if want.is_empty():
			want = {"kind": "wide"}
	var same: bool = not _shot.is_empty() and want.get("kind") == _shot.get("kind") and want.get("a") == _shot.get("a") \
		or (want.get("kind") in ["over", "two"] and _shot.get("kind") in ["over", "two"] and want.get("a") == _shot.get("a"))
	if _shot.is_empty() or (not same and _held > MIN_SHOT):
		_shot = want
		_held = 0.0
		_cut_now = true
	return _frame(_shot, cast)


func _nearest(to: Actor, cast: Array[Actor]) -> Actor:
	var best: Actor = null
	var d := INF
	for a in cast:
		if a != to and a.global_position.distance_to(to.global_position) < d:
			d = a.global_position.distance_to(to.global_position)
			best = a
	return best


## Where to stand and what to look at for a shot.
func _frame(shot: Dictionary, cast: Array[Actor]) -> Dictionary:
	var a: Actor = shot.get("a")
	var b: Actor = shot.get("b")
	if a != null and not is_instance_valid(a):
		return {}
	var head := func(x: Actor) -> Vector3: return x.global_position + Vector3(0, 1.0 if x.sitting != "" else 1.5, 0)
	match str(shot.get("kind", "wide")):
		"over":
			if b == null or not is_instance_valid(b):
				return {}
			var d: Vector3 = head.call(a) - head.call(b)
			d.y = 0.0
			var right := Vector3(-d.normalized().z, 0, d.normalized().x)
			return {"at": _unblocked(head.call(a), head.call(b) - d.normalized() * 1.1 + right * 0.55 + Vector3(0, 0.15, 0)), "look": head.call(a)}
		"two":
			if b == null or not is_instance_valid(b):
				return {}
			var mid: Vector3 = (head.call(a) + head.call(b)) / 2.0
			var line := b.global_position - a.global_position
			line.y = 0.0
			var side := Vector3.UP.cross(line).normalized()
			if side.dot(-a.global_transform.basis.z - b.global_transform.basis.z) < 0.0:
				side = -side
			return {"at": _unblocked(mid, mid + side * maxf(2.6, line.length() * 1.3) + Vector3(0, 0.2, 0)), "look": mid}
		"single":
			var f := -a.global_transform.basis.z
			return {"at": _unblocked(head.call(a), head.call(a) + f * 2.4 + a.global_transform.basis.x * 0.5 + Vector3(0, 0.05, 0)), "look": head.call(a)}
		"medium":
			var fm := -a.global_transform.basis.z
			var mid_at: Vector3 = a.global_position + Vector3(0, 1.1, 0)
			return {"at": _unblocked(mid_at, mid_at + fm * 3.6 + a.global_transform.basis.x * 0.9 + Vector3(0, 0.35, 0)), "look": mid_at}
		"follow":
			var back := a.global_transform.basis.z
			var dir := back.rotated(Vector3.UP, 0.45)
			return {"at": _unblocked(head.call(a), a.global_position + dir * 4.0 + Vector3(0, 2.0, 0)), "look": head.call(a)}
	# Wide: the whole cast, from beside the line they stand along, on the
	# side with the clearer view (the side they face when both are clear).
	var c := Vector3.ZERO
	for x in cast:
		c += x.global_position
	c /= cast.size()
	var spread := 0.0
	var far_a := cast[0].global_position
	var far_b := cast[0].global_position
	for x in cast:
		for y in cast:
			if x.global_position.distance_to(y.global_position) > far_a.distance_to(far_b):
				far_a = x.global_position
				far_b = y.global_position
	spread = far_a.distance_to(far_b)
	var line := far_b - far_a
	line.y = 0.0
	var side := Vector3.UP.cross(line).normalized() if line.length() > 0.3 else Vector3(0, 0, 1)
	var face := Vector3.ZERO
	for x in cast:
		face += -x.global_transform.basis.z
	var dist := clampf(3.4 + spread * 0.9, 3.4, 10.0)
	var eye := c + Vector3(0, 1.3, 0)
	var best := side
	var best_room := -1.0
	for s: Vector3 in [side, -side]:
		var want := eye + s * dist + Vector3(0, 0.4, 0)
		var got := _unblocked(eye, want)
		var room := eye.distance_to(got) + (0.5 if s.dot(face) > 0.0 else 0.0)
		if room > best_room:
			best_room = room
			best = s
	var at := eye + best * dist + Vector3(0, 0.4, 0)
	return {"at": _unblocked(eye, at), "look": c + Vector3(0, 1.1, 0)}


## A camera spot pulled in toward the subject if something solid stands
## between.
func _unblocked(subject: Vector3, want: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(subject, want, 1)
	var ex: Array[RID] = []
	for a: Actor in stage.actors.values():
		ex.append(a.get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return want
	var p: Vector3 = hit["position"]
	return p + (subject - p).normalized() * 0.3


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
