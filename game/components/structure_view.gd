class_name StructureView
extends StaticBody3D
## A placed structural element: real collision on layer 1, so runs can
## be routed along it, waypoints land on it, and the support rule
## counts it. Not sim-backed — structure carries load, not process.
## Doors slide open on E; signs open the text editor on E.

var type_id: String
var struct_name: String
var config_cb: Callable = Callable()

var _door_leaf: Node3D = null
var _door_blocker: CollisionShape3D = null
var _door_open := false
var _sign_label: Label3D = null


func describe() -> String:
	match type_id:
		"s_door":
			return "%s — E opens/closes (X removes)" % struct_name
		"s_sign":
			return "%s — E edits the text (X removes)" % struct_name
	return "%s — structure (X removes)" % struct_name


func use() -> void:
	if type_id == "s_door":
		_door_open = not _door_open
	elif type_id == "s_sign" and config_cb.is_valid():
		config_cb.call(self)


func set_text(text: String) -> void:
	if _sign_label != null:
		_sign_label.text = text


func _physics_process(_delta: float) -> void:
	if _door_leaf == null:
		return
	var target := 1.32 if _door_open else 0.0
	_door_leaf.position.x = lerpf(_door_leaf.position.x, target, 0.15)
	if _door_blocker != null:
		_door_blocker.position.x = _door_leaf.position.x
		_door_blocker.set_deferred("disabled", _door_leaf.position.x > 0.8)
