class_name SimSource
extends SimComponent
## Supply header: a utility tie-in at the edge of the modeled plant —
## the honest root of every flow path, the way the mains feeder is
## for power. Availability is unlimited (the wider utility system is
## off-plot), but everything drawn through it is metered. Inlets wire
## to "supply" (always wet); pumps and valves return their "draw" here
## for the meter. Mirrors sim/components.py Source.
##
## A header is what it carries: this is where a species enters the
## plant, and everything downstream finds out by being piped to it
## rather than by being told.

const AVAILABLE_LPS := 1.0e6

var species_index: int = SimSpecies.WATER
var temp_c: float = SimStream.AMBIENT_C
var total_l: float = 0.0

var draw: SimInputPort
var supply: SimOutputPort


func _init(name_: String, species_: String = "water",
		temp_c_: float = SimStream.AMBIENT_C) -> void:
	super(name_)
	var index := SimSpecies.index_of(species_)
	species_index = index if index >= 0 else SimSpecies.WATER
	temp_c = temp_c_
	draw = add_input("draw", SimTypes.PortKind.PROCESS_FLOW)
	supply = add_output("supply", SimTypes.PortKind.PROCESS_SUPPLY)
	supply.stream = _offered()
	add_observable("total_l", &"total_l")


func species_key() -> String:
	return SimSpecies.key_of(species_index)


func species_label() -> String:
	return SimSpecies.label_of(species_index)


func set_species(key: String) -> void:
	var index := SimSpecies.index_of(key)
	if index >= 0:
		species_index = index


func _offered() -> SimStream:
	return SimStream.pure(species_index, AVAILABLE_LPS, temp_c)


func tick(dt: float) -> void:
	total_l += draw.value * dt
	supply.stream = _offered()


func state_dict() -> Dictionary:
	return {"total_l": total_l, "species": species_key(), "temp_c": temp_c}


func apply_state(state: Dictionary) -> void:
	total_l = state.get("total_l", total_l)
	temp_c = state.get("temp_c", temp_c)
	if state.has("species"):
		set_species(state["species"])
