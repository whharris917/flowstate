class_name VialTrackView
extends VialPartView
## Renders a SimVialTrack: a slat-top chain belt between guide rails set
## to the line's vial, on a stainless frame at bench height with legs,
## the drive at the outfeed end and the idler at the infeed. The view's
## origin is the middle of the track: vials enter at -L/2 and leave at
## +L/2, and s along the kernel is x + L/2. The belt's slats move at the
## real belt speed while it runs; the drive hums while it does.

const WIDTH := 0.083      # the chain: 82.5 mm, the common slat-top size

var track: SimVialTrack
var _belt_mat: ShaderMaterial
var _vials: VialDraw
var _lamp: StandardMaterial3D
var _motor: EquipmentAudio = null
var _travel := 0.0


static func anchors(length_m: float) -> Dictionary:
	var end := length_m / 2.0
	return {
		"run": {"pos": Vector3(end - 0.08, 0.62, 0.13), "dir": Vector3.BACK},
		"power": {"pos": Vector3(end - 0.20, 0.62, 0.13), "dir": Vector3.BACK},
	}


func _build() -> void:
	track = record as SimVialTrack
	var length := track.length_m
	var half := length / 2.0
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.24, 0.25, 0.27))
	var row := vial_row()
	var d: float = row[0]
	var h: float = row[1]
	# The belt: one plane the length of the track, its slats a shader.
	var belt := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(length, WIDTH)
	belt.mesh = plane
	_belt_mat = ShaderMaterial.new()
	_belt_mat.shader = load("res://components/belt.gdshader") as Shader
	_belt_mat.set_shader_parameter("length_m", length)
	belt.material_override = _belt_mat
	belt.position = Vector3(0, DECK, 0)
	add_child(belt)
	# The chain's return and the frame: two side channels under the belt.
	for z: float in [-1.0, 1.0]:
		ViewUtil.box(self, Vector3(length, 0.05, 0.006), Vector3(0, DECK - 0.03, z * (WIDTH / 2.0 + 0.006)), steel)
	ViewUtil.box(self, Vector3(length, 0.004, WIDTH), Vector3(0, DECK - 0.05, 0), dark)
	# Guide rails on posts, a hand's clearance either side of the vial,
	# at two thirds of its height.
	var rail_y := DECK + h * 0.62
	var rail_z := d / 2.0 + 0.004
	for z: float in [-1.0, 1.0]:
		ViewUtil.box(self, Vector3(length, 0.006, 0.004), Vector3(0, rail_y, z * (rail_z + 0.002)), steel)
		var posts := maxi(2, ceili(length / 0.5) + 1)
		for i in posts:
			var x := -half + 0.04 + (length - 0.08) * float(i) / float(posts - 1)
			ViewUtil.box(self, Vector3(0.008, rail_y - DECK + 0.03, 0.008),
				Vector3(x, (rail_y + DECK - 0.03) / 2.0, z * (WIDTH / 2.0 + 0.016)), steel)
	# Legs every metre and a bit, with feet and a stretcher.
	var pairs := maxi(2, ceili(length / 1.2) + 1)
	for i in pairs:
		var x := -half + 0.1 + (length - 0.2) * float(i) / float(pairs - 1)
		for z: float in [-1.0, 1.0]:
			ViewUtil.box(self, Vector3(0.03, DECK - 0.06, 0.03), Vector3(x, (DECK - 0.06) / 2.0, z * 0.06), steel)
			ViewUtil.cylinder(self, 0.025, 0.012, Vector3(x, 0.006, z * 0.06), dark)
		ViewUtil.box(self, Vector3(0.02, 0.02, 0.12), Vector3(x, 0.18, 0), steel)
	# The idler at the infeed and the drive at the outfeed: sprocket
	# housings, and a gear motor under the drive end.
	for x: float in [-half, half]:
		var housing := ViewUtil.cylinder(self, 0.035, WIDTH + 0.02, Vector3(x, DECK - 0.03, 0), steel)
		housing.rotation_degrees = Vector3(90, 0, 0)
	var motor := ViewUtil.cylinder(self, 0.045, 0.16, Vector3(half - 0.14, DECK - 0.13, 0.05), ViewUtil.flat(Color(0.20, 0.34, 0.55)))
	motor.rotation_degrees = Vector3(90, 0, 0)
	ViewUtil.box(self, Vector3(0.09, 0.09, 0.07), Vector3(half - 0.14, DECK - 0.13, -0.06), dark)
	ViewUtil.box(self, Vector3(0.22, 0.12, 0.02), Vector3(half - 0.14, 0.62, 0.12), dark)
	_lamp = ViewUtil.glow(Color(0.1, 0.8, 0.3), 1.0)
	ViewUtil.cylinder(self, 0.007, 0.01, Vector3(half - 0.04, 0.66, 0.131), _lamp).rotation_degrees = Vector3(90, 0, 0)
	_vials = VialDraw.new()
	_vials.set_meta("no_merge", true)
	add_child(_vials)
	var tag := ViewUtil.label(self, track.comp_name, Vector3(0, DECK + 0.25, 0))
	tag.font_size = 24
	ViewUtil.interact_body(self, Vector3(length, 0.16, 0.16), Vector3(0, DECK, 0))
	if DisplayServer.get_name() != "headless":
		_motor = EquipmentAudio.make(self, "res://audio/motor_loop.wav", Vector3(half - 0.14, DECK - 0.13, 0), -24.0, 1.6)


func item_points() -> Dictionary:
	var half := track.length_m / 2.0
	return {"infeed": Vector3(-half, DECK, 0), "outfeed": Vector3(half, DECK, 0)}


func _process(delta: float) -> void:
	if track == null:
		return
	if track.running:
		_travel = fmod(_travel + track.speed_mps * delta, 1000.0)
	_belt_mat.set_shader_parameter("travel_m", _travel)
	_lamp.emission_energy_multiplier = 1.0 if track.running else 0.0
	_lamp.albedo_color = Color(0.1, 0.8, 0.3) if track.running else Color(0.2, 0.24, 0.2)
	if _motor != null:
		_motor.set_running(track.running)
	var half := track.length_m / 2.0
	var items: Array = []
	for pair: Array in smoothed(track.vials(), delta):
		items.append([pair[0], Vector3(float(pair[1]) - half, DECK + BELT / 2.0, 0)])
	_vials.draw(items)


func describe() -> String:
	var state := "RUNNING" if track.running else ("STOPPED" if track.power.value > 0.5 else "STOPPED · NO 24 V")
	var how := " · E starts and stops it (nothing wired to run)" if track.is_hand_operated else ""
	return "%s — vial track, %.1f m at %.2f m/s\n%s · %d vials on it, %.1f mL in them%s" % [
		track.comp_name, track.length_m, track.speed_mps, state, track.vials_on, track.held_l * 1000.0, how]


func use() -> void:
	if track.is_hand_operated:
		track.hand_on = not track.hand_on
		EquipmentAudio.play_once(self, "res://audio/relay_click.wav", Vector3(track.length_m / 2.0, 0.62, 0.12), -10.0)
