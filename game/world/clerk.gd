class_name Clerk
extends CharacterBody3D
## Claude's body in the courthouse world: a studious 1880s clerk who
## walks where his script sends him. A script is a list of commands
## (ClerkLink carries them in from outside while the world runs); he
## works through them in order, each a walk, a turn, a gesture, a line
## said aloud or a wait:
##   {"do": "walk", "to": [x, z]}                 straight there
##   {"do": "path", "points": [[x, z], ...]}      through each in turn
##   {"do": "goto", "place": "courtroom"}         by the named places
##   {"do": "circle", "center": [x, z], "radius": r, "laps": 1, "dir": "ccw"}
##   {"do": "face", "to": [x, z]} or {"do": "face", "yaw": degrees}
##   {"do": "look", "pitch": degrees}             up is positive
##   {"do": "say", "text": "...", "secs": 4}      a line over his head
##   {"do": "wave" | "bow" | "read" | "point", "secs": 2}
##   {"do": "wait", "secs": 1}
##   {"do": "teleport", "to": [x, y, z]}
##   {"do": "speed", "value": 1.3}                metres a second
## x and z are the courthouse's own metres (+x east, -z north); a walk
## keeps to the floor he is on and climbs by ramps, as the player does.
## A walk that makes no headway for two seconds gives up and says so in
## the log. yaw 0 faces north, 90 west.

const EYE := 1.62
const RADIUS := 0.3
const HEIGHT := 1.8
const GRAVITY := 9.8
const ARRIVE := 0.25

var speed := 1.3
var figure: ClerkFigure
var queue: Array[Dictionary] = []
var current: Dictionary = {}
var log_lines: Array[String] = []
var head_pitch := 0.0
var _targets: Array[Vector3] = []
var _t := 0.0
var _yaw_goal := 0.0
var _turning := false
var _say: Label3D
var _say_left := 0.0
var _stuck_check := 0.0
var _stuck_from := Vector3.ZERO
var _steps: AudioStreamPlayer3D
var _step_streams: Array[AudioStream] = []
var eyes: SubViewport
var follow: SubViewport
var _eye_cam: Camera3D
var _follow_cam: Camera3D


func _ready() -> void:
	name = "Clerk"
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(46.0)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	shape.shape = cap
	shape.position.y = HEIGHT / 2.0
	add_child(shape)
	figure = ClerkFigure.new()
	add_child(figure)
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
	# Two cameras of his own, each drawing into a picture on request:
	# through his eyes, and from behind and above him.
	eyes = _viewport()
	_eye_cam = Camera3D.new()
	_eye_cam.fov = 70.0
	# Past his own spectacles and eyeshade.
	_eye_cam.near = 0.3
	eyes.add_child(_eye_cam)
	follow = _viewport()
	_follow_cam = Camera3D.new()
	_follow_cam.fov = 60.0
	follow.add_child(_follow_cam)
	_yaw_goal = rotation.y


## Stand him somewhere, facing yaw (radians; 0 north).
func place(at: Vector3, yaw: float) -> void:
	global_position = at
	rotation.y = yaw
	_yaw_goal = yaw


func _viewport() -> SubViewport:
	var v := SubViewport.new()
	v.size = Vector2i(1280, 720)
	v.render_target_update_mode = SubViewport.UPDATE_DISABLED
	v.world_3d = get_viewport().world_3d
	add_child(v)
	return v


## Replace what he is doing with a new script, or add it after.
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


func state() -> Dictionary:
	return {
		"position": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
		"yaw_deg": snappedf(rad_to_deg(rotation.y), 0.1),
		"near": CourthousePlaces.nearest(global_position),
		"on_floor": is_on_floor(),
		"doing": current.get("do", ""),
		"busy": not current.is_empty() or not queue.is_empty(),
		"queued": queue.size(),
		"speed": speed,
		"log": log_lines.slice(maxi(0, log_lines.size() - 14)),
	}


func _note(line: String) -> void:
	log_lines.append("%.1f %s" % [Time.get_ticks_msec() / 1000.0, line])
	if log_lines.size() > 60:
		log_lines.remove_at(0)


func _physics_process(delta: float) -> void:
	if current.is_empty() and not queue.is_empty():
		_begin(queue.pop_front())
	var move := Vector3.ZERO
	if not current.is_empty():
		move = _step(delta)
	# Gravity and the floor; the walk's velocity across it.
	velocity.x = move.x
	velocity.z = move.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# He turns toward where he walks, or where he was told to face.
	if move.length() > 0.05:
		_yaw_goal = atan2(-move.x, -move.z)
	rotation.y = lerp_angle(rotation.y, _yaw_goal, 1.0 - exp(-7.0 * delta))
	var local := global_transform.basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	if figure.pose(delta, local, is_on_floor(), deg_to_rad(head_pitch)) and not _step_streams.is_empty():
		_steps.stream = _step_streams[randi() % _step_streams.size()]
		_steps.pitch_scale = randf_range(0.9, 1.08)
		_steps.play()
	if _say_left > 0.0:
		_say_left -= delta
		if _say_left <= 0.0:
			_say.visible = false


func _begin(c: Dictionary) -> void:
	current = c
	_t = 0.0
	_targets.clear()
	_stuck_check = 0.0
	_stuck_from = global_position
	var what := str(c.get("do", ""))
	match what:
		"walk":
			_targets.append(_xz(c.get("to", [])))
		"path":
			for p in c.get("points", []):
				_targets.append(_xz(p))
		"goto":
			var target := CourthousePlaces.resolve(str(c.get("place", "")))
			if target == "":
				_note("goto: no place called '%s'" % c.get("place", ""))
				_finish()
				return
			var from := CourthousePlaces.nearest(global_position)
			var way := CourthousePlaces.route(from, target)
			if way.is_empty():
				_note("goto: no way from %s to %s" % [from, target])
				_finish()
				return
			for n in way:
				var q: Vector3 = CourthousePlaces.NODES[n]
				_targets.append(Vector3(q.x, 0, q.z))
			_note("goto %s: %s" % [target, " > ".join(way)])
		"circle":
			var ctr := _xz(c.get("center", [-22.5, 0.0]))
			var r := float(c.get("radius", 4.0))
			var laps := float(c.get("laps", 1.0))
			var sgn := -1.0 if str(c.get("dir", "ccw")) == "cw" else 1.0
			# Start from where he stands, round the centre.
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
		"say":
			_say.text = str(c.get("text", ""))
			_say.visible = true
			_say_left = float(c.get("secs", 2.0 + _say.text.length() * 0.07))
			_note("said: " + _say.text)
		"wave", "bow", "read", "point":
			figure.set_gesture(what)
		"wait", "teleport", "speed":
			pass
		_:
			_note("unknown command: " + JSON.stringify(c))
			_finish()
			return
	if what == "teleport":
		var v: Array = c.get("to", [])
		if v.size() >= 3:
			global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			velocity = Vector3.ZERO
		_finish()
	elif what == "speed":
		speed = clampf(float(c.get("value", 1.3)), 0.3, 4.0)
		_finish()


## One physics step of the command in hand; returns the walk's velocity.
func _step(delta: float) -> Vector3:
	_t += delta
	var what := str(current.get("do", ""))
	if what in ["walk", "path", "goto", "circle"]:
		while not _targets.is_empty():
			var to := _targets[0] - global_position
			to.y = 0.0
			if to.length() > ARRIVE:
				break
			_targets.pop_front()
			_stuck_check = 0.0
			_stuck_from = global_position
		if _targets.is_empty():
			_finish()
			return Vector3.ZERO
		# No headway for two seconds: give up this walk.
		_stuck_check += delta
		if _stuck_check > 2.0:
			if global_position.distance_to(_stuck_from) < 0.25:
				var t := _targets[0]
				_note("stuck at (%.1f, %.1f, %.1f) short of (%.1f, %.1f)" % [global_position.x, global_position.y, global_position.z, t.x, t.z])
				_finish()
				return Vector3.ZERO
			_stuck_check = 0.0
			_stuck_from = global_position
		var d := _targets[0] - global_position
		d.y = 0.0
		return d.normalized() * minf(speed, d.length() / maxf(delta, 0.001))
	var secs := float(current.get("secs", _default_secs(what)))
	if what in ["face", "look"]:
		if _t > 0.6:
			_finish()
	elif what == "say":
		if not bool(current.get("wait", false)) or _t > secs:
			_finish()
	elif _t > secs:
		_finish()
	return Vector3.ZERO


func _default_secs(what: String) -> float:
	match what:
		"wave":
			return 2.5
		"bow":
			return 1.6
		"read":
			return 4.0
		"point":
			return 2.0
	return 1.0


func _finish() -> void:
	if not current.is_empty():
		var what := str(current.get("do", ""))
		if what in ["wave", "bow", "read", "point"]:
			figure.set_gesture("")
		if what in ["walk", "path", "goto", "circle"]:
			_note("%s done at (%.1f, %.1f, %.1f)" % [what, global_position.x, global_position.y, global_position.z])
	current = {}
	_targets.clear()


func _xz(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 2:
		var a: Array = v
		return Vector3(float(a[0]), 0.0, float(a[a.size() - 1]))
	return global_position


## A picture from one of his cameras ("eyes", "follow" from behind,
## "front" facing him), saved to
## path. Awaitable.
func capture(which: String, path: String) -> Error:
	var v := eyes if which == "eyes" else follow
	var head := global_position + Vector3(0, EYE, 0)
	var fwd := -global_transform.basis.z
	if which == "eyes":
		_eye_cam.global_transform = Transform3D(Basis(), head)
		_eye_cam.look_at(head + fwd.rotated(global_transform.basis.x, deg_to_rad(head_pitch)), Vector3.UP)
	elif which == "front":
		var from := global_position + Vector3(0, 1.7, 0) + fwd * 3.2
		_follow_cam.global_transform = Transform3D(Basis(), from)
		_follow_cam.look_at(global_position + Vector3(0, 1.3, 0), Vector3.UP)
	else:
		var from := global_position + Vector3(0, 3.2, 0) - fwd * 5.5
		_follow_cam.global_transform = Transform3D(Basis(), from)
		_follow_cam.look_at(global_position + Vector3(0, 1.2, 0), Vector3.UP)
	v.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return v.get_texture().get_image().save_png(path)
