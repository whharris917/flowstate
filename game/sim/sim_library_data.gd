class_name SimLibraryData
## The in-game equipment library pages. HAND-AUTHORED under the
## director's editorial review (2026-09-01) — edit this file directly.
##
## It was seeded from the Python EquipmentSpecs by a generator that
## has since been removed. It is not derived from the Python source
## and is not required to match it.
##
## Port NAMES, KINDS and DIRECTIONS are deliberately absent: the
## library reads those off a live component so a page can never
## describe I/O the game does not actually have.

const PAGES := {
	"tank": {
		"title": "Storage Tank",
		"tier": "process",
		"summary": "Holds liquid, and knows what the liquid is. Anything arriving blends into the contents, so a hot stream genuinely warms the vessel and a reagent charge genuinely changes what is in it. What leaves does so at whatever the contents currently are. Overfill it and it spills, and the spill is counted.\n\nIts two nozzles differ only in where they are, and that is the whole of its hydraulic behaviour: the outlet is at the bottom and carries the head of everything standing above it, the inlet is at the top at headspace pressure. Which is why a full tank will drain into an empty one through nothing but a pipe, and why filling one never has to fight its own level.",
		"ports": {
			"inlet": "Top nozzle. Several runs may land here; they meet at a tee and blend. It sits above the liquid, so it cannot flow backwards.",
			"outlet": "Bottom nozzle, at headspace pressure plus the static head of the liquid. Material goes whichever way the network solves -- charging a vessel up through it is normal.",
			"level": "Internal tap that a switch or transmitter mounted on the shell reads. Not a nozzle you pipe: mounting the instrument makes the connection.",
		},
		"equations": [
			["P_outlet = P_headspace + rho*g*(z + depth)", "The boundary pressure the network sees at the bottom nozzle. Piezometric, so elevation costs head without the solver ever learning what elevation is."],
			["dV/dt = F_inlet + F_outlet  (both signed into the vessel)", "One balance covers filling, draining, and a line that reversed on you."],
			["x_new = (V*x + F_in*dt*x_in) / (V + F_in*dt)", "Incoming material blends by volume. What leaves and what overflows both go at the contents composition, so neither changes it -- only the inflow does."],
			["T_new = (V*T + F_in*dt*T_in) / (V + F_in*dt)", "Temperature blends the same way."],
			["opening = min(depth / 0.03 m, 1)", "The bottom nozzle uncovers as the level falls past it, so a vessel tails off instead of siphoning itself dry. Smooth, so it does not chatter shut."],
		],
		"params": [
			["capacity_l", "L", "required", "Volume before it overflows. Follows the geometry if you give height and diameter."],
			["level_l", "L", "0", "Starting inventory."],
			["drain_lps", "L/s", "0", "A standing leak off the inventory, for standing in for an unmodelled user. Not a nozzle: it takes no head."],
			["height_m", "m", "0", "Shell height. Sets capacity with diameter, and sets how high the top nozzle sits."],
			["diameter_m", "m", "0", "Shell diameter."],
			["headspace_kpa", "kPa", "0", "Blanket pressure over the liquid. Adds to both nozzles equally."],
			["elevation_m", "m", "placement", "Height of the vessel floor above grade. Taken from where you set it down; this is what buys you gravity flow."],
		],
		"assumptions": [
			"Perfectly mixed: one temperature and one composition throughout, so there is no stratification and no settling.",
			"Heat loss is a single first-order term, not an insulation model.",
			"The headspace is a fixed pressure, not a gas volume: filling the vessel does not compress it and draining does not pull vacuum.",
			"Only the two nozzles exist. There is no vent line, no overflow nozzle you can pipe, and a spill just leaves the model.",
		],
	},
	"pump": {
		"title": "Centrifugal Transfer Pump",
		"tier": "process",
		"summary": "Adds head to a line, and then finds its own operating point against whatever the system puts in front of it. It does not deliver its rating on demand: open the discharge and it runs out along its curve, throttle it and it walks back up. Ask it to lift more than its shutoff head and it dead-heads -- the motor turns, the valve is open, and nothing moves.\n\nA Manual On / Off / Auto selector decides where the run command comes from, exactly like the switch on a real motor starter, and none of the three positions do anything without 480 V at the starter.",
		"ports": {
			"run": "Run command in Auto. Ignored in Manual On and Off.",
			"power": "480 V to the starter. No power, no motor, Manual On included.",
			"inlet": "Suction nozzle. Pipe it to whatever it pulls from; the pressure it finds there is what decides whether it cavitates.",
			"outlet": "Discharge nozzle, one head rise above the suction, at the same temperature and composition.",
		},
		"equations": [
			["running = (Manual On) or (Auto and run), and powered", "The selector, then the starter."],
			["dP = H0 * (1 - (Q/Qmax)^2)", "The curve. Shutoff head at no flow, falling away as the square of flow, so two in parallel do not double the flow and a longer line genuinely costs you rate."],
			["H0 = rho*g*head_m ,  Qmax = 1.35 * rated_lps", "What you sized it for: shutoff head from the head rating, and a runout cap a third above rated flow."],
			["Q = 0 when not running", "A stopped pump shuts its line. That is not what a real one does -- see the assumptions."],
			["Q >= 0 always", "It never runs backwards, however the pressures fall out."],
			["dry_run_s += dt   when running with no flow", "The wear metric that makes a mistake provable afterwards."],
		],
		"params": [
			["rated_lps", "L/s", "required", "Flow at the rated point. Runout is a third above it."],
			["mode", "-", "auto", "Manual On, Off, or Auto."],
			["head_m", "m", "30", "Shutoff head, as metres of liquid. This is the lift it cannot exceed however long you run it."],
		],
		"assumptions": [
			"One generic curve shape for every pump. No published curve, no impeller trim, no speed control.",
			"No efficiency and no best-efficiency point, so running far off rated costs nothing in power or in wear.",
			"Cavitation is a suction-pressure taper, not NPSH available against NPSH required -- the species table carries no vapour pressure to compute one from. It loses its curve over the last 20 kPa above a hard vacuum and delivers nothing at the bottom, which is what makes a pump on an empty vessel stop rather than keep insisting. The cavitating flag trips earlier than that, so it warns before the flow has gone.",
			"No start ramp -- it is on its curve on the scan it starts.",
			"It is its own check valve, in both directions: stopped, it blocks the line completely, and running, it will not reverse however the pressures fall out. A real centrifugal does neither -- it freewheels backwards under discharge head, which is why real trains carry check valves this plant does not need.",
		],
	},
	"reactor": {
		"title": "Jacketed Stirred Reactor",
		"tier": "process",
		"summary": "The heart of the train. Two reagents blend into the inventory and combine into product, with an impurity alongside. It needs heat to run at all and an agitator to run properly, and the hotter you push it the faster it goes and the dirtier it gets. There is no correct setpoint; that argument is the game.\n\nA vessel, so its nozzles behave like one: the feeds enter at the top against headspace pressure, and the outlet at the bottom carries the static head of the batch standing above it.",
		"ports": {
			"inlet_a": "First feed nozzle, at the top. Anything piped here joins the batch, and it cannot flow backwards.",
			"inlet_b": "Second feed nozzle, alongside the first.",
			"heat_duty": "Jacket duty in kW. Wire an exchanger or a controller.",
			"power": "480 V to the agitator. Unstirred, it barely reacts.",
			"outlet": "Bottom nozzle, carrying the head of the batch standing above it. It uncovers as the vessel empties.",
			"level": "Contents level tap, for a switch or a transmitter.",
			"purity": "Product fraction of the contents, as an analog signal.",
			"temp": "Batch temperature, as an analog signal.",
		},
		"equations": [
			["f_T = clamp((T - 60) / (100 - 60), 0, 1)", "Temperature gate: nothing below 60 C, flat out at 100 C."],
			["f_mix = 1 if agitating else 0.05", "An unstirred vessel reacts at a twentieth of the rate."],
			["consumed = min(k * f_T * f_mix * dt, V*x_A, V*x_B)", "First-order in rate, limited by whichever reagent runs out first. The two combine one for one by volume."],
			["produced = 2 * consumed", "A litre of A and a litre of B make two litres of products, so the volume balance closes exactly."],
			["y_impurity = clamp(0.02 + 0.004 * (T - 70), 0, 1)", "Selectivity. Every degree above 70 C costs a little more of the batch to the impurity."],
			["dT/dt = Q / (m * cp) - (T - T_ambient) * k_loss", "Lumped energy balance: jacket duty in, ambient loss out. Incoming feed blends its own temperature in as it arrives."],
			["T <= bubble point of the contents", "Surplus duty boils the most volatile species present instead of raising the temperature further. That vapour leaves through the vent, so it comes off the inventory rather than out of a nozzle you can pipe."],
		],
		"params": [
			["capacity_l", "L", "4000", "Working volume before it overflows."],
			["rate_lps", "L/s", "6", "Reagent consumed per second at full temperature and full agitation."],
			["height_m", "m", "2.4", "Shell height. Sets how high the feed nozzles sit and how much head a full batch puts on the outlet."],
			["elevation_m", "m", "placement", "Height of the vessel floor above grade. Taken from where you set it down; this is what buys you gravity flow."],
		],
		"assumptions": [
			"Perfectly mixed: one temperature and one composition for the whole vessel.",
			"The reaction is first-order in rate and gated, not a real rate law with an activation energy.",
			"No heat of reaction -- all the heat comes from the jacket.",
			"The bubble point is the lowest boiling species present, not a real vapour-liquid equilibrium.",
			"Boil-off has no nozzle. It leaves the model through an unmodelled vent, so you cannot condense it, recover it, or route it anywhere -- it is only counted.",
			"The vessel is atmospheric. The headspace holds no pressure, so boiling is never suppressed by blanketing it.",
		],
	},
	"hx": {
		"title": "Shell-and-Tube Exchanger",
		"tier": "process",
		"summary": "Steam on the shell, process on the tubes. It heats the stream you actually run through it, and it cannot heat that stream past the temperature of the steam supplying it -- so an undersized header shows up as a process that will not come up to heat however long you wait.\n\nThe shell is a real path, not a number: steam flows from the header through the shell to the condensate nozzle, driven by the pressure across it. An exchanger whose condensate has nowhere to go passes no steam and delivers no duty, exactly as a shell with no trap fitted would.",
		"ports": {
			"steam_in": "Shell inlet. Pipe it to a steam header.",
			"cold_in": "Tube inlet: the process stream, cold.",
			"cold_out": "Tube outlet: the same stream, hotter. Composition is unchanged -- an exchanger moves heat, not material.",
			"condensate": "Shell outlet. Pipe it to a trap or a return header; leave it dead and no steam flows at all.",
			"duty": "Heat actually transferred, kW, as an analog signal.",
		},
		"equations": [
			["dP_shell = K * Q_steam^2 ,  dP_tubes = K' * Q_process^2", "Both sides are ordinary resistances, so the exchanger costs pressure to push anything through -- and the shell only passes steam if there is somewhere for the condensate to go."],
			["Q_available = m_steam * latent", "The heat the steam could give up if it all condensed."],
			["Q_offered = min(Q_available, Q_max)", "Capped by the area you bought."],
			["T_out = min(T_in + Q_offered / (m_cold * cp), T_steam - approach)", "The temperature rise, limited by the steam temperature. This is the line that matters."],
			["Q = m_cold * cp * (T_out - T_in)", "Duty is recomputed from the rise actually achieved, so the signal never claims heat the process did not take."],
			["m_condensate = m_steam", "Everything admitted to the shell condenses and leaves by the trap. Steam the process could not absorb is wasted, not destroyed -- pipe the condensate somewhere and the waste is counted rather than hidden."],
		],
		"params": [
			["max_duty_kw", "kW", "1200", "Duty at full steam: the area limit."],
		],
		"assumptions": [
			"No LMTD and no heat transfer coefficient: duty is capped by a flat maximum and by the steam temperature, nothing else.",
			"A fixed 5 C approach stands in for the pinch.",
			"Zero holdup and zero thermal mass -- the exchanger responds within one scan.",
			"Surplus heat in over-admitted steam leaves with the condensate rather than being tracked as an enthalpy.",
			"Both resistances are fixed: fouling never builds up, so an exchanger does not degrade with service.",
			"Nothing checks that you piped steam to the shell. Run process fluid through the shell side and it will be treated as the heating medium.",
		],
	},
	"steamgen": {
		"title": "Steam Generator",
		"tier": "utility",
		"summary": "An electrically fired package boiler. Give it feedwater, 480 V and a run command and it makes saturated steam at a header pressure that rises and falls with firing. Fire it without water and it does not break, but it keeps a running total of how long you did it for.\n\nWhat it holds is a real pressure, and that pressure is what pushes steam anywhere at all -- which is why an exchanger whose condensate has nowhere to go gets no steam from it.",
		"ports": {
			"inlet": "Feedwater nozzle. Its own feed pump pulls through this while firing, so a header on the far end of a long run genuinely starves it.",
			"power": "480 V to the burner. No power, no steam, ever.",
			"steam": "The steam header nozzle. Holds boiler pressure, and that is what drives steam into whatever you pipe to it.",
			"press": "Header pressure tap for a gauge.",
		},
		"equations": [
			["dP_feed = rho*g*110 m * (1 - (Q/rated)^2)   while firing", "The feed pump, on the same curve shape as any other pump, tall enough to beat drum pressure. Stop firing and it stops pulling."],
			["P_steam = P   (fixed)", "The steam nozzle is a boundary at drum pressure. Everything downstream flows because of this number."],
			["dP/dt = (P_target - P) / tau,  P_target = P_full * F_feed/rated", "Drum pressure lags firing with a first-order time constant, and what it is chasing is set by the feedwater actually arriving."],
			["T_sat = 100 + (180 - 100) * P / P_full", "Saturation temperature, linearised across the range. This is the ceiling on anything the steam is used to heat."],
		],
		"params": [
			["rated_kgps", "kg/s", "0.5", "Steam output at full fire, and the rated flow of its feed pump."],
		],
		"assumptions": [
			"Saturation temperature is a straight line in pressure, not a steam table.",
			"No superheat, no blowdown, no boiler inventory: feedwater in becomes steam out on the same scan.",
			"Steam is carried on the same 1 L = 1 kg liquid basis as everything else -- the network has one phase, so the vapour is not compressible and does not expand as it drops pressure.",
			"The drum is a pressure boundary, like a supply header. It holds its pressure however hard you draw on it, so it will hand out more steam than its feedwater is bringing in and make up the difference from nowhere. Mass does not close across the boiler: it is the one place in the plant where that is true, and it is why the drum pressure sags with feedwater rather than with demand.",
		],
	},
	"vialfill": {
		"title": "Vial Filler / Capper",
		"tier": "process",
		"summary": "A three-station machine: index the conveyor, fill a vial, press the cap. Every millilitre it puts in a vial is genuinely pulled through its inlet. It will fill vials with whatever you pipe to it and keep an honest record of what that was.",
		"ports": {
			"inlet": "Fill nozzle. The dosing pump pulls through this, and only while the fill station is actually filling.",
			"power": "480 V to the machine.",
		},
		"equations": [
			["Q = V_vial / t_fill  while filling, else 0   (imposed)", "The draw is not continuous: it is zero while indexing and capping, which is what gives the machine its rhythm and what makes the fill line pulse."],
			["cycle = t_index + t_fill + t_cap", "One vial per cycle, so throughput follows directly."],
			["starved = filling and Q < 0.9 * needed", "A dosing pump that cannot get its charge is starved, and the suction heading for vacuum is how it finds out."],
			["product_filled += Q * x_product * dt", "What actually reached the vials, as opposed to what was supposed to."],
		],
		"params": [
		],
		"assumptions": [
			"No reject station, no fill-weight variation, no stoppering distinct from capping.",
			"The dose is an imposed rate, so a starved machine still fills a short vial and counts it as done rather than faulting.",
			"Filled vials leave the modelled plant at the nozzle. Nothing downstream of the fill point is simulated.",
		],
	},
	"crystallizer": {
		"title": "Cooling Crystallizer",
		"tier": "separation",
		"summary": "A cooled, agitated vessel that drops product out of solution by taking it below its solubility. Cool it and crystals grow; warm it back up and they dissolve again, because it is the same equation running in both directions. It needs the agitator: nucleation wants the shear.\n\nA vessel, so its inlet sits at the top and its outlet carries the head of the slurry standing above it.",
		"ports": {
			"inlet": "Top feed nozzle: hot, dilute solution from upstream. It sits above the liquid and cannot run backwards.",
			"cool_duty": "Kilowatts *removed*, as an analog signal. Wire a chiller or a controller output.",
			"power": "480 V to the agitator.",
			"outlet": "Bottom nozzle, carrying the head of the slurry above it. It uncovers as the vessel empties.",
			"level": "Contents level tap.",
			"solids": "Fraction of the contents present as crystal, as an analog signal.",
			"temp": "Batch temperature, as an analog signal.",
		},
		"equations": [
			["S(T) = (S20 + m * (T - 20)) / 1000", "Solubility as a straight line in temperature. Dividing by 1000 turns grams per litre into a volume fraction, because the kernel takes 1 L as 1 kg."],
			["excess = x_dissolved - S(T)", "The driving force. Positive means crystals will grow; negative means they will redissolve."],
			["dx_solid/dt = excess * f_mix / tau", "First-order approach to equilibrium, slowed tenfold without agitation."],
			["dT/dt = -Q_cool / (m * cp) - (T - T_ambient) * k_loss", "Energy balance. Duty is heat removed, so it subtracts."],
			["T >= T_coolant", "A jacket cannot chill the batch below the coolant feeding it, whatever duty you ask for."],
		],
		"params": [
			["capacity_l", "L", "3000", "Working volume before it overflows."],
			["height_m", "m", "2.2", "Shell height. Sets how high the feed nozzle sits and how much head a full vessel puts on the outlet."],
			["elevation_m", "m", "placement", "Height of the vessel floor above grade. Taken from where you set it down; this is what buys you gravity flow."],
		],
		"assumptions": [
			"One crystallizing species, and crystals are pure -- no co-precipitation and no inclusion of impurity in the lattice.",
			"No crystal size distribution: the solid is a single number, so there is no fines/growth behaviour and nothing for a mill.",
			"Solubility is linear in temperature, not a real curve.",
			"The slurry flows exactly like the liquid it came from: solids add no viscosity, settle nowhere, and never plug a line.",
		],
	},
	"centrifuge": {
		"title": "Disc-Stack Centrifuge",
		"tier": "separation",
		"summary": "Spins crystals out of the liquor they formed in. It reads the solid phase actually present in its feed -- nothing tells it what it is separating. Feed it clear liquid and it honestly sends everything out the liquor nozzle. The cake comes off wet, which is why there is a dryer after it.\n\nIt has its own feed pump, so what it draws is its curve against the suction you gave it. Starve it and the rate falls away rather than the machine inventing material.",
		"ports": {
			"inlet": "Feed nozzle. Its own pump pulls slurry through this while the bowl is spinning.",
			"power": "480 V to the bowl drive.",
			"product": "Wet cake: captured crystals plus clinging liquor.",
			"waste": "Mother liquor, plus any crystals the bowl missed.",
		},
		"equations": [
			["dP_feed = rho*g*18 m * (1 - (Q/rated)^2)   while spinning", "The feed pump curve. Stop the bowl and it stops pulling."],
			["Q_cake + Q_liquor = F   (imposed at the discharges)", "Whatever it drew last scan leaves as two streams that add back to it, so the bowl holds no inventory and the balance closes across the machine."],
			["captured = F * s * eta", "Of the solid in the feed, the bowl catches a fixed fraction."],
			["cake_liquid = captured * w", "Cake wetness: liquor retained per unit of crystal, carrying everything dissolved in it along for the ride."],
			["liquor = F - (captured + cake_liquid)", "Everything else leaves the other nozzle. The two add to F."],
		],
		"params": [
			["rate_lps", "L/s", "4", "Throughput of the bowl: the rated flow of its feed pump."],
			["capture_eff", "-", "0.95", "Fraction of incoming solid caught."],
			["cake_wetness", "-", "0.25", "Litres of liquor retained per litre of crystal."],
		],
		"assumptions": [
			"A fixed capture efficiency: no g-force, no residence time, no particle size.",
			"The cake retains liquor at the feed composition -- there is no wash step yet, so this caps the purity the train can reach.",
			"The two discharges are imposed rates, not pressure-driven: the bowl will push its split out against any back pressure you put on it, and it cannot be blocked in.",
			"The split follows the draw by one scan, so a step change in feed shows up at the discharges the scan after.",
		],
	},
	"dryer": {
		"title": "Cake Dryer",
		"tier": "separation",
		"summary": "Drives the last of the liquid off a wet filter cake. What evaporates is whatever is most volatile, so the solvent goes and the crystals stay. Note what that means: anything dissolved in the retained mother liquor is still there when the solvent leaves. A dryer concentrates impurity exactly as well as it concentrates product.",
		"ports": {
			"inlet": "Feed nozzle. Its own feed pump pulls wet cake through this while the dryer is running, so an empty hopper above it simply starves it.",
			"heat_duty": "Drying duty in kW, as an analog signal.",
			"power": "480 V to the tumbler.",
			"product": "Dried cake, pushed out at whatever did not evaporate.",
		},
		"equations": [
			["dP_feed = rho*g*12 m * (1 - (Q/rated)^2)   while running", "The feed pump curve. Switch the dryer off and it stops pulling cake."],
			["liquid_in = F * (1 - s)", "Only the liquid part of the cake can evaporate."],
			["evap = min(Q_duty / latent, liquid_in)", "Energy sets the ceiling; the liquid present sets the other one. A huge duty on a dry cake does nothing."],
			["Q_product = F - evap   (imposed at the discharge)", "Everything that did not leave as vapour leaves as cake, so the balance closes across the machine."],
		],
		"params": [
			["rate_lps", "L/s", "2", "Cake throughput: the rated flow of its feed pump."],
		],
		"assumptions": [
			"No drying curve: no constant-rate period, no falling-rate period, no bound moisture. Duty divided by latent heat, capped.",
			"Evaporation is strictly in order of boiling point.",
			"The vapour has no nozzle. It leaves through an unmodelled vent, so you cannot condense or recover it -- only dried_l remembers it went.",
			"The cake discharge is an imposed rate, not pressure-driven: it cannot be blocked in and takes no back pressure.",
		],
	},
	"still": {
		"title": "Solvent Recovery Still",
		"tier": "separation",
		"summary": "Takes mother liquor and sends the light ends overhead and the heavy ends out the bottom. The reboiler duty is the throttle: no duty, no boilup, no separation, and everything you feed it leaves through the bottoms. This is the unit that closes the loop -- pipe the distillate back to a feed header and the solvent goes round again.",
		"ports": {
			"inlet": "Feed nozzle. Its own feed pump pulls through this while the still is running.",
			"heat_duty": "Reboiler duty in kW, as an analog signal.",
			"power": "480 V to the reboiler.",
			"distillate": "Overhead product, condensed. Usually the recycle.",
			"bottoms": "Heavy ends, including every crystal in the feed.",
		},
		"equations": [
			["dP_feed = rho*g*20 m * (1 - (Q/rated)^2)   while running", "The feed pump curve. No power, no feed."],
			["boilup = Q_duty / latent", "The reboiler sets how much can go overhead at all."],
			["to_top(i) = f_i * eta          if boil(i) <  cut", "A species lighter than the cut mostly goes over."],
			["to_top(i) = f_i * (1 - eta)    if boil(i) >= cut", "A heavy one mostly stays down -- but not entirely. A real column is never a perfect cut, and that leak is why recycled solvent is never quite clean."],
			["distillate = min(sum(to_top), boilup)", "Scaled back proportionally if the reboiler cannot keep up."],
		],
		"params": [
			["rate_lps", "L/s", "3", "Feed throughput: the rated flow of its feed pump."],
			["cut_c", "C", "150", "Boiling point dividing light from heavy."],
			["sharpness", "-", "0.95", "How clean the cut is. 1.0 would be perfect separation."],
			["condenser_c", "C", "40", "Temperature the distillate leaves at."],
		],
		"assumptions": [
			"No trays, no reflux ratio, no McCabe-Thiele: a single split ratio per species about one cut temperature.",
			"No column holdup -- feed in becomes products out on the same scan.",
			"Solids never distill; they always report to the bottoms.",
			"Both products are imposed rates, not pressure-driven: the still pushes its split out against any back pressure and cannot be blocked in.",
			"No column pressure, so the cut temperature never moves with it.",
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
		"summary": "A utility tie-in at the edge of the modelled plant -- the honest root of every flow path, the way a mains feeder is for power. A header is three things and nothing else: what it carries, how hot it is, and what pressure it holds.\n\nIt has one nozzle. There is no inlet, because from the plant's point of view there is nothing upstream. And nothing announces what it took: what leaves is whatever the network pulls out, and the meter simply reads that.",
		"ports": {
			"outlet": "The tie-in nozzle. Holds its rated pressure whatever you draw, and the meter keeps a running total of what left through it.",
		},
		"equations": [
			["P_outlet = pressure_kpa + rho*g*z   (fixed)", "A boundary node. The header holds this pressure no matter what is hung off it -- which is what makes a higher-pressure header genuinely deliver more."],
			["total += max(-F_outlet, 0) * dt", "The meter. Flow at a nozzle is signed into the component, so material leaving reads negative; this is the number a mass balance is checked against."],
		],
		"params": [
			["species", "-", "water", "What the header carries."],
			["temp_c", "C", "20", "Storage temperature."],
			["pressure_kpa", "kPa", "400", "The pressure it holds at the tie-in. This, and the resistance of what you pipe to it, is what sets the flow."],
			["elevation_m", "m", "placement", "Height of the tie-in above grade. Taken from where you set it down."],
		],
		"assumptions": [
			"Infinite availability and a perfectly stiff pressure: the header never runs out and never sags, however much you pull.",
			"It cannot be pushed into. Piping a running pump at it will not back material up the utility system.",
			"One fixed composition and temperature -- a header does not change with the season or with what its own supply is doing.",
		],
	},
	"drain": {
		"title": "Drain / Sewer Connection",
		"tier": "utility",
		"summary": "Where material leaves the plant: a nozzle, a valve, and a pipe to sewer. It has no magic rate -- its valve has a Cv like any other, and what goes down it is whatever the head above it pushes through. So a nearly empty vessel drains slowly, as one does, and a deep one runs fast and then tails off.\n\nIt meters everything it swallows, and separately how much product you sent down it, which is the number that hurts.",
		"ports": {
			"inlet": "The line to sewer. Pipe a vessel bottom, a separator's waste, or a relief blowdown into it -- it is the same nozzle either way, and several lines may land on it.",
		},
		"equations": [
			["Q = rate_lps * open * sqrt(dP / 100 kPa)", "The drain valve, following the same valve equation as any other. Shut it and it holds."],
			["P_sewer = rho*g*z   (fixed)", "The far side of the valve is atmosphere at the drain's own elevation, and it will take whatever it is given."],
			["lost_product += F * x_product * dt", "Yield to sewer, on a trend. Nothing else in the plant will tell you about this."],
		],
		"params": [
			["rate_lps", "L/s", "1", "Size of the drain valve: what it passes wide open across a 1 bar drop, not a rate it is guaranteed to achieve."],
			["elevation_m", "m", "placement", "Height of the sewer connection. Taken from where you set it down; put it below what you are draining."],
		],
		"assumptions": [
			"The sewer is an infinite sink at atmospheric pressure: it never backs up and never floods.",
			"The drain valve does not check. Set the sewer connection above what it serves and its own static head will push back up the line -- correct arithmetic, but not a drain any longer.",
			"Nothing is recovered and nothing is treated -- material down here is simply gone, and only the meters remember it.",
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
		"summary": "An air-actuated valve that follows a 0-100 % command with a positioner lag, onto a trim that obeys the valve equation. Which means its authority is real: half open is not half the flow, and a valve sized far larger than the line it sits in buys you almost nothing for the last half of its travel. That is the classic badly-sized loop, and here it is something the player can actually diagnose from a trend.",
		"ports": {
			"cmd": "Position command, 0-100 %, from a controller or an HMI.",
			"inlet": "Upstream nozzle.",
			"outlet": "Downstream nozzle, at the same temperature and composition -- a valve changes rate, not material.",
		},
		"equations": [
			["dx/dt = (cmd - x) / tau", "The positioner chases the command first-order. This lag is what a controller has to tune around."],
			["Q = Cv * (x/100) * sqrt(dP / 100 kPa)", "The valve equation. Flow follows the square root of the drop across the valve, so it is the rest of the system, not the command alone, that decides what gets through."],
			["Q = 0 when x = 0", "Shut is shut: it holds against any drop the network puts across it."],
		],
		"params": [
			["cv_lps", "L/s", "6", "The size of the valve: what it passes wide open across a 1 bar drop. Not US Cv (gpm at 1 psi) and not metric Kv."],
			["tau_s", "s", "1", "Positioner time constant."],
		],
		"assumptions": [
			"Linear trim only -- no equal-percentage or quick-opening characteristic, so the installed characteristic comes entirely from the line it sits in.",
			"No seat leakage, no hysteresis, no stiction, no dead band.",
			"It resists in both directions equally and will not check reverse flow.",
			"No actuator fail position: cut the command and it goes to zero, rather than to fail-open or fail-closed.",
		],
	},
	"block_valve": {
		"title": "Block Valve",
		"tier": "control",
		"summary": "An on/off valve with a stroking actuator: one discrete command, a fixed travel time from seat to full open, and a trim that follows the valve equation the whole way. It is the valve a sequence uses -- open it, wait for it to travel, move to the next step -- rather than one a controller throttles. Its position and flow are historized, so a valve that was told to open and did not is a fact on a trend rather than a mystery.",
		"ports": {
			"open": "Discrete command: energized opens, de-energized closes. Land a PLC output, a relay contact or a switch here.",
			"inlet": "Upstream nozzle.",
			"outlet": "Downstream nozzle, at the same temperature and composition -- a valve changes rate, not material.",
		},
		"equations": [
			["dx/dt = +100 / stroke_s opening, -100 / stroke_s closing", "The actuator travels at a fixed rate, so for stroke_s after the command changes the valve is neither open nor shut. A sequence that does not wait for that has a leak in it."],
			["Q = Cv * (x/100) * sqrt(dP / 100 kPa)", "The valve equation with the travel fraction as the opening. The head across it decides what flows, not the command."],
			["Q = 0 when x = 0", "Shut is shut: it holds against any drop the network puts across it."],
		],
		"params": [
			["cv_lps", "L/s", "20", "The size of the valve: what it passes wide open across a 1 bar drop. Not US Cv (gpm at 1 psi) and not metric Kv."],
			["stroke_s", "s", "4", "Seat to full open, and back."],
		],
		"assumptions": [
			"Linear travel and a linear trim: a real ball or gate valve passes most of its flow in the first part of its travel.",
			"No limit switches, so a sequence trusts the stroke time rather than an open or closed contact.",
			"No seat leakage, no stiction, and no fail position: lose the signal and it closes at stroke speed.",
			"It resists in both directions equally and will not check reverse flow.",
		],
	},
	"float_switch": {
		"title": "Level Switch",
		"tier": "control",
		"summary": "A mechanical level switch with two trip points. The contact closes on falling level at the low point and opens on rising level at the high one, holding its state in between. Set the two apart and a pump cycles calmly; set them equal and it chatters -- which is a valid configuration, and the lesson.",
		"ports": {
			"contact": "Dry contact, closed when calling for fill.",
			"level": "The level of the vessel it is mounted on. Not a nozzle you pipe: mounting the switch on the shell makes the connection.",
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
			"process": "The tap, for the tapped kinds: a level, a thermowell, an analyser sample, a pressure tapping. A level transmitter is mounted on its vessel and the connection is made for it.",
			"inlet": "Inline flow meter, upstream side. The line runs through the element.",
			"outlet": "Inline flow meter, downstream side.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "The flow that actually passes through the element, signed forward."],
			["dP = K * F^2                     [flow]", "An inline element costs the line a little pressure, like any fitting."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
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
			"process": "The tap, for the tapped kinds: a level, a thermowell, an analyser sample, a pressure tapping. A level transmitter is mounted on its vessel and the connection is made for it.",
			"inlet": "Inline flow meter, upstream side. The line runs through the element.",
			"outlet": "Inline flow meter, downstream side.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "The flow that actually passes through the element, signed forward."],
			["dP = K * F^2                     [flow]", "An inline element costs the line a little pressure, like any fitting."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
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
			"process": "The tap, for the tapped kinds: a level, a thermowell, an analyser sample, a pressure tapping. A level transmitter is mounted on its vessel and the connection is made for it.",
			"inlet": "Inline flow meter, upstream side. The line runs through the element.",
			"outlet": "Inline flow meter, downstream side.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "The flow that actually passes through the element, signed forward."],
			["dP = K * F^2                     [flow]", "An inline element costs the line a little pressure, like any fitting."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
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
			"process": "The tap, for the tapped kinds: a level, a thermowell, an analyser sample, a pressure tapping. A level transmitter is mounted on its vessel and the connection is made for it.",
			"inlet": "Inline flow meter, upstream side. The line runs through the element.",
			"outlet": "Inline flow meter, downstream side.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "The flow that actually passes through the element, signed forward."],
			["dP = K * F^2                     [flow]", "An inline element costs the line a little pressure, like any fitting."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
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
			"process": "The tap, for the tapped kinds: a level, a thermowell, an analyser sample, a pressure tapping. A level transmitter is mounted on its vessel and the connection is made for it.",
			"inlet": "Inline flow meter, upstream side. The line runs through the element.",
			"outlet": "Inline flow meter, downstream side.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "The flow that actually passes through the element, signed forward."],
			["dP = K * F^2                     [flow]", "An inline element costs the line a little pressure, like any fitting."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
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
			"process": "The tap, for the tapped kinds: a level, a thermowell, an analyser sample, a pressure tapping. A level transmitter is mounted on its vessel and the connection is made for it.",
			"inlet": "Inline flow meter, upstream side. The line runs through the element.",
			"outlet": "Inline flow meter, downstream side.",
			"process_a": "High-side tap on a differential gauge.",
			"process_b": "Low-side tap on a differential gauge.",
			"signal": "The reading, mirrored as a 4-20 mA analog output.",
		},
		"equations": [
			["P = level / L_per_m * rho*g      [level_kpa]", "Hydrostatic head at a vessel bottom, in kPa."],
			["reading = F                      [flow]", "The flow that actually passes through the element, signed forward."],
			["dP = K * F^2                     [flow]", "An inline element costs the line a little pressure, like any fitting."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
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
