"""Tests for the plant as a hydraulic network.

The unit tests in test_hydraulics.py check the solver. These check that
real equipment, wired the way a player would wire it, behaves like a
plant: mass closes, head matters, pumps can be defeated, and a header
has no draw port because nothing announces what it took.
"""
from __future__ import annotations

import pytest

from conftest import Duty, wire_power
from sim.components import ControlValve, Drain, Pump, Source, Tank
from sim.core import PortKind, Simulation
from sim.hydraulics import Network


def _plant(header_kpa: float = 400.0, pump_lps: float = 3.0,
           head_m: float = 30.0, tank_h: float = 3.0):
    sim = Simulation(dt=0.05)
    header = sim.add(Source("hdr", species="water", pressure_kpa=header_kpa))
    pump = sim.add(Pump("p", rated_lps=pump_lps, mode="hand", head_m=head_m))
    tank = sim.add(Tank("t", capacity_l=4000.0, level_l=0.0, height_m=tank_h))
    wire_power(sim, pump)
    sim.connect(header, "outlet", pump, "inlet")
    sim.connect(pump, "outlet", tank, "inlet")
    return sim, header, pump, tank


class TestTheHeaderHasNoDrawPort:
    def test_a_header_is_species_temperature_and_pressure(self) -> None:
        """It has one nozzle and nothing else. Nothing upstream, and
        nothing announcing what was taken."""
        header = Source("hdr", species="solvent", temp_c=35.0, pressure_kpa=250.0)
        assert list(header.inputs) == []
        assert list(header.outputs) == ["outlet"]
        assert header.outlet.kind is PortKind.PROCESS_MATERIAL
        assert header.temp_c == 35.0
        assert header.pressure_kpa == 250.0

    def test_it_meters_what_the_plant_actually_pulled(self) -> None:
        sim, header, pump, tank = _plant()
        sim.run(60.0)
        assert header.total_l > 0.0
        assert header.total_l == pytest.approx(tank.level_l, rel=0.02)

    def test_a_header_at_higher_pressure_delivers_more(self) -> None:
        low = _plant(header_kpa=120.0)[0]
        high = _plant(header_kpa=600.0)[0]
        low.run(30.0)
        high.run(30.0)
        assert high.get_component("hdr").total_l > low.get_component("hdr").total_l


class TestConservation:
    def test_mass_closes_from_header_to_drain(self) -> None:
        sim, header, pump, tank = _plant()
        drain = sim.add(Drain("d", rate_lps=1.0))
        sim.connect(tank, "outlet", drain, "inlet")
        sim.run(300.0)
        assert header.total_l > 100.0
        assert drain.total_l > 1.0
        assert header.total_l == pytest.approx(
            tank.level_l + drain.total_l, abs=0.5)

    def test_the_solve_actually_balances(self) -> None:
        sim, header, pump, tank = _plant()
        drain = sim.add(Drain("d", rate_lps=1.0))
        sim.connect(tank, "outlet", drain, "inlet")
        sim.run(30.0)
        assert sim._network.residual_lps <= Network.TOLERANCE_LPS
        # Warm-started it should barely have to work.
        assert sim._network.iterations <= 6


class TestHeadMatters:
    def test_a_drain_runs_faster_under_more_head(self) -> None:
        """The thing a fixed rate_lps could never do."""
        sim, header, pump, tank = _plant()
        drain = sim.add(Drain("d", rate_lps=2.0))
        sim.connect(tank, "outlet", drain, "inlet")
        sim.run(20.0)
        shallow = drain.flow_lps
        sim.run(400.0)
        deep = drain.flow_lps
        assert tank.depth_m > 0.5
        assert deep > shallow * 1.5

    def test_a_raised_tank_drains_into_a_low_one_with_no_pump(self) -> None:
        """Two vessels and a pipe. The old model could not express this
        at all: it needed a pump to make the bookkeeping work."""
        sim = Simulation(dt=0.05)
        full = sim.add(Tank("full", capacity_l=2000.0, level_l=1800.0,
                            height_m=3.0, elevation_m=5.0))
        low = sim.add(Tank("low", capacity_l=2000.0, level_l=0.0,
                           height_m=3.0))
        sim.connect(full, "outlet", low, "inlet")
        sim.run(200.0)
        assert low.level_l > 50.0
        assert full.level_l < 1800.0
        assert full.level_l + low.level_l == pytest.approx(1800.0, abs=0.5)

    def test_gravity_will_not_run_uphill(self) -> None:
        """Both vessels at grade: the receiving nozzle is at the top of
        a 2 m shell, and the source only has 1.6 m of liquid standing in
        it. Nothing moves, and nothing should."""
        sim = Simulation(dt=0.05)
        full = sim.add(Tank("full", capacity_l=500.0, level_l=400.0, height_m=2.0))
        other = sim.add(Tank("other", capacity_l=500.0, level_l=0.0, height_m=2.0))
        assert full.depth_m < other.height_m      # the geometry of the problem
        sim.connect(full, "outlet", other, "inlet")
        sim.run(200.0)
        assert other.level_l == pytest.approx(0.0, abs=0.1)
        assert full.level_l == pytest.approx(400.0, abs=0.1)

    def test_it_drains_until_the_nozzle_uncovers(self) -> None:
        sim = Simulation(dt=0.05)
        full = sim.add(Tank("full", capacity_l=500.0, level_l=400.0,
                            height_m=2.0, elevation_m=6.0))
        low = sim.add(Tank("low", capacity_l=500.0, level_l=0.0, height_m=2.0))
        sim.connect(full, "outlet", low, "inlet")
        sim.run(600.0)
        # It runs down to the nozzle and stops there, rather than
        # siphoning a vessel dry.
        assert full.level_l < 20.0
        assert full.level_l + low.level_l == pytest.approx(400.0, abs=0.5)


class TestPumpsCanBeDefeated:
    def test_a_pump_cannot_fill_a_tank_taller_than_its_head(self) -> None:
        sim = Simulation(dt=0.05)
        header = sim.add(Source("hdr", pressure_kpa=0.0))
        pump = sim.add(Pump("p", rated_lps=3.0, mode="hand", head_m=4.0))
        tower = sim.add(Tank("tower", capacity_l=8000.0, level_l=0.0,
                             height_m=20.0))
        wire_power(sim, pump)
        sim.connect(header, "outlet", pump, "inlet")
        sim.connect(pump, "outlet", tower, "inlet")   # 20 m up to the top
        sim.run(60.0)
        assert pump.running                     # the motor is turning
        assert pump.flow_lps < 0.01             # and nothing is moving

    def test_an_unpowered_pump_moves_nothing(self) -> None:
        sim, header, pump, tank = _plant()
        sim.disconnect(sim.get_component("mains_1"), "power", pump, "power")
        sim.run(20.0)
        assert not pump.running
        assert pump.flow_lps == pytest.approx(0.0)
        assert tank.level_l == pytest.approx(0.0)

    def test_off_selector_beats_a_run_signal(self) -> None:
        sim, header, pump, tank = _plant()
        pump.set_mode("off")
        sim.run(20.0)
        assert pump.flow_lps == pytest.approx(0.0)


class TestValveAuthority:
    def _loop(self, cv_lps: float):
        sim = Simulation(dt=0.05)
        header = sim.add(Source("hdr", pressure_kpa=300.0))
        valve = sim.add(ControlValve("v", cv_lps=cv_lps, tau_s=0.2))
        tank = sim.add(Tank("t", capacity_l=9000.0, level_l=0.0, height_m=4.0))
        # The command has to be wired: an input port is reset every scan,
        # so a value poked onto one is gone before the valve ticks.
        hand = sim.add(Duty("hic", 0.0))
        sim.connect(hand, "out", valve, "cmd")
        sim.connect(header, "outlet", valve, "inlet")
        sim.connect(valve, "outlet", tank, "inlet")
        return sim, valve, tank, hand

    def test_a_shut_valve_passes_nothing(self) -> None:
        sim, valve, tank, hand = self._loop(6.0)
        hand.kw = 0.0
        sim.run(20.0)
        assert valve.flow_lps == pytest.approx(0.0)
        assert tank.level_l == pytest.approx(0.0)

    def test_opening_it_passes_more(self) -> None:
        sim, valve, tank, hand = self._loop(6.0)
        readings = []
        for command in (20.0, 60.0, 100.0):
            hand.kw = command
            sim.run(15.0)
            readings.append(valve.flow_lps)
        assert readings == sorted(readings)
        assert readings[-1] > readings[0] * 1.5

    def test_flow_follows_the_square_root_not_the_position(self) -> None:
        """Half open is not half the flow, because the valve equation is
        not linear. This is the thing a linear trim model got wrong."""
        sim, valve, tank, hand = self._loop(6.0)
        hand.kw = 100.0
        sim.run(20.0)
        wide = valve.flow_lps
        hand.kw = 50.0
        sim.run(20.0)
        half = valve.flow_lps
        assert half > wide * 0.5


class TestTeesNeedNoComponent:
    def test_one_nozzle_feeding_two_lines_splits_by_resistance(self) -> None:
        """A tee is a node, so branching costs nothing and needs no
        splitter component."""
        sim = Simulation(dt=0.05)
        header = sim.add(Source("hdr", pressure_kpa=300.0))
        pump = sim.add(Pump("p", rated_lps=6.0, mode="hand"))
        easy = sim.add(Tank("easy", capacity_l=9000.0, height_m=4.0))
        hard = sim.add(Tank("hard", capacity_l=9000.0, height_m=4.0))
        wire_power(sim, pump)
        sim.connect(header, "outlet", pump, "inlet")
        a = sim.connect(pump, "outlet", easy, "inlet")
        b = sim.connect(pump, "outlet", hard, "inlet")
        a.k_pa_per_lps2 = 2_000.0
        b.k_pa_per_lps2 = 18_000.0     # a longer, thinner run
        sim.run(120.0)
        assert easy.level_l > 0.0 and hard.level_l > 0.0
        # Nine times the resistance is a third of the flow.
        assert easy.level_l == pytest.approx(3.0 * hard.level_l, rel=0.15)

    def test_the_split_still_conserves(self) -> None:
        sim = Simulation(dt=0.05)
        header = sim.add(Source("hdr", pressure_kpa=300.0))
        pump = sim.add(Pump("p", rated_lps=6.0, mode="hand"))
        one = sim.add(Tank("one", capacity_l=9000.0, height_m=4.0))
        two = sim.add(Tank("two", capacity_l=9000.0, height_m=4.0))
        wire_power(sim, pump)
        sim.connect(header, "outlet", pump, "inlet")
        sim.connect(pump, "outlet", one, "inlet")
        sim.connect(pump, "outlet", two, "inlet")
        sim.run(120.0)
        assert header.total_l == pytest.approx(one.level_l + two.level_l, abs=0.5)


class TestCompositionFollowsFlow:
    def test_what_a_header_carries_reaches_the_tank(self) -> None:
        sim = Simulation(dt=0.05)
        header = sim.add(Source("hdr", species="solvent", temp_c=70.0,
                                pressure_kpa=300.0))
        tank = sim.add(Tank("t", capacity_l=4000.0, level_l=0.0, height_m=3.0))
        sim.connect(header, "outlet", tank, "inlet")
        sim.run(120.0)
        assert tank.level_l > 10.0
        assert tank.comp.get("solvent", 0.0) > 0.95
        assert tank.temp_c > 50.0

    def test_two_headers_into_one_vessel_blend(self) -> None:
        sim = Simulation(dt=0.05)
        hot = sim.add(Source("hot", species="solvent", temp_c=80.0,
                             pressure_kpa=300.0))
        cold = sim.add(Source("cold", species="water", temp_c=20.0,
                              pressure_kpa=300.0))
        tank = sim.add(Tank("t", capacity_l=8000.0, level_l=0.0, height_m=4.0))
        sim.connect(hot, "outlet", tank, "inlet")
        sim.connect(cold, "outlet", tank, "inlet")
        sim.run(120.0)
        assert 0.2 < tank.comp.get("solvent", 0.0) < 0.8
        assert 20.0 < tank.temp_c < 80.0

    def test_a_drain_records_the_product_it_swallowed(self) -> None:
        sim = Simulation(dt=0.05)
        tank = sim.add(Tank("t", capacity_l=2000.0, level_l=1500.0,
                            height_m=3.0, comp={"product": 1.0}))
        drain = sim.add(Drain("d", rate_lps=2.0))
        sim.connect(tank, "outlet", drain, "inlet")
        sim.run(120.0)
        assert drain.total_l > 10.0
        assert drain.lost_product_l == pytest.approx(drain.total_l, rel=0.05)
