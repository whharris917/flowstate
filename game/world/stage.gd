class_name Stage
extends Node
## The company of actors in a world: who is here, what each has said
## within earshot of the others, the notes they pass, and what each has
## made of itself (its body, the actions it has taught itself, its
## profile) kept on disk under user://actors/<name>/ so an actor is the
## same when the world is opened again.

const DIR := "user://actors"

var actors: Dictionary = {}          # name -> Actor
var world: Node3D


func _init(w: Node3D) -> void:
	world = w
	name = "Stage"


## Bring an actor on: from what it saved last time, or from a preset.
func spawn(actor_name: String, preset: String, at: Vector3, yaw: float) -> Actor:
	if actors.has(actor_name):
		return actors[actor_name]
	var a := Actor.new()
	a.actor_name = actor_name
	a.stage = self
	var saved := _load(actor_name)
	a.body_spec = saved.get("body", ActorPresets.body(preset))
	a.learned = saved.get("actions", {})
	a.profile = saved.get("profile", "")
	world.add_child(a)
	a.place(at, yaw)
	actors[actor_name] = a
	if saved.is_empty():
		save(a)
	return a


func remove(actor_name: String) -> void:
	if actors.has(actor_name):
		(actors[actor_name] as Actor).queue_free()
		actors.erase(actor_name)


## Words said aloud reach everyone within earshot, and a line meant for
## one actor still reaches the others near enough to overhear.
func hear(speaker: Actor, text: String, to: String) -> void:
	for a: Actor in actors.values():
		if a == speaker:
			continue
		var d := a.global_position.distance_to(speaker.global_position)
		if d > Actor.HEAR_M:
			continue
		a.heard.append({"from": speaker.actor_name, "said": text, "to": to if to != "" else "everyone",
			"distance_m": snappedf(d, 0.1)})
		if a.heard.size() > 40:
			a.heard.remove_at(0)


## A private note from one actor to another, wherever they are.
func deliver(from: String, to: String, text: String) -> bool:
	if not actors.has(to):
		return false
	var a: Actor = actors[to]
	a.inbox.append({"from": from, "text": text.left(4000), "sent": Time.get_datetime_string_from_system(), "read": false})
	if a.inbox.size() > 200:
		a.inbox.remove_at(0)
	return true


func save(a: Actor) -> void:
	var d := "%s/%s" % [DIR, a.actor_name]
	DirAccess.make_dir_recursive_absolute(d)
	_write(d + "/body.json", JSON.stringify(a.body_spec, "  "))
	_write(d + "/actions.json", JSON.stringify(a.learned, "  "))
	_write(d + "/profile.md", a.profile)


func _load(actor_name: String) -> Dictionary:
	var d := "%s/%s" % [DIR, actor_name]
	if not DirAccess.dir_exists_absolute(d):
		return {}
	var out := {}
	var body: Variant = JSON.parse_string(_read(d + "/body.json"))
	if body is Dictionary and ActorFigure.check_body(body).is_empty():
		out["body"] = body
	var acts: Variant = JSON.parse_string(_read(d + "/actions.json"))
	if acts is Dictionary:
		out["actions"] = acts
	out["profile"] = _read(d + "/profile.md")
	return out


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
