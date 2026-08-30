class_name SimColumn
extends SimComponent
## Batch distillation column at total reflux. The sump charge heats
## under the reboiler duty; at the boiling point the surplus duty
## becomes boilup, and vapor arriving faster than the condenser vent
## passes it raises the overhead pressure — a first-order lag that
## settles where boilup equals vent flow. Total reflux for now: the
## charge is conserved, so the column is a pure temperature/pressure
## machine until composition modelling arrives in a later tier.
## p_top is gauge pressure in Pa (PROCESS_PRESSURE ports carry Pa).

const DUTY_STEPS: Array[float] = [0.0, 0.5, 1.0]
const BOIL_C := 78.0
const AMBIENT_C := 20.0
const CP_KJ_PER_KG_K := 4.0
const LATENT_KJ_PER_KG := 850.0
const VENT_KG_PER_S_PA := 2.94e-6   # condenser/vent conductance
const PRESSURE_TAU_S := 30.0        # overhead pressure first-order lag
const COOL_TAU_S := 1800.0          # passive cooling with the duty off

var charge_l: float
var max_duty_kw: float
var temp_c: float
var duty_frac: float = 0.0
var duty_kw: float = 0.0
var boilup_kgps: float = 0.0
var p_top_pa: float = 0.0

var p_top: SimOutputPort


func _init(name_: String, charge_l_: float = 60.0, max_duty_kw_: float = 100.0,
		temp_c_: float = 74.0) -> void:
	super(name_)
	assert(charge_l_ > 0.0, "charge_l must be positive")
	assert(max_duty_kw_ > 0.0, "max_duty_kw must be positive")
	charge_l = charge_l_
	max_duty_kw = max_duty_kw_
	temp_c = temp_c_
	p_top = add_output("p_top", SimTypes.PortKind.PROCESS_PRESSURE)
	add_observable("temp_c", &"temp_c")
	add_observable("duty_kw", &"duty_kw")
	add_observable("boilup_kgps", &"boilup_kgps")


func set_duty(frac: float) -> void:
	duty_frac = clampf(frac, 0.0, 1.0)


## Cycle off -> half -> full -> off, for the E interaction.
func step_duty() -> void:
	var index := DUTY_STEPS.find(duty_frac)
	set_duty(DUTY_STEPS[(index + 1) % DUTY_STEPS.size()] if index >= 0 else 0.0)


func tick(dt: float) -> void:
	duty_kw = duty_frac * max_duty_kw
	var mass_kg := charge_l  # aqueous charge, ~1 kg/L
	if duty_kw > 0.0 and temp_c < BOIL_C:
		temp_c = minf(BOIL_C, temp_c + duty_kw / (mass_kg * CP_KJ_PER_KG_K) * dt)
		boilup_kgps = 0.0
	elif duty_kw > 0.0:
		boilup_kgps = duty_kw / LATENT_KJ_PER_KG
	else:
		temp_c += (AMBIENT_C - temp_c) * dt / COOL_TAU_S
		boilup_kgps = 0.0
	p_top_pa += (boilup_kgps / VENT_KG_PER_S_PA - p_top_pa) / PRESSURE_TAU_S * dt
	p_top.value = p_top_pa


func state_dict() -> Dictionary:
	return {"temp_c": temp_c, "duty_frac": duty_frac, "p_top_pa": p_top_pa}


func apply_state(state: Dictionary) -> void:
	temp_c = state.get("temp_c", temp_c)
	duty_frac = state.get("duty_frac", duty_frac)
	p_top_pa = state.get("p_top_pa", p_top_pa)
	p_top.value = p_top_pa
