"""Shared test helpers."""
from __future__ import annotations

from sim.components import MainsFeed, Source
from sim.core import Component, Simulation


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
        inlet = "suction" if "suction" in component.inputs else "supply"
        sim.connect(source, "supply", component, inlet)
        sim.connect(component, "draw", source, "draw")
    return source
