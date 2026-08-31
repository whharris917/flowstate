extends Node
## Debug harness: boots the sandbox (which builds the showcase) and
## screenshots the unit area — aerial overview, Unit 100, and the MCC
## zone — after letting the processes run a few seconds.
## Run windowed: godot --path game res://world/showcase_probe.tscn


func _ready() -> void:
	var world: Node = (load("res://world/sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	_run(world)


func _run(world: Node) -> void:
	await get_tree().create_timer(4.0).timeout  # let loops move
	var player: Player = (world as WorldBase).player

	player.global_position = Vector3(26.0, 0.15, 26.0)
	player.zoom_t = 2.4
	player._zoom_now = 2.4
	player.camera.rotation.x = -0.62
	await get_tree().create_timer(0.8).timeout
	await _shot("user://probe_showcase_aerial.png")

	player.global_position = Vector3(16.0, 0.15, 1.5)
	player.rotation.y = 0.0  # facing -z, toward Unit 100
	player.zoom_t = 0.55
	player._zoom_now = 0.55
	player.camera.rotation.x = -0.25
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_showcase_u100.png")

	player.global_position = Vector3(16.5, 0.15, 12.5)
	player.rotation.y = 0.0
	player.zoom_t = 0.5
	player._zoom_now = 0.5
	player.camera.rotation.x = -0.2
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_showcase_mcc.png")

	player.global_position = Vector3(31.5, 0.15, -11.5)
	player.rotation.y = PI  # facing +z, into the synthesis train
	player.zoom_t = 0.85
	player._zoom_now = 0.85
	player.camera.rotation.x = -0.32
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_showcase_u300.png")

	# Honest numbers, not just pictures: after ~6 s of sim the boiler
	# should be firing, both feeds moving, and the reactor warming.
	var plant := (world as WorldBase).plant
	var sg := plant.sim.get_component("sg_301") as SimSteamGen
	var reac := plant.sim.get_component("r_301") as SimReactor
	var cx := plant.sim.get_component("cx_303") as SimCrystallizer
	var fuge := plant.sim.get_component("cf_301") as SimCentrifuge
	var dryer := plant.sim.get_component("dr_305") as SimDryer
	var still := plant.sim.get_component("st_307") as SimStill
	var solvent_tank := plant.sim.get_component("sv_308") as SimTank
	var product_tank := plant.sim.get_component("pt_300") as SimTank
	# Steam is material now, so read the rate off the stream, not off
	# the port float, which no longer carries it.
	print("[probe] u300 front: steam %.2f kg/s at %.0f C · duty->%.0f kW · reactor %.0f L %.1f C %.1f%% pure" % [
		sg.steam.stream.flow_lps, sg.steam.stream.temp_c, reac.heat_duty.value,
		reac.volume_l, reac.temp_c, reac.purity_frac * 100.0])
	print("[probe] u300 sep:   crystallizer %.0f L %.1f C %.1f%% solids (%s) · fuge %s cake %.2f L/s liquor %.2f L/s" % [
		cx.volume_l, cx.temp_c, cx.solids_frac * 100.0,
		"supersat" if cx.supersaturation > 0.0 else "undersat",
		"SPIN" if fuge.spinning else "idle", fuge.cake_lps, fuge.liquor_lps])
	print("[probe] u300 back:  dryer %s evap %.3f L/s · still boilup %.2f L/s -> distillate %.2f L/s (%.0f L recovered)" % [
		"RUN" if dryer.running else "off", dryer.evap_lps,
		still.boilup_lps, still.distillate_lps, still.recovered_l])
	print("[probe] u300 tanks: solvent %.0f L (%.0f%% solvent) · product silo %.0f L (%.0f%% product)" % [
		solvent_tank.level_l, solvent_tank.contents.frac(SimSpecies.SOLVENT) * 100.0,
		product_tank.level_l, product_tank.purity_frac() * 100.0])
	player.global_position = Vector3(47.5, 0.15, -9.5)
	player.rotation.y = PI  # facing +z, along the cake side
	player.zoom_t = 0.55
	player._zoom_now = 0.55
	player.camera.rotation.x = -0.2
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_showcase_vialfill.png")

	# The recycle side: liquor tank, still, solvent tank, recycle pump.
	# rotation.y = 0 faces -z, which is where this equipment sits.
	player.global_position = Vector3(41.0, 0.15, 12.5)
	player.rotation.y = 0.0
	player.zoom_t = 0.8
	player._zoom_now = 0.8
	player.camera.rotation.x = -0.24
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_showcase_recycle.png")

	var filler := plant.sim.get_component("vf_310") as SimVialFiller
	print("[probe] vf_310: %s · %d vials · drawing %.4f L/s · filling at %.1f%% product" % [
		filler.state, filler.vials_done, filler.draw.value, filler.fill_purity * 100.0])
	var lock := plant.sim.get_component("vl_302") as SimVacuumLock
	print("[probe] vl_302: %s · %.1f kPa · condensate %.1f L · %d bursts" % [
		lock.state, lock.press_pa / 1000.0, lock.condensate_l, lock.vent_bursts_done])
	# Soak: advance the kernel twenty minutes at once and report again.
	# A train can look right in the first seconds and still not close;
	# this is where the recycle either works or does not.
	var fed_before := _fed_in(plant)
	var held_before := _held(plant)
	plant.sim.run_for(1200.0)
	print("[probe] --- after a simulated 20 minutes ---")
	print("[probe] reactor %.0f L %.1f C · %.1f%% product %.1f%% impurity" % [
		reac.volume_l, reac.temp_c, reac.purity_frac * 100.0, reac.impurity_frac * 100.0])
	print("[probe] crystallizer %.0f L %.1f C · %.1f%% solids (%s)" % [
		cx.volume_l, cx.temp_c, cx.solids_frac * 100.0,
		"supersat" if cx.supersaturation > 0.0 else "undersat"])
	print("[probe] fuge cake %.2f L/s liquor %.2f L/s · dryer evap %.3f L/s" % [
		fuge.cake_lps, fuge.liquor_lps, dryer.evap_lps])
	print("[probe] still distillate %.2f L/s · %.0f L recovered · solvent tank %.0f L at %.0f%% solvent" % [
		still.distillate_lps, still.recovered_l, solvent_tank.level_l,
		solvent_tank.contents.frac(SimSpecies.SOLVENT) * 100.0])
	print("[probe] product silo %.0f L at %.1f%% product · %d vials filled" % [
		product_tank.level_l, product_tank.purity_frac() * 100.0, filler.vials_done])
	# Material balance around the whole unit: what came in across the
	# plant boundary has to still be somewhere.
	var fed := _fed_in(plant) - fed_before
	var gained := _held(plant) - held_before
	print("[probe] balance: fed %.1f L, accounted %.1f L (%.1f%% closed)" % [
		fed, gained, 100.0 * (1.0 - absf(fed - gained) / maxf(fed, 1.0))])

	var bad: Array[String] = []
	for visual: Dictionary in plant._wire_visuals:
		var node: Node = visual["node"]
		if node is PipeView and (node as PipeView)._unsupported:
			bad.append("%s->%s" % [visual["a"], visual["b"]])
	print("[probe] unsupported runs: %s" % ("none" if bad.is_empty() else ", ".join(bad)))
	print("[probe] showcase screenshots written to user://")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


## Fresh material crossing the plant boundary. Mostly the headers, plus
## one input that is easy to miss: the transfer lock knocks condensate
## out of the humid air it vents, and that water is real material
## entering from outside the modelled system. Leave it out and the
## balance looks like the plant is manufacturing water.
func _fed_in(plant: Plant) -> float:
	var total := 0.0
	for header: String in ["supply_301a", "supply_301b", "supply_bfw", "supply_solv"]:
		var src := plant.sim.get_component(header) as SimSource
		if src != null:
			total += src.total_l
	var lock := plant.sim.get_component("vl_302") as SimVacuumLock
	if lock != null:
		total += lock.cycles * SimVacuumLock.CONDENSATE_PER_CYCLE_L + lock.condensate_l
	return total


## Everything currently inside Unit 300, plus everything that has left
## it. The two together are what the headers fed in.
func _held(plant: Plant) -> float:
	var total := 0.0
	for vessel: String in ["r_301", "cx_303"]:
		var comp := plant.sim.get_component(vessel)
		if comp is SimReactor:
			var r := comp as SimReactor
			total += r.volume_l + r.boiled_off_l + r.overflowed_l
		elif comp is SimCrystallizer:
			var c := comp as SimCrystallizer
			total += c.volume_l + c.overflowed_l
	for tank_name: String in ["ht_304", "pt_300", "lt_306", "sv_308"]:
		var tank := plant.sim.get_component(tank_name) as SimTank
		if tank != null:
			total += tank.level_l + tank.overflowed_l
	for drain_name: String in ["du_301", "du_302"]:
		var drain := plant.sim.get_component(drain_name) as SimDrain
		if drain != null:
			total += drain.total_l
	var dryer := plant.sim.get_component("dr_305") as SimDryer
	if dryer != null:
		total += dryer.dried_l          # left as vapour
	var filler := plant.sim.get_component("vf_310") as SimVialFiller
	if filler != null:
		total += filler.filled_l        # left in vials
	return total
