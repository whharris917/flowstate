extends Node3D
## Bootstraps the first playable: a clean modern industrial hall —
## high ceiling with a skylight grid, clerestory window bands, steel
## columns and beams, floor markings — plus ambience (music, ship hum,
## room reverb) and the plant. Still procedural placeholder geometry;
## the design intent is in proportion, light, and color.

const ROOM_W := 14.0   # x
const ROOM_D := 10.0   # z
const ROOM_H := 4.2
const WALL_T := 0.3

const COL_FLOOR := Color(0.62, 0.62, 0.60)
const COL_WALL := Color(0.85, 0.85, 0.82)
const COL_STEEL := Color(0.16, 0.17, 0.19)
const COL_PLINTH := Color(0.50, 0.50, 0.49)
const COL_SAFETY := Color(0.95, 0.78, 0.05)
const COL_GLASS := Color(0.75, 0.85, 0.95, 0.16)

@onready var player: Player = $Player

var plant: Plant
var hud: Hud
var _loop_players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_build_environment()
	_build_shell()
	_build_fixtures()
	_build_markings()
	_build_audio()
	plant = Plant.new()
	plant.position.y = 0.08  # equipment sits on the concrete plinth
	add_child(plant)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.toast("WASD move · mouse look · E use · F5 save · F9 load · Esc mouse")


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


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.70, 0.78, 0.88)  # sky through the glass
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.60)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 25, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	add_child(sun)


func _build_shell() -> void:
	var half_w := ROOM_W / 2.0
	var half_d := ROOM_D / 2.0

	_static_box(Vector3(ROOM_W, 0.5, ROOM_D), Vector3(0, -0.25, 0), COL_FLOOR)
	_static_box(Vector3(9.2, 0.08, 3.4), Vector3(-1.0, 0.04, -3.2), COL_PLINTH)

	# Solid end walls (z), full height — the plant wall and the entry wall.
	_static_box(Vector3(ROOM_W, ROOM_H, WALL_T), Vector3(0, ROOM_H / 2.0, -half_d), COL_WALL)
	_static_box(Vector3(ROOM_W, ROOM_H, WALL_T), Vector3(0, ROOM_H / 2.0, half_d), COL_WALL)

	# Side walls (x): solid below, clerestory window band 2.4-3.4, solid above.
	for side: float in [-1.0, 1.0]:
		var wall_x := side * half_w
		_static_box(Vector3(WALL_T, 2.4, ROOM_D), Vector3(wall_x, 1.2, 0), COL_WALL)
		_static_box(Vector3(WALL_T, ROOM_H - 3.4, ROOM_D), Vector3(wall_x, (3.4 + ROOM_H) / 2.0, 0), COL_WALL)
		for post_z: float in [-5.0, -3.0, -1.0, 1.0, 3.0, 5.0]:
			_static_box(Vector3(WALL_T, 1.0, 0.12), Vector3(wall_x, 2.9, post_z), COL_STEEL)
		_glass(Vector3(0.06, 1.0, ROOM_D), Vector3(wall_x, 2.9, 0))

	# Ceiling slab with two rows of three skylight openings.
	var ceil_y := ROOM_H + 0.1
	for strip: Array in [[0.0, -4.1, ROOM_W, 1.8], [0.0, 0.0, ROOM_W, 2.4], [0.0, 4.1, ROOM_W, 1.8]]:
		_static_box(Vector3(strip[2], 0.2, strip[3]), Vector3(strip[0], ceil_y, strip[1]), COL_WALL)
	for row_z: float in [-2.2, 2.2]:
		for fill_x: float in [-6.0, -2.0, 2.0, 6.0]:
			_static_box(Vector3(2.0, 0.2, 2.0), Vector3(fill_x, ceil_y, row_z), COL_WALL)
		for sky_x: float in [-4.0, 0.0, 4.0]:
			_glass(Vector3(1.96, 0.05, 1.96), Vector3(sky_x, ROOM_H + 0.13, row_z))

	# Steel: perimeter columns and a mid-span beam.
	for col_z: float in [-3.3, 0.0, 3.3]:
		for side: float in [-1.0, 1.0]:
			_static_box(Vector3(0.28, ROOM_H, 0.28), Vector3(side * (half_w - 0.3), ROOM_H / 2.0, col_z), COL_STEEL)
	_static_box(Vector3(ROOM_W, 0.3, 0.22), Vector3(0, ROOM_H - 0.15, 0), COL_STEEL)


func _build_fixtures() -> void:
	for pos: Vector3 in [Vector3(-3.5, 0, -1.5), Vector3(1.5, 0, -1.5),
			Vector3(-3.5, 0, 2.5), Vector3(1.5, 0, 2.5)]:
		var strip := ViewUtil.box(self, Vector3(1.8, 0.06, 0.12),
			Vector3(pos.x, ROOM_H - 0.25, pos.z), ViewUtil.glow(Color(0.95, 0.94, 0.90), 2.2))
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light := OmniLight3D.new()
		light.position = Vector3(pos.x, ROOM_H - 0.5, pos.z)
		light.light_energy = 1.1
		light.light_color = Color(1.0, 0.96, 0.90)
		light.omni_range = 7.0
		add_child(light)


func _build_markings() -> void:
	# Safety-yellow demarcation around the equipment zone.
	var y := 0.006
	_marking(Vector3(10.0, 0.012, 0.08), Vector3(-1.0, y, -0.9))
	_marking(Vector3(0.08, 0.012, 4.0), Vector3(-6.0, y, -2.9))
	_marking(Vector3(0.08, 0.012, 4.0), Vector3(4.0, y, -2.9))


func _marking(size: Vector3, pos: Vector3) -> void:
	ViewUtil.box(self, size, pos, ViewUtil.flat(COL_SAFETY)) \
		.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_audio() -> void:
	# "Room" bus with a hall reverb; footsteps and hum feed it.
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Room")
	AudioServer.set_bus_send(bus, "Master")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.75
	reverb.wet = 0.22
	reverb.damping = 0.6
	AudioServer.add_bus_effect(bus, reverb)

	_looping_player("res://audio/music_loop.wav", -16.0, "Master")
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


## Streams still playing at engine teardown leak their playback objects;
## stop them while the audio server is alive.
func _exit_tree() -> void:
	for audio_player in _loop_players:
		audio_player.stop()


func _glass(size: Vector3, pos: Vector3) -> void:
	var mat := ViewUtil.flat(COL_GLASS)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.2
	mat.roughness = 0.05
	var pane := ViewUtil.box(self, size, pos, mat)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
