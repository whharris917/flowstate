"""Tests for the kernel core: ports, wiring rules, scan order, determinism."""
from __future__ import annotations

import pytest

from conftest import wire_power
from sim.components import FloatSwitch, Pump, Relay, Tank
from sim.core import Component, PortKind, Simulation
from sim.stream import Stream


class ConstantFlow(Component):
    """Test stub: unconditionally pushes a fixed stream of water."""

    def __init__(self, name: str, lps: float) -> None:
        super().__init__(name)
        self.lps = lps
        self.flow = self.add_output("flow", PortKind.PROCESS_STREAM)
        self.flow.value = Stream.pure("water", lps)

    def tick(self, dt: float) -> None:
        self.flow.value = Stream.pure("water", self.lps)


def test_wire_rejects_mismatched_kinds() -> None:
    sim = Simulation()
    tank = sim.add(Tank("t", capacity_l=10.0))
    pump = sim.add(Pump("p", rated_lps=1.0))
    with pytest.raises(ValueError):
        sim.connect(tank, "level", pump, "run")  # process level -> discrete


def test_single_source_kinds_reject_second_wire() -> None:
    sim = Simulation()
    tank_a = sim.add(Tank("a", capacity_l=10.0))
    tank_b = sim.add(Tank("b", capacity_l=10.0))
    switch = sim.add(FloatSwitch("s", low_l=2.0, high_l=8.0))
    sim.connect(tank_a, "level", switch, "level")
    with pytest.raises(ValueError):
        sim.connect(tank_b, "level", switch, "level")


def test_flow_inputs_sum() -> None:
    sim = Simulation(dt=1.0)
    tank = sim.add(Tank("t", capacity_l=100.0))
    sim.connect(sim.add(ConstantFlow("fa", 2.0)), "flow", tank, "inlet")
    sim.connect(sim.add(ConstantFlow("fb", 3.0)), "flow", tank, "inlet")
    sim.run(2.0)
    assert tank.level_l == pytest.approx(10.0)


def test_discrete_inputs_or_like_parallel_contacts() -> None:
    sim = Simulation(dt=1.0)
    relay_a = sim.add(Relay("ra"))
    relay_b = sim.add(Relay("rb"))
    pump = sim.add(Pump("p", rated_lps=1.0))
    wire_power(sim, pump)
    sim.connect(relay_a, "contact", pump, "run")
    sim.connect(relay_b, "contact", pump, "run")
    relay_a.contact.value = False
    relay_b.contact.value = True
    sim.tick()
    assert pump.running is True


def test_propagation_is_one_scan_per_hop() -> None:
    """switch -> relay -> pump: the run signal arrives two scans later."""
    sim = Simulation(dt=1.0)
    tank = sim.add(Tank("t", capacity_l=100.0, level_l=0.0))
    switch = sim.add(FloatSwitch("s", low_l=10.0, high_l=90.0))
    relay = sim.add(Relay("r"))
    pump = sim.add(Pump("p", rated_lps=1.0))
    wire_power(sim, pump)
    sim.connect(tank, "level", switch, "level")
    sim.connect(switch, "contact", relay, "coil")
    sim.connect(relay, "contact", pump, "run")

    sim.tick()  # switch sees empty tank, closes
    assert switch.closed is True
    assert pump.running is False
    sim.tick()  # relay energizes
    assert relay.energized is True
    assert pump.running is False
    sim.tick()  # pump starts
    assert pump.running is True


def test_determinism_two_identical_sims_match_exactly() -> None:
    def build() -> tuple[Simulation, Tank, Relay]:
        sim = Simulation(dt=0.05)
        tank = sim.add(Tank("t", capacity_l=100.0, level_l=70.0, drain_lps=1.5))
        switch = sim.add(FloatSwitch("s", low_l=40.0, high_l=80.0))
        relay = sim.add(Relay("r"))
        pump = sim.add(Pump("p", rated_lps=4.0))
        wire_power(sim, pump)
        sim.connect(tank, "level", switch, "level")
        sim.connect(switch, "contact", relay, "coil")
        sim.connect(relay, "contact", pump, "run")
        sim.connect(pump, "outlet", tank, "inlet")
        return sim, tank, relay

    sim_a, tank_a, relay_a = build()
    sim_b, tank_b, relay_b = build()
    sim_a.run(300.0)
    sim_b.run(300.0)
    assert tank_a.level_l == tank_b.level_l
    assert relay_a.cycles == relay_b.cycles
    assert sim_a.time == sim_b.time


def test_duplicate_component_name_rejected() -> None:
    sim = Simulation()
    sim.add(Relay("r"))
    with pytest.raises(ValueError):
        sim.add(Relay("r"))
