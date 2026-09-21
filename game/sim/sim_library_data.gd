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
		"summary": "Holds liquid, and knows what the liquid is. Anything arriving blends into the contents, so a hot stream genuinely warms the vessel and a reagent charge genuinely changes what is in it. What leaves does so at whatever the contents currently are. Overfill it and it spills, and the spill is counted.\n\nIts two nozzles differ only in where they are, and that is the whole of its hydraulic behaviour: the outlet is at the bottom and carries the head of everything standing above it, the inlet is at the top at headspace pressure. Which is why a full tank will drain into an empty one through nothing but a pipe, and why filling one never has to fight its own level.\n\nA tank can be OPEN-TOPPED (the CONFIGURE tab): no roof, its liquid seen from above, and a line ending in the air over it lands what it delivers in it.",
		"ports": {
			"inlet": "Top nozzle. Several runs may land here; they meet at a tee and blend. It sits above the liquid, so it cannot flow backwards.",
			"outlet": "Bottom nozzle, at headspace pressure plus the static head of the liquid. Material goes whichever way the network solves -- charging a vessel up through it is normal.",
			"level": "Internal tap that a switch or transmitter mounted on the shell reads. Not a nozzle you pipe: mounting the instrument makes the connection.",
			"contents": "Internal tap of the contents that a temperature probe mounted on the shell reads. Nothing flows through it; it holds what the vessel holds. Mounting the probe makes the connection.",
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
			["nozzle_cv_lps", "L/s", "20", "Size of the nozzles: what the bottom nozzle passes wide open across a 1 bar drop, with the top nozzle's stub sized to match. The default suits a few litres a second; a line carrying tens needs a bigger vessel nozzle as much as a bigger pipe."],
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
			["elevation_m", "m", "where it stands", "Height of its nozzles above grade, taken from where you put it. Its suction gauge reads the static pressure there, and a pump high above its supply loses prime where the same pump at grade would not."],
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
			"wash": "Wash liquor nozzle: pipe clean solvent here under pressure and it sprays onto the cake while the bowl spins, displacing the mother liquor the cake would keep. Shut unless the bowl spins.",
			"power": "480 V to the bowl drive.",
			"product": "Wet cake: captured crystals plus what liquid is left clinging to them -- mother liquor, or wash if you washed.",
			"waste": "Mother liquor, spent wash, plus any crystals the bowl missed.",
		},
		"equations": [
			["dP_feed = rho*g*18 m * (1 - (Q/rated)^2)   while spinning", "The feed pump curve. Stop the bowl and it stops pulling."],
			["Q_cake + Q_liquor = F   (imposed at the discharges)", "Whatever it drew last scan leaves as two streams that add back to it, so the bowl holds no inventory and the balance closes across the machine."],
			["captured = F * s * eta", "Of the solid in the feed, the bowl catches a fixed fraction."],
			["cake_liquid = captured * w", "Cake wetness: liquor retained per unit of crystal, carrying everything dissolved in it along for the ride."],
			["kept = exp(-W / cake_liquid)", "Displacement washing: each cake-liquid volume of wash pushes out 63 % of the mother liquor still in the cake and takes its place. Two volumes leave 14 % of it, three leave 5 %."],
			["liquor = F - (captured + cake_liquid) + W", "Everything else leaves the other nozzle, spent wash included. In and out still add up."],
		],
		"params": [
			["rate_lps", "L/s", "4", "Throughput of the bowl: the rated flow of its feed pump."],
			["capture_eff", "-", "0.95", "Fraction of incoming solid caught."],
			["cake_wetness", "-", "0.25", "Litres of liquor retained per litre of crystal."],
		],
		"assumptions": [
			"A fixed capture efficiency: no g-force, no residence time, no particle size.",
			"Washing is ideal displacement: the wash never channels past the cake, and it never dissolves crystal. A real solvent wash loses some product to the liquor.",
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
			["elevation_m", "m", "where it stands", "Height of its nozzles above grade, taken from where you put it. The drop across the valve does not depend on it; the static pressure a gauge at the valve reads does."],
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
			"open": "Discrete command: energized opens, de-energized closes. Land a PLC output, a relay contact or a switch here. Leave it unwired and this is a hand valve: E at the valve opens and shuts it.",
			"inlet": "Upstream nozzle.",
			"outlet": "Downstream nozzle, at the same temperature and composition -- a valve changes rate, not material.",
			"zso": "Open limit switch: a dry contact that makes in the last 2 % of travel. Wire it to a PLC input and a step can wait for the valve to report open instead of trusting the stroke time.",
			"zsc": "Closed limit switch: makes in the first 2 % of travel. Both off means the valve is somewhere in between.",
		},
		"equations": [
			["dx/dt = +100 / stroke_s opening, -100 / stroke_s closing", "The actuator travels at a fixed rate, so for stroke_s after the command changes the valve is neither open nor shut. A sequence that does not wait for that has a leak in it."],
			["Q = Cv * (x/100) * sqrt(dP / 100 kPa)", "The valve equation with the travel fraction as the opening. The head across it decides what flows, not the command."],
			["Q = 0 when x = 0", "Shut is shut: it holds against any drop the network puts across it."],
		],
		"params": [
			["cv_lps", "L/s", "20", "The size of the valve: what it passes wide open across a 1 bar drop. Not US Cv (gpm at 1 psi) and not metric Kv."],
			["stroke_s", "s", "4", "Seat to full open, and back."],
			["elevation_m", "m", "where it stands", "Height of its nozzles above grade, taken from where you put it. The drop across the valve does not depend on it; the static pressure a gauge at the valve reads does."],
		],
		"assumptions": [
			"Linear travel and a linear trim: a real ball or gate valve passes most of its flow in the first part of its travel.",
			"The limit switches are ideal: they make at exactly 2 % from either end, never stick, and never drift.",
			"No seat leakage, no stiction, and no fail position: lose the signal and it closes at stroke speed.",
			"It resists in both directions equally and will not check reverse flow.",
		],
	},
	"hmi_trend": {
		"title": "Trend Screen",
		"tier": "control",
		"summary": "An operator screen on two posts showing up to four historian tags over a window you choose. Every pen is replayed from the historian's own samples -- the same record every gauge, HMI and balance page reads -- so what it shows is what happened, not a smoothed picture of it. Pick the pens in the right-click CONFIGURE tab: type part of a tag and take one from the matches. Each pen carries its own scale; the legend shows the live value and the range over the window.",
		"ports": {},
		"equations": [
			["y(t) = historian[tag](t)   for t in [now - window, now]", "A plain replay. The historian samples every tag every scan, so a pen has one point per scan and the screen thins them only to fit its pixels."],
		],
		"params": [
			["tags", "-", "none", "Up to four historian tags, one per pen. Any tag: a level, a flow, a composition fraction, a controller output, a valve position."],
			["window_s", "s", "600", "How far back the screen looks."],
		],
		"assumptions": [
			"It shows the historian and nothing else: no alarms, no setpoints, no cursors yet.",
			"Each pen has its own scale, so two pens crossing on the screen means nothing about their values -- read the legend.",
		],
	},
	"cap": {
		"title": "Pipe cap",
		"tier": "utility",
		"summary": "A short spool with a nozzle at each end and a blind flange on whichever end carries no line. The two nozzles are one point in the network. A line cut in play leaves a cap on each side of the cut; the pipe behind it stands at pressure and moves nothing, since a dead end has nowhere for material to go. Run a line from a capped end and the blind comes off: the cap is then a plain coupling. A line laid to nowhere ends in an OPEN cap: the blind is off, the end vents to the air at its own height, and whatever the line delivers falls out of it. Over an open-topped vessel it lands in the vessel and fills it, drop by drop or as a stream, and the delivery is totalled; anywhere else it spills to the ground and the spill is totalled. Press E on it to put the blind on, and again to take it off.",
		"ports": {
			"a": "The upstream nozzle: the line arriving at the cap.",
			"b": "The downstream nozzle: the line leaving it, if any.",
		},
		"equations": [
			["P_a = P_b", "One node: both nozzles see the same pressure."],
			["Q_a = Q_b", "What arrives leaves; with one nozzle blind, both are zero."],
			["Q_spill = Cv * sqrt(dP / 1 bar), open", "An open end is a free discharge to atmosphere at its own height; the line behind it sets the rate."],
		],
		"params": [],
		"assumptions": [
			"No pressure drop through the fitting: the lines carry the resistance.",
			"A blind end holds pressure without leaking; nothing is vented or drained by a cut.",
			"The cap has no volume: material in the cut line is not stored in it.",
			"An open end over an open-topped vessel lands its spill in the vessel, blended in like any other arrival; over anything else it spills to the ground, counted and gone.",
			"What falls is drawn and heard off the real rate: below three millilitres a second it is drops, about twenty to the millilitre, above that a stream.",
		],
	},
	"tee_split": {
		"title": "Tee — Splitter",
		"tier": "utility",
		"summary": "A pipe fitting whose nozzles are one point in the network: the same pressure at every leg, flows that add to zero. One inlet, three outlets on separated nozzles; an unused leg is capped. It exists because a nozzle takes one line -- joining and splitting is a fitting's job, and the split is whatever the resistances downstream make of it.",
		"ports": {
			"in": "Inlet: the line being split.",
			"a": "Outlet, straight through.",
			"b": "Outlet, the near side leg.",
			"c": "Outlet, the far side leg.",
		},
		"equations": [
			["P_in = P_a = P_b = P_c", "One node: every leg sees the same pressure."],
			["Q_in = Q_a + Q_b + Q_c", "What comes in leaves; each leg takes what its own run's resistance and destination allow."],
		],
		"params": [],
		"assumptions": [
			"No pressure drop through the fitting itself: the legs' runs carry the resistance.",
			"A capped leg is a dead nozzle, not a leak.",
		],
	},
	"tee_mix": {
		"title": "Tee — Mixer",
		"tier": "utility",
		"summary": "A pipe fitting whose nozzles are one point in the network: the same pressure at every leg, and the flow-weighted blend of whatever arrives. Three inlets on separated nozzles, one outlet; an unused leg is capped. It exists because a nozzle takes one line -- joining is a fitting's job.",
		"ports": {
			"a": "Inlet, straight through.",
			"b": "Inlet, the near side leg.",
			"c": "Inlet, the far side leg.",
			"out": "Outlet: the blend.",
		},
		"equations": [
			["P_a = P_b = P_c = P_out", "One node: every leg sees the same pressure."],
			["x_out = sum(Q_i x_i) / sum(Q_i)", "The blend, flow-weighted, one scan later like every other hop. Temperature and solids blend the same way."],
		],
		"params": [],
		"assumptions": [
			"No pressure drop through the fitting itself: the legs' runs carry the resistance.",
			"Perfect mixing at the node: no stratification, no dead leg.",
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
		"summary": "The plant's electrical supply: numbered always-energized ways at its voltage class, one per load. The honest root of every power circuit -- nothing in the plant runs without a cable back to one of these, and a way takes one cable. Feed several loads from several ways; a busy plant needs a feeder with more ways, set when it is placed.",
		"ports": {
			"way1": "Way 1: energized supply at the feeder's voltage class, for one load.",
			"way2": "Way 2, the same.",
			"way3": "Way 3, the same.",
			"way4": "Way 4, the same.",
			"way5": "Way 5, the same.",
			"way6": "Way 6, the same.",
			"way7": "Way 7, the same.",
			"way8": "Way 8, the same.",
		},
		"equations": [
			["way_n = 1 always", "No load accounting or breakers yet."],
		],
		"params": [
			["spec", "-", "480VAC", "Voltage class, e.g. 480VAC."],
			["ways", "-", "8", "How many loads it can feed; set when placed."],
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
			["total += max(F, 0) * dt          [flow]", "The totalizer: forward flow integrated since the meter was placed. What a batch was, not only what it is."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
			["meter_k", "Pa/(L/s)^2", "1000", "What the inline element costs the line, for the flow kind. Size it to the line: about 10 to 30 kPa at design flow."],
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
			["total += max(F, 0) * dt          [flow]", "The totalizer: forward flow integrated since the meter was placed. What a batch was, not only what it is."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
			["meter_k", "Pa/(L/s)^2", "1000", "What the inline element costs the line, for the flow kind. Size it to the line: about 10 to 30 kPa at design flow."],
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
			["total += max(F, 0) * dt          [flow]", "The totalizer: forward flow integrated since the meter was placed. What a batch was, not only what it is."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
			["meter_k", "Pa/(L/s)^2", "1000", "What the inline element costs the line, for the flow kind. Size it to the line: about 10 to 30 kPa at design flow."],
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
			["total += max(F, 0) * dt          [flow]", "The totalizer: forward flow integrated since the meter was placed. What a batch was, not only what it is."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
			["meter_k", "Pa/(L/s)^2", "1000", "What the inline element costs the line, for the flow kind. Size it to the line: about 10 to 30 kPa at design flow."],
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
			["total += max(F, 0) * dt          [flow]", "The totalizer: forward flow integrated since the meter was placed. What a batch was, not only what it is."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
			["meter_k", "Pa/(L/s)^2", "1000", "What the inline element costs the line, for the flow kind. Size it to the line: about 10 to 30 kPa at design flow."],
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
			["total += max(F, 0) * dt          [flow]", "The totalizer: forward flow integrated since the meter was placed. What a batch was, not only what it is."],
			["reading = T                      [temp_c]", "Temperature of the stream in the line."],
			["reading = x_species * 100        [conc_pct]", "The analyser. Until one of these is on the line, nobody can say anything true about quality."],
			["reading = P_a - P_b              [dp_pa]", "Differential pressure across two taps."],
		],
		"params": [
			["kind", "-", "required", "level_kpa, flow, temp_c, conc_pct, dp_pa, or press_kpa."],
			["liters_per_meter", "L/m", "45.45", "Vessel cross-section, for turning level into head."],
			["species", "-", "product", "Which species an analyser reads."],
			["meter_k", "Pa/(L/s)^2", "1000", "What the inline element costs the line, for the flow kind. Size it to the line: about 10 to 30 kPa at design flow."],
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
	"control_station": {
		"title": "Local Control Station",
		"tier": "control",
		"summary": "An enclosure on a post with a row of pushbuttons and a row of pilot lights: the station a plant runs a motor or a sequence from without a screen. Each button and light is a real record the ladder sees; each button is its own target, E presses it. The circuits leave on the right flank and land in the cabinet like any other. Placed with START, STOP, RUNNING and STOPPED.",
		"ports": {
		},
		"equations": [
			["START makes on a press, STOP breaks on a press", "A normally-open and a normally-closed contact, which is what a seal-in rung needs: START sets the latch, STOP drops it, and the latch holds itself through STOP's made contact in between."],
		],
		"params": [
		],
		"assumptions": [
			"Four devices in the default station; the layout is fixed once placed.",
		],
	},
	"pushbutton": {
		"title": "Pushbutton",
		"tier": "control",
		"summary": "A pushbutton on a local control station. Momentary by default: the contact follows the button while it is held, which in a scanned plant means for a short hold after a press. A maintained button, a selector, toggles on each press. Normally closed for a STOP, so the circuit is made until someone presses it, which is the seal-in a start/stop station relies on.",
		"ports": {
			"contact": "Dry contact: made while pressed (normally open) or while not pressed (normally closed).",
		},
		"equations": [
			["contact = pressed XOR normally_closed", "A normally-open button makes on a press; a normally-closed one breaks on a press."],
			["pressed holds 0.6 s after a momentary press", "A finger stays on a button longer than one scan, so a momentary press is a short hold, not a single-scan blip a seal-in could miss."],
		],
		"params": [
			["momentary", "-", "true", "True for a pushbutton that releases, false for a selector that stays."],
			["normally_closed", "-", "false", "True for a STOP-style button whose contact is made until pressed."],
		],
		"assumptions": [
			"No contact bounce, no wear, no illuminated buttons.",
		],
	},
	"pilot_light": {
		"title": "Pilot Light",
		"tier": "control",
		"summary": "A pilot light: lit while its lamp circuit is energized, nothing more. The thing on a station that tells an operator what the PLC believes without a screen.",
		"ports": {
			"lamp": "The lamp circuit, from a PLC output or a relay contact.",
		},
		"equations": [
			["lit = lamp > 0.5", "Energized is lit."],
		],
		"params": [
			["color", "-", "green", "Lens colour: green, red, amber, white or blue. Meaning is convention, not the kernel's."],
		],
		"assumptions": [
			"The lamp never burns out and draws no accounted power.",
		],
	},
	"junction_box": {
		"title": "Junction Box",
		"tier": "control",
		"summary": "A field enclosure on a post where an area's instrument and valve circuits land on terminals and leave together in one multicore cable to the cabinet, the way a real plant gathers its field wiring instead of running every conduit home. Each terminal is a real record, one scan late like any terminal; the multicore is a hidden kernel wire per circuit and one cable to look at, which the support rule checks like any run.",
		"ports": {
		},
		"equations": [
			["out = in   (one scan later, per terminal)", "A terminal block. The scan is the honest cost of landing a wire on a strip."],
		],
		"params": [
			["channels", "-", "12", "Terminals in the box: one per circuit that passes through."],
		],
		"assumptions": [
			"Discrete terminals only for now: 4-20 mA circuits still run their own conduit.",
			"No gland count limit, no ingress rating, no segregation of power from signal.",
		],
	},

	# ---- the small-bore family (director, 2026-09-20): new machines for
	# little lines, sized in L/s at 1 bar like every valve ---------------
	"orifice": {
		"title": "Restriction Orifice",
		"tier": "utility",
		"summary": "A plate with a hole in it, held between two faces in the line: the flow limiter. It has one number, the flow it passes at a 1 bar drop, and the square law does the rest. It limits by resistance alone, so what gets through still rises with the pressure behind it -- a limiter, not a regulator. Nothing to turn and nothing to wire; a tag on its handle is the only way to tell one from another.",
		"ports": {
			"inlet": "Upstream nozzle.",
			"outlet": "Downstream nozzle, the same material at a lower pressure.",
		},
		"equations": [
			["Q = Cv * sqrt(dP / 1 bar)", "The square law through a fixed hole: four times the pressure buys twice the flow."],
		],
		"params": [
			["cv_lps", "L/s at 1 bar", "0.001", "The flow through the hole at the reference drop. A drip is a fraction of a millilitre a second."],
		],
		"assumptions": [
			"No vena contracta and no pressure recovery: the drop is the drop.",
			"It never clogs, erodes or cavitates.",
		],
	},
	"needle_valve": {
		"title": "Needle Valve",
		"tier": "control",
		"summary": "A hand valve with a fine tapered stem: many turns from shut to full open, so a fraction of a turn is a real adjustment. This is the valve a small line is trimmed with. No actuator and no command; the operator is the control system. E opens it a turn at a time, and from full open the next press shuts it; the CONFIGURE tab sets the stem exactly.",
		"ports": {
			"inlet": "Upstream nozzle.",
			"outlet": "Downstream nozzle.",
		},
		"equations": [
			["x = turns_open / turns", "The stem's travel as a fraction of full open."],
			["Q = Cv * x * sqrt(dP / 1 bar)", "The valve equation: the drop across it decides what flows, the stem decides how much of the seat is open."],
		],
		"params": [
			["cv_lps", "L/s at 1 bar", "0.005", "Flow at full open across the reference drop."],
			["turns", "turns", "10", "How many turns of the handle from shut to full open."],
			["elevation_m", "m", "where it stands", "Height of its nozzles above grade, taken from where you put it: the static pressure at the valve, not the drop across it."],
		],
		"assumptions": [
			"A linear characteristic in the turns: a real needle valve is closer to equal percentage, most of its authority in the last turns.",
			"No packing leak and no seat wear.",
		],
	},
	"ball_valve": {
		"title": "Ball Valve",
		"tier": "control",
		"summary": "A quarter-turn hand valve: a lever, open or shut, and half a second of travel between. The lever lies along the line when open and across it when shut, which is the only indication there is -- no actuator, no limit switch. The valve equation while it travels, as for the block valve, so it is not a wall until it lands. E throws the lever.",
		"ports": {
			"inlet": "Upstream nozzle.",
			"outlet": "Downstream nozzle.",
		},
		"equations": [
			["dx/dt = +-100 / stroke_s", "The lever's own quarter turn, at the hand's speed."],
			["Q = Cv * (x/100) * sqrt(dP / 1 bar)", "The valve equation with the travel as the opening."],
		],
		"params": [
			["cv_lps", "L/s at 1 bar", "0.5", "Flow at full open across the reference drop. A full-bore ball valve barely restricts its line."],
			["stroke_s", "s", "0.5", "How long the quarter turn takes."],
			["elevation_m", "m", "where it stands", "Height of its nozzles above grade, taken from where you put it: the static pressure at the valve, not the drop across it."],
		],
		"assumptions": [
			"A linear characteristic through the travel; a ball's is not.",
			"Bubble-tight when shut.",
		],
	},
	"solenoid_valve": {
		"title": "Solenoid Valve",
		"tier": "control",
		"summary": "A coil-operated valve: shut until its coil is energized, open while it is, and the plunger snaps in a few hundredths of a second. Normally closed, so a lost signal is a shut valve. There is no hand override: nothing wired to the coil means it never opens. The lamp on the connector is lit while the coil is energized, and every operation is counted.",
		"ports": {
			"coil": "The coil: a 24 V discrete signal. Land a PLC output, a relay contact or a switch here. Energized opens.",
			"inlet": "Upstream nozzle.",
			"outlet": "Downstream nozzle.",
		},
		"equations": [
			["x -> 100 in 0.05 s energized, -> 0 de-energized", "The plunger snaps: within a scan or two it is at one end or the other."],
			["Q = Cv * (x/100) * sqrt(dP / 1 bar)", "The valve equation."],
		],
		"params": [
			["cv_lps", "L/s at 1 bar", "0.3", "Flow at full open across the reference drop."],
			["elevation_m", "m", "where it stands", "Height of its nozzles above grade, taken from where you put it: the static pressure at the valve, not the drop across it."],
		],
		"assumptions": [
			"The coil draws nothing from the signal: no current, no heating, no burn-out.",
			"No minimum operating differential: it opens against any drop, which a pilot-operated valve would not.",
		],
	},
	"metering_pump": {
		"title": "Metering Pump",
		"tier": "process",
		"summary": "A positive-displacement dosing pump: a diaphragm and two check valves, driven by a small motor. It delivers its stroke volume every stroke whatever the discharge pressure, until the pressure reaches what its drive can push against -- so its curve is nearly vertical, the opposite of the centrifugal pump, and two in parallel really do double the flow. The stroke length is the dose adjustment, a knob on the pump or a 4-20 mA signal. It runs on 24 V DC. With nothing wired to run it is a hand pump: E starts and stops it.",
		"ports": {
			"run": "Discrete run command. Unwired, the pump is hand-operated at its own switch.",
			"stroke": "Analog stroke length, 0-100 %. Unwired, the knob on the pump sets it (the CONFIGURE tab).",
			"power": "24 V DC supply. No supply, no pump.",
			"inlet": "Suction nozzle.",
			"outlet": "Discharge nozzle, the same material as the suction.",
		},
		"equations": [
			["Q_stroke = rated_lps * stroke / 100", "The dose set at the knob or by the signal."],
			["Q = Q_stroke * (1 - (H / H_max)^8)^(1/8)", "Nearly the full stroke until the head approaches the maximum, then nothing: the drive stalls."],
		],
		"params": [
			["rated_lps", "L/s", "0.01", "Delivery at full stroke against no head."],
			["max_head_m", "m", "50", "The head the drive can push against; past it the pump stalls."],
			["elevation_m", "m", "where it stands", "Height of its nozzles above grade, taken from where you put it: prime is judged on the static suction there."],
		],
		"assumptions": [
			"No pulsation: the flow is the average over the strokes, and nothing downstream sees the pulses.",
			"No check-valve leakage and no loss of prime beyond the suction taper every pump has.",
			"It does not care what it pumps: no viscosity, no gas locking.",
		],
	},
	"regulator": {
		"title": "Pressure Regulator",
		"tier": "control",
		"summary": "A self-acting pressure-reducing valve: a spring against a diaphragm that feels the downstream pressure and throttles the seat as it rises. No signal in or out. It holds its outlet near the setting while the inlet is higher and the flow within its Cv; above the setting it shuts. The little gauge on its outlet reads the real downstream pressure, and it never reads the setting exactly, because a regulator droops as the flow through it rises.",
		"ports": {
			"inlet": "Upstream nozzle, the higher pressure.",
			"outlet": "Downstream nozzle, held near the setting.",
		},
		"equations": [
			["x = clamp((P_set - P_out) / P_band, 0, 1)", "The diaphragm against its spring, solved with the network: the seat opens as the outlet falls below the setting."],
			["Q = Cv * x * sqrt(dP / 1 bar)", "The valve equation."],
			["P_band = max(0.1 * P_set, 5 kPa)", "The droop: the outlet sags a tenth of the setting from no flow to full open."],
		],
		"params": [
			["set_kpa", "kPa", "200", "The downstream pressure it holds."],
			["cv_lps", "L/s at 1 bar", "0.5", "Flow at full open across the reference drop: the most it can pass."],
			["elevation_m", "m", "where it stands", "Height of its nozzles above grade, taken from where you put it. The diaphragm feels the static pressure there, so the outlet it holds is the setting at that height, and its gauge reads the same."],
		],
		"assumptions": [
			"Proportional only, a straight-line droop: a real regulator's curve is not straight.",
			"No relief: an outlet pushed above the setting from downstream is not vented, only shut against.",
		],
	},
	"rotameter": {
		"title": "Rotameter",
		"tier": "control",
		"summary": "A variable-area flow indicator: a float in a tapered glass tube, riding at the height where the drag of the flow balances its weight. A local indication and nothing else, no signal out -- the flow gauge is the transmitting instrument. The tube is a small resistance the line pays for the reading.",
		"ports": {
			"inlet": "Upstream nozzle, the bottom of the tube.",
			"outlet": "Downstream nozzle.",
		},
		"equations": [
			["float_frac = Q / Q_range", "The float's height up the tube, clamped to it."],
			["dP = k * Q^2, k = 5 kPa / Q_range^2", "What the tube costs the line: 5 kPa at full scale."],
		],
		"params": [
			["range_lps", "L/s", "0.01", "Full-scale flow: the top of the tube."],
		],
		"assumptions": [
			"A linear scale: a real tube is calibrated for one fluid and reads wrong for another.",
			"No float bounce, and nothing readable below a tenth of scale.",
		],
	},
}
