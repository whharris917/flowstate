"""The small-bore family (director, 2026-09-20): new machines for little
lines, each a real branch in the network. A test cannot name a flow
rate -- flow is solved -- so each checks the shape of the answer
against the meters and the equations the page states."""
import math

from sim.components import Drain, Source, Tank
from sim.core import Simulation
from sim.small_bore import (
    BallValve, MeteringPump, NeedleValve, Orifice, Regulator, Rotameter, SolenoidValve,
)
from tests.conftest import open_drain, wire_supply


def _line(component, pressure_kpa: float = 400.0):
    """Header -> component -> generous drain, so the component sets the rate."""
    sim = Simulation()
    sim.add(component)
    source = wire_supply(sim, component, pressure_kpa=pressure_kpa)
    drain = open_drain(sim, component, rate_lps=50.0)
    return sim, source, drain


def test_an_orifice_passes_its_cv_scaled_by_the_root_of_the_drop() -> None:
    ro = Orifice("ro", cv_lps=0.001)
    sim, source, drain = _line(ro, pressure_kpa=400.0)
    sim.run(5.0)
    # Nearly the whole 4 bar is across the orifice: about Cv * sqrt(4).
    assert 0.0017 < ro.flow_lps < 0.0021
    assert abs(drain.total_l - source.total_l) < 0.02 * source.total_l


def test_a_tighter_orifice_passes_less() -> None:
    loose = Orifice("loose", cv_lps=0.002)
    tight = Orifice("tight", cv_lps=0.0005)
    sim_a, _, _ = _line(loose)
    sim_b, _, _ = _line(tight)
    sim_a.run(2.0)
    sim_b.run(2.0)
    assert tight.flow_lps < loose.flow_lps / 3.0


def test_a_needle_valve_opens_turn_by_turn() -> None:
    nv = NeedleValve("nv", cv_lps=0.005, turns=10.0)
    sim, _, _ = _line(nv)
    sim.run(1.0)
    assert nv.flow_lps == 0.0
    nv.turn(1.0)
    sim.run(1.0)
    one_turn = nv.flow_lps
    assert one_turn > 0.0
    nv.turn(4.0)
    sim.run(1.0)
    assert nv.flow_lps > 4.0 * one_turn
    nv.turn(20.0)
    assert nv.turns_open == 10.0
    nv.turn(-30.0)
    assert nv.turns_open == 0.0


def test_a_ball_valve_travels_its_quarter_turn() -> None:
    bv = BallValve("bv", cv_lps=0.5, stroke_s=0.5)
    sim, _, _ = _line(bv)
    sim.run(1.0)
    assert bv.position == 0.0 and bv.flow_lps == 0.0
    bv.open = True
    sim.run(0.25)
    assert 40.0 < bv.position < 60.0
    sim.run(0.5)
    assert bv.position == 100.0
    assert bv.flow_lps > 0.5
    bv.open = False
    sim.run(1.0)
    assert bv.position == 0.0 and bv.flow_lps == 0.0


def test_a_solenoid_is_shut_until_its_coil_is_energized() -> None:
    from tests.conftest import Contact
    sv = SolenoidValve("sv", cv_lps=0.3)
    sim, _, _ = _line(sv)
    switch = sim.add(Contact("switch"))
    sim.connect(switch, "out", sv, "coil")
    sim.run(1.0)
    assert sv.flow_lps == 0.0 and sv.cycles == 0
    switch.closed = True
    sim.run(0.5)
    assert sv.position == 100.0
    assert sv.flow_lps > 0.3
    assert sv.cycles == 1
    switch.closed = False
    sim.run(0.5)
    assert sv.position == 0.0 and sv.flow_lps == 0.0


def test_a_metering_pump_delivers_its_stroke_against_a_modest_head() -> None:
    sim = Simulation()
    low = sim.add(Tank("low", capacity_l=100.0, level_l=80.0, height_m=1.0))
    high = sim.add(Tank("high", capacity_l=100.0, level_l=0.0, height_m=1.0, elevation_m=3.0))
    mp = sim.add(MeteringPump("mp", rated_lps=0.01, max_head_m=50.0))
    sim.connect(low, "outlet", mp, "inlet")
    sim.connect(mp, "outlet", high, "inlet")
    _dc_power(sim, mp)
    mp.hand_on = True
    sim.run(10.0)
    # Four metres of lift against a fifty-metre drive: nearly the full stroke.
    assert 0.0095 < mp.flow_lps <= 0.0101
    assert mp.starts == 1
    mp.stroke_pct = 50.0
    sim.run(5.0)
    assert 0.0047 < mp.flow_lps < 0.0051
    mp.hand_on = False
    sim.run(1.0)
    assert mp.flow_lps == 0.0


def test_a_metering_pump_is_dead_without_24v() -> None:
    mp = MeteringPump("mp")
    sim, _, _ = _line(mp)
    mp.hand_on = True
    sim.run(1.0)
    assert not mp.running and mp.flow_lps == 0.0


def test_a_metering_pump_stalls_past_its_maximum_head() -> None:
    sim = Simulation()
    low = sim.add(Tank("low", capacity_l=100.0, level_l=80.0, height_m=1.0))
    high = sim.add(Tank("high", capacity_l=100.0, level_l=0.0, height_m=1.0, elevation_m=12.0))
    mp = sim.add(MeteringPump("mp", rated_lps=0.01, max_head_m=10.0))
    sim.connect(low, "outlet", mp, "inlet")
    sim.connect(mp, "outlet", high, "inlet")
    _dc_power(sim, mp)
    mp.hand_on = True
    sim.run(5.0)
    assert mp.running
    assert mp.flow_lps < 1e-6


def test_a_regulator_holds_its_outlet_near_the_setting() -> None:
    sim = Simulation()
    pr = sim.add(Regulator("pr", set_kpa=150.0, cv_lps=0.5))
    ro = sim.add(Orifice("ro", cv_lps=0.05))
    wire_supply(sim, pr, pressure_kpa=400.0)
    sim.connect(pr, "outlet", ro, "inlet")
    open_drain(sim, ro, rate_lps=50.0)
    sim.run(10.0)
    # Within the droop of the setting, and the orifice sees that, not 4 bar.
    assert 120.0 < pr.out_kpa < 150.0
    expected = 0.05 * math.sqrt(pr.out_kpa / 100.0)
    assert abs(ro.flow_lps - expected) < 0.1 * expected


def test_a_regulator_set_above_its_supply_is_simply_open() -> None:
    sim = Simulation()
    pr = sim.add(Regulator("pr", set_kpa=800.0, cv_lps=0.5))
    ro = sim.add(Orifice("ro", cv_lps=0.05))
    wire_supply(sim, pr, pressure_kpa=300.0)
    sim.connect(pr, "outlet", ro, "inlet")
    open_drain(sim, ro, rate_lps=50.0)
    sim.run(5.0)
    assert pr.opening == 1.0
    # The orifice sees nearly the whole header: the regulator is a fitting.
    assert pr.out_kpa > 290.0


def _dc_power(sim: Simulation, *components) -> None:
    """24 V DC for the small machines: a feeder into a power supply."""
    from sim.components import MainsFeed, PowerSupply
    mains = sim.add(MainsFeed(sim.unique_name("mains"), ways=1))
    psu = sim.add(PowerSupply(sim.unique_name("psu")))
    sim.connect(mains, "way1", psu, "ac_in")
    for component in components:
        sim.connect(psu, "dc_out", component, "power")


def test_a_rotameter_reads_the_flow_through_it() -> None:
    fi = Rotameter("fi", range_lps=0.01)
    sim, _, _ = _line(fi, pressure_kpa=20.0)
    sim.run(3.0)
    assert fi.flow_lps > 0.0
    assert abs(fi.float_frac - min(fi.flow_lps / 0.01, 1.0)) < 1e-9
    fast = Rotameter("fast", range_lps=0.01)
    sim2, _, _ = _line(fast, pressure_kpa=400.0)
    sim2.run(3.0)
    assert fast.float_frac == 1.0


def test_states_round_trip() -> None:
    nv = NeedleValve("nv")
    nv.turn(3.0)
    fresh = NeedleValve("nv2")
    fresh.apply_state(nv.state_dict())
    assert fresh.turns_open == 3.0
    bv = BallValve("bv")
    bv.open = True
    bv.position = 100.0
    fresh_bv = BallValve("bv2")
    fresh_bv.apply_state(bv.state_dict())
    assert fresh_bv.open and fresh_bv.position == 100.0
    mp = MeteringPump("mp")
    mp.hand_on = True
    mp.stroke_pct = 35.0
    fresh_mp = MeteringPump("mp2")
    fresh_mp.apply_state(mp.state_dict())
    assert fresh_mp.hand_on and fresh_mp.stroke_pct == 35.0
