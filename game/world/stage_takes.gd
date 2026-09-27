class_name StageTakes
extends Node
## Takes: a performance on the stage recorded as it happens and played
## back, live or rendered to film.
##
## A take is JSON: the hour, the cast as they stood at the start (where,
## facing, on what seat), and events at times from the start: an actor's
## commands (as it was sent them), a camera direction, a title card. It
## is recorded from the live stage (start, then every /do and /camera,
## then stop), or written by hand as a screenplay in the same form. On
## saving, the stretches where no one was doing anything (the actors
## thinking between moves) are cut down to a beat, so the take plays at
## the pace of the scene rather than of the thinking.
##   {"title", "hour", "subtitles": true, "camera": {...},
##    "cast": [{"name", "at": [x, y, z], "yaw_deg", "sitting_on"}],
##    "events": [{"t": 0.0, "actor": "wren", "commands": [...], "append": false},
##               {"t": 3.0, "camera": {...}}, {"t": 0.0, "card": "THE CLOCK AND THE PLAYER", "secs": 4},
##               {"t": 30.0, "cast": [...]}   a new scene: everyone on their marks
##               {"t": 60.0, "end": true}]}

const DIR := "user://takes"
const GAP_KEEP := 1.4        # a pause longer than this ...
const GAP_TO := 1.0          # ... is cut to this

var stage: Stage
var camera: StageCamera
var recording := false
var _rec: Dictionary = {}
var _t0 := 0.0
var _busy: Array = []        # [start, end] of each /do while recording
var playing: Dictionary = {}
var _play_t := 0.0
var _next := 0
var _subs: CanvasLayer
var _sub_label: Label
var _card: Label
var _sub_left := 0.0
var _card_left := 0.0
var subtitles := false
var on_end: Callable


func _ready() -> void:
	name = "StageTakes"
	_subs = CanvasLayer.new()
	_subs.name = "Subtitles"
	_subs.layer = 20
	add_child(_subs)
	_sub_label = _label(30, Vector2(0.08, 0.80), Vector2(0.92, 0.96))
	_card = _label(64, Vector2(0.05, 0.3), Vector2(0.95, 0.7))
	_card.add_theme_color_override("font_color", Color(0.97, 0.93, 0.80))


func _label(size: int, lo: Vector2, hi: Vector2) -> Label:
	var l := Label.new()
	l.anchor_left = lo.x
	l.anchor_top = lo.y
	l.anchor_right = hi.x
	l.anchor_bottom = hi.y
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 10)
	l.visible = false
	_subs.add_child(l)
	return l


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## ---- recording --------------------------------------------------------------

func start(title: String) -> Dictionary:
	recording = true
	_t0 = _now()
	_busy.clear()
	var cast := []
	for a: Actor in stage.actors.values():
		cast.append(_standing(a))
	var hour := 15.0
	if stage.world.get("time_of_day") != null:
		hour = float(stage.world.get("time_of_day"))
	_rec = {"title": title, "hour": hour, "subtitles": true, "camera": {"mode": "auto"}, "cast": cast, "events": []}
	return {"recording": title}


func _standing(a: Actor) -> Dictionary:
	return {"name": a.actor_name, "at": [snappedf(a.global_position.x, 0.01), snappedf(a.global_position.y, 0.01), snappedf(a.global_position.z, 0.01)],
		"yaw_deg": snappedf(rad_to_deg(a.rotation.y), 0.1), "sitting_on": a.sitting}


## An actor was sent commands; returns a handle to close when done.
func note_do(a: Actor, commands: Array, append: bool) -> int:
	if not recording:
		return -1
	var t := _now() - _t0
	# An actor who joined after the start stands where it was then.
	var known := false
	for c: Dictionary in _rec["cast"]:
		if c["name"] == a.actor_name:
			known = true
	if not known:
		var s := _standing(a)
		s["enter_at"] = t
		(_rec["cast"] as Array).append(s)
	(_rec["events"] as Array).append({"t": t, "actor": a.actor_name, "commands": commands, "append": append})
	_busy.append([t, INF])
	return _busy.size() - 1


func note_done(handle: int) -> void:
	if handle >= 0 and handle < _busy.size():
		_busy[handle][1] = _now() - _t0


func note_camera(spec: Dictionary) -> void:
	if recording:
		(_rec["events"] as Array).append({"t": _now() - _t0, "camera": spec})


## Stop, cut the dead time, save; the take's path.
func stop() -> Dictionary:
	if not recording:
		return {"error": "not recording"}
	recording = false
	var end := _now() - _t0
	for b: Array in _busy:
		if b[1] == INF:
			b[1] = end
	var events: Array = _rec["events"]
	# The stretches where someone was busy, merged.
	var spans: Array = _busy.duplicate()
	spans.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var merged: Array = []
	for s: Array in spans:
		if not merged.is_empty() and s[0] <= merged[merged.size() - 1][1]:
			merged[merged.size() - 1][1] = maxf(merged[merged.size() - 1][1], s[1])
		else:
			merged.append([s[0], s[1]])
	# Map each time onto the cut timeline.
	var remap := func(t: float) -> float:
		var cut := 0.0
		var prev_end := 0.0
		for m: Array in merged:
			if m[0] > t:
				break
			var gap: float = m[0] - prev_end
			if gap > GAP_KEEP:
				cut += gap - GAP_TO
			prev_end = m[1]
		var gap_now := t - prev_end
		if gap_now > GAP_KEEP:
			cut += gap_now - GAP_TO
		return maxf(t - cut, 0.0)
	for e: Dictionary in events:
		e["t"] = snappedf(remap.call(float(e["t"])), 0.01)
	for c: Dictionary in _rec["cast"]:
		if c.has("enter_at"):
			c["enter_at"] = snappedf(remap.call(float(c["enter_at"])), 0.01)
	var last := 0.0
	if not merged.is_empty():
		last = remap.call(float(merged[merged.size() - 1][1]))
	events.append({"t": snappedf(last + 2.5, 0.01), "end": true})
	var path := save(str(_rec["title"]), _rec)
	return {"saved": ProjectSettings.globalize_path(path), "events": events.size(), "length_s": snappedf(last + 2.5, 0.1)}


static func file_for(title: String) -> String:
	var slug := title.to_lower().strip_edges().replace(" ", "_")
	var ok := ""
	for ch in slug:
		if ch in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			ok += ch
	return "%s/%s.json" % [DIR, ok if ok != "" else "take"]


func save(title: String, take: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := file_for(title)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(take, "  "))
	return path


static func load_take(title_or_path: String) -> Dictionary:
	var path := title_or_path if title_or_path.ends_with(".json") else file_for(title_or_path)
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## ---- playing ------------------------------------------------------------------

## Put the cast where they stood at the start and play the events in time.
func play(take: Dictionary) -> Dictionary:
	if take.is_empty():
		return {"error": "no such take"}
	recording = false
	playing = take
	_play_t = 0.0
	_next = 0
	subtitles = bool(take.get("subtitles", true))
	if stage.world.has_method("set_time_of_day"):
		stage.world.call("set_time_of_day", float(take.get("hour", 15.0)))
	for c: Dictionary in take.get("cast", []):
		var a: Actor = stage.actors.get(c["name"])
		if a == null:
			a = stage.spawn(c["name"], "plain", Vector3.ZERO, 0.0)
		var at: Array = c["at"]
		a.reset_to(Vector3(float(at[0]), float(at[1]), float(at[2])), deg_to_rad(float(c.get("yaw_deg", 0.0))), str(c.get("sitting_on", "")))
		a.visible = not c.has("enter_at") or float(c["enter_at"]) <= 0.0
	# Only the cast is on stage for the take.
	var names := (take.get("cast", []) as Array).map(func(c: Dictionary) -> String: return c["name"])
	for a: Actor in stage.actors.values():
		if not a.actor_name in names:
			a.visible = false
	camera.direct(take.get("camera", {"mode": "auto"}))
	camera.hide_speech(subtitles)
	print("[play] %d" % Engine.get_frames_drawn())
	return {"playing": take.get("title", ""), "events": (take.get("events", []) as Array).size()}


func _process(delta: float) -> void:
	if _sub_left > 0.0:
		_sub_left -= delta
		_sub_label.visible = _sub_left > 0.0
	if _card_left > 0.0:
		_card_left -= delta
		_card.visible = _card_left > 0.0
	if playing.is_empty():
		return
	_play_t += delta
	var events: Array = playing.get("events", [])
	for c: Dictionary in playing.get("cast", []):
		if c.has("enter_at") and _play_t >= float(c["enter_at"]) and stage.actors.has(c["name"]):
			(stage.actors[c["name"]] as Actor).visible = true
	while _next < events.size() and float((events[_next] as Dictionary).get("t", 0.0)) <= _play_t:
		var e: Dictionary = events[_next]
		_next += 1
		if e.has("actor") and stage.actors.has(e["actor"]):
			(stage.actors[e["actor"]] as Actor).run(e.get("commands", []), bool(e.get("append", false)))
		elif e.has("camera"):
			camera.direct(e["camera"])
		elif e.has("cast"):
			# A new scene: everyone on their marks.
			for c: Dictionary in e["cast"]:
				var a: Actor = stage.actors.get(c["name"])
				if a != null:
					var at: Array = c["at"]
					a.reset_to(Vector3(float(at[0]), float(at[1]), float(at[2])), deg_to_rad(float(c.get("yaw_deg", 0.0))), str(c.get("sitting_on", "")))
					a.visible = true
		elif e.has("card"):
			print("[card] %d	%s" % [Engine.get_frames_drawn(), str(e["card"])])
			_card.text = str(e["card"])
			_card_left = float(e.get("secs", 3.5))
			_card.visible = true
		elif e.has("end"):
			print("[end] %d" % Engine.get_frames_drawn())
			playing = {}
			camera.hide_speech(false)
			if on_end.is_valid():
				on_end.call()
			return


## A line said aloud, as a subtitle while a take plays.
func said(speaker: Actor, text: String) -> void:
	if playing.is_empty():
		return
	# The frame each line is said on: the film's voices are laid there.
	print("[said] %d	%s	%s" % [Engine.get_frames_drawn(), speaker.actor_name, text])
	if not subtitles:
		return
	_sub_label.text = "%s:  %s" % [speaker.actor_name.capitalize(), text]
	_sub_left = 1.2 + text.length() * 0.065
	_sub_label.visible = true
