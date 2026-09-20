class_name SolenoidValveView
extends Node3D
## Renders a SimSolenoidValve: a brass body on the line with the coil
## can standing on it, a DIN connector on the can with a cable gland
## (the coil's fitting lands there) and a lamp lit while the coil is
## energized. A click each time the plunger moves — a real edge in the
## sim. Built at the bore of the line on it.

const LINE_Y := 0.32
const HALF := 0.20

var valve: SimSolenoidValve
var bore := 0.07
var _lamp: StandardMaterial3D
var _was_energized := false


func set_bore(r: float) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	setup(valve, r)


func setup(valve_: SimSolenoidValve, bore_r: float = 0.07) -> void:
	valve = valve_
	bore = bore_r
	var half := SmallBoreUtil.half_for(HALF, bore_r)
	var s := SmallBoreUtil.body_scale(bore_r)
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var brass := ViewUtil.flat(Color(0.72, 0.60, 0.34))
	var black := ViewUtil.flat(Color(0.12, 0.12, 0.13))
	var body_w := 0.10 * s + 0.04
	ViewUtil.box(self, Vector3(body_w, 0.07 * s + 0.03, 0.07 * s + 0.03), Vector3(0, LINE_Y, 0), brass)
	SmallBoreUtil.spool(self, -half, -body_w / 2.0, LINE_Y, bore_r, steel)
	SmallBoreUtil.spool(self, body_w / 2.0, half, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, -half, LINE_Y, bore_r, steel)
	SmallBoreUtil.port_end(self, half, LINE_Y, bore_r, steel)
	# The coil can on its tube, and the connector on the can.
	var can_r := 0.026 * s + 0.014
	var can_h := 0.07 * s + 0.03
	var can_base := LINE_Y + 0.035 * s + 0.015
	ViewUtil.cylinder(self, can_r * 0.45, 0.012, Vector3(0, can_base + 0.006, 0), steel)
	ViewUtil.cylinder(self, can_r, can_h, Vector3(0, can_base + 0.012 + can_h / 2.0, 0), black)
	var can_top := can_base + 0.012 + can_h
	ViewUtil.cylinder(self, 0.006, 0.02, Vector3(0, can_top + 0.01, 0), steel)
	ViewUtil.box(self, Vector3(0.03, 0.03, 0.03), Vector3(0, can_top - can_h * 0.35, can_r + 0.012), black)
	_lamp = ViewUtil.glow(Color(0.10, 0.80, 0.35), 1.2)
	var lamp := ViewUtil.cylinder(self, 0.005, 0.006, Vector3(0, can_top - can_h * 0.35 + 0.008, can_r + 0.03), _lamp)
	lamp.rotation_degrees = Vector3(90, 0, 0)
	var tag := ViewUtil.label(self, valve.comp_name, Vector3(0, can_top + 0.20, 0))
	tag.font_size = 24
	ViewUtil.interact_body(self, Vector3(half * 2.0, can_top + 0.03 - LINE_Y + 0.12, 0.16),
		Vector3(0, (LINE_Y + can_top) / 2.0, 0))
	_was_energized = valve.energized


func _process(_delta: float) -> void:
	if valve == null:
		return
	var on := valve.energized
	_lamp.albedo_color = Color(0.10, 0.80, 0.35) if on else Color(0.20, 0.24, 0.20)
	_lamp.emission_energy_multiplier = 1.2 if on else 0.0
	if on != _was_energized:
		_was_energized = on
		EquipmentAudio.play_once(self, "res://audio/relay_click.wav", Vector3(0, LINE_Y + 0.08, 0), -10.0,
			1.3 if on else 1.1)


func describe() -> String:
	var state := "OPEN" if valve.position >= 99.5 else ("SHUT" if valve.position <= 0.5 else "%.0f %%" % valve.position)
	var coil := "coil ENERGIZED" if valve.energized else "coil de-energized"
	if valve.coil.wire_count == 0:
		coil += " (nothing wired to it: it stays shut)"
	return "%s — solenoid valve, %s at 1 bar, normally closed\n%s · %s · passing %s · %d cycles" % [
		valve.comp_name, SimTypes.flow_text(valve.cv_lps), coil, state,
		SimTypes.flow_text(valve.flow_lps), valve.cycles]


func use() -> void:
	pass
