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
var with_home := true             # the commissioned starting loop and its HMI
var with_campaign := false        # the milestone ladder gates the build menu
var with_hum := true              # machine-room ambience loop
var campaign: Milestones = null
var journal: MilestonePanel = null
var _journal_refresh := 0.0
var autosave_s := 0.0             # > 0: save this often, and on quit
var _autosave_left := 0.0
var alarms := SimAlarms.new()
var _alarm_scan_left := 0.0
var reverb_room_size := 0.85
var reverb_wet := 0.25

var _loop_players: Array[AudioStreamPlayer] = []

# On-screen options (director, 2026-09-05): the sun follows a
# time-of-day slider and the music is a toggle, off by default. Both
# persist in user://settings.json. Worlds hand their sun (and, outdoors,
# their sky material) to these so one slider serves both worlds.
const SETTINGS_PATH := "user://settings.json"
var sun: DirectionalLight3D = null
var sky_mat: Material = null          # PhysicalSkyMaterial outdoors; a ProceduralSkyMaterial is still honoured
var sky_env: Environment = null
var settings: SettingsPanel
var music_player: AudioStreamPlayer = null
var time_of_day := 10.0
var music_on := false
var graphics := GraphicsSettings.new()   # presets and knobs; see ui/graphics_settings.gd
var _sun_base_energy := 1.5
var _sun_base_color := Color(1.0, 0.97, 0.90)


func _ready() -> void:
	var t_start := Time.get_ticks_msec()
	var t0 := t_start
	_build_world()
	_build_audio()
	var ms_world := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	plant = Plant.new()
	plant.position.y = plant_height
	plant.save_path = plant_save_path
	plant.build_suite = with_suite
	plant.build_home = with_home
	if with_campaign:
		campaign = Milestones.new()
		plant.campaign = campaign
	add_child(plant)
	var ms_plant := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
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
	library = LibraryPanel.new()
	layer.add_child(library)
	journal = MilestonePanel.new()
	layer.add_child(journal)
	settings = SettingsPanel.new()
	layer.add_child(settings)
	settings.on_time_changed = func(hours: float) -> void:
		set_time_of_day(hours)
		_save_settings()
	settings.on_music_changed = func(on: bool) -> void:
		set_music(on)
		_save_settings()
	settings.graphics = graphics
	settings.on_graphics_changed = func() -> void:
		graphics.apply(self)
		_save_settings()
	builder = BuildController.new()
	add_child(builder)
	builder.setup(player, plant, hud)
	var ms_ui := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	if DisplayServer.get_name() == "headless" and campaign != null:
		_campaign_self_check()  # before _after_plant loads a save onto the bare ground
	_after_plant()
	var ms_after := Time.get_ticks_msec() - t0
	print("[flowstate] startup %d ms — world %d · plant %d (self-check %d, home loop %d) · ui %d · after_plant %d"
		% [Time.get_ticks_msec() - t_start, ms_world, ms_plant,
		int(plant.startup_ms.get("self-check", 0)), int(plant.startup_ms.get("home loop", 0)),
		ms_ui, ms_after])
	print("[flowstate] router: %d searches (%d failed), %d cells expanded, %d ms"
		% [PipeRoute.searches, PipeRoute.failures, PipeRoute.expansions, PipeRoute.search_usec / 1000])
	_load_settings()
	hud.toast("WASD move · E use · wheel zoom (ctrl: optic) · B build · C connect · X remove · L library · O options · F5/F9 save/load")
	if DisplayServer.get_name() == "headless" and with_home:
		builder.exercise_device_menu()
	if DisplayServer.get_name() == "headless" and with_home:
		# Ten seconds of the commissioned plant, then the annunciator:
		# the showcase's P-402 runs against a shut head on purpose.
		for _i in roundi(10.0 / Plant.SIM_DT):
			plant.sim.tick()
		var names := PackedStringArray()
		for alarm: Dictionary in alarms.scan(plant.sim):
			names.append("%s %s" % [alarm["tag"], alarm["text"]])
		print("[flowstate] alarm scan — %d active: %s" % [names.size(), "; ".join(names)])
		_report_in = 20  # after the deferred routing pass has settled, see _process


var _report_in: int = 0


## Runs sharing the same space, or through each other, or in the air:
## the walkdown findings the smoke run makes before the director does.
## Frames after startup, so the deferred routing pass has run.
func _headless_reports() -> void:
	var unsupported := plant.unsupported_report()
	print("[flowstate] unsupported runs: %s" % ("none" if unsupported.is_empty() else str(unsupported.size())))
	for line in unsupported:
		print("    " + line)

	var crossings := plant.crossing_report()
	print("[flowstate] run crossings: %s" % ("none" if crossings.is_empty() else str(crossings.size())))
	for line in crossings:
		print("    " + line)
	var overlaps := plant.overlap_report()
	print("[flowstate] run overlaps: %d" % overlaps.size())
	for line in overlaps:
		print("    " + line)
	var through := plant.intersection_report()
	print("[flowstate] runs through solid geometry: %s" % ("none" if through.is_empty() else str(through.size())))
	for line in through:
		print("    " + line)
	var fanouts := plant.fanout_report()
	print("[flowstate] ports with more than one wire: %d" % fanouts.size())
	for line in fanouts:
		print("    " + line)
	# Where the draw calls come from, by owner: the map for any merge.
	for line in DrawCensus.report(self):
		print(line)
	# What a frame's main loop costs without rendering: the views'
	# _process, the HUD, the world. The sim ticks in physics, not here.
	print("[flowstate] main loop: %.1f ms a frame over %d headless frames"
		% [_loop_acc / maxi(_loop_n, 1) * 1000.0, _loop_n])
	if OS.get_environment("FLOWSTATE_LOOP_PROFILE") != "":
		LoopProfile.run(self)  # bisects that loop by node group, then quits


## Environment, geometry, lighting. Override in each world.
func _build_world() -> void:
	pass


## Headless: the ladder starts at the bottom, nothing is met on bare
## ground, and the first rung unlocks the pump.
func _campaign_self_check() -> void:
	var problems: Array[String] = []
	if not campaign.unlocked("tank") or campaign.unlocked("pump") or not campaign.unlocked("s_column"):
		problems.append("base gating wrong")
	var first := campaign.current()
	if str(first.get("id", "")) != "first_water":
		problems.append("ladder does not start at first_water")
	else:
		for req: Dictionary in first["requires"]:
			var p := campaign.progress(plant, req)
			if bool(p["done"]):
				problems.append("'%s' met on bare ground" % p["label"])
	if not campaign.tick(plant).is_empty():
		problems.append("a milestone completed on bare ground")
	campaign.done.append("first_water")
	if not campaign.unlocked("pump") or campaign.unlocked("relay"):
		problems.append("first_water unlocks the wrong things")
	var saved := campaign.state_dict()
	campaign.done.clear()
	campaign.apply_state(saved)
	if not campaign.unlocked("pump"):
		problems.append("campaign state did not round-trip")
	campaign.done.clear()
	if problems.is_empty():
		print("[flowstate] campaign self-check OK — %d milestones, none met on bare ground, the first unlocks the pump"
			% Milestones.LADDER.size())
	else:
		print("[flowstate] campaign self-check FAILED: " + ", ".join(problems))


## Commissioned equipment specific to one world, placed through the
## plant's build API once it exists. Override where needed.
func _after_plant() -> void:
	pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and autosave_s > 0.0 and plant != null:
		plant.save_game()


var _loop_acc := 0.0
var _loop_n := 0


func _process(delta: float) -> void:
	if _report_in > 0:
		_report_in -= 1
		_loop_acc += Performance.get_monitor(Performance.TIME_PROCESS)
		_loop_n += 1
		if _report_in == 0:
			_headless_reports()
	if autosave_s > 0.0 and DisplayServer.get_name() != "headless":
		_autosave_left -= delta
		if _autosave_left <= 0.0:
			_autosave_left = autosave_s
			if plant.save_game():
				hud.toast("autosaved")
	# The annunciator: scan twice a second, ring once per new alarm.
	_alarm_scan_left -= delta
	if _alarm_scan_left <= 0.0:
		_alarm_scan_left = 0.5
		var active := alarms.scan(plant.sim)
		var lines := PackedStringArray()
		for alarm: Dictionary in active:
			lines.append(SimAlarms.line(alarm, plant.sim.time))
		hud.set_alarms(lines)
		if not alarms.new_keys.is_empty():
			EquipmentAudio.play_once(player, "res://audio/beep.wav", Vector3.ZERO, -10.0, 0.8)
	if campaign != null:
		var finished := campaign.tick(plant)
		if not finished.is_empty():
			var names: PackedStringArray = PackedStringArray()
			for type_id: String in finished["unlocks"]:
				names.append(PlantFactory.label_for(type_id))
			hud.toast("MILESTONE — %s.%s" % [finished["title"],
				("  Unlocked: " + ", ".join(names)) if not names.is_empty() else "  The ladder is complete."])
			EquipmentAudio.play_once(player, "res://audio/milestone.wav", Vector3.ZERO, -4.0, 1.0)
			builder.refresh_menu()
		if journal.visible:
			_journal_refresh -= delta
			if _journal_refresh <= 0.0:
				_journal_refresh = 0.5
				journal.refresh(campaign, plant)
	hud.sim_ms = plant.last_tick_ms
	var view := player.look_view()
	_reveal_labels(view)
	if view != null and view.has_method("describe"):
		hud.set_look_text(str(view.call("describe")))
	else:
		hud.set_look_text("")
	if plant.tank == null:
		# A blank map has no starting loop to report on: just the clock,
		# and in the campaign the next thing the plant has to prove.
		var line := "t %s" % _fmt_time(plant.sim.time)
		if campaign != null:
			var milestone := campaign.current()
			if not milestone.is_empty():
				for req: Dictionary in milestone["requires"]:
					var p := campaign.progress(plant, req)
					if not bool(p["done"]):
						line += "   %s — %s %.0f / %.0f %s" % [milestone["title"], p["label"],
							float(p["value"]), float(p["target"]), p["unit"]]
						break
		hud.set_readout_text(line)
		return
	hud.set_readout_text("t %s   level %.1f L   relay %d cyc   pump %s" % [
		_fmt_time(plant.sim.time), plant.tank.level_l, plant.relay.cycles,
		"RUN" if plant.pump.running else "stop"])


## Floating text (equipment names, port tags, line labels) shows only
## on what the crosshair is over (director, 2026-09-13: "remove the
## floating text, perhaps only showing it on hover"). Signs and
## instrument faces are physical and stay. A port fitting under the
## crosshair reveals its owner's labels.
var _labelled: Node = null


func _reveal_labels(view: Node3D) -> void:
	var target: Node = view
	if target == null:
		var collider := player.aimed_collider()
		if collider != null and collider.has_meta("owner_view"):
			target = collider.get_meta("owner_view") as Node
	if target == _labelled:
		return
	if _labelled != null and is_instance_valid(_labelled):
		_set_floating(_labelled, false)
	_labelled = target
	if target != null:
		_set_floating(target, true)


static func _set_floating(root: Node, on: bool) -> void:
	for label in root.find_children("*", "Label3D", true, false):
		if label.has_meta("floating"):
			(label as Label3D).visible = on


## A key or a button may act on the sim (E turns a valve, a click
## places a machine): the scan thread is collected before any handler
## sees the event. Mouse motion never touches the sim and is left alone.
func _input(event: InputEvent) -> void:
	if plant != null and (event is InputEventKey or event is InputEventMouseButton):
		plant._finish_scans()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("library"):
		library.toggle()
		# The panel owns the screen while it is up: free the mouse so the
		# page can be read, and stop the player walking off behind it.
		player.input_locked = library.visible
		MouseMode.set_captured(not library.visible)
	elif event.is_action_pressed("journal") and campaign != null:
		journal.toggle()
		if journal.visible:
			journal.refresh(campaign, plant)
		player.input_locked = journal.visible
		MouseMode.set_captured(not journal.visible)
	elif event.is_action_pressed("options"):
		settings.toggle()
		player.input_locked = settings.visible
		MouseMode.set_captured(not settings.visible)
	elif event.is_action_pressed("quicksave"):
		hud.toast("saved" if plant.save_game() else "save FAILED")
	elif event.is_action_pressed("quickload"):
		hud.toast("loaded" if plant.load_game() else "no save found")
	elif event.is_action_pressed("graphics_preset"):
		# F7: the next preset, applied on the spot, so the frame rate and
		# the picture can be compared without leaving the plant.
		graphics.next_preset()
		graphics.apply(self)
		_save_settings()
		settings.refresh()
		hud.toast("Graphics: " + graphics.summary())


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
	# Below the horizon the same light is the moon: thirty degrees up in
	# the south, dim and blue, so night has shadows and a physical sky
	# renders a faint moonlit dome instead of black.
	sun.rotation_degrees = Vector3(-elevation, azimuth, 0) if up else Vector3(-30.0, 180.0, 0)
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
	sun.light_energy = lerpf(0.35, _sun_base_energy * (0.25 + 0.75 * horizon), twilight)
	if sky_mat is ShaderMaterial:
		# Our sky (world/sky.gdshader) wants the sun's true direction,
		# under the horizon too, and the moon's; and with a dome that is
		# bright at dawn, the direct sun can be as weak as it really is
		# at the horizon, coming up over the first twelve degrees.
		var painted := sky_mat as ShaderMaterial
		var true_elevation := 60.0 * sin(day_frac * PI)
		var sun_basis := Basis.from_euler(Vector3(deg_to_rad(-true_elevation), deg_to_rad(azimuth), 0.0))
		painted.set_shader_parameter("sun_dir", sun_basis.z)
		painted.set_shader_parameter("moon_dir", Basis.from_euler(Vector3(deg_to_rad(-30.0), PI, 0.0)).z)
		var sun_strength := smoothstep(0.0, 1.0, clampf(elevation / 12.0, 0.0, 1.0))
		sun.light_energy = lerpf(0.3, _sun_base_energy * (0.05 + 0.95 * sun_strength), twilight)
	var day_horizon := Color(0.72, 0.78, 0.84)
	var dusk_horizon := Color(0.95, 0.55, 0.32)
	var night_horizon := Color(0.10, 0.12, 0.18)
	var horizon_color := night_horizon.lerp(dusk_horizon.lerp(day_horizon, horizon), twilight)
	if sky_mat is PhysicalSkyMaterial:
		# A low sun leaves a physical sky dim while the real one glows:
		# lift its energy toward the horizon, and let night fade it.
		# Lower at high sun than at a low one: a bright dome tone-maps
		# toward grey, and a crisp day wants its blue kept.
		(sky_mat as PhysicalSkyMaterial).energy_multiplier = \
			lerpf(0.5, 1.4 + 1.6 * (1.0 - horizon), maxf(twilight, 0.25))
	if sky_mat is ProceduralSkyMaterial:
		# The painted sky: its colours follow the clock by hand. A
		# physical sky needs nothing here; it follows the sun itself.
		var painted := sky_mat as ProceduralSkyMaterial
		var day_top := Color(0.30, 0.48, 0.72)
		var dusk_top := Color(0.16, 0.18, 0.34)
		var night_top := Color(0.03, 0.04, 0.08)
		painted.sky_top_color = night_top.lerp(dusk_top.lerp(day_top, horizon), twilight)
		painted.sky_horizon_color = horizon_color
		painted.ground_horizon_color = horizon_color.darkened(0.15)
	if sky_env != null:
		if sky_mat is PhysicalSkyMaterial or sky_mat is ShaderMaterial:
			# The ambient follows the clock by hand: blue-grey by day, warm
			# at dusk, blue at night (a physical sky's dome went dim long
			# before the real one stopped lighting the ground; our own sky
			# could supply it, but the tuned colours are kept). The sky
			# supplies the reflections.
			var day_amb := Color(0.62, 0.68, 0.78)
			var dusk_amb := Color(0.62, 0.44, 0.34)
			var night_amb := Color(0.14, 0.18, 0.28)
			sky_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			sky_env.ambient_light_color = night_amb.lerp(dusk_amb.lerp(day_amb, horizon), twilight)
			sky_env.ambient_light_energy = lerpf(0.55, 0.66 + 0.04 * horizon, twilight)
		else:
			sky_env.ambient_light_energy = lerpf(0.25, 0.55 + 0.05 * horizon, twilight)
		sky_env.fog_light_color = horizon_color
	_on_time_of_day(horizon, twilight)


## A world's own response to the clock: hall lights, stars. horizon is
## 0 at the horizon and 1 with the sun 20 degrees up; twilight is 1 by
## day and 0 by night.
func _on_time_of_day(_horizon: float, _twilight: float) -> void:
	pass


## The graphics options (2026-09-12): GraphicsSettings holds the values
## and applies them; the options panel edits them, F7 cycles the
## presets, and the frame-rate overlay shows what each costs. The old
## "high lighting" toggle (SDFGI and volumetric fog) is the Ultra preset.
func apply_graphics() -> void:
	graphics.apply(self)


func set_music(on: bool) -> void:
	music_on = on
	if music_player == null:
		return
	if on and not music_player.playing:
		# Headless runs never start a stream (see _looping_player): a
		# saved "music on" would otherwise leak its playback at exit.
		if DisplayServer.get_name() != "headless":
			music_player.play()
	elif not on and music_player.playing:
		music_player.stop()


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"time_of_day": time_of_day, "music": music_on,
		"graphics": graphics.to_dict()}))


func _load_settings() -> void:
	var hours := time_of_day
	var on := music_on
	if FileAccess.file_exists(SETTINGS_PATH):
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				var saved := parsed as Dictionary
				hours = float(saved.get("time_of_day", hours))
				on = bool(saved.get("music", on))
				if saved.get("graphics") is Dictionary:
					graphics.from_dict(saved["graphics"])
				elif bool(saved.get("high_lighting", false)):
					graphics.set_preset("Ultra")  # the toggle this replaced
	set_time_of_day(hours)
	set_music(on)
	graphics.apply(self)
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

	# The music is off until the options toggle turns it on (director,
	# 2026-09-05: it must not play for the seconds before the settings
	# load, so it is never told to autoplay at all).
	music_player = _looping_player("res://audio/music_loop.wav", -16.0, "Master", false)
	if with_hum:
		_looping_player("res://audio/hum_loop.wav", -18.0, "Room")


func _looping_player(path: String, volume_db: float, bus: String,
		autoplay: bool = true) -> AudioStreamPlayer:
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
	audio_player.autoplay = autoplay and DisplayServer.get_name() != "headless"
	add_child(audio_player)
	_loop_players.append(audio_player)
	return audio_player


func _exit_tree() -> void:
	for audio_player in _loop_players:
		audio_player.stop()


## Where the static boxes go: the world itself, or a container a world
## sets while it builds something it will merge as one (the hall).
var _box_parent: Node3D = null


func _static_box(size: Vector3, pos: Vector3, color: Color, material: Material = null) -> void:
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
	# Pads, floors, walls: concrete and paint, or a floor shader.
	mesh.material_override = material if material != null else ViewUtil.matte(color)
	body.add_child(mesh)
	(_box_parent if _box_parent != null else self).add_child(body)


## The plant floor: matte off-white tiles with grout, world-space, so
## every slab tiles alike (director, 2026-09-12).
static func tile_floor() -> ShaderMaterial:
	return StructureFactory.tile_floor()
