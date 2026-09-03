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

	# The plant runs from x~0 to x~54, so the aerial stands off to the
	# south of its midpoint and looks back up the train.
	player.global_position = Vector3(28.0, 0.15, 24.0)
	player.rotation.y = 0.0  # facing -z, up the length of the plant
	player.zoom_t = 2.2
	player._zoom_now = 2.2
	player.camera.rotation.x = -0.70
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
		filler.state, filler.vials_done, filler.draw_lps, filler.fill_purity * 100.0])

	# Unit 400: the gravity rig, seen from the south-east, then the east
	# stairs and the mid-deck landing up close.
	player.global_position = Vector3(4.5, 0.15, 20.5)
	player.rotation.y = 0.45
	player.zoom_t = 0.95
	player._zoom_now = 0.95
	player.camera.rotation.x = 0.02
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_showcase_u400.png")
	player.global_position = Vector3(5.2, 0.15, 15.4)
	player.rotation.y = 0.75
	player.zoom_t = 0.6
	player._zoom_now = 0.6
	player.camera.rotation.x = 0.12
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_showcase_u400_stairs.png")
	_print_rig(plant, "u400 at start")
	# Walk the stairs for real: from the foot of the east flight onto
	# the mid deck, then from the foot of the west flight onto the top
	# deck. A step at either landing leaves the player short.
	await _walk(player, Vector3(5.3, 0.15, 11.75), PI / 2.0, 3.5)
	var mid := player.global_position
	print("[probe] stairs: east flight leaves the player at (%.1f, %.2f, %.1f) — %s" % [
		mid.x, mid.y, mid.z, "ON THE MID DECK" if mid.y > 2.9 and mid.x < 0.0 else "BLOCKED"])
	await _walk(player, Vector3(-3.2, 3.2, 18.6), 0.0, 3.5)
	var top := player.global_position
	print("[probe] stairs: west flight leaves the player at (%.1f, %.2f, %.1f) — %s" % [
		top.x, top.y, top.z, "ON THE TOP DECK" if top.y > 5.9 and top.z < 12.9 else "BLOCKED"])
	# And Unit 100's flight, which used to run under the frame's beam.
	await _walk(player, Vector3(16.5, 0.15, 3.3), 0.0, 3.5)
	var u100 := player.global_position
	print("[probe] stairs: Unit 100 flight leaves the player at (%.1f, %.2f, %.1f) — %s" % [
		u100.x, u100.y, u100.z, "ON THE DECK" if u100.y > 2.9 and u100.z < -2.0 else "BLOCKED"])
	# Unit 500, the gallery, which sits south (+z) of everything else.
	# rotation.y for a forward direction (fx, fz) is atan2(-fx, -fz).
	# The row from the north-east, high up; the bioreactor whole from
	# the south-east and its head from the catwalk; then each exhibit
	# from where a visitor would stand.
	await _vantage(player, Vector3(16.0, 0.15, 19.0), Vector2(-11.0, 13.0), 1.6, -0.78)
	await _shot("user://probe_gallery_row.png")
	await _vantage(player, Vector3(2.5, 0.15, 45.5), Vector2(-12.1, -8.5), 0.5, 0.22)
	await _shot("user://probe_gallery_bioreactor.png")
	await _vantage(player, Vector3(-7.2, 9.2, 37.0), Vector2(-1.0, 0.0), 0.0, -0.35)
	await _shot("user://probe_gallery_bioreactor_head.png")
	await _vantage(player, Vector3(6.8, 0.15, 25.2), Vector2(-2.5, 3.5), 0.0, -0.02)
	await _shot("user://probe_gallery_autoclave.png")
	await _vantage(player, Vector3(12.6, 0.15, 26.6), Vector2(-2.0, 3.0), 0.0, -0.02)
	await _shot("user://probe_gallery_isolator.png")
	await _vantage(player, Vector3(14.8, 0.15, 27.8), Vector2(3.7, 4.7), 0.0, -0.06)
	await _shot("user://probe_gallery_lab.png")
	var lock := plant.sim.get_component("vl_302") as SimVacuumLock
	print("[probe] vl_302: %s · %.1f kPa · condensate %.1f L · %d bursts" % [
		lock.state, lock.press_pa / 1000.0, lock.condensate_l, lock.vent_bursts_done])
	# Soak: advance the kernel twenty minutes at once and report again.
	# A train can look right in the first seconds and still not close;
	# this is where the recycle either works or does not.
	var fed_before := _fed_in(plant)
	var held_before := _held(plant)
	# Soak one scan at a time so the worst Newton residual and the
	# scans that hit the iteration cap are on record.
	var worst_residual := 0.0
	var capped_scans := 0
	var reported := 0
	for _i in roundi(1200.0 / Plant.SIM_DT):
		plant.sim.tick()
		var net := plant.sim.network()
		worst_residual = maxf(worst_residual, net.residual_lps)
		var capped := net.iterations >= SimNetwork.MAX_ITERATIONS
		if capped:
			capped_scans += 1
		if reported < 6 and (net.residual_lps > 0.05 or (capped and capped_scans <= 3)):
			reported += 1
			print("[probe] %s scan at t=%.1f s, %d iterations, residual %.4f L/s: %s" % [
				"capped" if capped else "unconverged", plant.sim.time, net.iterations,
				net.residual_lps, net.describe_node(net.worst_node)])
	print("[probe] --- after a simulated 20 minutes (worst residual %.5f L/s, %d scans hit the iteration cap) ---" % [
		worst_residual, capped_scans])
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
	print("[probe] boiler made %.1f L of steam from %.1f L of feedwater: the known gap, counted as fed above" % [
		sg.steam_total_l, sg.feedwater_total_l])
	var net := plant.sim.network()
	print("[probe] hydraulics: %d nodes, %d branches, band %d, %d iterations, residual %.6f L/s, last pass %.2f ms (Newton %.2f ms)" % [
		net.node_count(), net.branches.size(), net.bandwidth(), net.iterations, net.residual_lps,
		plant.sim.solve_ms, plant.sim.newton_ms])

	_print_rig(plant, "u400 after 20 min")

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


## Stand the player at `at`, facing along `forward` (xz), with the
## zoom track at `zoom` and the camera pitched `pitch`, then let the
## camera settle. Velocity is cleared so a walk test cannot carry on.
func _vantage(player: Player, at: Vector3, forward: Vector2, zoom: float, pitch: float) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.rotation.y = atan2(-forward.x, -forward.y)
	player.zoom_t = zoom
	player._zoom_now = zoom
	player.camera.rotation.x = pitch
	await get_tree().create_timer(0.6).timeout


## Stand the player somewhere, face them a way, and hold forward for a
## while: the same input the director gives, so a landing the geometry
## says is flush is proven walkable rather than assumed.
func _walk(player: Player, from: Vector3, facing: float, seconds: float) -> void:
	player.global_position = from
	player.velocity = Vector3.ZERO
	player.rotation.y = facing
	await get_tree().physics_frame
	Input.action_press("move_forward")
	var trail: Array[String] = []
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
		var p := player.global_position
		trail.append("(%.1f, %.2f, %.1f)" % [p.x, p.y, p.z])
	Input.action_release("move_forward")
	await get_tree().create_timer(0.3).timeout
	print("[probe] walk from (%.1f, %.1f, %.1f) facing %.2f: %s" % [
		from.x, from.y, from.z, facing, " ".join(trail)])


## The gravity rig's honest state: three levels that should always add
## up to what was charged, the lift pump under its switch, and the pump
## that cannot make the lift.
func _print_rig(plant: Plant, label: String) -> void:
	var t401 := plant.sim.get_component("t_401") as SimTank
	var t402 := plant.sim.get_component("t_402") as SimTank
	var t403 := plant.sim.get_component("t_403") as SimTank
	var p401 := plant.sim.get_component("p_401") as SimPump
	var p402 := plant.sim.get_component("p_402") as SimPump
	var k401 := plant.sim.get_component("k_401") as SimRelay
	var fi := plant.sim.get_component("fi_401") as SimGauge
	if t401 == null or p401 == null:
		return
	var header := plant.sim.get_component("supply_401") as SimSource
	var lv := plant.sim.get_component("lv_401") as SimControlValve
	print("[probe] %s: T-401 %.0f L (%.2f m) · T-402 %.0f L · T-403 %.0f L · in the rig %.1f L, header delivered %.1f L · LV-401 %.0f %%" % [
		label, t401.level_l, t401.depth_m, t402.level_l, t403.level_l,
		t401.level_l + t402.level_l + t403.level_l, header.total_l, lv.position])
	print("[probe] %s: sump ran dry %d scans, overflowed %.1f L · T-402 overflowed %.1f L · T-401 overflowed %.1f L" % [
		label, t403.ran_dry_ticks, t403.overflowed_l, t402.overflowed_l, t401.overflowed_l])
	print("[probe] %s: P-401 %s %.2f L/s (FI-401 %.2f, %d starts, K-401 %d cycles) · P-402 %s %.2f L/s, %.0f s dry, suction %.0f kPa discharge %.0f kPa" % [
		label, "RUN" if p401.running else "stop", p401.flow_lps, fi.reading, p401.starts, k401.cycles,
		"RUN" if p402.running else "stop", p402.flow_lps, p402.dry_run_s,
		p402.suction_pa / 1000.0, p402.discharge_pa / 1000.0])


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
	# The steam drum is a pressure boundary, so it hands out whatever
	# steam is drawn and makes up the difference from nowhere. That
	# makeup is real material entering the plant, and the balance has
	# to say so rather than hide it.
	var sg := plant.sim.get_component("sg_301") as SimSteamGen
	if sg != null:
		total += sg.steam_total_l - sg.feedwater_total_l
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
