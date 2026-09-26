class_name ClerkLink
extends Node
## The line from outside into the running world: a small web server on
## this computer alone (127.0.0.1, PORT) that hands the clerk his scripts
## and answers what he is doing, so a script can be sent while the game
## runs and the conversation that wrote it stays open.
##   POST /run     {"commands": [...], "append": false}   a new script
##   POST /stop                                           stop him
##   GET  /state                                          where he is, what he is doing, his log
##   GET  /places                                         the named places
##   GET  /shot?cam=eyes|follow|front|player                    a picture, saved; its path returned
## Every answer is JSON.

const PORT := 47886

var clerk: Clerk
var _server := TCPServer.new()
var _peers: Array[Dictionary] = []    # {peer, buf, t}
var _shots := 0


func _ready() -> void:
	name = "ClerkLink"
	var err := _server.listen(PORT, "127.0.0.1")
	if err != OK:
		push_warning("ClerkLink: cannot listen on %d (%s)" % [PORT, error_string(err)])
	else:
		print("[flowstate] clerk link: listening on http://127.0.0.1:%d" % PORT)


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
		var st := peer.get_status()
		if st != StreamPeerTCP.STATUS_CONNECTED or float(p["t"]) > 30.0:
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


## A request once all of it has come: {method, path, query, body}.
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
	var body_bytes := buf.slice(head_end + 4)
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
	return {"method": first[0], "path": target, "query": query, "body": body_bytes.get_string_from_utf8()}


func _serve(p: Dictionary, req: Dictionary) -> void:
	var out: Variant = await _answer(req)
	_reply(p["peer"], 200 if not (out is Dictionary and out.has("error")) else 400, out)


func _answer(req: Dictionary) -> Variant:
	if clerk == null:
		return {"error": "no clerk in this world"}
	match [req["method"], req["path"]]:
		["GET", "/state"], ["GET", "/"]:
			return clerk.state()
		["GET", "/places"]:
			return {"places": CourthousePlaces.NODES.keys(), "aliases": CourthousePlaces.ALIASES}
		["POST", "/stop"]:
			clerk.stop()
			return clerk.state()
		["POST", "/run"]:
			var parsed: Variant = JSON.parse_string(str(req["body"]))
			var commands: Array = []
			var append := false
			if parsed is Array:
				commands = parsed
			elif parsed is Dictionary:
				commands = (parsed as Dictionary).get("commands", [])
				append = bool((parsed as Dictionary).get("append", false))
			else:
				return {"error": "the body is not JSON: a list of commands, or {\"commands\": [...]}"}
			clerk.run(commands, append)
			return clerk.state()
		["GET", "/shot"]:
			var cam := str((req["query"] as Dictionary).get("cam", "follow"))
			_shots += 1
			var path := "user://clerk_%s_%d.png" % [cam, _shots]
			var err: Error
			if cam == "player":
				await RenderingServer.frame_post_draw
				err = get_viewport().get_texture().get_image().save_png(path)
			else:
				err = await clerk.capture(cam, path)
			if err != OK:
				return {"error": "could not save the picture (%s)" % error_string(err)}
			return {"path": ProjectSettings.globalize_path(path), "state": clerk.state()}
	return {"error": "no such request: %s %s" % [req["method"], req["path"]]}


func _reply(peer: StreamPeerTCP, code: int, data: Variant) -> void:
	var body := JSON.stringify(data, "  ").to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
		code, "OK" if code == 200 else "Bad Request", body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
