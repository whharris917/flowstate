class_name MeteringPumpView
extends Node3D
## Renders a SimMeteringPump: a diaphragm dosing pump — a painted drive
## housing on a base plate, the liquid end a round head on the line's
## axis with its two check-valve fittings, a stroke-length dial on the
## housing whose pointer follows the real stroke, a run lamp, and a
## motor cowl at the back. The drive ticks while it doses (a loop off
## the real running state) and clunks on start and stop. E is the
## switch when nothing is wired to run. Built at the bore of the line
## on it; the head keeps its size, the dose is what changes.

const LINE_Y := 0.32
const HALF := 0.30

var pump: SimMeteringPump
var bore := 0.07
var _lamp: StandardMaterial3D
var _pointer: Node3D
var _drive: EquipmentAudio
var _was_running := false
var _last_stroke := -1.0


func set_bore(r: float) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_pointer = null
	_drive = null
	setup(pump, r)


func setup(pump_: SimMeteringPump, bore_r: float = 0.07) -> void:
	pump = pump_
	bore = bore_r
	var half := SmallBoreUtil.half_for(HALF, bore_r)
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.22, 0.23, 0.25))
	var housing := ViewUtil.flat(Color(0.16, 0.36, 0.62))
	var head_mat := ViewUtil.flat(Color(0.86, 0.87, 0.85))
	# Base plate with its feet, the housing on it, the motor cowl behind.
	ViewUtil.box(self, Vector3(0.34, 0.02, 0.24), Vector3(0.04, 0.01, 0), dark)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ViewUtil.cylinder(self, 0.008, 0.02, Vector3(0.04 + corner.x * 0.15, 0.03, corner.y * 0.10), dark)
	ViewUtil.box(self, Vector3(0.24, 0.24, 0.20), Vector3(0.06, 0.16, 0), housing)
	var cowl := ViewUtil.cylinder(self, 0.06, 0.10, Vector3(0.06, 0.20, -0.14), housing)
	cowl.rotation_degrees = Vector3(90, 0, 0)
	for i in 5:
		var fin := ViewUtil.cylinder(self, 0.064, 0.006, Vector3(0.06, 0.20, -0.11 - i * 0.016), dark)
		fin.rotation_degrees = Vector3(90, 0, 0)
	# The liquid end: a round head on the axis, bolted to the housing
	# face, with the line's fittings on its two check valves.
	var head := ViewUtil.cylinder(self, 0.075, 0.09, Vector3(-0.10, LINE_Y, 0), head_mat)
	head.rotation_degrees = Vector3(0, 0, 90)
	for i in 6:
		var a := TAU / 6.0 * i
		var bolt := ViewUtil.cylinder(self, 0.006, 0.01, Vector3(-0.15, LINE_Y + cos(a) * 0.058, sin(a) * 0.058), dark)
		bolt.rotation_degrees = Vector3(0, 0, 90)
	# The check-valve bodies either side of the head, then the spools out.
	for side: float in [-1.0, 1.0]:
		var cv := ViewUtil.cylinder(self, maxf(bore_r * 1.4, 0.016), 0.05,
			Vector3(-0.10 + side * 0.07, LINE_Y, 0), steel)
		(cv.mesh as CylinderMesh).radial_segments = 6
		cv.rotation_degrees = Vector3(0, 0, 90)
	SmallBoreUtil.spool(self, -half, -0.195, LINE_Y, bore_r, steel)
	SmallBoreUtil.spool(self, -0.005, half, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, -half, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, half, LINE_Y, bore_r, steel)
	# The stroke dial on the housing front, its pointer held.
	var dial := ViewUtil.cylinder(self, 0.035, 0.008, Vector3(0.10, 0.20, 0.104), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	dial.rotation_degrees = Vector3(90, 0, 0)
	for i in 11:
		var a := deg_to_rad(-135.0 + 27.0 * i)
		var tick := ViewUtil.box(self, Vector3(0.003, 0.008, 0.002), Vector3.ZERO, dark)
		tick.position = Vector3(0.10 + sin(a) * 0.029, 0.20 + cos(a) * 0.029, 0.109)
		tick.rotation.z = -a
	_pointer = Node3D.new()
	_pointer.position = Vector3(0.10, 0.20, 0.110)
	add_child(_pointer)
	ViewUtil.box(_pointer, Vector3(0.004, 0.026, 0.003), Vector3(0, 0.013, 0), ViewUtil.flat(Color(0.80, 0.16, 0.12)))
	var hub := ViewUtil.cylinder(_pointer, 0.006, 0.006, Vector3.ZERO, dark)
	hub.rotation_degrees = Vector3(90, 0, 0)
	# The run lamp above the dial.
	_lamp = ViewUtil.glow(Color(0.10, 0.80, 0.35), 1.2)
	var lamp := ViewUtil.cylinder(self, 0.008, 0.006, Vector3(0.10, 0.265, 0.104), _lamp)
	lamp.rotation_degrees = Vector3(90, 0, 0)
	var plate := ViewUtil.plate(self, "DOSING PUMP", Vector3(0.02, 0.255, 0.106))
	plate.font_size = 9
	plate.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var tag := ViewUtil.label(self, pump.comp_name, Vector3(0, 0.55, 0))
	tag.font_size = 24
	ViewUtil.interact_body(self, Vector3(0.62, 0.42, 0.34), Vector3(0.02, 0.21, 0))
	_drive = EquipmentAudio.make(self, "res://audio/dosing_loop.wav", Vector3(0.06, 0.2, 0), -14.0)
	_was_running = pump.running
	_place_pointer()


func _place_pointer() -> void:
	if _pointer != null:
		# 0 % at the left stop, 100 % at the right: 270 degrees of dial.
		_pointer.rotation.z = deg_to_rad(135.0 - 270.0 * pump.stroke_now / 100.0)


func _process(_delta: float) -> void:
	if pump == null:
		return
	var on := pump.running
	_lamp.albedo_color = Color(0.10, 0.80, 0.35) if on else Color(0.20, 0.24, 0.20)
	_lamp.emission_energy_multiplier = 1.2 if on else 0.0
	if _drive != null:
		_drive.set_running(on and pump.flow_lps > 0.0)
	if on != _was_running:
		_was_running = on
		EquipmentAudio.play_once(self, "res://audio/clunk.wav", Vector3(0.06, 0.2, 0), -16.0, 1.6 if on else 1.3)
	if pump.stroke_now != _last_stroke:
		_last_stroke = pump.stroke_now
		_place_pointer()


func describe() -> String:
	var cmd := ("HAND %s · E to %s" % ["ON" if pump.hand_on else "OFF", "stop" if pump.hand_on else "start"]) \
		if pump.is_hand_operated else ("run " + ("ON" if pump.run.value > 0.5 else "OFF"))
	return "%s — metering pump, %s at full stroke, %.0f m maximum\n%s · %s · stroke %.0f %% · dosing %s · lifting %.1f m · %d starts" % [
		pump.comp_name, SimTypes.flow_text(pump.rated_lps), pump.max_head_m, cmd, pump.status(),
		pump.stroke_now, SimTypes.flow_text(pump.flow_lps), pump.head_pa / SimHydraulics.HEAD_PA_PER_M, pump.starts]


## E: the switch on the pump, while nothing is wired to run it.
func use() -> void:
	if pump.is_hand_operated:
		pump.hand_on = not pump.hand_on
