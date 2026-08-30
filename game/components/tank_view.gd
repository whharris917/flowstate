class_name TankView
extends Node3D
## Renders a SimTank: translucent shell, opaque fill column whose height
## is the actual level fraction, trip-band rings. Render only — all
## numbers come from the sim record.

const HEIGHT := 2.2
const RADIUS := 0.8

var tank: SimTank
var switch: SimFloatSwitch
var _fill: MeshInstance3D


func setup(tank_: SimTank, switch_: SimFloatSwitch) -> void:
	tank = tank_
	switch = switch_
	var shell_mat := ViewUtil.flat(Color(0.55, 0.62, 0.70, 0.28))
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ViewUtil.cylinder(self, RADIUS, HEIGHT, Vector3(0, HEIGHT / 2.0, 0), shell_mat)
	_fill = ViewUtil.cylinder(self, RADIUS * 0.9, 1.0, Vector3.ZERO,
		ViewUtil.flat(Color(0.16, 0.47, 0.84)))
	for trip_l: float in [switch.low_l, switch.high_l]:
		ViewUtil.cylinder(self, RADIUS + 0.03, 0.02,
			Vector3(0, _y_for_level(trip_l), 0), ViewUtil.flat(Color(0.54, 0.53, 0.51)))
	ViewUtil.label(self, tank.comp_name, Vector3(0, HEIGHT + 0.45, 0))
	ViewUtil.interact_body(self, Vector3(RADIUS * 2.2, HEIGHT, RADIUS * 2.2),
		Vector3(0, HEIGHT / 2.0, 0))


func _y_for_level(level_l: float) -> float:
	return HEIGHT * clampf(level_l / tank.capacity_l, 0.0, 1.0)


func _process(_delta: float) -> void:
	var height := maxf(_y_for_level(tank.level_l), 0.001)
	_fill.scale = Vector3(1, height, 1)
	_fill.position = Vector3(0, height / 2.0, 0)


func describe() -> String:
	return "%s — %.1f / %.0f L\ndrain %.1f L/s · trips %.0f/%.0f L\noverflowed %.1f L · ran dry %.1f s" % [
		tank.comp_name, tank.level_l, tank.capacity_l, tank.drain_lps,
		switch.low_l, switch.high_l, tank.overflowed_l, tank.ran_dry_ticks * 0.05]


func use() -> void:
	pass  # nothing to operate on the tank itself yet
