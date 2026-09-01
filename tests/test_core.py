"""Tests for the kernel core: ports, wiring rules, scan order, determinism."""
from __future__ import annotations

import pytest

from conftest import wire_power
from sim.components import FloatSwitch, Pump, Relay, Source, Tank
from sim.core import PortKind, Simulation


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


def test_material_inputs_sum() -> None:
    """Two runs onto one nozzle is a tee, and the vessel fills at the
    sum of them. Nothing declares those two rates — the network solves
    them — so the balance is what is checked, against the meters."""
    sim = Simulation(dt=0.05)
    tank = sim.add(Tank("t", capacity_l=4000.0, height_m=3.0))
    a = sim.add(Source("a", pressure_kpa=300.0))
    b = sim.add(Source("b", pressure_kpa=300.0))
    sim.connect(a, "outlet", tank, "inlet")
    sim.connect(b, "outlet", tank, "inlet")
    sim.run(60.0)
    assert a.total_l > 0.0 and b.total_l > 0.0
    assert tank.level_l == pytest.approx(a.total_l + b.total_l, abs=0.5)


def test_material_ports_are_not_reset_by_the_scan() -> None:
    """Every other input kind reverts to its default at the top of a
    scan, because a wire re-delivers it. A nozzle does not: what stands
    in the line is resolved by the hydraulic pass, and a reset would
    erase it every tick."""
    sim = Simulation(dt=0.05)
    tank = sim.add(Tank("t", capacity_l=4000.0, height_m=3.0))
    header = sim.add(Source("s", species="solvent", pressure_kpa=300.0))
    sim.connect(header, "outlet", tank, "inlet")
    sim.run(10.0)
    assert tank.inlet.stream.frac("solvent") == pytest.approx(1.0)
    for port in tank.inputs.values():
        port.reset()
    assert tank.inlet.stream.frac("solvent") == pytest.approx(1.0)


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
