"""Tests for Simulation.disconnect — pulling a run out of the graph."""
from __future__ import annotations

from sim.components import FloatSwitch, Pump, Relay, Tank
from sim.core import Simulation


def _loop() -> tuple[Simulation, Tank, FloatSwitch, Relay, Pump]:
    sim = Simulation(dt=0.05)
    tank = sim.add(Tank("tank", 100.0, 30.0, drain_lps=0.0))
    switch = sim.add(FloatSwitch("switch", 40.0, 80.0))
    relay = sim.add(Relay("relay"))
    pump = sim.add(Pump("pump", 4.0))
    sim.connect(tank, "level", switch, "level")
    sim.connect(switch, "contact", relay, "coil")
    sim.connect(relay, "contact", pump, "run")
    sim.connect(pump, "flow", tank, "in_flow")
    return sim, tank, switch, relay, pump


class TestDisconnect:
    def test_disconnect_stops_signal_next_scan(self) -> None:
        sim, tank, switch, relay, pump = _loop()
        sim.run(5.0)
        assert pump.running  # level 30 < low trip, loop is filling
        assert sim.disconnect(relay, "contact", pump, "run")
        sim.run(1.0)
        assert not pump.running  # input reverted to its default

    def test_disconnect_frees_single_source_slot(self) -> None:
        sim, tank, switch, relay, pump = _loop()
        assert pump.run.wire_count == 1
        assert sim.disconnect(relay, "contact", pump, "run")
        assert pump.run.wire_count == 0
        # The slot is free again: wire the switch straight to the pump.
        sim.connect(switch, "contact", pump, "run")
        sim.run(5.0)
        assert pump.running

    def test_disconnect_missing_wire_is_false(self) -> None:
        sim, tank, switch, relay, pump = _loop()
        assert not sim.disconnect(switch, "contact", pump, "run")
        assert not sim.disconnect(relay, "contact", pump, "nope")
        assert len(sim.wires) == 4
