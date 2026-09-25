class_name BenchSelfCheck
extends RefCounted
## The bench chemistry kernel against the numbers tests/test_bench.py
## holds the Python kernel to, so the two stay one answer. Run by the
## plant's headless self-checks; returns "" or what failed.


static func run() -> String:
	var problems: Array[String] = []
	var cases := [
		[{"water": 1000.0}, 7.0],
		[{"water": 1000.0, "hydrogen_chloride": 3.646}, 1.0],
		[{"water": 1000.0, "sodium_hydroxide": 4.0}, 13.0],
		[{"water": 1000.0, "acetic_acid": 6.005}, 2.88],
		[{"water": 1000.0, "acetic_acid": 6.005, "sodium_acetate": 8.203}, 4.76],
		[{"water": 1000.0, "sodium_dihydrogen_phosphate": 11.998,
			"disodium_hydrogen_phosphate": 14.196}, 7.20],
	]
	for case: Array in cases:
		var reading := _mix(case[0]).ph()
		if absf(reading - float(case[1])) > 0.06:
			problems.append("pH %.2f, wanted %.2f" % [reading, float(case[1])])

	# Neutralization warms by its heat.
	var acid := SimMixture.from_stock("hcl_1m", 0.1)
	acid.add(SimMixture.from_stock("naoh_1m", 0.1))
	var c := acid.heat_capacity()
	var t0 := acid.temp_c
	for _k in 50:
		acid.step(0.1, 0.0, 1.0)
	var rise := acid.temp_c - t0
	var expected := 0.05 * 57300.0 / c
	if absf(rise - expected) > 0.05 * expected:
		problems.append("neutralization warmed %.2f K, wanted %.2f" % [rise, expected])

	# Bicarbonate and acid fizz off their carbon dioxide, and mass holds.
	var fizz := SimMixture.from_stock("hcl_1m", 0.2)
	fizz.add(_mix({"sodium_bicarbonate": 4.2}))
	var before := _mass_with_vented(fizz)
	for _k in 600:
		fizz.step(0.2, 0.0, 1.0)
	var co2 := fizz.vented[ChemLibrary.index_of("carbon_dioxide")]
	if absf(co2 - 0.05) > 0.001:
		problems.append("bicarbonate gave %.4f mol CO2, wanted 0.05" % co2)
	if absf(_mass_with_vented(fizz) - before) > 0.01:
		problems.append("mass moved %.4f g through the fizz" % (_mass_with_vented(fizz) - before))

	# Esterification settles at its equilibrium.
	var ester := _mix({"acetic_acid": 60.05, "ethanol": 46.07, "sulfuric_acid": 2.0, "water": 5.0})
	ester.temp_c = 70.0
	for _k in 2400:
		ester.step(5.0, 0.0, 1.0)
		ester.temp_c = 70.0
	var q := ester.liquid[ChemLibrary.index_of("ethyl_acetate")] * ester.liquid[ChemLibrary.index_of("water")] \
		/ (ester.liquid[ChemLibrary.index_of("acetic_acid")] * ester.liquid[ChemLibrary.index_of("ethanol")])
	if absf(q - 4.0) > 0.12:
		problems.append("esterification settled at Q %.2f, wanted 4" % q)

	# Water boils at a hundred and no hotter.
	var pot := _mix({"water": 100.0})
	pot.temp_c = 95.0
	var hottest := 0.0
	for _k in 600:
		pot.step(0.5, 200.0, 1.0)
		hottest = maxf(hottest, pot.temp_c)
	if hottest > 100.1 or not pot.boiling:
		problems.append("water reached %.2f C" % hottest)

	# A hotplate holds a beaker at its setpoint.
	var beaker := SimLabVessel.new("b", "beaker", 250.0)
	beaker.contents = _mix({"water": 150.0})
	var plate := SimHotplate.new("hp")
	plate.load = beaker
	plate.setpoint_c = 60.0
	plate.stir_rpm = 400.0
	for _k in 3600:
		plate.tick(0.5)
		beaker.tick(0.5)
	if absf(beaker.temp_c - 60.0) > 1.5:
		problems.append("hotplate held %.1f C for 60" % beaker.temp_c)
	return "; ".join(problems)


static func _mix(grams: Dictionary) -> SimMixture:
	var m := SimMixture.new()
	for key: String in grams:
		m.add_grams(key, float(grams[key]))
	m.settle()
	return m


static func _mass_with_vented(m: SimMixture) -> float:
	var g := m.mass_g()
	for i in ChemLibrary.count():
		g += m.vented[i] * ChemLibrary.molar_mass[i]
	return g
