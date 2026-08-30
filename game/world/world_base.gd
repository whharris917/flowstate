class_name WorldBase
extends Node3D
## Shared bootstrap for every playable world: player, plant, HUD, build
## controller, audio buses, quicksave/quickload. Subclasses build their
## environment in _build_world() and tune the knobs below in _init().

@onready var player: Player = $Player

var plant: Plant
var hud: Hud
var builder: BuildController

# Knobs a world sets in _init(), before _ready runs.
var plant_height := 0.0
var plant_save_path := "user://save.json"
var with_suite := true            # build the aseptic annex + air cascade
var with_hum := true              # machine-room ambience loop
var reverb_room_size := 0.85
var reverb_wet := 0.25

var _loop_players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_build_world()
	_build_audio()
	plant = Plant.new()
	plant.position.y = plant_height
	plant.save_path = plant_save_path
	plant.build_suite = with_suite
	add_child(plant)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	var run_config := RunConfigPanel.new()
	layer.add_child(run_config)
	plant.config_panel = run_config
	var cabinet_editor := CabinetEditor.new()
	layer.add_child(cabinet_editor)
	plant.cabinet_editor = cabinet_editor
	var ladder_panel := LadderPanel.new()
	layer.add_child(ladder_panel)
	plant.ladder_panel = ladder_panel
	var tank_panel := TankConfigPanel.new()
	layer.add_child(tank_panel)
	plant.tank_panel = tank_panel
	builder = BuildController.new()
	add_child(builder)
	builder.setup(player, plant, hud)
	_after_plant()
	hud.toast("WASD move · E use · wheel zoom (ctrl: optic) · B build · C connect · X remove · F5/F9 save/load")


## Environment, geometry, lighting. Override in each world.
func _build_world() -> void:
	pass


## Commissioned equipment specific to one world, placed through the
## plant's build API once it exists. Override where needed.
func _after_plant() -> void:
	pass


func _process(_delta: float) -> void:
	var view := player.look_view()
	if view != null and view.has_method("describe"):
		hud.set_look_text(str(view.call("describe")))
	else:
		hud.set_look_text("")
	hud.set_readout_text("t %s   level %.1f L   relay %d cyc   pump %s" % [
		_fmt_time(plant.sim.time), plant.tank.level_l, plant.relay.cycles,
		"RUN" if plant.pump.running else "stop"])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quicksave"):
		hud.toast("saved" if plant.save_game() else "save FAILED")
	elif event.is_action_pressed("quickload"):
		hud.toast("loaded" if plant.load_game() else "no save found")


func _fmt_time(seconds: float) -> String:
	var total := int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]


func _build_audio() -> void:
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Room")
	AudioServer.set_bus_send(bus, "Master")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = reverb_room_size
	reverb.wet = reverb_wet
	reverb.damping = 0.55
	AudioServer.add_bus_effect(bus, reverb)

	_looping_player("res://audio/music_loop.wav", -16.0, "Master")
	if with_hum:
		_looping_player("res://audio/hum_loop.wav", -18.0, "Room")


func _looping_player(path: String, volume_db: float, bus: String) -> void:
	var stream := load(path) as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var audio_player := AudioStreamPlayer.new()
	audio_player.stream = stream
	audio_player.volume_db = volume_db
	audio_player.bus = bus
	# Playing streams leak their playback objects in a teardown race at
	# process exit; harmless in real play but noise in headless smoke
	# runs, so only start them when a real audio driver exists.
	audio_player.autoplay = DisplayServer.get_name() != "headless"
	add_child(audio_player)
	_loop_players.append(audio_player)


func _exit_tree() -> void:
	for audio_player in _loop_players:
		audio_player.stop()


func _static_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = ViewUtil.flat(color)
	body.add_child(mesh)
	add_child(body)
