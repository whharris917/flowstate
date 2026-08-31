"""Tests for the four step-1 components and their closed loop."""
from __future__ import annotations

import pytest

from conftest import wire_power, wire_supply
from sim.components import FloatSwitch, Pump, Relay, Tank
from sim.core import Simulation
from sim.stream import Stream


class TestTank:
    def test_integrates_inflow(self) -> None:
        sim = Simulation(dt=0.1)
        tank = sim.add(Tank("t", capacity_l=100.0, level_l=10.0))
        pump = sim.add(Pump("p", rated_lps=2.0, mode="hand"))
        wire_power(sim, pump)
        wire_supply(sim, pump)
        sim.connect(pump, "outlet", tank, "inlet")
        sim.run(10.0)
        # Pump flow reaches the tank one scan late; 9.9 s of flow landed.
        assert tank.level_l == pytest.approx(10.0 + 2.0 * 9.9, abs=0.2)

    def test_drains_and_clamps_at_empty(self) -> None:
        sim = Simulation(dt=0.1)
        tank = sim.add(Tank("t", capacity_l=100.0, level_l=1.0, drain_lps=2.0))
        sim.run(2.0)
        assert tank.level_l == 0.0
        assert tank.ran_dry_ticks > 0

    def test_overflow_is_tracked_and_level_clamped(self) -> None:
        sim = Simulation(dt=1.0)
        tank = sim.add(Tank("t", capacity_l=10.0, level_l=10.0))
        tank.inlet.value = Stream.pure("water", 5.0)
        tank.tick(1.0)
        assert tank.level_l == 10.0
        assert tank.overflowed_l == pytest.approx(5.0)

    def test_rejects_bad_construction(self) -> None:
        with pytest.raises(ValueError):
            Tank("t", capacity_l=0.0)
        with pytest.raises(ValueError):
            Tank("t", capacity_l=10.0, level_l=11.0)


class TestFloatSwitch:
    def _switch_at(self, level: float, switch: FloatSwitch) -> bool:
        switch.level_in.value = level
        switch.tick(0.05)
        return switch.closed

    def test_hysteresis_band(self) -> None:
        switch = FloatSwitch("s", low_l=40.0, high_l=80.0)
        assert self._switch_at(100.0, switch) is False
        assert self._switch_at(50.0, switch) is False   # falling, in band: hold
        assert self._switch_at(40.0, switch) is True    # reached low trip
        assert self._switch_at(60.0, switch) is True    # rising, in band: hold
        assert self._switch_at(79.9, switch) is True
        assert self._switch_at(80.0, switch) is False   # reached high trip

    def test_zero_deadband_chatters(self) -> None:
        switch = FloatSwitch("s", low_l=60.0, high_l=60.0)
        assert self._switch_at(59.9, switch) is True
        assert self._switch_at(60.1, switch) is False
        assert self._switch_at(59.9, switch) is True

    def test_band_is_adjustable_but_validated(self) -> None:
        switch = FloatSwitch("s", low_l=40.0, high_l=80.0)
        switch.set_band(30.0, 90.0)
        assert (switch.low_l, switch.high_l) == (30.0, 90.0)
        with pytest.raises(ValueError):
            switch.set_band(80.0, 40.0)
        with pytest.raises(ValueError):
            FloatSwitch("s2", low_l=80.0, high_l=40.0)


class TestRelay:
    def test_contact_follows_coil_and_counts_cycles(self) -> None:
        relay = Relay("r")
        for coil in (True, True, False, True, False):
            relay.coil.value = coil
            relay.tick(0.05)
            assert relay.contact.value is coil
        assert relay.cycles == 2


class TestPump:
    def test_flow_follows_run_in_auto_and_counts_starts(self) -> None:
        pump = Pump("p", rated_lps=4.0)
        pump.power.value = 1.0
        pump.inlet.value = Stream.pure("water", 1.0e9)
        pump.run.value = True
        pump.tick(0.05)
        assert pump.outlet.value.flow_lps == 4.0
        pump.run.value = False
        pump.tick(0.05)
        assert pump.outlet.value.flow_lps == 0.0
        pump.run.value = True
        pump.tick(0.05)
        assert pump.starts == 2

    def test_hand_off_auto_selector(self) -> None:
        pump = Pump("p", rated_lps=4.0)
        pump.power.value = 1.0
        pump.run.value = True
        pump.set_mode("off")
        pump.tick(0.05)
        assert pump.running is False       # off beats the run signal
        pump.run.value = False
        pump.set_mode("hand")
        pump.tick(0.05)
        assert pump.running is True        # hand beats the dead run signal
        pump.set_mode("auto")
        pump.tick(0.05)
        assert pump.running is False       # auto follows the signal again
        with pytest.raises(ValueError):
            pump.set_mode("jog")


class TestClosedLoop:
    """The build-order step 1 acceptance test: wire it and watch it."""

    def _build(self, low_l: float, high_l: float) -> tuple[Simulation, Tank, Relay]:
        sim = Simulation(dt=0.05)
        tank = sim.add(Tank("t", capacity_l=100.0, level_l=70.0, drain_lps=1.5))
        switch = sim.add(FloatSwitch("s", low_l=low_l, high_l=high_l))
        relay = sim.add(Relay("r"))
        pump = sim.add(Pump("p", rated_lps=4.0))
        wire_power(sim, pump)
        wire_supply(sim, pump)
        sim.connect(tank, "level", switch, "level")
        sim.connect(switch, "contact", relay, "coil")
        sim.connect(relay, "contact", pump, "run")
        sim.connect(pump, "outlet", tank, "inlet")
        return sim, tank, relay

    def test_hysteresis_holds_level_in_band(self) -> None:
        sim, tank, relay = self._build(low_l=40.0, high_l=80.0)
        sim.run(600.0)
        # Small excursions past the trips are physical (scan latency),
        # so allow a margin around the band.
        assert 38.0 <= tank.level_l <= 82.0
        assert tank.overflowed_l == 0.0
        assert tank.ran_dry_ticks == 0
        # 10 minutes, ~64 s per fill/drain cycle: a handful of cycles.
        assert relay.cycles < 15

    def test_zero_deadband_chatters(self) -> None:
        sim_good, _, relay_good = self._build(low_l=40.0, high_l=80.0)
        sim_bad, _, relay_bad = self._build(low_l=60.0, high_l=60.0)
        sim_good.run(600.0)
        sim_bad.run(600.0)
        # The chatter problem: the zero-deadband switch cycles the relay
        # orders of magnitude more often over the same 10 minutes.
        assert relay_bad.cycles > 50 * max(relay_good.cycles, 1)
