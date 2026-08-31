"""Tests for the source/drain flow network: conservation, dry running."""
from __future__ import annotations

import pytest

from conftest import wire_power
from sim.components import ControlValve, Drain, Pump, Source, Tank
from sim.core import Simulation


class TestFlowNetwork:
    def test_mass_is_conserved_source_to_drain(self) -> None:
        """source -> pump -> tank -> drain: everything metered out of
        the source shows up as inventory gain plus drain total."""
        sim = Simulation(dt=0.05)
        source = sim.add(Source("bl"))
        pump = sim.add(Pump("p", rated_lps=3.0, mode="hand"))
        tank = sim.add(Tank("t", capacity_l=500.0, level_l=0.0))
        drain = sim.add(Drain("d", rate_lps=1.0))
        wire_power(sim, pump)
        sim.connect(source, "supply", pump, "inlet")
        sim.connect(pump, "draw", source, "draw")
        sim.connect(pump, "outlet", tank, "inlet")
        sim.connect(tank, "outlet", drain, "inlet")
        sim.connect(drain, "draw", tank, "draw")
        sim.run(120.0)
        gained = tank.level_l
        assert source.total_l > 300.0
        assert drain.total_l > 50.0
        # A couple of scans of latency slop at most.
        assert source.total_l == pytest.approx(gained + drain.total_l, abs=1.0)

    def test_pump_from_empty_vessel_runs_dry(self) -> None:
        sim = Simulation(dt=0.05)
        empty = sim.add(Tank("e", capacity_l=100.0, level_l=0.0))
        pump = sim.add(Pump("p", rated_lps=3.0, mode="hand"))
        full = sim.add(Tank("f", capacity_l=100.0, level_l=0.0))
        wire_power(sim, pump)
        sim.connect(empty, "outlet", pump, "inlet")
        sim.connect(pump, "draw", empty, "draw")
        sim.connect(pump, "outlet", full, "inlet")
        sim.run(10.0)
        assert pump.running                 # the motor spins...
        assert full.level_l == 0.0          # ...but nothing moves
        assert pump.dry_run_s > 9.0         # and the seal pays for it

    def test_pump_transfers_between_tanks(self) -> None:
        sim = Simulation(dt=0.05)
        tank_a = sim.add(Tank("a", capacity_l=100.0, level_l=60.0))
        pump = sim.add(Pump("p", rated_lps=2.0, mode="hand"))
        tank_b = sim.add(Tank("b", capacity_l=100.0, level_l=0.0))
        wire_power(sim, pump)
        sim.connect(tank_a, "outlet", pump, "inlet")
        sim.connect(pump, "draw", tank_a, "draw")
        sim.connect(pump, "outlet", tank_b, "inlet")
        sim.run(20.0)
        assert tank_a.level_l == pytest.approx(20.0, abs=0.5)
        assert tank_b.level_l == pytest.approx(40.0, abs=0.5)
        assert tank_a.level_l + tank_b.level_l == pytest.approx(60.0, abs=0.3)

    def test_valve_dead_without_supply(self) -> None:
        valve = ControlValve("cv", cv_lps=6.0)
        valve.cmd.value = 100.0
        for _ in range(200):                # 10 s of direct scans
            valve.tick(0.05)
        assert valve.position > 95.0        # positioner obeys the command
        assert valve.outlet.value.flow_lps == 0.0      # but an empty header flows nothing

    def test_drain_stops_at_empty_and_closes(self) -> None:
        sim = Simulation(dt=0.05)
        tank = sim.add(Tank("t", capacity_l=100.0, level_l=5.0))
        drain = sim.add(Drain("d", rate_lps=2.0))
        sim.connect(tank, "outlet", drain, "inlet")
        sim.connect(drain, "draw", tank, "draw")
        sim.run(10.0)
        assert tank.level_l == pytest.approx(0.0, abs=0.2)
        assert drain.total_l == pytest.approx(5.0, abs=0.2)
        drain.is_open = False
        total_before = drain.total_l
        tank.level_l = 50.0
        sim.run(5.0)
        assert drain.total_l == total_before  # closed drains swallow nothing
        with pytest.raises(ValueError):
            Drain("bad", rate_lps=0.0)
