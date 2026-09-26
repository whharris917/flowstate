class_name StageLink
extends Node
## The line from outside into the running world: a small web server on
## this computer alone (127.0.0.1, PORT). Actors act and perceive through
## it, pass notes, and remake their bodies, actions and profiles; the
## director spawns actors, moves the camera and takes pictures. The
## actor's side is written up in data/actor_handbook.md (GET /handbook).
##   GET  /handbook
##   GET  /actors                         who is on stage
##   POST /actors {"name", "preset", "at"} bring one on (at: a place, affordance or [x, y, z])
##   GET  /actors/<n>                     body, actions, profile
##   POST /actors/<n>/do {"commands", "append", "wait", "view"}
##   GET  /actors/<n>/perceive?view=1
##   GET  /actors/<n>/inbox               the notes, marked read
##   PUT  /actors/<n>/body | /profile | /actions/<a>   DELETE /actions/<a>
##   GET  /actors/<n>/shot?cam=eyes|follow|front
##   GET  /actors/<n>/state               the director's view, with coordinates
##   POST /camera {...}                   see StageCamera
##   POST /world {"hour": 15.5}           the time of day
##   GET  /shot?cam=screen                what the screen shows
## The first actor, the clerk, keeps the older short forms: POST /run,
## GET /state, POST /stop, POST /explorer/step.

const PORT := 47886
const HANDBOOK := "res://data/actor_handbook.md"
const EXPLORER_OK := ["forward", "back", "turn", "look", "say", "wait", "act", "wave", "bow", "point", "read"]

var stage: Stage
var camera: StageCamera
var _server := TCPServer.new()
var _peers: Array[Dictionary] = []
var _shots := 0


func _ready() -> void:
	name = "StageLink"
	var err := _server.listen(PORT, "127.0.0.1")
	if err != OK:
		push_warning("StageLink: cannot listen on %d (%s)" % [PORT, error_string(err)])
	else:
		print("[flowstate] stage link: listening on http://127.0.0.1:%d" % PORT)


func _exit_tree() -> void:
	for p: Dictionary in _peers:
		(p["peer"] as StreamPeerTCP).disconnect_from_host()
	_server.stop()


func _process(delta: float) -> void:
	while _server.is_connection_available():
		_peers.append({"peer": _server.take_connection(), "buf": PackedByteArray(), "t": 0.0})
	for p: Dictionary in _peers.duplicate():
		var peer: StreamPeerTCP = p["peer"]
		peer.poll()
		p["t"] = float(p["t"]) + delta
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or float(p["t"]) > 120.0:
			_peers.erase(p)
			continue
		if p.get("done", false):
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got := peer.get_data(n)
			if int(got[0]) == OK:
				var buf: PackedByteArray = p["buf"]
				buf.append_array(got[1])
				p["buf"] = buf
		var req := _parse(p["buf"])
		if not req.is_empty():
			p["done"] = true
			_serve(p, req)


func _parse(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_utf8()
	var head_end := text.find("\r\n\r\n")
	if head_end < 0:
		return {}
	var lines := text.substr(0, head_end).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"method": "BAD", "path": "", "query": {}, "body": ""}
	var length := 0
	for l in lines:
		if l.to_lower().begins_with("content-length:"):
			length = int(l.substr(15).strip_edges())
	var head_bytes := text.substr(0, head_end + 4).to_utf8_buffer().size()
	var body_bytes := buf.slice(head_bytes)
	if body_bytes.size() < length:
		return {}
	var target := first[1]
	var query := {}
	var q := target.find("?")
	if q >= 0:
		for pair in target.substr(q + 1).split("&"):
			var kv := pair.split("=")
			query[kv[0]] = kv[1].uri_decode() if kv.size() > 1 else ""
		target = target.substr(0, q)
	return {"method": first[0], "path": target.uri_decode(), "query": query, "body": body_bytes.get_string_from_utf8()}


func _serve(p: Dictionary, req: Dictionary) -> void:
	var out: Variant = await _answer(req)
	var code := 200
	if out is Dictionary and (out as Dictionary).has("error"):
		code = 404 if str(out.get("error", "")).begins_with("no ") else 400
	if out is String:
		_reply_text(p["peer"], out)
	else:
		_reply(p["peer"], code, out)


func _body(req: Dictionary) -> Variant:
	return JSON.parse_string(str(req["body"])) if str(req["body"]).strip_edges() != "" else {}


func _answer(req: Dictionary) -> Variant:
	var m: String = req["method"]
	var parts: PackedStringArray = str(req["path"]).trim_prefix("/").split("/", false)
	if parts.is_empty():
		return {"hello": "the stage is open", "handbook": "/handbook", "actors": stage.actors.keys()}
	match parts[0]:
		"handbook":
			return FileAccess.get_file_as_string(HANDBOOK)
		"actors":
			if parts.size() == 1:
				if m == "POST":
					return _spawn(_body(req))
				var list := []
				for a: Actor in stage.actors.values():
					list.append({"name": a.actor_name, "doing": a._doing_words()})
				return {"actors": list}
			var n := parts[1]
			if not stage.actors.has(n):
				return {"error": "no actor called '%s'" % n}
			return await _actor(stage.actors[n], m, parts.slice(2), req)
		"camera":
			var s: Variant = _body(req)
			if not s is Dictionary:
				return {"error": "the camera takes an object: see the handbook"}
			return {"camera": camera.direct(s)}
		"shot":
			return await _screen_shot()
		"world":
			var w: Variant = _body(req)
			if w is Dictionary and (w as Dictionary).has("hour") and stage.world.has_method("set_time_of_day"):
				stage.world.call("set_time_of_day", clampf(float(w["hour"]), 0.0, 24.0))
				return {"hour": float(w["hour"])}
			return {"error": "send {\"hour\": 0 to 24}"}
		# The clerk's older short forms.
		"run", "state", "stop", "explorer":
			if not stage.actors.has("clerk"):
				return {"error": "no clerk on stage"}
			var c: Actor = stage.actors["clerk"]
			match parts[0]:
				"state":
					return c.director_state()
				"stop":
					c.stop()
					return c.director_state()
				"run":
					var b: Variant = _body(req)
					c.run(b if b is Array else (b as Dictionary).get("commands", []), false if b is Array else bool((b as Dictionary).get("append", false)))
					return c.director_state()
				"explorer":
					var b: Variant = _body(req)
					var cmds: Array = b if b is Array else (b as Dictionary).get("commands", [])
					var taken := cmds.filter(func(x: Variant) -> bool: return x is Dictionary and str((x as Dictionary).get("do", "")) in EXPLORER_OK)
					c.run(taken, false)
					await _until_idle(c)
					var out := {"last_step": c.last_walk, "looking_deg": c.head_pitch}
					out["view"] = await _actor_shot(c, "eyes")
					return out
	return {"error": "no such request: %s %s" % [m, req["path"]]}


func _actor(a: Actor, m: String, rest: PackedStringArray, req: Dictionary) -> Variant:
	var what := rest[0] if rest.size() > 0 else ""
	match [m, what]:
		["GET", ""]:
			return {"name": a.actor_name, "profile": a.profile, "body": a.body_spec, "actions": a.learned,
				"built_in_actions": ActorPresets.actions().keys()}
		["GET", "state"]:
			return a.director_state()
		["GET", "perceive"]:
			var out := a.perceive()
			if str((req["query"] as Dictionary).get("view", "0")) in ["1", "true"]:
				out["view"] = await _actor_shot(a, "eyes")
			return out
		["GET", "inbox"]:
			var notes: Array = []
			for note: Dictionary in a.inbox:
				notes.append({"from": note["from"], "text": note["text"], "sent": note["sent"], "new": not bool(note["read"])})
				note["read"] = true
			return {"notes": notes}
		["GET", "shot"]:
			return {"view": await _actor_shot(a, str((req["query"] as Dictionary).get("cam", "front")))}
		["POST", "do"]:
			var b: Variant = _body(req)
			var cmds: Array = []
			var append := false
			var wait := true
			var view := false
			if b is Array:
				cmds = b
			elif b is Dictionary:
				cmds = (b as Dictionary).get("commands", [])
				append = bool((b as Dictionary).get("append", false))
				wait = bool((b as Dictionary).get("wait", true))
				view = bool((b as Dictionary).get("view", false))
			else:
				return {"error": "send {\"commands\": [...]}"}
			a.last_walk = {}
			a.run(cmds, append)
			if wait:
				await _until_idle(a)
			var out := a.perceive()
			if view:
				out["view"] = await _actor_shot(a, "eyes")
			return out
		["POST", "stop"]:
			a.stop()
			return a.perceive()
		["PUT", "profile"]:
			var b: Variant = _body(req)
			if not b is Dictionary or not (b as Dictionary).has("text"):
				return {"error": "send {\"text\": \"...\"}"}
			a.profile = str(b["text"]).left(40000)
			stage.save(a)
			return {"profile": "saved", "chars": a.profile.length()}
		["PUT", "body"]:
			var b: Variant = _body(req)
			if not b is Dictionary:
				return {"error": "a body is an object: {\"parts\": [...]}"}
			var problems := ActorFigure.check_body(b)
			if not problems.is_empty():
				return {"error": "body refused", "problems": problems}
			a.wear(b)
			stage.save(a)
			return {"body": "worn", "parts": (b.get("parts", []) as Array).size()}
		["PUT", "actions"], ["DELETE", "actions"]:
			if rest.size() < 2:
				return {"error": "name the action: /actions/<name>"}
			var an := rest[1].to_lower()
			if m == "DELETE":
				a.learned.erase(an)
				stage.save(a)
				return {"forgotten": an}
			var b: Variant = _body(req)
			if not b is Dictionary:
				return {"error": "an action is an object: see the handbook"}
			var problems := ActorFigure.check_action(b)
			if not problems.is_empty():
				return {"error": "action refused", "problems": problems}
			a.learned[an] = b
			stage.save(a)
			return {"learned": an}
	return {"error": "no such request: %s %s" % [m, req["path"]]}


func _spawn(b: Variant) -> Dictionary:
	if not b is Dictionary or str((b as Dictionary).get("name", "")).strip_edges() == "":
		return {"error": "send {\"name\": \"...\", \"preset\": \"plain\", \"at\": \"<place>\"}"}
	var n := str(b["name"]).strip_edges().to_lower().replace(" ", "_").left(24)
	var at: Variant = b.get("at", "monument_n")
	var p := Vector3(-22.5, 0.2, -3.6)
	if at is Array and (at as Array).size() >= 3:
		p = Vector3(float(at[0]), float(at[1]), float(at[2]))
	else:
		var pl := CourthousePlaces.resolve(str(at))
		var af := CourthouseAffordances.find(str(at))
		if pl != "":
			p = CourthousePlaces.NODES[pl]
		elif not af.is_empty():
			p = af.get("approach", af["at"])
	var a := stage.spawn(n, str(b.get("preset", "plain")), p + Vector3(0, 0.15, 0), deg_to_rad(float(b.get("yaw_deg", 0.0))))
	return {"spawned": a.actor_name, "handbook": "/handbook"}


func _until_idle(a: Actor) -> void:
	var waited := 0.0
	while a.busy() and waited < 90.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	await get_tree().create_timer(0.2).timeout


func _actor_shot(a: Actor, cam: String) -> String:
	_shots += 1
	var path := "user://stage_%s_%s_%d.png" % [a.actor_name, cam, _shots]
	var err: Error = await a.capture(cam, path)
	return ProjectSettings.globalize_path(path) if err == OK else "could not save the picture"


func _screen_shot() -> Dictionary:
	await RenderingServer.frame_post_draw
	_shots += 1
	var path := "user://stage_screen_%d.png" % _shots
	get_viewport().get_texture().get_image().save_png(path)
	return {"view": ProjectSettings.globalize_path(path)}


func _reply(peer: StreamPeerTCP, code: int, data: Variant) -> void:
	var body := JSON.stringify(data, "  ").to_utf8_buffer()
	_send(peer, code, "application/json", body)


func _reply_text(peer: StreamPeerTCP, text: String) -> void:
	_send(peer, 200, "text/markdown; charset=utf-8", text.to_utf8_buffer())


func _send(peer: StreamPeerTCP, code: int, kind: String, body: PackedByteArray) -> void:
	var reason: String = {200: "OK", 400: "Bad Request", 404: "Not Found"}.get(code, "OK")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, reason, kind, body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
