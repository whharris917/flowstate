"""Bench chemistry: the library's integrity and the mixture's physics,
each against a number worked by hand."""
import math

import pytest

from sim.bench import Hotplate, LabBalance, LabMeter, LabVessel, Mixture, pour
from sim.chemistry import library


def mix_of(**grams: float) -> Mixture:
    m = Mixture()
    for key, g in grams.items():
        m.add_grams(key, g)
    m.settle()
    return m


def total_mass_with_vented(m: Mixture) -> float:
    lib = m.lib
    return m.mass_g() + sum(m.vented[i] * s.molar_mass for i, s in enumerate(lib.species))


# ---- the library -------------------------------------------------------------

def test_every_reaction_balances_by_mass():
    lib = library()
    for r in lib.reactions:
        left = sum(nu * lib.species[i].molar_mass for i, nu in r.reactants.items())
        right = sum(nu * lib.species[i].molar_mass for i, nu in r.products.items())
        assert left == pytest.approx(right, abs=0.05), r.key


def test_stocks_and_families_resolve():
    lib = library()
    for stock in lib.stocks.values():
        for key in stock.grams:
            assert key in lib.index_of, (stock.key, key)
    for s in lib.species:
        if s.family:
            assert s.family in lib.families, s.key


# ---- acidity -----------------------------------------------------------------

@pytest.mark.parametrize("grams, expected", [
    ({"water": 1000.0}, 7.0),
    ({"water": 1000.0, "hydrogen_chloride": 3.646}, 1.0),          # 0.1 M strong acid
    ({"water": 1000.0, "sodium_hydroxide": 4.0}, 13.0),            # 0.1 M strong base
    ({"water": 1000.0, "acetic_acid": 6.005}, 2.88),               # 0.1 M weak acid
    ({"water": 1000.0, "acetic_acid": 6.005, "sodium_acetate": 8.203}, 4.76),   # buffer
    ({"water": 1000.0, "sodium_dihydrogen_phosphate": 11.998,
      "disodium_hydrogen_phosphate": 14.196}, 7.20),
])
def test_ph_by_charge_balance(grams, expected):
    assert mix_of(**grams).ph() == pytest.approx(expected, abs=0.06)


def test_no_ph_without_water():
    assert mix_of(ethanol=100.0).ph() is None


# ---- reactions and their heat ------------------------------------------------

def test_neutralization_warms_by_its_heat():
    acid = Mixture.from_stock("hcl_1m", fill=0.1)     # 50 mL, 0.05 mol
    base = Mixture.from_stock("naoh_1m", fill=0.1)
    acid.add(base)
    c = acid.heat_capacity()
    t0 = acid.temp_c
    for _ in range(50):
        acid.step(0.1, mix=1.0)
    nacl = acid.liquid[acid.lib.index_of["sodium_chloride"]]
    assert nacl == pytest.approx(0.05, rel=0.01)
    assert acid.ph() == pytest.approx(7.0, abs=0.5)
    # 0.05 mol at 57.3 kJ/mol into the solution's own heat capacity.
    assert acid.temp_c - t0 == pytest.approx(0.05 * 57300.0 / c, rel=0.05)


def test_pellets_dissolving_heat_the_water():
    m = mix_of(water=100.0, sodium_hydroxide=4.0)
    m.solid[m.lib.index_of["sodium_hydroxide"]] = 0.1
    m.liquid[m.lib.index_of["sodium_hydroxide"]] = 0.0
    c = m.heat_capacity()
    for _ in range(600):
        m.step(0.2, mix=1.0)
    assert m.solid[m.lib.index_of["sodium_hydroxide"]] < 1e-4
    assert m.temp_c - 21.0 == pytest.approx(0.1 * 44500.0 / c, rel=0.05)


def test_chalk_precipitates_and_mass_is_kept():
    m = mix_of(water=200.0, calcium_chloride=5.549, sodium_carbonate=5.30)   # 0.05 mol each
    before = total_mass_with_vented(m)
    for _ in range(600):
        m.step(0.2, mix=1.0)
    caco3 = m.lib.index_of["calcium_carbonate"]
    assert m.solid[caco3] == pytest.approx(0.05, rel=0.02)
    assert total_mass_with_vented(m) == pytest.approx(before, abs=0.01)   # molar masses are rounded


def test_bicarbonate_and_acid_fizz_off_their_carbon_dioxide():
    m = Mixture.from_stock("hcl_1m", fill=0.2)          # 0.1 mol HCl
    m.add(mix_of(sodium_bicarbonate=4.2))               # 0.05 mol
    before = total_mass_with_vented(m)
    fizzed = False
    for _ in range(600):
        m.step(0.2, mix=1.0)
        fizzed = fizzed or m.gas_mol_s > 0.0
    co2 = m.vented[m.lib.index_of["carbon_dioxide"]]
    assert fizzed
    assert co2 == pytest.approx(0.05, rel=0.02)
    assert total_mass_with_vented(m) == pytest.approx(before, abs=0.01)   # molar masses are rounded


def test_peroxide_needs_its_catalyst_and_follows_its_rate_law():
    lib = library()
    plain = Mixture.from_stock("h2o2_30", fill=0.1)
    for _ in range(300):
        plain.step(0.2, mix=1.0)
    assert plain.vented[lib.index_of["oxygen"]] == 0.0

    m = Mixture.from_stock("h2o2_30", fill=0.1)
    m.add(mix_of(potassium_iodide=1.66))               # 0.01 mol
    for _ in range(100):                               # dissolve the iodide first
        m._dissolve(0.2, 1.0)
    litres = m.liquid_ml() / 1000.0
    h2o2 = lib.index_of["hydrogen_peroxide"]
    ki = lib.index_of["potassium_iodide"]
    r = next(x for x in lib.reactions if x.key == "peroxide_iodide")
    expected = r.k(m.temp_c) * m.conc(h2o2) * m.conc(ki) * litres   # extent per second
    m.step(0.1, mix=1.0)
    assert m.vented[lib.index_of["oxygen"]] / 0.1 == pytest.approx(expected, rel=0.05)


def test_esterification_stops_at_its_equilibrium():
    lib = library()
    m = mix_of(acetic_acid=60.05, ethanol=46.07, sulfuric_acid=2.0, water=5.0)
    m.temp_c = 70.0
    for _ in range(6000):              # a few hours: Fischer esterification is slow
        m.step(2.0, mix=1.0)
        m.temp_c = 70.0
    c = {k: m.liquid[lib.index_of[k]] for k in ("acetic_acid", "ethanol", "ethyl_acetate", "water")}
    q = c["ethyl_acetate"] * c["water"] / (c["acetic_acid"] * c["ethanol"])
    assert q == pytest.approx(4.0, rel=0.03)


def test_aspirin_forms_hot_and_crystallizes_cold():
    lib = library()
    m = mix_of(salicylic_acid=2.0, acetic_anhydride=5.4, sulfuric_acid=0.1)
    m.temp_c = 85.0
    for _ in range(900):
        m.step(1.0, mix=1.0)
        m.temp_c = 85.0
    asa = lib.index_of["acetylsalicylic_acid"]
    made = m.liquid[asa] + m.solid[asa]
    assert made > 0.9 * 2.0 / 138.12
    m.add(mix_of(water=40.0))
    m.temp_c = 5.0
    for _ in range(600):
        m.step(1.0, mix=1.0)
        m.temp_c = 5.0
    assert m.solid[asa] > 0.5 * made


# ---- heat and boiling --------------------------------------------------------

def test_water_boils_at_one_hundred_and_loses_its_steam():
    m = mix_of(water=100.0)
    m.temp_c = 95.0
    for _ in range(600):
        m.step(0.5, heat_w=200.0, mix=1.0)
        assert m.temp_c <= 100.1
    lost = m.vented[m.lib.index_of["water"]] * 18.015
    # 300 s at 200 W less the heat to reach 100 C, over 2257 J/g.
    expected = (200.0 * 300.0 - 5.0 * m.heat_capacity()) / 2257.0
    assert lost == pytest.approx(expected, rel=0.03)
    assert m.boiling


def test_ethanol_water_boils_between_the_two():
    tb = mix_of(water=50.0, ethanol=50.0).boiling_point()
    assert 78.4 < tb < 100.0


def test_hotplate_holds_a_beaker_at_its_setpoint():
    beaker = LabVessel("b1", "beaker", 250.0)
    beaker.contents = mix_of(water=150.0)
    plate = Hotplate("hp1")
    plate.load = beaker
    plate.setpoint_c = 60.0
    plate.stir_rpm = 400.0
    for _ in range(3600):
        plate.tick(0.5)
        beaker.tick(0.5)
    assert beaker.temp_c == pytest.approx(60.0, abs=1.5)
    assert beaker.mix == pytest.approx(1.0)


# ---- handling -----------------------------------------------------------------

def test_unstirred_pour_decants_the_solid():
    src = LabVessel("s", "beaker", 250.0)
    src.contents = mix_of(water=100.0, calcium_carbonate=5.0)
    dst = LabVessel("d", "beaker", 250.0)
    moved = pour(src, dst, 1000.0, stirred=False)
    assert moved == pytest.approx(100.0 / 0.997, rel=0.01)
    caco3 = src.contents.lib.index_of["calcium_carbonate"]
    assert src.contents.solid[caco3] == pytest.approx(5.0 / 100.09, rel=1e-3)   # all but what dissolved
    assert dst.contents.solid[caco3] == 0.0


def test_pour_stops_at_the_brim():
    src = LabVessel("s", "bottle", 1000.0, stock="water")
    dst = LabVessel("d", "vial", 20.0)
    moved = pour(src, dst, 500.0, stirred=False)
    assert moved == pytest.approx(20.0, rel=1e-6)
    assert dst.volume_ml == pytest.approx(20.0, rel=1e-6)


def test_meter_and_balance_read_the_vessel():
    v = LabVessel("v", "beaker", 250.0)
    v.contents = Mixture.from_stock("hcl_1m", fill=0.2)
    meter = LabMeter("m")
    meter.target = v
    meter.tick(0.1)
    assert meter.ph == pytest.approx(0.0, abs=0.1)
    bal = LabBalance("bal")
    bal.load = v
    assert bal.reading_g == pytest.approx(v.tare_g + v.mass_g)
    bal.tare()
    assert bal.reading_g == 0.0


def test_vessel_state_round_trips():
    v = LabVessel("v", "beaker", 250.0, stock="naoh_1m")
    v.contents.temp_c = 42.0
    w = LabVessel("v", "beaker", 250.0)
    w.apply_state(v.state_dict())
    assert w.contents.temp_c == 42.0
    assert w.mass_g == pytest.approx(v.mass_g)
