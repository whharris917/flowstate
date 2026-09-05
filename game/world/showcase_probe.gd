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
	# Probes on the shells read the contents: the solvent tank takes
	# hot distillate, the liquor tank takes cooled mother liquor.
	var ti308 := plant.sim.get_component("ti_308") as SimGauge
	var ti306 := plant.sim.get_component("ti_306") as SimGauge
	if ti308 != null and ti306 != null:
		print("[probe] u300 probes: TI-308 solvent tank %.1f C (contents %.1f C) · TI-306 liquor tank %.1f C (contents %.1f C)" % [
			ti308.reading, solvent_tank.temp_c, ti306.reading,
			(plant.sim.get_component("lt_306") as SimTank).temp_c])
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
	await _vantage(player, Vector3(17.0, 0.15, 18.0), Vector2(-11.0, 14.0), 1.7, -0.78)
	await _shot("user://probe_gallery_row.png")
	await _vantage(player, Vector3(-15.0, 0.15, 44.0), Vector2(5.4, -11.0), 0.5, 0.22)
	await _shot("user://probe_gallery_bioreactor.png")
	await _vantage(player, Vector3(-7.2, 9.2, 33.0), Vector2(-1.0, 0.0), 0.0, -0.35)
	await _shot("user://probe_gallery_bioreactor_head.png")
	await _vantage(player, Vector3(10.3, 0.15, 25.2), Vector2(-2.5, 3.5), 0.0, -0.02)
	await _shot("user://probe_gallery_autoclave.png")
	await _vantage(player, Vector3(14.6, 0.15, 26.6), Vector2(-2.0, 3.0), 0.0, -0.02)
	await _shot("user://probe_gallery_isolator.png")
	await _vantage(player, Vector3(17.2, 0.15, 27.8), Vector2(3.7, 4.7), 0.0, -0.06)
	await _shot("user://probe_gallery_lab.png")
	# The gallery's stair tower, with real input: three flights, then
	# the catwalk to the bioreactor head. The first flight's foot is
	# out in the aisle at x 4.3, so this also proves nothing is parked
	# on it (the autoclave was, 2026-09-02).
	await _walk(player, Vector3(6.2, 0.15, 29.75), PI / 2.0, 3.5)
	var l1 := player.global_position
	await _walk(player, Vector3(-3.2, 3.2, 29.0), PI, 3.5)
	var l2 := player.global_position
	await _walk(player, Vector3(-0.8, 6.2, 41.5), 0.0, 3.5)
	var l3 := player.global_position
	await _walk(player, Vector3(-1.0, 9.2, 33.0), PI / 2.0, 3.0)
	var head := player.global_position
	print("[probe] stairs: Unit 500 tower — L1 %s · L2 %s · L3 %s · catwalk %s" % [
		_landed(l1, l1.y > 2.9 and l1.x < 0.0),
		_landed(l2, l2.y > 5.9 and l2.z > 35.0),
		_landed(l3, l3.y > 8.9 and l3.z < 35.0),
		_landed(head, head.y > 8.9 and head.x < -7.0)])
	var lock := plant.sim.get_component("vl_302") as SimVacuumLock
	print("[probe] vl_302: %s · %.1f kPa · condensate %.1f L · %d bursts" % [
		lock.state, lock.press_pa / 1000.0, lock.condensate_l, lock.vent_bursts_done])
	# Soak: advance the kernel twenty minutes at once and report again.
	# A train can look right in the first seconds and still not close;
	# this is where the recycle either works or does not.
	var u300 := SimBalance.names_in(plant.sim, 300)
	var acc_before := SimBalance.accounts(plant.sim, u300)
	# Soak one scan at a time so the worst Newton residual and the
	# scans that hit the iteration cap are on record.
	var worst_residual := 0.0
	var capped_scans := 0
	var reported := 0
	# The Unit 400 sequence, as a timeline of its step changes.
	var u400_step := _u400_step(plant)
	var u400_timeline: Array[String] = []
	if u400_step >= 0:
		u400_timeline.append("%s %s" % [_clock(plant.sim.time), U400_STEPS[u400_step]])
	var scans := roundi(1200.0 / Plant.SIM_DT)
	for i in scans:
		# Let a frame through each simulated minute so the window's HUD
		# clock shows the soak advancing instead of freezing on the last
		# vantage for the two real minutes it takes.
		if i % roundi(60.0 / Plant.SIM_DT) == 0:
			await get_tree().process_frame
		plant.sim.tick()
		var step_now := _u400_step(plant)
		if step_now != u400_step:
			u400_step = step_now
			if step_now >= 0:
				u400_timeline.append("%s %s" % [_clock(plant.sim.time), U400_STEPS[step_now]])
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
	print("[probe] u400 sequence: %s" % " → ".join(u400_timeline))
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
	var acc_after := SimBalance.accounts(plant.sim, u300)
	var fed := float(acc_after["fed"]) - float(acc_before["fed"])
	var gained := (float(acc_after["out"]) + float(acc_after["held"])) \
		- (float(acc_before["out"]) + float(acc_before["held"]))
	print("[probe] balance: fed %.1f L, accounted %.1f L (%.1f%% closed)" % [
		fed, gained, 100.0 * (1.0 - absf(fed - gained) / maxf(fed, 1.0))])
	# Every unit since the plant started, the way the balance screen
	# shows it: the residual is what a closed balance keeps at zero.
	for unit in SimBalance.units(plant.sim):
		var acc := SimBalance.accounts(plant.sim, SimBalance.names_in(plant.sim, unit))
		var h0 := plant.balance_panel.held0(unit)
		print("[probe] %s since start: fed %.1f · out %.1f · held %.1f from %.1f · residual %+.2f L · %.2f%% closed" % [
			SimBalance.unit_label(unit), acc["fed"], acc["out"], acc["held"], h0,
			SimBalance.residual(acc, h0), SimBalance.closure_pct(acc, h0)])
	print("[probe] boiler made %.1f L of steam from %.1f L of feedwater: the known gap, counted as fed above" % [
		sg.steam_total_l, sg.feedwater_total_l])
	var net := plant.sim.network()
	print("[probe] hydraulics: %d nodes, %d branches, band %d, %d iterations, residual %.6f L/s, last pass %.2f ms (Newton %.2f ms)" % [
		net.node_count(), net.branches.size(), net.bandwidth(), net.iterations, net.residual_lps,
		plant.sim.solve_ms, plant.sim.newton_ms])

	_print_rig(plant, "u400 after 20 min")
	# The operator screen, photographed mid-cycle so it can be read
	# against the numbers just printed.
	await _vantage(player, Vector3(2.9, 0.15, 10.4), Vector2(0.0, -1.0), 0.0, 0.05)
	await _shot("user://probe_showcase_u400_hmi.png")
	var hmi := plant.get_node_or_null("hmi_400") as HmiScreenView
	if hmi != null:
		for page_name: String in ["hydraulics", "balance", "loops"]:
			hmi.use()
			await get_tree().create_timer(0.4).timeout
			await _shot("user://probe_showcase_u400_hmi_%s.png" % page_name)
		hmi.use()
	# The local control station: STOP holds the sequence where it is
	# with everything shut, START resumes it. Six seconds each way,
	# long enough for every valve to finish its stroke.
	var start := plant.sim.get_component("lcs_401_start") as SimPushbutton
	var stop := plant.sim.get_component("lcs_401_stop") as SimPushbutton
	if start != null and stop != null:
		stop.press()
		for _i in roundi(6.0 / Plant.SIM_DT):
			plant.sim.tick()
		print("[probe] u400 after STOP: %s" % _station_state(plant))
		start.press()
		for _i in roundi(6.0 / Plant.SIM_DT):
			plant.sim.tick()
		print("[probe] u400 after START: %s" % _station_state(plant))
	# The plant-wide balance screen beside the home HMI.
	await _vantage(player, Vector3(-6.9, 0.15, -2.6), Vector2(0.0, -1.0), 0.0, 0.05)
	await _shot("user://probe_showcase_balance.png")

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


func _landed(p: Vector3, ok: bool) -> String:
	if ok:
		return "OK"
	return "BLOCKED at (%.1f, %.2f, %.1f)" % [p.x, p.y, p.z]


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
const U400_STEPS: Array[String] = ["FILL", "LIFT", "DRAIN T-401", "DRAIN T-402", "SEWER"]


## Which step of the Unit 400 sequence is sealed in, or -1.
func _u400_step(plant: Plant) -> int:
	var plc_name := plant.cabinet_plc("u400_cab")
	if plc_name == "":
		return -1
	var plc := plant.sim.get_component(plc_name) as SimPLC
	for i in 5:
		if plc.mem[i]:
			return i
	return -1


func _station_state(plant: Plant) -> String:
	var parts: Array[String] = []
	var step := _u400_step(plant)
	parts.append("step %s" % (U400_STEPS[step] if step >= 0 else "none"))
	for lamp_name: String in ["lcs_401_running", "lcs_401_stopped"]:
		var lamp := plant.sim.get_component(lamp_name) as SimPilotLight
		if lamp != null:
			parts.append("%s %s" % [lamp_name.trim_prefix("lcs_401_").to_upper(), "LIT" if lamp.lit else "dark"])
	var p401 := plant.sim.get_component("p_401") as SimPump
	parts.append("P-401 %s" % ("RUN" if p401.running else "stop"))
	for valve_name: String in ["xv_401", "xv_402", "xv_403", "xv_404"]:
		var xv := plant.sim.get_component(valve_name) as SimBlockValve
		parts.append("%s %s" % [valve_name.to_upper().replace("_", "-"), xv.state()])
	return " · ".join(parts)


func _clock(t: float) -> String:
	var total := int(t)
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]


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
	var sewer := plant.sim.get_component("du_401") as SimDrain
	var in_rig := t401.level_l + t402.level_l + t403.level_l
	var step := _u400_step(plant)
	print("[probe] %s: step %s · T-401 %.0f L · T-402 %.0f L · T-403 %.0f L · in the rig %.1f L against header %.1f L less sewer %.1f L (%+.1f L)" % [
		label, U400_STEPS[step] if step >= 0 else "none", t401.level_l, t402.level_l, t403.level_l,
		in_rig, header.total_l, sewer.total_l, in_rig - (header.total_l - sewer.total_l)])
	var switches: Array[String] = []
	for switch_name: String in ["lsl_401", "lsh_401", "lsl_402", "lsl_403", "lsh_403"]:
		var ls := plant.sim.get_component(switch_name) as SimFloatSwitch
		switches.append("%s %s" % [switch_name.to_upper().replace("_", "-"), "closed" if ls.closed else "open"])
	var valves: Array[String] = []
	for valve_name: String in ["xv_401", "xv_402", "xv_403", "xv_404"]:
		var xv := plant.sim.get_component(valve_name) as SimBlockValve
		valves.append("%s %s" % [valve_name.to_upper().replace("_", "-"), xv.state()])
	print("[probe] %s: %s · %s" % [label, " · ".join(switches), " · ".join(valves)])
	print("[probe] %s: sump ran dry %d scans, overflowed %.1f L · T-402 overflowed %.1f L · T-401 overflowed %.1f L" % [
		label, t403.ran_dry_ticks, t403.overflowed_l, t402.overflowed_l, t401.overflowed_l])
	print("[probe] %s: P-401 %s %.2f L/s (FI-401 %.2f, %d starts, K-401 %d cycles) · P-402 %s %.2f L/s, %.0f s at no flow, suction %.0f kPa discharge %.0f kPa" % [
		label, "RUN" if p401.running else "stop", p401.flow_lps, fi.reading, p401.starts, k401.cycles,
		"RUN" if p402.running else "stop", p402.flow_lps, p402.dry_run_s,
		p402.suction_pa / 1000.0, p402.discharge_pa / 1000.0])
