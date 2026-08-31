"""Shared test helpers."""
from __future__ import annotations

from sim.components import MainsFeed, Source
from sim.core import Component, PortKind, Simulation


class Duty(Component):
    """A fixed analog output standing in for a controller or a duty
    setpoint. Duties have to be *wired*, like everything else: an input
    port is reset every scan, so a value poked onto one is gone before
    the component ticks."""

    def __init__(self, name: str, kw: float) -> None:
        super().__init__(name)
        self.kw = kw
        self.out = self.add_output("out", PortKind.SIGNAL_ANALOG)

    def tick(self, dt: float) -> None:
        self.out.value = self.kw


def wire_power(sim: Simulation, *components: Component) -> MainsFeed:
    """Feed each component's power input from a fresh mains feeder —
    the boilerplate of an energized plant."""
    mains = sim.add(MainsFeed(sim.unique_name("mains")))
    for component in components:
        sim.connect(mains, "power", component, "power")
    return mains


def wire_supply(sim: Simulation, *components: Component) -> Source:
    """Give each pump or valve a supply header to pull from —
    suction/supply wired in, draw metered back."""
    source = sim.add(Source(sim.unique_name("source")))
    for component in components:
        inlet = "inlet"
        sim.connect(source, "supply", component, inlet)
        sim.connect(component, "draw", source, "draw")
    return source
