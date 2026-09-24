"""Inline equipment stands at a height: a pump at the top of a rise
behaves differently from one at the bottom of a drop.

Node pressures are piezometric, so a pump, a valve or a regulator that
knows its own elevation can read the *static* pressure at its nozzles:
the node's pressure less rho*g*z. That is what its gauges show, what a
pump's prime is judged on, and what a regulator's diaphragm feels.
"""
from __future__ import annotations

import pytest

from sim.components import Cap, ControlValve, Drain, Pump, Source
from sim.core import Simulation
from sim.hydraulics import HEAD_PA_PER_M, MIN_PRESSURE_PA, PumpCurve
from sim.small_bore import Regulator
from tests.conftest import Duty, open_drain, wire_power


def _pump_drawing_from_an_atmospheric_tank(elevation_m: float) -> Pump:
    """A header at atmosphere (an open tank, in effect) feeding a pump
    that discharges to a drain at its own level."""
    sim = Simulation()
    header = sim.add(Source("hdr", pressure_kpa=0.0))
    pump = sim.add(Pump("p", rated_lps=4.0, mode="hand", head_m=30.0,
                        elevation_m=elevation_m))
    sim.connect(header, "outlet", pump, "inlet")
    open_drain(sim, pump)
    wire_power(sim, pump)
    sim.run(5.0)
    return pump


class TestPumpElevation:
    def test_a_pump_high_above_its_supply_loses_prime(self) -> None:
        # The static suction 9 m up is -88 kPa: inside the prime band,
        # and past the cavitation warning. At grade it is near zero.
        low = _pump_drawing_from_an_atmospheric_tank(0.0)
        high = _pump_drawing_from_an_atmospheric_tank(9.0)
        assert low.flow_lps > 3.0
        assert not low.cavitating
        assert 0.0 < high.flow_lps < 0.8 * low.flow_lps
        assert high.cavitating

    def test_a_pump_past_the_suction_lift_limit_moves_nothing(self) -> None:
        # 11 m of lift from an atmospheric tank is beyond a hard vacuum:
        # nothing can hold the column up, and the pump runs dry.
        pump = _pump_drawing_from_an_atmospheric_tank(11.0)
        assert pump.running
        assert pump.flow_lps == pytest.approx(0.0, abs=1e-6)
        assert pump.dry_run_s > 0.0

    def test_the_gauges_read_static_pressure_at_the_pump(self) -> None:
        pump = _pump_drawing_from_an_atmospheric_tank(3.0)
        # A pump 3 m up, drawing from a header at atmosphere through a
        # short run: its suction gauge reads about -29 kPa less the run's
        # loss, never the piezometric value near zero.
        assert pump.suction_pa < -3.0 * HEAD_PA_PER_M + 1.0
        assert pump.head_pa == pytest.approx(pump.discharge_pa - pump.suction_pa)

    def test_the_curve_tapers_on_static_suction(self) -> None:
        # The branch on its own: a datum inside the band scales the
        # curve exactly as a lower piezometric suction would.
        curve = PumpCurve(0, 1, head_pa=300_000.0, max_lps=4.0)
        curve.running = True
        band = PumpCurve.CAVITATION_BAND_PA
        curve.datum_pa = -MIN_PRESSURE_PA - band / 2.0   # static suction: half the band
        assert curve.prime(0.0) == pytest.approx(0.5)
        assert curve.flow_at(0.0, 0.0) == pytest.approx(2.0)
        curve.datum_pa = 0.0
        assert curve.prime(0.0) == pytest.approx(1.0)


class TestValveElevation:
    def test_the_drop_is_the_same_but_the_gauges_are_not(self) -> None:
        results = []
        for elevation in (0.0, 4.0):
            sim = Simulation()
            header = sim.add(Source("hdr", pressure_kpa=300.0))
            valve = sim.add(ControlValve("cv", cv_lps=6.0, tau_s=0.2,
                                         elevation_m=elevation))
            hand = sim.add(Duty("hic", 100.0))
            sim.connect(hand, "out", valve, "cmd")
            sim.connect(header, "outlet", valve, "inlet")
            open_drain(sim, valve)
            sim.run(5.0)
            results.append((valve.flow_lps, valve.inlet_pa, valve.outlet_pa))
        (q0, in0, out0), (q4, in4, out4) = results
        assert q4 == pytest.approx(q0, rel=1e-6)
        assert (in0 - out0) == pytest.approx(in4 - out4, rel=1e-6)
        assert in4 == pytest.approx(in0 - 4.0 * HEAD_PA_PER_M, rel=1e-6)


class TestRegulatorElevation:
    def test_a_regulator_holds_static_pressure_at_its_own_height(self) -> None:
        sim = Simulation()
        header = sim.add(Source("hdr", pressure_kpa=600.0))
        reg = sim.add(Regulator("pcv", set_kpa=150.0, cv_lps=0.5, elevation_m=5.0))
        sim.connect(header, "outlet", reg, "inlet")
        drain = open_drain(sim, reg, rate_lps=0.05)
        drain.elevation_m = 5.0
        sim.run(5.0)
        # Its own gauge reads the setting less the droop, and the node
        # behind that reading is the setting plus 5 m of head.
        assert reg.out_kpa == pytest.approx(150.0, abs=15.0)
        assert reg.out_kpa < 150.0
        outlet_node = sim._network.pressures[reg.outlet.node]
        assert outlet_node == pytest.approx(reg.out_kpa * 1000.0 + 5.0 * HEAD_PA_PER_M, rel=1e-6)


class TestBoundariesFollowTheirHeight:
    def test_an_open_end_moved_up_spills_less(self) -> None:
        sim = Simulation()
        header = sim.add(Source("hdr", pressure_kpa=50.0))
        cap = sim.add(Cap("end", elevation_m=0.0))
        cap.open = True
        sim.connect(header, "outlet", cap, "a")
        sim.run(2.0)
        low = cap.spill_lps()
        # Raised after the network was built: the air it vents to must
        # follow it without a rebuild.
        cap.elevation_m = 4.0
        sim.run(2.0)
        high = cap.spill_lps()
        assert 0.0 < high < low

    def test_a_drain_moved_up_takes_less(self) -> None:
        sim = Simulation()
        header = sim.add(Source("hdr", pressure_kpa=50.0))
        drain = sim.add(Drain("du", rate_lps=5.0, elevation_m=0.0))
        sim.connect(header, "outlet", drain, "inlet")
        sim.run(2.0)
        low = drain.flow_lps
        drain.elevation_m = 4.0
        sim.run(2.0)
        assert 0.0 < drain.flow_lps < low
