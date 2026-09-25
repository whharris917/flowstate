class_name BenchDemo
## The bench on the Maine site, east of the home pad: chemistry at the
## scale the route was written at. Two lab benches on a seamless floor.
##
##   LB-701  the reagents the hold packed, a row of bottles and jars along
##           the back: water, hydrochloric acid and sodium hydroxide at
##           1 M, phenolphthalein, acetic acid, sodium bicarbonate,
##           calcium chloride, sodium carbonate, copper sulfate,
##           hydrogen peroxide 30 % and potassium iodide
##   LB-702  a hotplate stirrer warming a beaker of water to 60 C, a pH
##           meter with a beaker of acid and indicator under its
##           electrode (pour base into it and watch the pH climb and the
##           colour turn), a balance with an empty beaker on its pan, and
##           a flask with bicarbonate in water to pour acid on
##
## Everything here is a placeable record, and every beaker was filled by
## pouring from a bottle, by the same rule a player's pour follows.

const ORIGIN := Vector3(16.0, 0.0, 0.0)   # the middle of the floor
const FLOOR := 0.06                        # the top of the slab
const TOP := FLOOR + 0.9                   # the bench tops

const REAGENTS: Array[String] = ["water", "hcl_1m", "naoh_1m", "phenolphthalein", "acetic_glacial",
	"nahco3", "cacl2", "na2co3", "cuso4", "h2o2_30", "ki"]


static func build(plant: Plant) -> void:
	for i in 2:
		plant.place_structure("s_slab_seamless", "fl_701_%d" % i,
			ORIGIN + Vector3(-2.0 + 4.0 * i, 0.0, 0.0), 0.0)
	# Two benches end to end along x, their cupboard fronts facing +z
	# (toward the pad), the reagents along the back of the west one.
	var west := ORIGIN + Vector3(-1.0, FLOOR, 0.0)
	var east := ORIGIN + Vector3(1.0, FLOOR, 0.0)
	plant.place_structure("s_lab_bench", "lb_701", west, PI)
	plant.place_structure("s_lab_bench", "lb_702", east, PI)
	var back := -0.24
	for i in REAGENTS.size():
		var x := west.x - 0.78 + i * 0.155
		plant.place("reagent_bottle", "rb_701_%s" % REAGENTS[i], {"stock": REAGENTS[i]},
			Vector3(x, TOP, back), 0.0, false)
	# A few empty beakers along the front of the reagent bench to pour into.
	for i in 3:
		plant.place("lab_beaker", "bk_701_%d" % (i + 1), {"capacity_ml": 250.0},
			Vector3(west.x - 0.5 + i * 0.25, TOP, 0.15), 0.0, false)
	plant.place("lab_vial", "sv_701", {"capacity_ml": 20.0}, Vector3(west.x + 0.35, TOP, 0.15), 0.0, false)

	# ---- the working bench -------------------------------------------------
	var hp := plant.place("hotplate", "hp_701", {"setpoint_c": 60.0, "stir_rpm": 400.0},
		Vector3(east.x - 0.55, TOP, 0.0), 0.0, false) as SimHotplate
	plant.place("lab_beaker", "bk_702", {"capacity_ml": 250.0},
		Vector3(east.x - 0.55, TOP + BenchView.HOTPLATE_TOP, 0.03), 0.0, false)
	plant.pour("rb_701_water", "bk_702", 150.0)

	plant.place("lab_meter", "mt_701", {}, Vector3(east.x - 0.12, TOP, -0.05), 0.0, false)
	plant.place("lab_beaker", "bk_703", {"capacity_ml": 250.0},
		Vector3(east.x - 0.12 + BenchView.METER_REACH.x, TOP, -0.05), 0.0, false)
	plant.pour("rb_701_hcl_1m", "bk_703", 50.0)
	plant.pour("rb_701_phenolphthalein", "bk_703", 1.0)

	plant.place("lab_balance", "bl_701", {}, Vector3(east.x + 0.45, TOP, 0.0), 0.0, false)
	plant.place("lab_beaker", "bk_704", {"capacity_ml": 100.0},
		Vector3(east.x + 0.45, TOP + BenchView.BALANCE_TOP, 0.03), 0.0, false)

	plant.place("lab_flask", "fk_701", {"capacity_ml": 250.0}, Vector3(east.x + 0.75, TOP, -0.22), 0.0, false)
	plant.pour("rb_701_water", "fk_701", 80.0)
	plant.pour("rb_701_nahco3", "fk_701", 4.0)
	if hp != null:
		hp.stir_rpm = 400.0
	BenchLayout.sync(plant)


## Headless: what the bench is doing, for the smoke's report.
static func report(plant: Plant) -> Array[String]:
	var out: Array[String] = []
	var b2 := plant.sim.get_component("bk_702") as SimLabVessel
	var hp := plant.sim.get_component("hp_701") as SimHotplate
	var mt := plant.sim.get_component("mt_701") as SimLabMeter
	var bl := plant.sim.get_component("bl_701") as SimLabBalance
	if b2 == null or hp == null or mt == null or bl == null:
		out.append("bench demo: missing its records")
		return out
	out.append("bench demo: BK-702 %.0f mL at %.1f C on HP-701 (%s, plate %.0f C) · MT-701 reads pH %.2f in %s · BL-701 %.2f g"
		% [b2.volume_ml, b2.temp_c, "linked" if hp.load == b2 else "NOT ON THE PLATE", hp.plate_c,
		mt.ph, mt.target.comp_name if mt.target != null else "nothing", bl.reading_g])
	return out
