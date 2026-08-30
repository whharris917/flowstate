class_name Plant
extends Node3D
## Owns the sim graph and the fixed-rate tick; child views only render.
## This is the step-1 loop standing in a room: pump fills tank, float
## switch reads level, relay carries the contact to the pump motor.

const SIM_DT := 0.05  # 20 Hz, decoupled from frame rate
const SAVE_PATH := "user://save.json"

var sim: Simulation
var tank: SimTank
var switch: SimFloatSwitch
var relay: SimRelay
var pump: SimPump
var historian: SimHistorian

var _accumulator: float = 0.0


func _ready() -> void:
	_build_sim()
	_self_check()
	_build_views()


func _physics_process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= SIM_DT:
		sim.tick()
		_accumulator -= SIM_DT


func _build_sim() -> void:
	sim = Simulation.new(SIM_DT)
	tank = sim.add(SimTank.new("supply_tank", 100.0, 70.0, 1.5)) as SimTank
	switch = sim.add(SimFloatSwitch.new("level_switch", 40.0, 80.0)) as SimFloatSwitch
	relay = sim.add(SimRelay.new("pump_relay")) as SimRelay
	pump = sim.add(SimPump.new("fill_pump", 4.0)) as SimPump
	sim.connect_ports(tank, "level", switch, "level")
	sim.connect_ports(switch, "contact", relay, "coil")
	sim.connect_ports(relay, "contact", pump, "run")
	sim.connect_ports(pump, "flow", tank, "in_flow")
	historian = sim.attach_historian(SimHistorian.new())


## Headless sanity run of an identical throwaway plant at startup, so a
## broken kernel port announces itself in the Output panel instead of as
## a silently weird tank.
func _self_check() -> void:
	var check := Simulation.new(SIM_DT)
	var c_tank := check.add(SimTank.new("t", 100.0, 70.0, 1.5)) as SimTank
	var c_switch := check.add(SimFloatSwitch.new("s", 40.0, 80.0)) as SimFloatSwitch
	var c_relay := check.add(SimRelay.new("r")) as SimRelay
	var c_pump := check.add(SimPump.new("p", 4.0)) as SimPump
	check.connect_ports(c_tank, "level", c_switch, "level")
	check.connect_ports(c_switch, "contact", c_relay, "coil")
	check.connect_ports(c_relay, "contact", c_pump, "run")
	check.connect_ports(c_pump, "flow", c_tank, "in_flow")
	check.run_for(600.0)
	var ok := c_tank.level_l >= 38.0 and c_tank.level_l <= 82.0 \
		and c_tank.overflowed_l == 0.0 and c_relay.cycles < 15
	if ok:
		print("[flowstate] kernel self-check OK — 600 s: level %.1f L, %d relay cycles"
			% [c_tank.level_l, c_relay.cycles])
	else:
		push_warning("[flowstate] kernel self-check FAILED — level %.1f L, overflow %.1f L, %d cycles"
			% [c_tank.level_l, c_tank.overflowed_l, c_relay.cycles])


func _build_views() -> void:
	var tank_view := TankView.new()
	tank_view.position = Vector3(2.5, 0, -2.0)
	add_child(tank_view)
	tank_view.setup(tank, switch)

	var band_mid_y := TankView.HEIGHT * (switch.low_l + switch.high_l) / (2.0 * tank.capacity_l)
	var switch_view := FloatSwitchView.new()
	switch_view.position = Vector3(1.55, band_mid_y, -2.0)
	add_child(switch_view)
	switch_view.setup(switch)

	var pump_view := PumpView.new()
	pump_view.position = Vector3(-0.5, 0, -2.6)
	add_child(pump_view)
	pump_view.setup(pump)

	var relay_view := RelayView.new()
	relay_view.position = Vector3(-2.5, 1.5, -4.78)
	add_child(relay_view)
	relay_view.setup(relay)

	var hmi_view := HmiView.new()
	hmi_view.position = Vector3(-4.6, 1.6, -4.85)
	add_child(hmi_view)
	hmi_view.setup(historian, tank, switch, relay, pump)

	_wire(Vector3(1.55, band_mid_y, -2.0), Vector3(-2.5, 1.5, -4.7),
		func() -> float: return switch.contact.value, Color(0.11, 0.69, 0.48), 0.03)
	_wire(Vector3(-2.5, 1.4, -4.7), Vector3(-0.5, 0.72, -2.6),
		func() -> float: return relay.contact.value, Color(0.91, 0.63, 0.0), 0.03)
	_wire(Vector3(-0.5, 0.55, -2.6), Vector3(2.5, 2.35, -2.0),
		func() -> float: return pump.flow.value, Color(0.16, 0.47, 0.84), 0.09)


func _wire(from: Vector3, to: Vector3, getter: Callable, color: Color, thickness: float) -> void:
	var wire := WireView.new()
	add_child(wire)
	wire.setup(from, to, getter, color, thickness)


func save_game() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(sim.state_dict(), "  "))
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		return false
	sim.apply_state(parsed)
	return true
