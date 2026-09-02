class_name SimSource
extends SimComponent
## Supply header: a utility tie-in at the edge of the modeled plant —
## the honest root of every flow path, the way the mains feeder is
## for power. Mirrors sim/components.py Source.
##
## A header is three things and nothing else: what it carries, how hot
## it is, and what pressure it holds. There is no inlet, because from
## the plant's point of view there is nothing upstream — just a
## reservoir deep enough to hold the pressure whatever you draw. And
## there is no draw port either: what leaves is whatever the network
## pulls out of it, and the meter reads that. This is where a species
## enters the plant, and everything downstream finds out by being
## piped to it rather than by being told.

var species_index: int = SimSpecies.WATER
var temp_c: float = SimStream.AMBIENT_C
var pressure_kpa: float = 400.0
var elevation_m: float = 0.0
var total_l: float = 0.0

var outlet: SimOutputPort

var _comp: PackedFloat32Array
var _supply: SimStream = null  # what it carries, rebuilt when that changes


func _init(name_: String, species_: String = "water",
		temp_c_: float = SimStream.AMBIENT_C, pressure_kpa_: float = 400.0,
		elevation_m_: float = 0.0) -> void:
	super(name_)
	var index := SimSpecies.index_of(species_)
	species_index = index if index >= 0 else SimSpecies.WATER
	temp_c = temp_c_
	pressure_kpa = pressure_kpa_
	elevation_m = elevation_m_
	_comp = _pure_comp()
	outlet = add_output("outlet", SimTypes.PortKind.PROCESS_MATERIAL)
	add_observable("total_l", &"total_l")
	add_observable("delivered_lps", &"delivered_lps")


## What the plant is drawing right now. Negative flow at the nozzle
## means material leaving, which is the normal direction.
var delivered_lps: float:
	get:
		return maxf(-outlet.flow_lps, 0.0)


func species_key() -> String:
	return SimSpecies.key_of(species_index)


func species_label() -> String:
	return SimSpecies.label_of(species_index)


func set_species(key: String) -> void:
	var index := SimSpecies.index_of(key)
	if index >= 0:
		species_index = index
		_comp = _pure_comp()


func _pure_comp() -> PackedFloat32Array:
	var c := SimStream.zero_amounts()
	c[species_index] = 1.0
	return c


func update_hydraulics(net: SimNetwork, node: Dictionary) -> void:
	net.set_pressure(node["outlet"],
		pressure_kpa * 1000.0 + SimHydraulics.static_head_pa(elevation_m), true)


func supplied_stream(_port_name: String) -> SimStream:
	if _supply == null or _supply.temp_c != temp_c or _supply.comp[species_index] != 1.0:
		_supply = SimStream.make(1.0, temp_c, _comp)
	return _supply


func tick(dt: float) -> void:
	total_l += delivered_lps * dt


func state_dict() -> Dictionary:
	return {"total_l": total_l, "species": species_key(), "temp_c": temp_c,
		"pressure_kpa": pressure_kpa}


func apply_state(state: Dictionary) -> void:
	total_l = state.get("total_l", total_l)
	temp_c = state.get("temp_c", temp_c)
	pressure_kpa = state.get("pressure_kpa", pressure_kpa)
	if state.has("species"):
		set_species(state["species"])
