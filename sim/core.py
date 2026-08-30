"""Simulation kernel core: ports, wires, components, and the scan loop.

The kernel is a graph of components. Each component is a small state
machine with declared, typed input/output ports and a ``tick(dt)``.

Tick order (one scan):
  1. Every input port resets to its default.
  2. Every wire copies its source output value into its destination input
     (values are whatever the source published on the *previous* scan).
  3. Every component ticks in insertion order.
  4. The historian, if attached, samples every tag.

Because components only ever read their own input ports — never another
component directly — the result is deterministic regardless of the order
things were built in, and every hop through the graph costs one scan of
latency. That latency is deliberate: it is what real relay and PLC scan
delay looks like, and it is what makes control problems like pump
chatter reproducible.
"""
from __future__ import annotations

from enum import Enum
from typing import Callable, Optional, Union

from sim.historian import Historian

Value = Union[bool, float]


class PortKind(Enum):
    """What a port carries. Wires may only join ports of the same kind."""

    SIGNAL_DISCRETE = "signal_discrete"  # 24 V on/off (bool)
    SIGNAL_ANALOG = "signal_analog"      # 4-20 mA (float)
    PROCESS_FLOW = "process_flow"        # liquid flow, L/s (float)
    PROCESS_LEVEL = "process_level"      # liquid level, L (float)


# How multiple wires landing on one input combine, per kind.
# Discrete signals OR together (parallel contacts); flows sum (two pumps
# into one header). Analog and level allow only a single source.
_SUMMING_KINDS = {PortKind.PROCESS_FLOW}
_ORING_KINDS = {PortKind.SIGNAL_DISCRETE}


def _default_for(kind: PortKind) -> Value:
    return False if kind is PortKind.SIGNAL_DISCRETE else 0.0


class Port:
    """Ports know their owner's *name* for tag paths, never the owner
    object — mirrors the GDScript port, where a back-reference would
    make a component<->port RefCounted cycle and leak the graph."""

    def __init__(self, owner_name: str, name: str, kind: PortKind) -> None:
        self.owner_name = owner_name
        self.name = name
        self.kind = kind
        self.value: Value = _default_for(kind)

    @property
    def path(self) -> str:
        return f"{self.owner_name}.{self.name}"


class InputPort(Port):
    def __init__(self, owner_name: str, name: str, kind: PortKind) -> None:
        super().__init__(owner_name, name, kind)
        self.wire_count = 0

    def reset(self) -> None:
        self.value = _default_for(self.kind)

    def accumulate(self, incoming: Value) -> None:
        if self.kind in _SUMMING_KINDS:
            self.value = float(self.value) + float(incoming)
        elif self.kind in _ORING_KINDS:
            self.value = bool(self.value) or bool(incoming)
        else:
            self.value = incoming


class OutputPort(Port):
    pass


class Wire:
    def __init__(self, src: OutputPort, dst: InputPort) -> None:
        if src.kind is not dst.kind:
            raise ValueError(
                f"cannot wire {src.path} ({src.kind.value}) to "
                f"{dst.path} ({dst.kind.value})"
            )
        if dst.wire_count > 0 and dst.kind not in (_SUMMING_KINDS | _ORING_KINDS):
            raise ValueError(f"{dst.path} ({dst.kind.value}) accepts only one wire")
        self.src = src
        self.dst = dst
        dst.wire_count += 1

    def propagate(self) -> None:
        self.dst.accumulate(self.src.value)


class Component:
    """Base class for everything in the sim graph.

    Besides ports, a component may declare *observables*: named internal
    state (wear counters, totals) exposed read-only so the historian can
    record it. Observables are how failure evidence becomes trend data.
    They are attribute names rather than closures so the GDScript port
    (whose closures over self would leak through RefCounted cycles) can
    mirror this structure exactly.
    """

    def __init__(self, name: str) -> None:
        self.name = name
        self.inputs: dict[str, InputPort] = {}
        self.outputs: dict[str, OutputPort] = {}
        self.observables: dict[str, str] = {}

    def add_input(self, name: str, kind: PortKind) -> InputPort:
        port = InputPort(self.name, name, kind)
        self.inputs[name] = port
        return port

    def add_output(self, name: str, kind: PortKind) -> OutputPort:
        port = OutputPort(self.name, name, kind)
        self.outputs[name] = port
        return port

    def add_observable(self, name: str, attr: str) -> None:
        self.observables[name] = attr

    def tick(self, dt: float) -> None:
        raise NotImplementedError

    def __repr__(self) -> str:
        return f"<{type(self).__name__} {self.name!r}>"


class Simulation:
    """Owns the component graph and advances it at a fixed rate."""

    def __init__(self, dt: float = 0.05) -> None:
        if dt <= 0.0:
            raise ValueError("dt must be positive")
        self.dt = dt
        self.time = 0.0
        self.components: list[Component] = []
        self.wires: list[Wire] = []
        self.historian: Optional[Historian] = None
        self._names: set[str] = set()

    def add(self, component: Component) -> Component:
        if component.name in self._names:
            raise ValueError(f"duplicate component name {component.name!r}")
        self._names.add(component.name)
        self.components.append(component)
        return component

    def connect(
        self, src: Component, out_name: str, dst: Component, in_name: str
    ) -> Wire:
        wire = Wire(src.outputs[out_name], dst.inputs[in_name])
        self.wires.append(wire)
        return wire

    def get_component(self, name: str) -> Optional[Component]:
        return next((c for c in self.components if c.name == name), None)

    def unique_name(self, prefix: str) -> str:
        index = 1
        while f"{prefix}_{index}" in self._names:
            index += 1
        return f"{prefix}_{index}"

    def remove_component(self, name: str) -> bool:
        """Remove a component and every wire touching it. Its historian
        tags are retired (history kept), matching pulling real
        equipment: the record stops, it doesn't vanish."""
        component = next((c for c in self.components if c.name == name), None)
        if component is None:
            return False
        kept = []
        for wire in self.wires:
            if wire.src.owner_name == name or wire.dst.owner_name == name:
                wire.dst.wire_count -= 1
            else:
                kept.append(wire)
        self.wires = kept
        self.components.remove(component)
        self._names.discard(name)
        if self.historian is not None:
            for port in component.outputs.values():
                if port.path in self.historian.active_tags:
                    self.historian.retire(port.path)
            for obs_name in component.observables:
                tag = f"{name}.{obs_name}"
                if tag in self.historian.active_tags:
                    self.historian.retire(tag)
        return True

    def register_with_historian(self, component: Component) -> None:
        """Register one component's tags (for equipment added after the
        historian was attached — mid-run placement)."""
        if self.historian is None:
            return
        for port in component.outputs.values():
            self.historian.register(port.path, lambda p=port: float(p.value))
        for obs_name, attr in component.observables.items():
            self.historian.register(
                f"{component.name}.{obs_name}",
                lambda c=component, a=attr: float(getattr(c, a)),
            )

    def attach_historian(self, historian: Historian) -> Historian:
        """Register every output port and observable as a tag, then take
        the t=0 baseline sample. Attach after the graph is built."""
        for component in self.components:
            for port in component.outputs.values():
                historian.register(port.path, lambda p=port: float(p.value))
            for name, attr in component.observables.items():
                historian.register(
                    f"{component.name}.{name}",
                    lambda c=component, a=attr: float(getattr(c, a)),
                )
        self.historian = historian
        historian.sample(self.time)
        return historian

    def tick(self) -> None:
        for component in self.components:
            for port in component.inputs.values():
                port.reset()
        for wire in self.wires:
            wire.propagate()
        for component in self.components:
            component.tick(self.dt)
        self.time += self.dt
        if self.historian is not None:
            self.historian.sample(self.time)

    def run(
        self,
        seconds: float,
        on_tick: Optional[Callable[["Simulation"], None]] = None,
    ) -> None:
        ticks = round(seconds / self.dt)
        for _ in range(ticks):
            self.tick()
            if on_tick is not None:
                on_tick(self)
