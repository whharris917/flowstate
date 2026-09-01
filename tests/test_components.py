"""Tests for the four step-1 components and their closed loop."""
from __future__ import annotations

import pytest

from conftest import Contact, wire_power, wire_supply
from sim.components import FloatSwitch, Pump, Relay, Source, Tank
from sim.core import Simulation
from sim.stream import Stream


class TestTank:
    def test_integrates_inflow(self) -> None:
        """Whatever the network delivers, the vessel accounts for all of
        it. The rate is not ours to name — the header's meter is the
        other half of the balance."""
        sim = Simulation(dt=0.05)
        tank = sim.add(Tank("t", capacity_l=4000.0, level_l=10.0, height_m=3.0))
        pump = sim.add(Pump("p", rated_lps=2.0, mode="hand"))
        wire_power(sim, pump)
        header = wire_supply(sim, pump)
        sim.connect(pump, "outlet", tank, "inlet")
        sim.run(30.0)
        assert header.total_l > 10.0
        assert tank.level_l == pytest.approx(10.0 + header.total_l, abs=0.2)

    def test_drains_and_clamps_at_empty(self) -> None:
        sim = Simulation(dt=0.1)
        tank = sim.add(Tank("t", capacity_l=100.0, level_l=1.0, drain_lps=2.0))
        sim.run(2.0)
        assert tank.level_l == 0.0
        assert tank.ran_dry_ticks > 0

    def test_overflow_is_tracked_and_level_clamped(self) -> None:
        """Fed at the nozzle the way the hydraulic pass feeds it: a
        signed flow into the port, and the material standing there."""
        tank = Tank("t", capacity_l=10.0, level_l=10.0)
        tank.inlet.flow_lps = 5.0
        tank.inlet.value = Stream.pure("water", 5.0)
        tank.tick(1.0)
        assert tank.level_l == 10.0
        assert tank.overflowed_l == pytest.approx(5.0)

    def test_a_full_tank_drains_into_an_empty_one_through_a_pipe(self) -> None:
        """No pump, no draw wire, no bookkeeping — just elevation."""
        sim = Simulation(dt=0.05)
        high = sim.add(Tank("high", capacity_l=1000.0, level_l=800.0,
                            height_m=2.0, elevation_m=4.0))
        low = sim.add(Tank("low", capacity_l=1000.0, level_l=0.0,
                           height_m=2.0))
        sim.connect(high, "outlet", low, "inlet")
        sim.run(120.0)
        assert low.level_l > 50.0
        assert high.level_l + low.level_l == pytest.approx(800.0, abs=0.5)

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
    """A pump is a branch in a network now, so it has to be *in* one to
    say anything. Whether it is running is decided during the hydraulic
    pass, before the components tick."""

    def _rig(self, mode: str = "auto") -> tuple[Simulation, Pump, Contact, Tank]:
        sim = Simulation(dt=0.05)
        header = sim.add(Source("hdr", pressure_kpa=300.0))
        pump = sim.add(Pump("p", rated_lps=4.0, mode=mode))
        tank = sim.add(Tank("t", capacity_l=9000.0, height_m=4.0))
        hand = sim.add(Contact("hs", closed=False))
        wire_power(sim, pump)
        sim.connect(hand, "out", pump, "run")
        sim.connect(header, "outlet", pump, "inlet")
        sim.connect(pump, "outlet", tank, "inlet")
        return sim, pump, hand, tank

    def test_flow_follows_run_in_auto_and_counts_starts(self) -> None:
        sim, pump, hand, _ = self._rig()
        sim.run(1.0)
        assert pump.flow_lps == pytest.approx(0.0)
        hand.closed = True
        sim.run(1.0)
        assert pump.running is True
        assert pump.flow_lps > 0.0
        hand.closed = False
        sim.run(1.0)
        assert pump.running is False
        assert pump.flow_lps == pytest.approx(0.0)
        hand.closed = True
        sim.run(1.0)
        assert pump.starts == 2

    def test_it_finds_its_own_operating_point_not_its_rating(self) -> None:
        """The thing a fixed rate could never do: what it delivers is
        its curve against the system, so throttling the discharge walks
        it back up the curve rather than doing nothing."""
        def deliver(k_pa_per_lps2: float) -> tuple[float, float]:
            sim = Simulation(dt=0.05)
            header = sim.add(Source("hdr", pressure_kpa=100.0))
            pump = sim.add(Pump("p", rated_lps=4.0, mode="hand"))
            tank = sim.add(Tank("t", capacity_l=9000.0, height_m=4.0))
            wire_power(sim, pump)
            sim.connect(header, "outlet", pump, "inlet")
            run = sim.connect(pump, "outlet", tank, "inlet")
            run.k_pa_per_lps2 = k_pa_per_lps2
            sim.run(5.0)
            return pump.flow_lps, pump.head_pa

        open_q, open_h = deliver(2_000.0)
        tight_q, tight_h = deliver(60_000.0)
        assert open_q > tight_q                 # a tighter line, less flow
        assert tight_h > open_h                 # and more head across it
        assert open_q != pytest.approx(4.0)     # never simply the rating

    def test_hand_off_auto_selector(self) -> None:
        sim, pump, hand, _ = self._rig()
        hand.closed = True
        pump.set_mode("off")
        sim.run(1.0)
        assert pump.running is False       # off beats the run signal
        hand.closed = False
        pump.set_mode("hand")
        sim.run(1.0)
        assert pump.running is True        # hand beats the dead run signal
        pump.set_mode("auto")
        sim.run(1.0)
        assert pump.running is False       # auto follows the signal again
        with pytest.raises(ValueError):
            pump.set_mode("jog")

    def test_a_stopped_pump_blocks_its_line(self) -> None:
        """It is its own check valve, which a real one is not. Stand
        6 m of head on its suction with the motor off and nothing gets
        through — a real centrifugal would pass it. Worth knowing,
        because it means this plant never needs a check valve."""
        sim = Simulation(dt=0.05)
        pump = sim.add(Pump("p", rated_lps=4.0, mode="off"))
        high = sim.add(Tank("high", capacity_l=1000.0, level_l=800.0,
                            height_m=2.0, elevation_m=6.0))
        low = sim.add(Tank("low", capacity_l=1000.0, level_l=0.0,
                           height_m=2.0))
        wire_power(sim, pump)
        sim.connect(high, "outlet", pump, "inlet")
        sim.connect(pump, "outlet", low, "inlet")
        sim.run(120.0)
        assert not pump.running
        assert low.level_l == pytest.approx(0.0, abs=1e-6)
        assert high.level_l == pytest.approx(800.0, abs=1e-6)

    def test_a_dead_headed_pump_turns_and_delivers_nothing(self) -> None:
        """Ask for more lift than its shutoff head and the motor runs,
        the line is open, and the level does not move. The failure a
        fixed rate could never produce."""
        sim = Simulation(dt=0.05)
        header = sim.add(Source("hdr", pressure_kpa=0.0))
        pump = sim.add(Pump("p", rated_lps=4.0, mode="hand", head_m=3.0))
        tower = sim.add(Tank("tower", capacity_l=9000.0, height_m=18.0))
        wire_power(sim, pump)
        sim.connect(header, "outlet", pump, "inlet")
        sim.connect(pump, "outlet", tower, "inlet")
        sim.run(60.0)
        assert pump.running
        assert pump.flow_lps < 0.01
        assert tower.level_l == pytest.approx(0.0, abs=1e-6)


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
        # 10 minutes at roughly 40 s per fill/drain cycle. The pump runs
        # out past its rating against this short line, so it fills
        # faster than the old fixed-rate one did and cycles a little
        # more often for it.
        assert relay.cycles < 25

    def test_zero_deadband_chatters(self) -> None:
        sim_good, _, relay_good = self._build(low_l=40.0, high_l=80.0)
        sim_bad, _, relay_bad = self._build(low_l=60.0, high_l=60.0)
        sim_good.run(600.0)
        sim_bad.run(600.0)
        # The chatter problem: the zero-deadband switch cycles the relay
        # orders of magnitude more often over the same 10 minutes.
        assert relay_bad.cycles > 50 * max(relay_good.cycles, 1)
