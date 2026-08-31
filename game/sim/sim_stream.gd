class_name SimStream
extends RefCounted
## A material stream: how much, how hot, and what is in it.
## Mirrors sim/stream.py.
##
## This is the value that travels on every process connection. Before it
## existed a process port carried a bare flow rate, which meant a
## separator had to be *told* the purity of its own feed on a signal
## wire. Nothing composed; every train worked only in the order it was
## wired.
##
## IMPORTANT: a Stream is treated as an IMMUTABLE VALUE. Every operation
## returns a new Stream rather than mutating, because one Stream object
## is published on an output port and read by every wire landing on it —
## mutating it in place would let one consumer corrupt another's feed.
## Nothing in the codebase may write to the fields of a stream it did
## not itself construct.
##
## Conventions, applied everywhere in the kernel:
##   * Flow is volumetric, L/s. 1 L is taken as 1 kg (aqueous basis), so
##     composition fractions are simultaneously mass and volume
##     fractions and nothing carries a density.
##   * comp is indexed by SimSpecies index and always sums to 1.
##   * solids_frac is the fraction of the whole stream present as
##     suspended crystal rather than dissolved. It is a phase split, not
##     a species: the solid is always SimSpecies.SOLID, and may never
##     exceed that species' fraction.

const AMBIENT_C := 20.0
const EPS := 1e-12

var flow_lps: float = 0.0
var temp_c: float = AMBIENT_C
var solids_frac: float = 0.0
var comp: PackedFloat32Array

## Shared dead stream. Safe to share only because streams are never
## mutated in place; input ports reset to this instead of allocating.
static var _empty: SimStream = null


func _init() -> void:
	comp = PackedFloat32Array()
	comp.resize(SimSpecies.COUNT)
	comp[SimSpecies.WATER] = 1.0


# -- construction ------------------------------------------------------

static func empty() -> SimStream:
	if _empty == null:
		_empty = SimStream.new()
	return _empty


## A single-species stream — what a supply header delivers.
static func pure(index: int, flow_lps_: float, temp_c_: float = AMBIENT_C) -> SimStream:
	var s := SimStream.new()
	s.flow_lps = maxf(flow_lps_, 0.0)
	s.temp_c = temp_c_
	var c := PackedFloat32Array()
	c.resize(SimSpecies.COUNT)
	c[index] = 1.0
	s.comp = c
	return s


## Build from an arbitrary composition, normalizing it to sum to one.
static func make(flow_lps_: float, temp_c_: float, comp_: PackedFloat32Array,
		solids_frac_: float = 0.0) -> SimStream:
	var s := SimStream.new()
	s.flow_lps = maxf(flow_lps_, 0.0)
	s.temp_c = temp_c_
	s.comp = normalized(comp_)
	s.solids_frac = clampf(solids_frac_, 0.0, 1.0)
	return s


## Composition from absolute quantities (litres, or any consistent
## unit). Unit operations do their bookkeeping in absolute terms — so
## much reagent consumed, so much product made — and come back to
## fractions through here.
static func normalized(amounts: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SimSpecies.COUNT)
	var total := 0.0
	for i in SimSpecies.COUNT:
		if i < amounts.size() and amounts[i] > 0.0:
			out[i] = amounts[i]
			total += amounts[i]
	if total <= EPS:
		# An empty or all-zero composition becomes pure water, so every
		# stream in the kernel always has a defined material.
		out[SimSpecies.WATER] = 1.0
		return out
	for i in SimSpecies.COUNT:
		out[i] = out[i] / total
	return out


static func zero_amounts() -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(SimSpecies.COUNT)
	return a


## Same material, different rate. This is how a stream is split: two
## branches of the same composition and temperature whose rates sum to
## the parent's.
func with_flow(flow_lps_: float) -> SimStream:
	var s := SimStream.new()
	s.flow_lps = maxf(flow_lps_, 0.0)
	s.temp_c = temp_c
	s.solids_frac = solids_frac
	s.comp = comp
	return s


func with_temp(temp_c_: float) -> SimStream:
	var s := SimStream.new()
	s.flow_lps = flow_lps
	s.temp_c = temp_c_
	s.solids_frac = solids_frac
	s.comp = comp
	return s


# -- queries -----------------------------------------------------------

func is_flowing() -> bool:
	return flow_lps > EPS


func frac(index: int) -> float:
	return comp[index]


## Rate of one species alone, L/s.
func species_lps(index: int) -> float:
	return flow_lps * comp[index]


func solids_lps() -> float:
	return flow_lps * solids_frac


## Composition-weighted heat capacity: cp = sum(x_i * cp_i).
func cp_kj_per_kg_k() -> float:
	var total := 0.0
	for i in SimSpecies.COUNT:
		total += comp[i] * SimSpecies.cp_of(i)
	return total if total > 0.0 else SimSpecies.cp_of(SimSpecies.WATER)


## The batch boils when its most volatile component does. A bubble-point
## stand-in: the lowest boiling point among species actually present in
## quantity.
func bubble_point_c() -> float:
	var lowest := 1.0e9
	for i in SimSpecies.COUNT:
		if comp[i] > 0.01:
			lowest = minf(lowest, SimSpecies.boil_of(i))
	return lowest if lowest < 1.0e9 else 100.0


## Index of the most volatile species present, or -1 if none.
func lightest_present() -> int:
	var best := -1
	var lowest := 1.0e9
	for i in SimSpecies.COUNT:
		if comp[i] > EPS and SimSpecies.boil_of(i) < lowest:
			lowest = SimSpecies.boil_of(i)
			best = i
	return best


## Composition of the liquid alone, with the crystals taken out.
func liquid_comp() -> PackedFloat32Array:
	if solids_frac <= EPS:
		return comp
	var liquid_total := 1.0 - solids_frac
	var out := PackedFloat32Array()
	out.resize(SimSpecies.COUNT)
	if liquid_total <= EPS:
		return out
	for i in SimSpecies.COUNT:
		var amount := comp[i] - (solids_frac if i == SimSpecies.SOLID else 0.0)
		out[i] = maxf(amount, 0.0) / liquid_total
	return out


## Enforce the standing invariant: there cannot be more solid than there
## is of the species the solid is made of.
func clamped_solids() -> SimStream:
	var limit := comp[SimSpecies.SOLID]
	if solids_frac <= limit:
		return self
	return SimStream.make(flow_lps, temp_c, comp, limit)


# -- combination -------------------------------------------------------

## Join two streams at a tee. Flows add; temperature and composition are
## flow-weighted averages:
##     F   = F_a + F_b
##     T   = (F_a*T_a + F_b*T_b) / F
##     x_i = (F_a*x_ia + F_b*x_ib) / F
## Temperature is weighted by flow rather than heat capacity — exact
## when the streams share a cp and close enough when they do not.
## Mixing a dead stream with a live one returns the live one untouched.
static func mix(a: SimStream, b: SimStream) -> SimStream:
	if not a.is_flowing():
		return b
	if not b.is_flowing():
		return a
	var total := a.flow_lps + b.flow_lps
	var s := SimStream.new()
	s.flow_lps = total
	s.temp_c = (a.flow_lps * a.temp_c + b.flow_lps * b.temp_c) / total
	s.solids_frac = clampf(
		(a.flow_lps * a.solids_frac + b.flow_lps * b.solids_frac) / total, 0.0, 1.0)
	var c := PackedFloat32Array()
	c.resize(SimSpecies.COUNT)
	for i in SimSpecies.COUNT:
		c[i] = (a.flow_lps * a.comp[i] + b.flow_lps * b.comp[i]) / total
	s.comp = c
	return s


# -- serialization -----------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"flow_lps": flow_lps,
		"temp_c": temp_c,
		"solids_frac": solids_frac,
		"comp": Array(comp),
	}


static func from_dict(data: Dictionary) -> SimStream:
	var c := PackedFloat32Array()
	c.resize(SimSpecies.COUNT)
	var raw: Array = data.get("comp", [])
	for i in mini(raw.size(), SimSpecies.COUNT):
		c[i] = float(raw[i])
	return SimStream.make(
		float(data.get("flow_lps", 0.0)),
		float(data.get("temp_c", AMBIENT_C)),
		c,
		float(data.get("solids_frac", 0.0)))


## One-line description for a describe() panel or a HUD readout.
func describe() -> String:
	if not is_flowing():
		return "no flow"
	var parts: Array[String] = []
	for i in SimSpecies.COUNT:
		if comp[i] > 0.005:
			parts.append("%s %d%%" % [SimSpecies.label_of(i), roundi(comp[i] * 100.0)])
	var text := "%.2f L/s at %.0f C — %s" % [flow_lps, temp_c, ", ".join(parts)]
	if solids_frac > 0.005:
		text += " (%d%% solids)" % roundi(solids_frac * 100.0)
	return text
