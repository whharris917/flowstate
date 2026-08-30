class_name BuildController
extends Node
## Build and connect modes. B toggles build (1-5 pick equipment, R
## rotates, click places), C toggles connect (click an output port,
## then an input port — the kernel's wiring rules decide), X removes
## player-placed equipment. The ghost is grid-snapped and colored by
## validity.

enum Mode { NORMAL, PLACE, CONNECT }

const GRID := 0.5
const REACH := 7.0

var mode: Mode = Mode.NORMAL
var catalog_index: int = 0
var rot_y: float = 0.0

var player: Player
var plant: Plant
var hud: Hud

var _ghost: MeshInstance3D
var _ghost_valid := false
var _ghost_pos := Vector3.ZERO
var _pending_marker: StaticBody3D = null


func setup(player_: Player, plant_: Plant, hud_: Hud) -> void:
	player = player_
	plant = plant_
	hud = hud_
	var mesh := BoxMesh.new()
	_ghost = MeshInstance3D.new()
	_ghost.mesh = mesh
	_ghost.visible = false
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.8, 0.3, 0.35)
	_ghost.material_override = mat
	add_child(_ghost)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		_set_mode(Mode.NORMAL if mode == Mode.PLACE else Mode.PLACE)
	elif event.is_action_pressed("connect_mode"):
		_set_mode(Mode.NORMAL if mode == Mode.CONNECT else Mode.CONNECT)
	elif event.is_action_pressed("ui_cancel"):
		_set_mode(Mode.NORMAL)
	elif event.is_action_pressed("rotate_item") and mode == Mode.PLACE:
		rot_y = wrapf(rot_y + PI / 2.0, 0.0, TAU)
	elif event.is_action_pressed("delete_item"):
		_try_delete()
	elif mode == Mode.PLACE and event.is_action_pressed("place"):
		_try_place()
	elif mode == Mode.CONNECT and event.is_action_pressed("place"):
		_try_pick_port()
	else:
		for i in range(PlantFactory.CATALOG.size()):
			if event.is_action_pressed("catalog_%d" % (i + 1)):
				catalog_index = i
				if mode != Mode.PLACE:
					_set_mode(Mode.PLACE)
				_update_hud()
				return


func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_ghost.visible = false
	_pending_marker = null
	# Connect mode lets the interact ray see port markers (layer 2).
	player.ray.collision_mask = 3 if mode == Mode.CONNECT else 1
	_update_hud()


func _update_hud() -> void:
	match mode:
		Mode.NORMAL:
			hud.set_mode_text("B build · C connect · X remove")
		Mode.PLACE:
			var lines: Array[String] = []
			for i in range(PlantFactory.CATALOG.size()):
				var entry: Dictionary = PlantFactory.CATALOG[i]
				var marker := "> " if i == catalog_index else "  "
				lines.append("%s%d %s" % [marker, i + 1, entry["label"]])
			hud.set_mode_text("BUILD — click place · R rotate · B/Esc exit\n" + "\n".join(lines))
		Mode.CONNECT:
			var step := "click an OUTPUT port (cube)" if _pending_marker == null \
				else "now click an INPUT port (sphere)"
			hud.set_mode_text("CONNECT — %s · C/Esc exit" % step)


func _physics_process(_delta: float) -> void:
	if mode == Mode.PLACE:
		_update_ghost()


func _update_ghost() -> void:
	var camera := player.camera
	var space := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * REACH, 1)
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.6:
		_ghost.visible = false
		_ghost_valid = false
		return
	var type_id := _current_type()
	var footprint: Vector3 = PlantFactory.FOOTPRINTS[type_id]
	var point := hit["position"] as Vector3
	_ghost_pos = Vector3(snappedf(point.x, GRID), point.y, snappedf(point.z, GRID))
	(_ghost.mesh as BoxMesh).size = footprint
	_ghost.global_position = _ghost_pos + Vector3(0, footprint.y / 2.0 + 0.02, 0)
	_ghost.rotation.y = rot_y
	_ghost.visible = true

	var shape := BoxShape3D.new()
	shape.size = footprint * 0.9
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = shape
	overlap.transform = Transform3D(Basis.from_euler(Vector3(0, rot_y, 0)),
		_ghost_pos + Vector3(0, footprint.y / 2.0 + 0.06, 0))
	overlap.collision_mask = 1
	overlap.exclude = [player.get_rid()]
	_ghost_valid = space.intersect_shape(overlap, 1).is_empty()
	(_ghost.material_override as StandardMaterial3D).albedo_color = \
		Color(0.2, 0.8, 0.3, 0.35) if _ghost_valid else Color(0.9, 0.25, 0.2, 0.35)


func _current_type() -> String:
	return PlantFactory.CATALOG[catalog_index]["type"]


func _try_place() -> void:
	if not _ghost.visible or not _ghost_valid:
		hud.toast("can't place here")
		return
	var record := plant.place_new(_current_type(), _ghost_pos, rot_y)
	if record != null:
		hud.toast("placed %s" % record.comp_name)


func _try_pick_port() -> void:
	var collider := player.ray.get_collider() if player.ray.is_colliding() else null
	if collider == null or not (collider as Node).has_meta("port_name"):
		return
	var marker := collider as StaticBody3D
	if _pending_marker == null:
		if bool(marker.get_meta("is_input")):
			hud.toast("start from an OUTPUT port (cube)")
			return
		_pending_marker = marker
		_update_hud()
		return
	if not bool(marker.get_meta("is_input")):
		hud.toast("finish on an INPUT port (sphere)")
		return
	var error := plant.connect_equipment(
		str(_pending_marker.get_meta("record_name")), str(_pending_marker.get_meta("port_name")),
		str(marker.get_meta("record_name")), str(marker.get_meta("port_name")))
	hud.toast("connected" if error == "" else error)
	_pending_marker = null
	_update_hud()


func _try_delete() -> void:
	var view := player.look_view()
	if view == null or not view.has_meta("record_name"):
		return
	var name_ := str(view.get_meta("record_name"))
	if plant.remove_equipment(name_):
		hud.toast("removed %s" % name_)
	else:
		hud.toast("%s is commissioned equipment — can't remove" % name_)
