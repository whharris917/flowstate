class_name CourthouseSquare
extends Node3D
## The courthouse square in Monroe and the town round it.

var k: CourthouseKit
var stats: Dictionary = {}
var lamp_mat: StandardMaterial3D
var lights: Array[Dictionary] = []


func build() -> void:
	name = "CourthouseSquare"
	var t0 := Time.get_ticks_msec()
	var solids := Node3D.new()
	solids.name = "Solids"
	add_child(solids)
	k = CourthouseKit.new(solids)
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = load("res://world/town_wall.gdshader")
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.82, 0.58)
	var g := Transform3D()
	k.m.quad("wall", Vector3(-400, 0, -400), Vector3(400, 0, -400), Vector3(400, 0, 400), Vector3(-400, 0, 400), Vector3.UP,
		CourthouseKit.kc(Color(0.32, 0.42, 0.18), CourthouseKit.K_LAWN))
	k.m.commit(self, {"wall": wall_mat, "lamp": lamp_mat}, ["wall"])
	stats = {"triangles": k.m.triangles, "solids": k.solid_count, "ms": Time.get_ticks_msec() - t0}


func set_darkness(dark: float) -> void:
	lamp_mat.emission_energy_multiplier = 3.0 * smoothstep(0.35, 0.6, dark)
