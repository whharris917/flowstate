extends Node
## Headless diagnostic: boots the sandbox and prints Unit 400's fill
## path every ten simulated seconds for four minutes — step, sump
## level, XV-404 travel and flow, the mixer tee's node pressure and
## the sump inlet's — so a stalled step can be read off, not guessed.
##   godot --headless --path game res://world/u400_probe.tscn


func _ready() -> void:
	MouseMode.probe = true
	var world: Node = (load("res://world/sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	var plant: Plant = (world as WorldBase).plant
	var sim := plant.sim
	var sump := sim.get_component("t_403") as SimTank
	var xv := sim.get_component("xv_404") as SimBlockValve
	var tee := sim.get_component("tee_403m") as SimTee
	var plc := sim.get_component(plant.cabinet_plc("u400_cab")) as SimPLC
	var header := sim.get_component("supply_401") as SimSource
	for i in 24:
		for _j in roundi(10.0 / Plant.SIM_DT):
			sim.tick()
		var step := -1
		for k in 5:
			if plc != null and plc.mem[k]:
				step = k
		print("[u400] t=%3d s step %d · T-403 %.0f L · XV-404 %s %.0f %% flow %.2f L/s · header %.0f kPa · tee %.1f kPa (a %.2f c %.2f out %.2f L/s) · sump inlet %.1f kPa" % [
			(i + 1) * 10, step, sump.level_l, xv.state(), xv.position, xv.flow_lps,
			sim.pressure_at(header.outputs["outlet"]) / 1000.0,
			sim.pressure_at(tee.outputs["out"]) / 1000.0,
			tee.inputs["a"].flow_lps, tee.inputs["c"].flow_lps, tee.outputs["out"].flow_lps,
			sim.pressure_at(sump.inputs["inlet"]) / 1000.0])
	get_tree().quit()
