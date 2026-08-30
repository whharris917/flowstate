"""Shared test helpers."""
from __future__ import annotations

from sim.components import MainsFeed
from sim.core import Component, Simulation


def wire_power(sim: Simulation, *components: Component) -> MainsFeed:
    """Feed each component's power input from a fresh mains feeder —
    the boilerplate of an energized plant."""
    mains = sim.add(MainsFeed(sim.unique_name("mains")))
    for component in components:
        sim.connect(mains, "power", component, "power")
    return mains
