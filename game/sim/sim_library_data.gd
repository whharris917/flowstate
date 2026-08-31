class_name SimLibraryData
## GENERATED FILE — do not edit by hand.
##
## Written by tools/generate_library.py from the EquipmentSpec
## declarations in sim/*.py, which are the single source of truth
## for equipment prose and equations. Edit a SPEC and re-run the
## generator; editing this file just means your change is lost the
## next time somebody does.
##
## Port NAMES, KINDS and DIRECTIONS are deliberately absent: the
## library reads those off a live component so a page can never
## describe I/O the game does not actually have.

const PAGES := {
	"tank": {
		"title": "Storage Tank",
		"tier": "process",
		"summary": "Holds liquid, and knows what the liquid is. Anything arriving blends into the contents, so a hot stream genuinely warms the vessel and a reagent charge genuinely changes what is in it. What is drawn off leaves at whatever the contents currently are. Overfill it and it spills, and the spill is counted.",
		"ports": {
			"draw": "What downstream equipment is pulling off the outlet.",
			"inlet": "Material delivered into the vessel. Several lines may land here and they blend.",
			"level": "Level tap, in litres, for a switch or a transmitter.",
			"outlet": "The contents, offered to whatever pulls on them.",
		},
		"equations": [
			["dV/dt = F_in - F_draw", "Plain inventory balance."],
			["x_new = (V*x + F_in*dt*x_in) / (V + F_in*dt)", "Incoming material blends by volume. Draw-off and overflow leave at the contents composition, so neither changes it -- only the inflow does."],
			["T_new = (V*T + F_in*dt*T_in) / (V + F_in*dt)", "Temperature blends the same way."],
			["offered = min(V / dt, nozzle_max)", "What the outlet advertises. A nearly empty tank offers almost nothing, which is what throttles a pump on it instead of letting the level go negative."],
		],
		"params": [
			["capacity_l", "L", "required", "Volume before it overflows. Follows the geometry if you give height and diameter."],
			["level_l", "L", "0", "Starting inventory."],
			["drain_lps", "L/s", "0", "A fixed background consumption, for standing in for downstream demand."],
			["height_m", "m", "0", "Shell height. Sets capacity with diameter."],
			["diameter_m", "m", "0", "Shell diameter."],
			["temp_c", "C", "20", "Starting temperature of the contents."],
			["comp", "-", "-", "Starting composition, as species fractions."],
		],
		"assumptions": [
			"Perfectly mixed: one temperature and one composition throughout, so there is no stratification and no settling.",
			"Heat loss is a single first-order term, not an insulation model.",
		],
	},
	"pump": {
		"title": "Fixed-Rate Transfer Pump",
		"tier": "process",
		"summary": "Moves material at its rating, or at whatever the suction can actually give it. A Hand-Off-Auto selector decides where the run command comes from, exactly like the switch on a real motor starter -- and none of the three positions do anything without 480 V at the starter. Run it against an empty vessel and the motor spins, nothing moves, and the seal wears.",
		"ports": {
			"draw": "What it is actually taking, metered back to the source.",
			"inlet": "Suction. Wire it to the vessel or header it pulls from.",
			"outlet": "Discharge, at the same temperature and composition as the suction.",
			"power": "480 V to the starter. No power, no motor, Hand included.",
			"run": "Run command in Auto. Ignored in Hand and Off.",
		},
		"equations": [
			["running = (Hand) or (Auto and run) , and powered", "The selector, then the starter."],
			["F = min(rated, offered) if running else 0", "It cannot pull what is not there, so an emptying tank throttles it smoothly rather than going negative."],
			["dry_run_s += dt   when running with nothing to pull", "The wear metric that makes a mistake provable afterwards."],
		],
		"params": [
			["rated_lps", "L/s", "required", "Flow when running with a wet suction."],
			["mode", "-", "auto", "Hand, Off, or Auto."],
		],
		"assumptions": [
			"No pump curve: flow does not fall off with discharge pressure, because the kernel has no hydraulic network.",
			"No start ramp -- it is at full rate on the scan it starts.",
		],
	},
	"reactor": {
		"title": "Jacketed Stirred Reactor",
		"tier": "process",
		"summary": "The heart of the train. Two reagents blend into the inventory and combine into product, with an impurity alongside. It needs heat to run at all and an agitator to run properly, and the hotter you push it the faster it goes and the dirtier it gets. There is no correct setpoint; that argument is the game.",
		"ports": {
			"draw": "What downstream equipment is pulling off the outlet.",
			"heat_duty": "Jacket duty in kW. Wire an exchanger or a controller.",
			"inlet_a": "First feed nozzle. Anything piped here joins the batch.",
			"inlet_b": "Second feed nozzle.",
			"level": "Contents level tap, for a switch or a transmitter.",
			"outlet": "The batch, offered to whatever pulls on it.",
			"power": "480 V to the agitator. Unstirred, it barely reacts.",
			"purity": "Product fraction of the contents, as an analog signal.",
			"temp": "Batch temperature, as an analog signal.",
			"vapor": "What boils off when duty exceeds the bubble point.",
		},
		"equations": [
			["f_T = clamp((T - 60) / (100 - 60), 0, 1)", "Temperature gate: nothing below 60 C, flat out at 100 C."],
			["f_mix = 1 if agitating else 0.05", "An unstirred vessel reacts at a twentieth of the rate."],
			["consumed = min(k * f_T * f_mix * dt, V*x_A, V*x_B)", "First-order in rate, limited by whichever reagent runs out first. The two combine one for one by volume."],
			["produced = 2 * consumed", "A litre of A and a litre of B make two litres of products, so the volume balance closes exactly."],
			["y_impurity = clamp(0.02 + 0.004 * (T - 70), 0, 1)", "Selectivity. Every degree above 70 C costs a little more of the batch to the impurity."],
			["dT/dt = Q / (m * cp) - (T - T_ambient) * k_loss", "Lumped energy balance: jacket duty in, ambient loss out. Incoming feed blends its own temperature in as it arrives."],
			["T <= bubble point of the contents", "Surplus duty boils the most volatile species present instead of raising the temperature further."],
		],
		"params": [
			["capacity_l", "L", "4000", "Working volume before it overflows."],
			["rate_lps", "L/s", "6", "Reagent consumed per second at full temperature and full agitation."],
		],
		"assumptions": [
			"Perfectly mixed: one temperature and one composition for the whole vessel.",
			"The reaction is first-order in rate and gated, not a real rate law with an activation energy.",
			"No heat of reaction -- all the heat comes from the jacket.",
			"The bubble point is the lowest boiling species present, not a real vapour-liquid equilibrium.",
		],
	},
	"hx": {
		"title": "Shell-and-Tube Exchanger",
		"tier": "process",
		"summary": "Steam on the shell, process on the tubes. It heats the stream you actually run through it, and it cannot heat that stream past the temperature of the steam supplying it -- so an undersized header shows up as a process that will not come up to heat however long you wait.",
		"ports": {
			"cold_in": "Process stream into the tubes.",
			"cold_out": "The same stream, hotter. Composition is unchanged.",
			"condensate": "Condensed steam, for a trap or a return header.",
			"duty": "Heat actually transferred, kW, as an analog signal.",
			"steam_in": "Steam to the shell.",
		},
		"equations": [
			["Q_available = m_steam * latent", "The heat the steam could give up if it all condensed."],
			["Q_offered = min(Q_available, Q_max)", "Capped by the area you bought."],
			["T_out = min(T_in + Q_offered / (m_cold * cp), T_steam - approach)", "The temperature rise, limited by the steam temperature. This is the line that matters."],
			["Q = m_cold * cp * (T_out - T_in)", "Duty is recomputed from the rise actually achieved, so the signal never claims heat the process did not take."],
			["m_condensate = m_steam", "Everything admitted to the shell condenses and leaves by the trap. Steam the process could not absorb is wasted, not destroyed -- pipe the condensate somewhere and the waste is on a totalizer."],
		],
		"params": [
			["max_duty_kw", "kW", "1200", "Duty at full steam: the area limit."],
		],
		"assumptions": [
			"No LMTD and no heat transfer coefficient: duty is capped by a flat maximum and by the steam temperature, nothing else.",
			"A fixed 5 C approach stands in for the pinch.",
			"Zero holdup and zero thermal mass -- the exchanger responds within one scan.",
			"Surplus heat in over-admitted steam leaves with the condensate rather than being tracked as an enthalpy.",
		],
	},
	"steamgen": {
		"title": "Steam Generator",
		"tier": "utility",
		"summary": "An electrically fired package boiler. Give it feedwater, 480 V and a run command and it makes saturated steam at a header pressure that rises and falls with firing. Fire it without water and it does not break, but it keeps a running total of how long you did it for.",
		"ports": {
			"draw": "Feedwater actually consumed, metered back to the header.",
			"inlet": "Feedwater. Pipe a water header to it.",
			"power": "480 V to the burner. No power, no steam, ever.",
			"press": "Header pressure tap for a gauge.",
			"steam": "Saturated steam to the plant, at the header temperature.",
		},
		"equations": [
			["m_steam = min(rated, feed) if fired and wet else 0", "It makes its rating, or whatever feedwater it can get."],
			["dP/dt = (P_target - P) / tau,  P_target = P_full * m/rated", "Header pressure lags firing with a first-order time constant."],
			["T_sat = 100 + (180 - 100) * P / P_full", "Saturation temperature, linearised across the range. This is the ceiling on anything the steam is used to heat."],
		],
		"params": [
			["rated_kgps", "kg/s", "0.5", "Steam output at full fire."],
		],
		"assumptions": [
			"Saturation temperature is a straight line in pressure, not a steam table.",
			"No superheat, no blowdown, no boiler inventory: feedwater in becomes steam out on the same scan.",
		],
	},
	"vialfill": {
		"title": "Vial Filler / Capper",
		"tier": "process",
		"summary": "A three-station machine: index the conveyor, fill a vial, press the cap. Every millilitre it puts in a vial is genuinely pulled through its inlet. It will fill vials with whatever you pipe to it and keep an honest record of what that was.",
		"ports": {
			"draw": "Fill rate, metered back upstream. Zero except while actually filling.",
			"inlet": "Product, pulled from an upstream vessel.",
			"power": "480 V to the machine.",
		},
		"equations": [
			["rate = V_vial / t_fill    [fill station only]", "Draw is not continuous: it is zero while indexing and capping, which is what gives the machine its rhythm."],
			["cycle = t_index + t_fill + t_cap", "One vial per cycle, so throughput follows directly."],
			["product_filled += rate * x_product * dt", "What actually reached the vials, as opposed to what was supposed to."],
		],
		"params": [
		],
		"assumptions": [
			"No reject station, no fill-weight variation, no stoppering distinct from capping.",
		],
	},
	"crystallizer": {
		"title": "Cooling Crystallizer",
		"tier": "separation",
		"summary": "A cooled, agitated vessel that drops product out of solution by taking it below its solubility. Cool it and crystals grow; warm it back up and they dissolve again, because it is the same equation running in both directions. It needs the agitator: nucleation wants the shear.",
		"ports": {
			"cool_duty": "Kilowatts *removed*, as an analog signal. Wire a chiller or a controller output.",
			"draw": "What downstream equipment is pulling off the outlet.",
			"inlet": "Hot, dilute solution from upstream.",
			"level": "Contents level tap.",
			"outlet": "Slurry, offered to whatever pulls on it.",
			"power": "480 V to the agitator.",
			"solids": "Fraction of the contents present as crystal, as an analog signal.",
			"temp": "Batch temperature, as an analog signal.",
		},
		"equations": [
			["S(T) = (S20 + m * (T - 20)) / 1000", "Solubility as a straight line in temperature. Dividing by 1000 turns grams per litre into a volume fraction, because the kernel takes 1 L as 1 kg."],
			["excess = x_dissolved - S(T)", "The driving force. Positive means crystals will grow; negative means they will redissolve."],
			["dx_solid/dt = excess * f_mix / tau", "First-order approach to equilibrium, slowed twentyfold without agitation."],
			["dT/dt = -Q_cool / (m * cp) - (T - T_ambient) * k_loss", "Energy balance. Duty is heat removed, so it subtracts."],
			["T >= T_coolant", "A jacket cannot chill the batch below the coolant feeding it, whatever duty you ask for."],
		],
		"params": [
			["capacity_l", "L", "3000", "Working volume before it overflows."],
		],
		"assumptions": [
			"One crystallizing species, and crystals are pure -- no co-precipitation and no inclusion of impurity in the lattice.",
			"No crystal size distribution: the solid is a single number, so there is no fines/growth behaviour and nothing for a mill.",
			"Solubility is linear in temperature, not a real curve.",
		],
	},
	"centrifuge": {
		"title": "Disc-Stack Centrifuge",
		"tier": "separation",
		"summary": "Spins crystals out of the liquor they formed in. It reads the solid phase actually present in its feed -- nothing tells it what it is separating. Feed it clear liquid and it honestly sends everything out the liquor nozzle. The cake comes off wet, which is why there is a dryer after it.",
		"ports": {
			"draw": "Slurry actually taken, metered back upstream.",
			"inlet": "Slurry, pulled from an upstream vessel.",
			"power": "480 V to the bowl drive.",
			"product": "Wet cake: captured crystals plus clinging liquor.",
			"waste": "Mother liquor, plus any crystals the bowl missed.",
		},
		"equations": [
			["F = min(rated, offered)", "It processes its rating or whatever the vessel can give it."],
			["captured = F * s * eta", "Of the solid in the feed, the bowl catches a fixed fraction."],
			["cake_liquid = captured * w", "Cake wetness: liquor retained per unit of crystal, carrying everything dissolved in it along for the ride."],
			["liquor = F - (captured + cake_liquid)", "Everything else leaves the other nozzle. The two add to F."],
		],
		"params": [
			["rate_lps", "L/s", "4", "Throughput of the bowl."],
			["capture_eff", "-", "0.95", "Fraction of incoming solid caught."],
			["cake_wetness", "-", "0.25", "Litres of liquor retained per litre of crystal."],
		],
		"assumptions": [
			"A fixed capture efficiency: no g-force, no residence time, no particle size.",
			"The cake retains liquor at the feed composition -- there is no wash step yet.",
		],
	},
	"dryer": {
		"title": "Cake Dryer",
		"tier": "separation",
		"summary": "Drives the last of the liquid off a wet filter cake. What evaporates is whatever is most volatile, so the solvent goes and the crystals stay. Note what that means: anything dissolved in the retained mother liquor is still there when the solvent leaves. A dryer concentrates impurity exactly as well as it concentrates product.",
		"ports": {
			"draw": "Cake actually taken, metered back upstream.",
			"heat_duty": "Drying duty in kW, as an analog signal.",
			"inlet": "Wet cake, pulled from a hopper or a vessel.",
			"power": "480 V to the tumbler.",
			"product": "Dried cake.",
			"vapor": "What was driven off, as a real stream to condense or vent.",
		},
		"equations": [
			["liquid_in = F * (1 - s)", "Only the liquid part of the cake can evaporate."],
			["evap = min(Q / latent, liquid_in)", "Energy sets the ceiling; the liquid present sets the other one. A huge duty on a dry cake does nothing."],
			["product = F - evap", "Everything that did not leave as vapour leaves as cake."],
		],
		"params": [
			["rate_lps", "L/s", "2", "Cake throughput."],
		],
		"assumptions": [
			"No drying curve: no constant-rate period, no falling-rate period, no bound moisture. Duty divided by latent heat, capped.",
			"Evaporation is strictly in order of boiling point.",
		],
	},
	"still": {
		"title": "Solvent Recovery Still",
		"tier": "separation",
		"summary": "Takes mother liquor and sends the light ends overhead and the heavy ends out the bottom. The reboiler duty is the throttle: no duty, no boilup, no separation, and everything you feed it leaves through the bottoms. This is the unit that closes the loop -- pipe the distillate back to a feed header and the solvent goes round again.",
		"ports": {
			"bottoms": "Heavy ends, including every crystal in the feed.",
			"distillate": "Overhead product, condensed. Usually the recycle.",
			"draw": "Feed actually taken, metered back upstream.",
			"heat_duty": "Reboiler duty in kW, as an analog signal.",
			"inlet": "Feed, pulled from an upstream vessel.",
			"power": "480 V to the reboiler.",
		},
		"equations": [
			["boilup = Q / latent", "The reboiler sets how much can go overhead at all."],
			["to_top(i) = f_i * eta          if boil(i) <  cut", "A species lighter than the cut mostly goes over."],
			["to_top(i) = f_i * (1 - eta)    if boil(i) >= cut", "A heavy one mostly stays down -- but not entirely. A real column is never a perfect cut, and that leak is why recycled solvent is never quite clean."],
			["distillate = min(sum(to_top), boilup)", "Scaled back proportionally if the reboiler cannot keep up."],
		],
		"params": [
			["rate_lps", "L/s", "3", "Feed throughput."],
			["cut_c", "C", "150", "Boiling point dividing light from heavy."],
			["sharpness", "-", "0.95", "How clean the cut is. 1.0 would be perfect separation."],
			["condenser_c", "C", "40", "Temperature the distillate leaves at."],
		],
		"assumptions": [
			"No trays, no reflux ratio, no McCabe-Thiele: a single split ratio per species about one cut temperature.",
			"No column holdup -- feed in becomes products out on the same scan.",
			"Solids never distill; they always report to the bottoms.",
		],
	},
	"column": {
		"title": "Batch Distillation Column",
		"tier": "separation",
		"summary": "A batch column at total reflux: the sump charge heats under the reboiler, and past the boiling point the surplus duty becomes boilup. Vapour arriving faster than the vent can pass it raises the overhead pressure. The condenser returns everything, so the charge is conserved and this is a pure temperature and pressure machine. For a column that actually separates and draws product, see the Solvent Recovery Still.",
		"ports": {
			"p_top": "Overhead pressure tap for a gauge.",
			"power": "480 V to the reboiler.",
		},
		"equations": [
			["dT/dt = Q / (m * cp)      below the boiling point", "All the duty goes into sensible heat while it is coming up."],
			["boilup = Q / latent       at the boiling point", "Past boiling the temperature stops and the duty makes vapour instead."],
			["dP/dt = (boilup / C_vent - P) / tau", "Overhead pressure settles where boilup equals what the vent can pass."],
		],
		"params": [
			["charge_l", "L", "60", "Sump charge."],
			["max_duty_kw", "kW", "100", "Reboiler duty at full fire."],
			["temp_c", "C", "74", "Starting sump temperature."],
		],
		"assumptions": [
			"Total reflux only -- no product draw and no composition change.",
			"A single fixed boiling point rather than a bubble point that moves with composition.",
		],
	},
	"source": {
		"title": "Supply Header",
		"tier": "utility",
		"summary": "A utility tie-in at the edge of the modelled plant -- the honest root of every flow path, the way a mains feeder is for power. Supply is unlimited because the rest of the utility system is off-plot, but everything drawn through it is metered. A header is what it carries: this is where a species enters the plant, and everything downstream finds out by being piped to it.",
		"ports": {
			"draw": "What equipment is pulling from the header. Totalized.",
			"supply": "The material on offer, at its storage temperature.",
		},
		"equations": [
			["total += F_draw * dt", "The meter. This is the number a mass balance is checked against."],
		],
		"params": [
			["species", "-", "water", "What the header carries."],
			["temp_c", "C", "20", "Storage temperature."],
			["comp", "-", "-", "Full composition, for a premixed feed."],
		],
		"assumptions": [
			"Infinite availability and no supply pressure: the header never runs out and never sags.",
		],
	},
	"drain": {
		"title": "Drain / Sewer Connection",
		"tier": "utility",
		"summary": "Where material leaves the plant. It pulls from a vessel when open, accepts a discharge line dumped straight into it, and meters everything it swallows -- including how much product you sent down it, which is the number that hurts.",
		"ports": {
			"draw": "What it is pulling from the vessel.",
			"flow_in": "A discharge line dumped straight to sewer: a separator's waste, a relief blowdown.",
			"inlet": "The vessel it drains, when open.",
		},
		"equations": [
			["F = min(rated, offered) if open else 0", "It cannot swallow faster than its rating or faster than the vessel can give."],
			["lost_product += (F * x_product + F_in * x_product_in) * dt", "Yield to sewer, on a trend. Nothing else in the plant will tell you about this."],
		],
		"params": [
			["rate_lps", "L/s", "1", "Maximum drain rate."],
		],
		"assumptions": [
			"No back pressure and no sewer capacity: an open drain always takes its rating.",
		],
	},
	"vaclock": {
		"title": "Cyclic Vacuum Transfer Lock",
		"tier": "utility",
		"summary": "A chamber that pulls down to rough vacuum, dwells, lets air back in through the main valve in discrete bursts, and drains the condensate each cycle knocks out of the humid air. A real state machine on a real timer.",
		"ports": {
			"drain_flow": "Condensate to a drain, delivered as it is made.",
			"power": "480 V to the vacuum pump. Lose it and the lock equalizes back to atmosphere.",
			"press": "Chamber pressure tap for a gauge.",
		},
		"equations": [
			["dP/dt = (P_vac - P) / tau      [evacuate]", "First-order pull-down toward the pump's blank-off pressure."],
			["P += (P_atm - P_vac) / n       [each vent burst]", "Re-pressurization happens in n discrete steps, not smoothly."],
			["condensate += V_cycle          [end of vent]", "Each completed cycle knocks a fixed volume out of the air."],
		],
		"params": [
		],
		"assumptions": [
			"A fixed condensate volume per cycle rather than a humidity calculation.",
			"No gas composition and no leak rate: the chamber is either being pumped, holding, venting, or draining.",
		],
	},
	"valve": {
		"title": "Control Valve",
		"tier": "control",
		"summary": "An air-actuated valve that follows a 0-100 % command with a positioner lag. It passes only what its upstream header offers, so a wide open valve on a dead header still flows nothing.",
		"ports": {
			"cmd": "Position command, 0-100 %, from a controller or an HMI.",
			"draw": "What it is passing, metered back to the header.",
			"inlet": "Upstream header.",
			"outlet": "Downstream line, at the header's temperature and composition.",
		},
		"equations": [
			["dx/dt = (cmd - x) / tau", "The positioner chases the command first-order. This lag is what a controller has to tune around."],
			["F = min(x/100 * Cv, offered)", "Linear trim, capped by what the header can supply."],
		],
		"params": [
			["cv_lps", "L/s", "6", "Flow at 100 % open with supply available."],
			["tau_s", "s", "1", "Positioner time constant."],
		],
		"assumptions": [
			"Linear trim and no pressure drop: flow is proportional to position, not to the square root of dP.",
			"No seat leakage, no hysteresis, no stiction.",
		],
	},
	"float_switch": {
		"title": "Level Switch",
		"tier": "control",
		"summary": "A mechanical level switch with two trip points. The contact closes on falling level at the low point and opens on rising level at the high one, holding its state in between. Set the two apart and a pump cycles calmly; set them equal and it chatters -- which is a valid configuration, and the lesson.",
		"ports": {
			"contact": "Dry contact, closed when calling for fill.",
			"level": "Level tap from the vessel it watches.",
		},
		"equations": [
			["closed = true   when level <= low", "Calls for fill on falling level."],
			["closed = false  when level >= high", "Drops out on rising level. Between the two it holds -- that gap is the hysteresis."],
		],
		"params": [
			["low_l", "L", "required", "Level at which the contact closes."],
			["high_l", "L", "required", "Level at which it opens again."],
		],
		"assumptions": [
			"Instant, bounce-free switching at an exact level.",
		],
	},
	"relay": {
		"title": "Interposing Relay",
		"tier": "control",
		"summary": "Coil in, contact out, one scan later. It counts its own energizations, which is what turns pump chatter from a feeling into a number you can put on a trend.",
		"ports": {
			"coil": "Coil. Several contacts landing here behave as parallel contacts and OR together.",
			"contact": "Normally-open contact, following the coil.",
		},
		"equations": [
			["contact = coil   (one scan later)", "The scan delay is deliberate: it is what real relay and PLC latency looks like, and what makes chatter reproducible."],
			["cycles += 1  on each rising edge", "The wear counter."],
		],
		"params": [
		],
		"assumptions": [
			"No contact bounce, no pickup or dropout delay, no welded contacts.",
		],
	},
	"mains": {
		"title": "Mains Feeder",
		"tier": "utility",
		"summary": "The plant's electrical supply: one always-energized output at its voltage class. The honest root of every power circuit -- nothing in the plant runs without a cable back to one of these.",
		"ports": {
			"power": "Energized supply at the feeder's voltage class.",
		},
		"equations": [
			["power = 1 always", "No load accounting or breakers yet."],
		],
		"params": [
			["spec", "-", "480VAC", "Voltage class, e.g. 480VAC."],
		],
		"assumptions": [
			"Infinite capacity: no breaker, no load accounting, no volt drop. Every feeder carries whatever you hang on it.",
		],
	},
	"psu": {
		"title": "Control Power Supply",
		"tier": "utility",
		"summary": "The cabinet PSU: 480 V in, 24 V out. Controllers ride on it, and it dies with its feeder.",
		"ports": {
			"ac_in": "480 V supply from a feeder.",
			"dc_out": "24 V control power.",
		},
		"equations": [
			["dc_out = 1 if ac_in else 0", "It passes through or it does not."],
		],
		"params": [
		],
		"assumptions": [
			"No current rating, no ride-through, no inrush.",
		],
	},
	"terminal": {
		"title": "Terminal Block",
		"tier": "control",
		"summary": "One terminal on a DIN rail: in to out, one scan later. The honest cost of landing a wire on a strip.",
		"ports": {
			"in": "Field or panel side.",
			"out": "The other side.",
		},
		"equations": [
			["out = in   (one scan later)", "A wire is not free."],
		],
		"params": [
			["kind", "-", "discrete", "discrete or analog."],
		],
		"assumptions": [
			"No resistance, no loose terminals.",
		],
	},
	"controller": {
		"title": "PID Controller",
		"tier": "control",
		"summary": "A single loop: it reads one measurement, compares it to a setpoint, and drives one output. Derivative acts on the measurement rather than the error, so a setpoint change does not kick the output. The integrator is held back whenever the output is railed, which is what stops it winding up while the valve is already wide open. Manual and auto transfer bumplessly because the integrator tracks the output in manual.\n\nDirection is in the sign of the gains: positive gains raise the output when the measurement is BELOW setpoint (heating, filling). Negative gains raise it when the measurement is ABOVE setpoint (cooling). A loop that runs away when you close it usually has the sign wrong.",
		"ports": {
			"out": "Controller output. A valve command by default, but the range is yours to set -- point it at a duty and the output is kilowatts.",
			"pv": "The measurement. Wire a transmitter or analyser here.",
		},
		"equations": [
			["e = SP - PV", "Error. Its sign is what makes a loop direct or reverse acting."],
			["I += ki * e * dt", "The integrator: it is what removes steady-state offset, and what winds up if you let it."],
			["D = -kd * (PV - PV_prev) / dt", "Derivative on the measurement, not the error, so a setpoint step does not spike the output."],
			["out = clamp(kp*e + I + D, out_min, out_max)", "The three terms, clamped to the output range."],
			["if railed: I = out - kp*e - D", "Anti-windup. While the output is against a limit the integrator is held to match it, so the loop comes off the rail the moment the error reverses instead of minutes later."],
		],
		"params": [
			["kp", "-", "1", "Proportional gain. Negative for a direct-acting loop such as cooling."],
			["ki", "1/s", "0", "Integral gain. Zero makes it a P-only loop, which is how a hand controller is built."],
			["kd", "s", "0", "Derivative gain. Usually zero on a noisy measurement."],
			["sp", "-", "0", "Setpoint, in the units of the measurement."],
			["out_min", "-", "0", "Bottom of the output range."],
			["out_max", "-", "100", "Top of the output range. Raise it to drive a duty in kW rather than a valve in percent."],
		],
		"assumptions": [
			"No output rate limit, no deadband, no filtering on the measurement.",
			"The scan is the simulation tick: there is no separate, slower controller execution period.",
		],
	},
	"plc": {
		"title": "Programmable Controller",
		"tier": "control",
		"summary": "A small PLC running a ladder program. Every scan it samples its inputs, solves each rung in order, and writes its outputs -- so a rung can see a coil that an earlier rung set this same scan, and a rung that reads a coil set later sees last scan's value. That ordering is not a quirk to work around; it is the thing that makes seal-in circuits and one-shots behave the way they do in a real cabinet.\n\nIts channels are dead unless the matching I/O card is fitted in the rack, and the whole processor is dead without 24 V.",
		"ports": {
			"ai_0": "Analog input channel.",
			"ai_1": "Analog input channel.",
			"ai_2": "Analog input channel.",
			"ai_3": "Analog input channel.",
			"ao_0": "Analog output channel.",
			"ao_1": "Analog output channel.",
			"ao_2": "Analog output channel.",
			"ao_3": "Analog output channel.",
			"di_0": "Discrete input channel.",
			"di_1": "Discrete input channel.",
			"di_2": "Discrete input channel.",
			"di_3": "Discrete input channel.",
			"di_4": "Discrete input channel.",
			"di_5": "Discrete input channel.",
			"di_6": "Discrete input channel.",
			"di_7": "Discrete input channel.",
			"do_0": "Discrete output channel.",
			"do_1": "Discrete output channel.",
			"do_2": "Discrete output channel.",
			"do_3": "Discrete output channel.",
			"do_4": "Discrete output channel.",
			"do_5": "Discrete output channel.",
			"do_6": "Discrete output channel.",
			"do_7": "Discrete output channel.",
			"power": "24 V from the cabinet supply. No power, no scan.",
		},
		"equations": [
			["scan: read inputs -> solve rungs in order -> write outputs", "One pass per tick. Rung order is program order."],
			["rung = OR over branches of (AND over contacts)", "Parallel branches are an OR, series contacts an AND -- the whole of ladder logic in one line."],
			["TON: elapsed += dt while enabled; done when elapsed >= preset", "An on-delay timer resets the moment its rung goes false."],
		],
		"params": [
			["di", "channels", "8", "Discrete input channels."],
			["do", "channels", "8", "Discrete output channels."],
			["ai", "channels", "4", "Analog input channels."],
			["ao", "channels", "4", "Analog output channels."],
			["memories", "bits", "16", "Internal coils. Not wired to anything in the field: they are the latches and flags the program keeps for itself."],
			["timers", "count", "4", "On-delay timers available to the program."],
		],
		"assumptions": [
			"The scan is instantaneous and takes exactly one tick, however long the program is.",
			"No forcing, no online edits, no retentive memory across a power cycle.",
		],
	},
	"gauge_level": {
		"title": "Gauge / Transmitter",
		"tier": "control",
		"summary": "A local indicator that is also a transmitter. It reads one honest derivation of the process it is tapped into and mirrors it on an analog output, so it is a dial today and a measurement the moment you wire it. Every reading here is a real conversion of real sim state; nothing is smoothed or invented.",
		"ports": {
			"process": "The tap. What it means depends on the kind of gauge.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "Rate straight off the stream in the line."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. This is what the AI needs before it can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
		],
		"assumptions": [
			"No sensor lag, no noise, no drift, no calibration error. The gauge reads the process exactly.",
		],
	},
	"gauge_flow": {
		"title": "Gauge / Transmitter",
		"tier": "control",
		"summary": "A local indicator that is also a transmitter. It reads one honest derivation of the process it is tapped into and mirrors it on an analog output, so it is a dial today and a measurement the moment you wire it. Every reading here is a real conversion of real sim state; nothing is smoothed or invented.",
		"ports": {
			"process": "The tap. What it means depends on the kind of gauge.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "Rate straight off the stream in the line."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. This is what the AI needs before it can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
		],
		"assumptions": [
			"No sensor lag, no noise, no drift, no calibration error. The gauge reads the process exactly.",
		],
	},
	"gauge_dp": {
		"title": "Gauge / Transmitter",
		"tier": "control",
		"summary": "A local indicator that is also a transmitter. It reads one honest derivation of the process it is tapped into and mirrors it on an analog output, so it is a dial today and a measurement the moment you wire it. Every reading here is a real conversion of real sim state; nothing is smoothed or invented.",
		"ports": {
			"process": "The tap. What it means depends on the kind of gauge.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "Rate straight off the stream in the line."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. This is what the AI needs before it can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
		],
		"assumptions": [
			"No sensor lag, no noise, no drift, no calibration error. The gauge reads the process exactly.",
		],
	},
	"gauge_press": {
		"title": "Gauge / Transmitter",
		"tier": "control",
		"summary": "A local indicator that is also a transmitter. It reads one honest derivation of the process it is tapped into and mirrors it on an analog output, so it is a dial today and a measurement the moment you wire it. Every reading here is a real conversion of real sim state; nothing is smoothed or invented.",
		"ports": {
			"process": "The tap. What it means depends on the kind of gauge.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "Rate straight off the stream in the line."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. This is what the AI needs before it can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
		],
		"assumptions": [
			"No sensor lag, no noise, no drift, no calibration error. The gauge reads the process exactly.",
		],
	},
	"gauge_temp": {
		"title": "Gauge / Transmitter",
		"tier": "control",
		"summary": "A local indicator that is also a transmitter. It reads one honest derivation of the process it is tapped into and mirrors it on an analog output, so it is a dial today and a measurement the moment you wire it. Every reading here is a real conversion of real sim state; nothing is smoothed or invented.",
		"ports": {
			"process": "The tap. What it means depends on the kind of gauge.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "Rate straight off the stream in the line."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. This is what the AI needs before it can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
		],
		"assumptions": [
			"No sensor lag, no noise, no drift, no calibration error. The gauge reads the process exactly.",
		],
	},
	"gauge_conc": {
		"title": "Gauge / Transmitter",
		"tier": "control",
		"summary": "A local indicator that is also a transmitter. It reads one honest derivation of the process it is tapped into and mirrors it on an analog output, so it is a dial today and a measurement the moment you wire it. Every reading here is a real conversion of real sim state; nothing is smoothed or invented.",
		"ports": {
			"process": "The tap. What it means depends on the kind of gauge.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "Rate straight off the stream in the line."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. This is what the AI needs before it can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
		],
		"assumptions": [
			"No sensor lag, no noise, no drift, no calibration error. The gauge reads the process exactly.",
		],
	},
	"cabinet": {
		"title": "Control Cabinet",
		"tier": "control",
		"summary": "An empty enclosure with bare DIN rails. It simulates nothing on its own: open the door, press EDIT, and fit it out with a supply, a processor, I/O cards, relays and terminal strips. Those modules are the real records, and the internal wiring between them is landed for you as hidden kernel wires. Field runs terminate on the flank markers; a channel with no card behind it is dead, and so is the whole rack without 24 V.",
		"ports": {
		},
		"equations": [
		],
		"params": [
		],
		"assumptions": [
			"The enclosure itself has no thermal, ingress or space limit: any module fits anywhere on the rail.",
		],
	},
}
