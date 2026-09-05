class_name WorldBase
extends Node3D
## Shared bootstrap for every playable world: player, plant, HUD, build
## controller, audio buses, quicksave/quickload. Subclasses build their
## environment in _build_world() and tune the knobs below in _init().

@onready var player: Player = $Player

var plant: Plant
var hud: Hud
var builder: BuildController
var library: LibraryPanel

# Knobs a world sets in _init(), before _ready runs.
var plant_height := 0.0
var plant_save_path := "user://save.json"
var with_suite := true            # build the aseptic annex + air cascade
var with_hum := true              # machine-room ambience loop
var reverb_room_size := 0.85
var reverb_wet := 0.25

var _loop_players: Array[AudioStreamPlayer] = []

# On-screen options (director, 2026-09-05): the sun follows a
# time-of-day slider and the music is a toggle, off by default. Both
# persist in user://settings.json. Worlds hand their sun (and, outdoors,
# their sky material) to these so one slider serves both worlds.
const SETTINGS_PATH := "user://settings.json"
var sun: DirectionalLight3D = null
var sky_mat: ProceduralSkyMaterial = null
var sky_env: Environment = null
var settings: SettingsPanel
var music_player: AudioStreamPlayer = null
var time_of_day := 10.0
var music_on := false
var _sun_base_energy := 1.5
var _sun_base_color := Color(1.0, 0.97, 0.90)


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
	library = LibraryPanel.new()
	layer.add_child(library)
	settings = SettingsPanel.new()
	layer.add_child(settings)
	settings.on_time_changed = func(hours: float) -> void:
		set_time_of_day(hours)
		_save_settings()
	settings.on_music_changed = func(on: bool) -> void:
		set_music(on)
		_save_settings()
	builder = BuildController.new()
	add_child(builder)
	builder.setup(player, plant, hud)
	_after_plant()
	_load_settings()
	hud.toast("WASD move · E use · wheel zoom (ctrl: optic) · B build · C connect · X remove · L library · O options · F5/F9 save/load")


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
	if event.is_action_pressed("library"):
		library.toggle()
		# The panel owns the screen while it is up: free the mouse so the
		# page can be read, and stop the player walking off behind it.
		player.input_locked = library.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if library.visible \
			else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("options"):
		settings.toggle()
		player.input_locked = settings.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if settings.visible \
			else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("quicksave"):
		hud.toast("saved" if plant.save_game() else "save FAILED")
	elif event.is_action_pressed("quickload"):
		hud.toast("loaded" if plant.load_game() else "no save found")


## ---- options: the sun and the music ---------------------------------------

## Hours 0-24. The sun rises in the east at six, stands 60 degrees up at
## noon, sets in the west at six, and below the horizon the world runs
## on a dim blue moon. Colour warms toward the horizon; the outdoor sky
## darkens with it.
func set_time_of_day(hours: float) -> void:
	time_of_day = fposmod(hours, 24.0)
	if sun == null:
		return
	var day_frac := (time_of_day - 6.0) / 12.0          # 0 at sunrise, 1 at sunset
	var elevation := 60.0 * sin(clampf(day_frac, 0.0, 1.0) * PI)
	var up := day_frac >= 0.0 and day_frac <= 1.0
	var azimuth := 90.0 + clampf(day_frac, 0.0, 1.0) * 180.0
	sun.rotation_degrees = Vector3(-(elevation if up else 8.0), azimuth, 0)
	# Twilight: an hour either side of the horizon, night fades in and
	# out instead of switching.
	var twilight := 1.0
	if day_frac < 0.0:
		twilight = clampf(1.0 + day_frac / 0.085, 0.0, 1.0)
	elif day_frac > 1.0:
		twilight = clampf(1.0 - (day_frac - 1.0) / 0.085, 0.0, 1.0)
	var horizon := clampf(elevation / 20.0, 0.0, 1.0)
	var warm := Color(1.0, 0.62, 0.35).lerp(_sun_base_color, horizon)
	var night := Color(0.45, 0.55, 0.80)
	sun.light_color = night.lerp(warm, twilight)
	sun.light_energy = lerpf(0.12, _sun_base_energy * (0.25 + 0.75 * horizon), twilight)
	if sky_mat != null:
		var day_top := Color(0.30, 0.48, 0.72)
		var day_horizon := Color(0.72, 0.78, 0.84)
		var dusk_top := Color(0.16, 0.18, 0.34)
		var dusk_horizon := Color(0.95, 0.55, 0.32)
		var night_top := Color(0.03, 0.04, 0.08)
		var night_horizon := Color(0.10, 0.12, 0.18)
		sky_mat.sky_top_color = night_top.lerp(dusk_top.lerp(day_top, horizon), twilight)
		sky_mat.sky_horizon_color = night_horizon.lerp(dusk_horizon.lerp(day_horizon, horizon), twilight)
		sky_mat.ground_horizon_color = sky_mat.sky_horizon_color.darkened(0.15)
	if sky_env != null:
		sky_env.ambient_light_energy = lerpf(0.15, 0.35 + 0.45 * horizon, twilight)
		sky_env.fog_light_color = sky_mat.sky_horizon_color if sky_mat != null else sky_env.fog_light_color


func set_music(on: bool) -> void:
	music_on = on
	if music_player == null:
		return
	if on and not music_player.playing:
		music_player.play()
	elif not on and music_player.playing:
		music_player.stop()


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"time_of_day": time_of_day, "music": music_on}))


func _load_settings() -> void:
	var hours := time_of_day
	var on := music_on
	if FileAccess.file_exists(SETTINGS_PATH):
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				hours = float((parsed as Dictionary).get("time_of_day", hours))
				on = bool((parsed as Dictionary).get("music", on))
	set_time_of_day(hours)
	set_music(on)
	settings.set_values(time_of_day, music_on)


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

	# The music is off until the options toggle turns it on.
	music_player = _looping_player("res://audio/music_loop.wav", -16.0, "Master")
	music_player.autoplay = false
	if with_hum:
		_looping_player("res://audio/hum_loop.wav", -18.0, "Room")


func _looping_player(path: String, volume_db: float, bus: String) -> AudioStreamPlayer:
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
	return audio_player


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
