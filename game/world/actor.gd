class_name Actor
extends CharacterBody3D
## An actor on the stage: a body the player's size that walks where its
## script sends it, perceives what it can see, hears what is said near
## it, and remembers who it is. Its body, its learnt actions and its
## profile are its own to rewrite (Stage keeps them on disk).
##
## A script is a list of commands, worked through in order:
##   by intention (the stage finds the way):
##     {"do": "go", "to": "<affordance, place or actor>"}
##     {"do": "climb", "stairs": "<stairs>", "to": 0.74}   0 foot .. 1 head
##     {"do": "sit", "on": "<seat>"}   {"do": "stand"}
##     {"do": "look_at", "target": "<affordance or actor>"}
##     {"do": "act", "name": "<action>"}                   built-in or learnt
##     {"do": "say", "text": "...", "secs": 4}             heard within 14 m
##     {"do": "message", "to": "<actor>", "text": "..."}  a private note
##   by body: {"do": "forward", "m": 2}, "back", {"do": "turn", "deg": 30} (left +),
##     {"do": "look", "pitch": 20} (up +), {"do": "wait", "secs": 1}
##   by the courthouse's metres (the director's): walk, path, goto, circle,
##     face, teleport, speed; see the handbook.

const EYE := 1.55
const RADIUS := 0.3
const HEIGHT := 1.8
const GRAVITY := 9.8
const ARRIVE := 0.25
const HEAR_M := 14.0
const SEE_M := 35.0

var actor_name := "actor"
var stage: Stage
var speed := 1.3
var figure: ActorFigure
var body_spec: Dictionary = {}
var learned: Dictionary = {}
var profile := ""
var inbox: Array[Dictionary] = []
var heard: Array[Dictionary] = []
var queue: Array[Dictionary] = []
var current: Dictionary = {}
var log_lines: Array[String] = []
var head_pitch := 0.0
var sitting := ""
var sit_spot := 0
## Speech over heads is drawn on its own layer, left out of the actors'
## own cameras so a line said close by never fills their view.
const SPEECH_LAYER := 1 << 19
var last_walk := {}
var _targets: Array[Vector3] = []
var _t := 0.0
var _yaw_goal := 0.0
var _say: Label3D
var _say_left := 0.0
var _stuck_check := 0.0
var _stuck_from := Vector3.ZERO
var _walk_from := Vector3.ZERO
var _walk_asked := 0.0
var _blocked := false
var _steps: AudioStreamPlayer3D
var _step_streams: Array[AudioStream] = []
var _shape: CollisionShape3D
var _settle_from := Vector3.ZERO
var _settle_to := Vector3.ZERO
var _cams: Dictionary = {}
var _talk_left := 0.0
var _wait_from := 0.0
## Whoever it is attending to, and for how long: a speaker nearby.
var _attend_to: Actor = null
var _attend_left := 0.0


func _ready() -> void:
	name = "Actor_" + actor_name
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(46.0)
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	_shape.shape = cap
	_shape.position.y = HEIGHT / 2.0
	add_child(_shape)
	figure = ActorFigure.new()
	add_child(figure)
	figure.wear(body_spec)
	_say = Label3D.new()
	_say.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_say.font_size = 44
	_say.pixel_size = 0.0042
	_say.outline_size = 14
	_say.outline_modulate = Color(0.08, 0.07, 0.12)
	_say.modulate = Color(1.0, 0.97, 0.88)
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say.width = 620.0
	_say.position.y = 2.25
	_say.no_depth_test = true
	_say.layers = SPEECH_LAYER
	_say.visible = false
	add_child(_say)
	for i in 4:
		var path := "res://audio/step_%d.wav" % i
		if ResourceLoader.exists(path):
			_step_streams.append(load(path))
	_steps = AudioStreamPlayer3D.new()
	_steps.unit_size = 4.0
	_steps.volume_db = -8.0
	add_child(_steps)


## Back to a starting mark for a take: nothing in hand, standing or
## sitting as given.
func reset_to(at: Vector3, yaw: float, seat: String) -> void:
	queue.clear()
	current = {}
	_targets.clear()
	figure.action = {}
	figure.release()
	_say_left = 0.0
	_say.visible = false
	_talk_left = 0.0
	head_pitch = 0.0
	sitting = ""
	_shape.disabled = false
	velocity = Vector3.ZERO
	place(at, yaw)
	if seat != "":
		var s := CourthouseAffordances.find(seat)
		if not s.is_empty():
			sitting = seat
			sit_spot = maxi(_free_spot(s), 0)
			_shape.disabled = true
			global_position = _spot_point(s, sit_spot)
			var sit := action_def("sit").duplicate()
			if not sit.is_empty():
				sit["name"] = "sit"
				figure.play(sit)


## Stand it somewhere, facing yaw (radians; 0 north, pi/2 west).
func place(at: Vector3, yaw: float) -> void:
	global_position = at
	rotation.y = yaw
	_yaw_goal = yaw


func wear(spec: Dictionary) -> void:
	body_spec = spec
	if figure != null:
		figure.wear(spec)


## Every action it can do: its own first, then the built-in ones.
func action_def(n: String) -> Dictionary:
	if learned.has(n):
		return learned[n]
	return ActorPresets.actions().get(n, {})


## ---- scripts ----------------------------------------------------------------

## Replace what it is doing with a new script, or add it after.
func run(commands: Array, append: bool) -> void:
	if not append:
		queue.clear()
		_finish()
	for c in commands:
		if c is Dictionary:
			queue.append(c)
	_note("script: %d commands%s" % [commands.size(), " (added)" if append else ""])


func stop() -> void:
	queue.clear()
	_finish()
	_note("stopped")


func busy() -> bool:
	return not current.is_empty() or not queue.is_empty()


func _note(line: String) -> void:
	log_lines.append("%.1f %s" % [Time.get_ticks_msec() / 1000.0, line])
	if log_lines.size() > 80:
		log_lines.remove_at(0)


func _physics_process(delta: float) -> void:
	if current.is_empty() and not queue.is_empty():
		_begin(queue.pop_front())
	var move := Vector3.ZERO
	if not current.is_empty():
		move = _step(delta)
	if sitting == "" and str(current.get("do", "")) != "_settle":
		velocity.x = move.x
		velocity.z = move.z
		if is_on_floor():
			velocity.y = -0.5
		else:
			velocity.y -= GRAVITY * delta
		move_and_slide()
	if move.length() > 0.05 and str(current.get("do", "")) != "back":
		_yaw_goal = atan2(-move.x, -move.z)
	rotation.y = lerp_angle(rotation.y, _yaw_goal, 1.0 - exp(-7.0 * delta))
	var local := global_transform.basis.inverse() * Vector3(move.x, 0, move.z)
	var grounded := is_on_floor() or sitting != ""
	if figure.pose(delta, local, grounded, deg_to_rad(head_pitch)) and not _step_streams.is_empty():
		_steps.stream = _step_streams[randi() % _step_streams.size()]
		_steps.pitch_scale = randf_range(0.9, 1.08)
		_steps.play()
	if _say_left > 0.0:
		_say_left -= delta
		if _say_left <= 0.0:
			_say.visible = false
	# The mouth works for the time the words would take to say.
	figure.talking = _say_left > 0.0 and _talk_left > 0.0
	_talk_left -= delta
	_attend(delta)


func _begin(c: Dictionary) -> void:
	current = c
	_t = 0.0
	_targets.clear()
	_stuck_check = 0.0
	_stuck_from = global_position
	_walk_from = global_position
	_blocked = false
	var what := str(c.get("do", ""))
	# Getting up comes first for anything that moves it.
	if sitting != "" and what in ["go", "climb", "sit", "walk", "path", "goto", "circle", "forward", "back", "teleport"]:
		queue.push_front(c)
		current = {"do": "stand"}
		what = "stand"
	match what:
		"go":
			var target := str(c.get("to", ""))
			var dest := _destination(target)
			if dest.is_empty():
				_fail("go: nothing here called '%s'" % target)
				return
			_targets = _plan(dest["at"], float(dest["short"]))
			if _targets.is_empty():
				_fail("go: no way to '%s' from here" % target)
				return
			_note("go %s" % target)
		"climb":
			var st := CourthouseAffordances.find(str(c.get("stairs", "")))
			if st.is_empty() or st["kind"] != "stairs":
				_fail("climb: no stairs called '%s'" % c.get("stairs", ""))
				return
			_targets = _climb(st, clampf(float(c.get("to", 1.0)), 0.0, 1.0))
		"sit":
			var seat := CourthouseAffordances.find(str(c.get("on", "")))
			if seat.is_empty() or seat["kind"] != "seat":
				_fail("sit: no seat called '%s'" % c.get("on", ""))
				return
			var spot := _free_spot(seat)
			if spot < 0:
				_fail("sit: %s is full" % seat["id"])
				return
			_targets = _plan(seat["approach"], 0.0)
			queue.push_front({"do": "_settle", "seat": seat["id"], "spot": spot})
		"_settle":
			var seat := CourthouseAffordances.find(str(c.get("seat", "")))
			var spot := int(c.get("spot", 0))
			if _free_spot(seat) < 0 or _spot_taken(seat["id"], spot):
				spot = _free_spot(seat)
			if spot < 0:
				_fail("sit: %s filled up" % seat["id"])
				return
			_settle_from = global_position
			_settle_to = _spot_point(seat, spot)
			_yaw_goal = float(seat["yaw"])
			sitting = seat["id"]
			sit_spot = spot
			_shape.disabled = true
			var sit := action_def("sit")
			if not sit.is_empty():
				figure.play(sit)
			_note("sat on " + sitting)
		"stand":
			if sitting == "":
				_finish()
				return
			var seat := CourthouseAffordances.find(sitting)
			figure.release()
			_settle_from = global_position
			_settle_to = seat.get("approach", global_position)
			current = {"do": "_rise"}
			_note("stood up from " + sitting)
		"look_at":
			var target := str(c.get("target", ""))
			var p: Variant = _point_of(target)
			if p == null:
				_fail("look_at: nothing here called '%s'" % target)
				return
			var d: Vector3 = (p as Vector3) - (global_position + Vector3(0, EYE, 0))
			_yaw_goal = atan2(-d.x, -d.z)
			head_pitch = clampf(rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())), -60.0, 70.0)
		"act", "wave", "bow", "read", "point", "nod", "shrug", "smile", "jump", "think", "shake_head":
			var n := str(c.get("name", what)) if what == "act" else what
			var a := action_def(n).duplicate()
			if a.is_empty():
				_fail("act: no action called '%s'" % n)
				return
			a["name"] = n
			figure.play(a)
		"say":
			_say.text = str(c.get("text", ""))
			_say.visible = true
			_say_left = float(c.get("secs", 2.0 + _say.text.length() * 0.07))
			_talk_left = 0.4 + _say.text.length() * 0.055
			_note("said: " + _say.text)
			if stage != null:
				stage.hear(self, _say.text, str(c.get("to", "")))
		"message":
			if stage != null:
				var ok := stage.deliver(actor_name, str(c.get("to", "")), str(c.get("text", "")))
				_note(("sent a note to " if ok else "no one to send a note to: ") + str(c.get("to", "")))
			_finish()
			return
		"forward", "back":
			var m := clampf(float(c.get("m", 1.0)), 0.0, 20.0)
			var fwd := -global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() * (1.0 if what == "forward" else -1.0)
			_walk_asked = m
			_targets.append(global_position + fwd * m)
		"turn":
			_yaw_goal = rotation.y + deg_to_rad(float(c.get("deg", 0.0)))
		"walk":
			_targets.append(_xz(c.get("to", [])))
		"path":
			for p in c.get("points", []):
				_targets.append(_xz(p))
		"goto":
			var target := CourthousePlaces.resolve(str(c.get("place", "")))
			if target == "":
				_fail("goto: no place called '%s'" % c.get("place", ""))
				return
			_targets = _plan(CourthousePlaces.NODES[target], 0.0)
		"circle":
			var ctr := _xz(c.get("center", [-22.5, 0.0]))
			var r := float(c.get("radius", 4.0))
			var laps := float(c.get("laps", 1.0))
			var sgn := -1.0 if str(c.get("dir", "ccw")) == "cw" else 1.0
			var a0 := atan2(global_position.z - ctr.z, global_position.x - ctr.x)
			var n := int(ceil(24.0 * laps))
			for k in n + 1:
				var a := a0 - sgn * TAU * laps * k / n
				_targets.append(ctr + Vector3(cos(a) * r, 0, sin(a) * r))
		"face":
			if c.has("to"):
				var p := _xz(c["to"])
				_yaw_goal = atan2(-(p.x - global_position.x), -(p.z - global_position.z))
			else:
				_yaw_goal = deg_to_rad(float(c.get("yaw", 0.0)))
		"look":
			head_pitch = clampf(float(c.get("pitch", 0.0)), -60.0, 70.0)
		"wait":
			_wait_from = Time.get_ticks_msec() / 1000.0
		"teleport":
			var v: Array = c.get("to", [])
			if v.size() >= 3:
				global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
				velocity = Vector3.ZERO
			_finish()
		"speed":
			speed = clampf(float(c.get("value", 1.3)), 0.3, 4.0)
			_finish()
		_:
			_fail("unknown command: " + JSON.stringify(c))


## A speaker near it draws its eyes: it turns its head to them while
## they talk, and turns to face them if spoken to and doing nothing else.
func notice(speaker: Actor, secs: float, addressed: bool) -> void:
	if speaker.global_position.distance_to(global_position) > 9.0:
		return
	_attend_to = speaker
	_attend_left = secs
	if addressed and current.is_empty() and queue.is_empty() and sitting == "" and not figure.busy():
		var d := speaker.global_position - global_position
		_yaw_goal = atan2(-d.x, -d.z)


func _attend(delta: float) -> void:
	var want := 0.0
	if _attend_to != null and is_instance_valid(_attend_to) and _attend_left > 0.0:
		_attend_left -= delta
		var d := _attend_to.global_position - global_position
		var fwd := -global_transform.basis.z
		var ang := Vector2(fwd.x, fwd.z).angle_to(Vector2(d.x, d.z))
		want = clampf(-ang, -1.2, 1.2)
	figure.head_turn = lerpf(figure.head_turn, want, 1.0 - exp(-5.0 * delta))


func _fail(why: String) -> void:
	_note(why)
	last_walk = {"failed": why}
	current = {}
	_targets.clear()


## Where a name points, and how far short of it to stop: an affordance,
## a place, or another actor.
func _destination(target: String) -> Dictionary:
	var a := CourthouseAffordances.find(target)
	if not a.is_empty():
		match str(a["kind"]):
			"seat":
				return {"at": a["approach"], "short": 0.0}
			"stairs":
				var path: Array = a["path"]
				var foot: Vector3 = path[0]
				var head: Vector3 = path[path.size() - 1]
				return {"at": foot if foot.distance_to(global_position) <= head.distance_to(global_position) else head, "short": 0.0}
			"door":
				return {"at": a["at"], "short": 0.0}
			"window":
				return {"at": a["at"], "short": 0.9}
		return {"at": a["at"], "short": 1.4}
	var pl := CourthousePlaces.resolve(target)
	if pl != "":
		return {"at": CourthousePlaces.NODES[pl], "short": 0.0}
	if stage != null and stage.actors.has(target) and stage.actors[target] != self:
		return {"at": (stage.actors[target] as Actor).global_position, "short": 1.2}
	return {}


## A point to look at by name.
func _point_of(target: String) -> Variant:
	var a := CourthouseAffordances.find(target)
	if not a.is_empty():
		return (a["at"] as Vector3) + Vector3(0, 0.6 if a["kind"] in ["seat", "door", "stairs"] else 0.0, 0)
	if stage != null and stage.actors.has(target):
		return (stage.actors[target] as Actor).global_position + Vector3(0, 1.55, 0)
	var pl := CourthousePlaces.resolve(target)
	if pl != "":
		return (CourthousePlaces.NODES[pl] as Vector3) + Vector3(0, 1.5, 0)
	return null


## The first free place on a seat, -1 when every place is taken.
func _free_spot(seat: Dictionary) -> int:
	for k in int(seat.get("spots", 1)):
		if not _spot_taken(seat["id"], k):
			return k
	return -1


func _spot_taken(seat: String, k: int) -> bool:
	if stage == null:
		return false
	for a: Actor in stage.actors.values():
		if a != self and a.sitting == seat and a.sit_spot == k:
			return true
	return false


func _taken(seat: String) -> int:
	var n := 0
	if stage != null:
		for a: Actor in stage.actors.values():
			if a != self and a.sitting == seat:
				n += 1
	return n


## Where place k of a seat is: spread along it, gap apart, round its middle.
func _spot_point(seat: Dictionary, k: int) -> Vector3:
	var n := int(seat.get("spots", 1))
	var yaw := float(seat["yaw"])
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	return (seat["at"] as Vector3) + right * (k - (n - 1) / 2.0) * float(seat.get("gap", 0.55))


## The walk to a point: straight when it is in plain sight on this
## floor, otherwise by the places, then straight; the last leg stops
## short by `short`.
func _plan(to: Vector3, short: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if absf(to.y - global_position.y) < 0.8 and _clear(global_position, to) and global_position.distance_to(to) < 30.0:
		out.append(to)
	else:
		var a := _visible_node(global_position)
		var b := _visible_node(to)
		if a == "" or b == "":
			return out
		for n in CourthousePlaces.route(a, b):
			out.append(CourthousePlaces.NODES[n])
		out.append(to)
	if short > 0.0 and not out.is_empty():
		# Stop `short` from the end, measured back along the way: drop the
		# points that close, then come to rest on the leg that crosses it.
		var end := out[out.size() - 1]
		out.remove_at(out.size() - 1)
		while not out.is_empty() and _flat(out[out.size() - 1], end) < short:
			out.remove_at(out.size() - 1)
		var from := global_position if out.is_empty() else out[out.size() - 1]
		var d := end - from
		d.y = 0.0
		if d.length() > short:
			out.append(end - d.normalized() * short)
	return out


## Stopped by another actor in the way: step aside to the right once
## and carry on. False when no one is in the way or it has already tried.
func _sidestep() -> bool:
	if current.get("_sidestepped", false) or stage == null or _targets.is_empty():
		return false
	var d := _targets[0] - global_position
	d.y = 0.0
	for other: Actor in stage.actors.values():
		if other == self:
			continue
		var to := other.global_position - global_position
		to.y = 0.0
		if to.length() < 1.2 and d.normalized().dot(to.normalized()) > 0.3:
			current["_sidestepped"] = true
			var right := Vector3(-d.normalized().z, 0, d.normalized().x)
			_targets.push_front(global_position + right * 0.8 + d.normalized() * 0.3)
			_note("stepped aside for " + other.actor_name)
			return true
	return false


## How near a point on the way counts as reached: the end exactly; a
## corner on the way loosely, so it is rounded rather than touched; a
## corner someone else is standing on, from further off. Sitting down,
## the last stretch to the seat is slid, so near enough will do.
func _arrive_within(p: Vector3, last: bool, what: String) -> float:
	var tol := ARRIVE if last else 0.35
	if last and what == "sit":
		tol = 0.9
	if stage != null:
		for other: Actor in stage.actors.values():
			if other != self and _flat(other.global_position, p) < 0.8:
				return maxf(tol, 1.3)
	return tol


## Whether another actor stands on the line from a to b.
func _someone_between(a: Vector3, b: Vector3) -> bool:
	if stage == null:
		return false
	for other: Actor in stage.actors.values():
		if other == self or not other.visible:
			continue
		var p := other.global_position + Vector3(0, 1.0, 0)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if (a + ab * t).distance_to(p) < 0.45:
			return true
	return false


## A camera spot pulled in toward the head if a wall stands between.
func _clear_spot(want: Vector3) -> Vector3:
	var head := global_position + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(head, want, 1, _exclude())
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return want
	var at: Vector3 = hit["position"]
	return at + (head - at).normalized() * 0.25


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The nearest place with a clear line from p, on p's floor first.
func _visible_node(p: Vector3) -> String:
	var names: Array = CourthousePlaces.NODES.keys()
	names.sort_custom(func(x: String, y: String) -> bool:
		return _node_cost(p, CourthousePlaces.NODES[x]) < _node_cost(p, CourthousePlaces.NODES[y]))
	for n: String in names.slice(0, 8):
		if _clear(p, CourthousePlaces.NODES[n]):
			return n
	return names[0] if not names.is_empty() else ""


func _node_cost(p: Vector3, q: Vector3) -> float:
	return Vector2(q.x - p.x, q.z - p.z).length() + 4.0 * absf(q.y - p.y)


## Whether a walker could see from a to b, at knee and chest height.
func _clear(a: Vector3, b: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	for h: float in [0.5, 1.3]:
		var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, h, 0), b + Vector3(0, h, 0), 1, _exclude())
		if not space.intersect_ray(q).is_empty():
			return false
	return true


func _exclude() -> Array[RID]:
	var out: Array[RID] = [get_rid()]
	if stage != null:
		for a: Actor in stage.actors.values():
			out.append(a.get_rid())
	return out


## The points of a climb: to the nearer end of the stairs, then along
## them to the share of their height asked for.
func _climb(st: Dictionary, f: float) -> Array[Vector3]:
	var path: Array = st["path"]
	var lengths: Array[float] = [0.0]
	for i in range(1, path.size()):
		lengths.append(lengths[i - 1] + (path[i] as Vector3).distance_to(path[i - 1]))
	var total := lengths[lengths.size() - 1]
	var goal := f * total
	# Where along the stairs it stands now (the nearest point).
	var here := 0.0
	var best := INF
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var ab := b - a
		var t := clampf((global_position - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := (a + ab * t).distance_to(global_position)
		if d < best:
			best = d
			here = lengths[i - 1] + ab.length() * t
	var out: Array[Vector3] = []
	if best > 1.2:
		var foot: Vector3 = path[0]
		var head: Vector3 = path[path.size() - 1]
		var end := foot if absf(goal) < absf(goal - total) or foot.distance_to(global_position) < head.distance_to(global_position) else head
		out = _plan(end, 0.0)
		here = 0.0 if end == foot else total
	# Along the path from here to the goal.
	var step := 1 if goal >= here else -1
	var pts: Array[Vector3] = []
	for k in range(path.size()):
		var l := lengths[k]
		if (step > 0 and l > here and l < goal) or (step < 0 and l < here and l > goal):
			pts.append(path[k])
	if step < 0:
		pts.reverse()
	out.append_array(pts)
	out.append(_along(path, lengths, goal))
	return out


func _along(path: Array, lengths: Array[float], s: float) -> Vector3:
	for i in range(1, path.size()):
		if s <= lengths[i]:
			var seg := lengths[i] - lengths[i - 1]
			return (path[i - 1] as Vector3).lerp(path[i], 0.0 if seg <= 0.0 else (s - lengths[i - 1]) / seg)
	return path[path.size() - 1]


## One physics step of the command in hand; returns the walk's velocity.
func _step(delta: float) -> Vector3:
	_t += delta
	var what := str(current.get("do", ""))
	if what in ["_settle", "_rise"]:
		var f := clampf(_t / (0.6 + _settle_from.distance_to(_settle_to) / 1.6), 0.0, 1.0)
		global_position = _settle_from.lerp(_settle_to, f)
		if f >= 1.0:
			if what == "_rise":
				sitting = ""
				_shape.disabled = false
			_finish()
		return Vector3.ZERO
	if not _targets.is_empty() or what in ["go", "climb", "sit", "walk", "path", "goto", "circle", "forward", "back"]:
		while not _targets.is_empty():
			var to := _targets[0] - global_position
			to.y = 0.0
			if to.length() > _arrive_within(_targets[0], _targets.size() == 1, what):
				break
			_targets.pop_front()
			_stuck_check = 0.0
			_stuck_from = global_position
		if _targets.is_empty():
			_finish()
			return Vector3.ZERO
		_stuck_check += delta
		if _stuck_check > (1.0 if what in ["forward", "back"] else 2.0):
			if global_position.distance_to(_stuck_from) < 0.25 and _sidestep():
				_stuck_check = 0.0
				_stuck_from = global_position
				return Vector3.ZERO
			if global_position.distance_to(_stuck_from) < 0.25:
				_blocked = true
				var t := _targets[0]
				_note("stuck at (%.1f, %.1f, %.1f) short of (%.1f, %.1f)" % [global_position.x, global_position.y, global_position.z, t.x, t.z])
				if what == "sit":
					queue.pop_front()   # the settle that would follow
				_finish()
				return Vector3.ZERO
			_stuck_check = 0.0
			_stuck_from = global_position
		var d := _targets[0] - global_position
		d.y = 0.0
		var v := d.normalized() * minf(speed, d.length() / maxf(delta, 0.001))
		# Keep to the right of anyone close ahead, as people do in a hall;
		# two who meet both step right and pass.
		if stage != null and v.length() > 0.05:
			var dir := v.normalized()
			var right := Vector3(-dir.z, 0, dir.x)
			for other: Actor in stage.actors.values():
				if other == self or other.sitting != "":
					continue
				var to := other.global_position - global_position
				to.y = 0.0
				var dist := to.length()
				if dist < 1.6 and absf(other.global_position.y - global_position.y) < 1.0 and dir.dot(to) > 0.0:
					v += right * speed * (1.6 - dist) * 1.4
			v = v.normalized() * minf(speed, d.length() / maxf(delta, 0.001))
		return v
	if what in ["face", "look", "turn", "look_at"]:
		if (_t > 0.4 and absf(angle_difference(rotation.y, _yaw_goal)) < 0.03) or _t > 3.0:
			_finish()
	elif what == "say":
		if not bool(current.get("wait", false)) or _t > _say_left:
			_finish()
	elif what in ["act", "wave", "bow", "read", "point", "nod", "shrug", "smile", "jump", "think", "shake_head"]:
		if not figure.busy() or bool(figure.action.get("hold", false)) or bool(figure.action.get("loop", false)):
			_finish()
	elif what == "wait":
		# A wait "until": "spoken_to" ends when someone speaks to it.
		var heard_to_me := str(current.get("until", "")) == "spoken_to" and heard.any(
			func(h: Dictionary) -> bool: return str(h.get("to", "")) == actor_name and float(h.get("at", 0.0)) >= _wait_from)
		if _t > float(current.get("secs", 1.0)) or heard_to_me:
			_finish()
	else:
		_finish()
	return Vector3.ZERO


func _finish() -> void:
	if not current.is_empty():
		var what := str(current.get("do", ""))
		if what in ["forward", "back", "go", "climb", "sit", "walk", "path", "goto", "circle"]:
			var flat := global_position - _walk_from
			var rise := flat.y
			flat.y = 0.0
			last_walk = {"moved_m": snappedf(flat.length(), 0.01), "blocked": _blocked, "climbed_m": snappedf(rise, 0.01)}
			if what in ["forward", "back"]:
				last_walk["asked_m"] = snappedf(_walk_asked, 0.01)
	current = {}
	_targets.clear()


func _xz(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 2:
		var a: Array = v
		return Vector3(float(a[0]), 0.0, float(a[a.size() - 1]))
	if v is Vector3:
		return v
	return global_position


## ---- perception ---------------------------------------------------------

## What it knows of the world just now: itself, what it can see (the
## things it can use and the other actors), what it has heard since it
## last asked, and how many notes wait for it. No coordinates.
func perceive() -> Dictionary:
	var eye := global_position + Vector3(0, EYE, 0)
	var fwd := -global_transform.basis.z
	var seen: Array[Dictionary] = []
	for a in CourthouseAffordances.all():
		var at: Vector3 = a["at"]
		var aim := at + Vector3(0, {"door": 1.2, "stairs": 0.8, "seat": 0.5}.get(a["kind"], 0.3), 0)
		var dist := eye.distance_to(aim)
		if dist > (80.0 if a["id"] == "clock_tower" else SEE_M):
			continue
		if not _sees(eye, aim):
			continue
		var entry := {"id": a["id"], "kind": a["kind"], "what": a["desc"], "distance_m": snappedf(dist, 0.1),
			"direction": _bearing(fwd, aim - eye), "height": _height(aim.y - global_position.y), "can": a["verbs"]}
		if sitting == a["id"]:
			entry["note"] = "you are sitting here"
		elif a["kind"] == "seat" and _taken(a["id"]) > 0:
			var n := _taken(a["id"])
			entry["note"] = ("%d of its %d places taken" % [n, int(a.get("spots", 1))]) if int(a.get("spots", 1)) > 1 else "someone is sitting here"
		seen.append(entry)
	seen.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["distance_m"]) < float(y["distance_m"]))
	var people: Array[Dictionary] = []
	if stage != null:
		for other: Actor in stage.actors.values():
			if other == self:
				continue
			var aim := other.global_position + Vector3(0, 1.0 if other.sitting != "" else 1.5, 0)
			if eye.distance_to(aim) > SEE_M or not _sees(eye, aim):
				continue
			var their := -other.global_transform.basis.z
			var to_me := (global_position - other.global_position).normalized()
			var facing := "toward you" if their.dot(to_me) > 0.7 else ("away from you" if their.dot(to_me) < -0.7 else "to one side")
			people.append({"name": other.actor_name, "distance_m": snappedf(eye.distance_to(aim), 0.1),
				"direction": _bearing(fwd, aim - eye), "facing": facing, "doing": other._doing_words()})
	var news: Array[Dictionary] = heard.duplicate()
	heard.clear()
	return {
		"you": {"name": actor_name, "doing": _doing_words(), "sitting_on": sitting, "looking": _pitch_words(),
			"level": _level_words(), "last_step": last_walk},
		"see": seen.slice(0, 28),
		"people": people,
		"heard": news,
		"notes_waiting": inbox.filter(func(m: Dictionary) -> bool: return not bool(m.get("read", false))).size(),
	}


func _sees(eye: Vector3, aim: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(eye, aim, 1, _exclude())
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(aim) < 0.9


func _bearing(fwd: Vector3, d: Vector3) -> String:
	var f := Vector2(fwd.x, fwd.z).normalized()
	var v := Vector2(d.x, d.z)
	if v.length() < 0.3:
		return "here"
	var ang := rad_to_deg(f.angle_to(v.normalized()))   # + clockwise seen from above: to the right
	var a := absf(ang)
	var side := "right" if ang > 0.0 else "left"
	if a < 12.0:
		return "straight ahead"
	if a < 60.0:
		return "ahead, %d degrees to the %s" % [int(round(a)), side]
	if a < 120.0:
		return "to your %s (%d degrees)" % [side, int(round(a))]
	return "behind you, to the %s (%d degrees)" % [side, int(round(a))]


func _height(dy: float) -> String:
	if dy > 2.5:
		return "well above you"
	if dy > 0.6:
		return "above you"
	if dy < -2.5:
		return "well below you"
	if dy < -0.6:
		return "below you"
	return "on your level"


func _pitch_words() -> String:
	if head_pitch > 10.0:
		return "up, %d degrees" % int(head_pitch)
	if head_pitch < -10.0:
		return "down, %d degrees" % int(-head_pitch)
	return "level"


func _level_words() -> String:
	var y := global_position.y
	if y < 0.8:
		return "at street level"
	if y < 2.5:
		return "a few steps up from the street"
	if y < 5.5:
		return "half a storey up"
	if y < 9.0:
		return "a full storey up"
	return "high up, above an upper floor"


func _doing_words() -> String:
	if sitting != "":
		return "sitting"
	var w := str(current.get("do", ""))
	if w in ["go", "walk", "path", "goto", "circle", "forward", "back", "climb"]:
		return "walking"
	if w == "act":
		return str(current.get("name", "acting"))
	if w == "say":
		return "speaking"
	if figure != null and figure.busy():
		return str(figure.action.get("name", "moving"))
	return "standing still" if w == "" else w


func director_state() -> Dictionary:
	return {
		"name": actor_name,
		"position": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
		"yaw_deg": snappedf(rad_to_deg(rotation.y), 0.1),
		"near": CourthousePlaces.nearest(global_position),
		"doing": current.get("do", ""),
		"sitting_on": sitting,
		"busy": busy(),
		"queued": queue.size(),
		"log": log_lines.slice(maxi(0, log_lines.size() - 16)),
	}


## ---- its own cameras -------------------------------------------------------

## A picture from one of its cameras ("eyes"; "follow", from behind;
## "front", facing it) saved to path. Awaitable.
func capture(which: String, path: String) -> Error:
	if not _cams.has(which):
		var v := SubViewport.new()
		v.size = Vector2i(1280, 720)
		v.render_target_update_mode = SubViewport.UPDATE_DISABLED
		v.world_3d = get_viewport().world_3d
		var cam := Camera3D.new()
		cam.fov = 70.0 if which == "eyes" else 55.0
		cam.near = 0.3 if which == "eyes" else 0.05
		cam.cull_mask &= ~SPEECH_LAYER
		v.add_child(cam)
		add_child(v)
		_cams[which] = cam
	var cam: Camera3D = _cams[which]
	var head := global_position + Vector3(0, EYE + 0.07, 0)
	var fwd := -global_transform.basis.z
	if which == "eyes":
		cam.global_transform = Transform3D(Basis(), head)
		cam.look_at(head + fwd.rotated(global_transform.basis.x, deg_to_rad(head_pitch)), Vector3.UP)
	elif which == "front":
		# From in front, or a little to one side if someone stands between.
		var spot := _clear_spot(global_position + Vector3(0, 1.6, 0) + fwd * 2.6)
		for ang: float in [0.0, 0.6, -0.6, 1.1, -1.1]:
			var try := _clear_spot(global_position + Vector3(0, 1.6, 0) + fwd.rotated(Vector3.UP, ang) * 2.6)
			if not _someone_between(try, global_position + Vector3(0, 1.3, 0)):
				spot = try
				break
		cam.global_transform = Transform3D(Basis(), spot)
		cam.look_at(global_position + Vector3(0, 1.25, 0), Vector3.UP)
	else:
		cam.global_transform = Transform3D(Basis(), _clear_spot(global_position + Vector3(0, 3.0, 0) - fwd * 5.0))
		cam.look_at(global_position + Vector3(0, 1.2, 0), Vector3.UP)
	var vp := cam.get_parent() as SubViewport
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image().save_png(path)
