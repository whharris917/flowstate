"""Shared test helpers."""
from __future__ import annotations

from sim.components import Drain, MainsFeed, Source
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


def feed(port, stream) -> None:
    """Stand material at a nozzle, arriving, exactly the way the
    hydraulic pass leaves it: the composition at the node, and a signed
    rate into the component.

    This is how a unit operation is tested on its own equations without
    building a network around it. Setting only ``value`` does nothing
    -- a component reads its rate off ``flow_lps``, because
    that is the half of it the solver decides.
    """
    port.value = stream
    port.flow_lps = stream.flow_lps


class Contact(Component):
    """A hand switch standing in for a field contact or a relay output.

    Discrete commands have to be *wired* for the same reason analog ones
    do: an input port is reset every scan, so a value poked onto one is
    gone before the component ticks.
    """

    def __init__(self, name: str, closed: bool = False) -> None:
        super().__init__(name)
        self.closed = closed
        self.out = self.add_output("out", PortKind.SIGNAL_DISCRETE)

    def tick(self, dt: float) -> None:
        self.out.value = self.closed


def wire_power(sim: Simulation, *components: Component) -> MainsFeed:
    """Feed each component's power input from a fresh mains feeder —
    the boilerplate of an energized plant."""
    mains = sim.add(MainsFeed(sim.unique_name("mains"), ways=max(len(components), 1)))
    for i, component in enumerate(components, start=1):
        sim.connect(mains, f"way{i}", component, "power")
    return mains


def wire_supply(
    sim: Simulation, *components: Component, pressure_kpa: float = 400.0
) -> Source:
    """Give each pump or valve a header to pull from.

    One header, one pipe run per machine, and nothing else — there is no
    draw wire to pair with it. What each component gets is
    whatever the network solves for it, so a test that wants a *known*
    flow has to arrange the pressures and resistances that produce it
    rather than asserting a rate.
    """
    source = sim.add(
        Source(sim.unique_name("source"), pressure_kpa=pressure_kpa))
    for component in components:
        sim.connect(source, "outlet", component, "inlet")
    return source


def open_drain(sim: Simulation, component: Component, out_name: str = "outlet",
               rate_lps: float = 50.0) -> Drain:
    """Somewhere for a discharge to go.

    A machine piped only on its suction is dead-headed: with pressure
    solving direction, a line that ends nowhere passes nothing. Most
    tests do not care where the material went, only that it moved, so
    this is the generous sewer they hang off the discharge.
    """
    drain = sim.add(Drain(sim.unique_name("drain"), rate_lps=rate_lps))
    sim.connect(component, out_name, drain, "inlet")
    return drain
