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
from sim.hydraulics import Network, Resistance
from sim.species import SPECIES_KEYS
from sim.stream import Stream

Value = Union[bool, float, Stream]


class PortKind(Enum):
    """What a port carries. Wires may only join ports of the same kind."""

    SIGNAL_DISCRETE = "signal_discrete"  # 24 V on/off (bool)
    SIGNAL_ANALOG = "signal_analog"      # 4-20 mA (float)
    # A nozzle. There is exactly one material kind, because with
    # pressure driving flow there is nothing left for a second one to
    # protect against: any nozzle may legitimately be piped to any
    # other, and which way material goes is *solved*, not declared.
    # Each material port is a node in the hydraulic network; each wire
    # between two of them is a pipe run with a resistance.
    PROCESS_MATERIAL = "process_material"
    PROCESS_LEVEL = "process_level"      # liquid level, L (float) — instruments
    PROCESS_PRESSURE = "process_pressure"  # gauge pressure, Pa (float)
    POWER = "power"                      # electrical supply (1.0 = energized)


# How multiple wires landing on one input combine, per kind. Discrete
# signals OR together (parallel contacts). Material does not combine
# here at all: several runs landing on one nozzle is a tee, and the
# network resolves it by solving the node.
_ORING_KINDS = {PortKind.SIGNAL_DISCRETE}
_MULTI_WIRE_KINDS = _ORING_KINDS | {PortKind.PROCESS_MATERIAL}


def _default_for(kind: PortKind) -> Value:
    if kind is PortKind.SIGNAL_DISCRETE:
        return False
    if kind is PortKind.PROCESS_MATERIAL:
        return Stream.empty()
    return 0.0


class Port:
    """Ports know their owner's *name* for tag paths, never the owner
    object — mirrors the GDScript port, where a back-reference would
    make a component<->port RefCounted cycle and leak the graph."""

    def __init__(
        self, owner_name: str, name: str, kind: PortKind, spec: str = ""
    ) -> None:
        self.owner_name = owner_name
        self.name = name
        self.kind = kind
        self.spec = spec  # e.g. voltage class "480VAC" / "24VDC" for POWER
        self.value: Value = _default_for(kind)
        # Material ports only. `flow_lps` is signed and reads from the
        # component's point of view: positive is material coming IN
        # through this nozzle, negative is going out. Direction is an
        # answer from the hydraulic solve, not something declared, so a
        # nozzle that normally discharges can genuinely run backwards.
        # `stream` is what is present at the node: composition and
        # temperature, with its rate set to |flow_lps|.
        self.flow_lps: float = 0.0
        self.node: int = -1  # index into the hydraulic network

    @property
    def path(self) -> str:
        return f"{self.owner_name}.{self.name}"

    @property
    def stream(self) -> Stream:
        """The material at this nozzle. Always a live Stream for a
        material port; meaningless on any other kind."""
        return self.value if isinstance(self.value, Stream) else Stream.empty()


class InputPort(Port):
    def __init__(
        self, owner_name: str, name: str, kind: PortKind, spec: str = ""
    ) -> None:
        super().__init__(owner_name, name, kind, spec)
        self.wire_count = 0

    def reset(self) -> None:
        # Material ports keep their value: the node composition is
        # resolved by the hydraulic pass, not delivered by a wire.
        if self.kind is not PortKind.PROCESS_MATERIAL:
            self.value = _default_for(self.kind)

    def accumulate(self, incoming: Value) -> None:
        if self.kind in _ORING_KINDS:
            self.value = bool(self.value) or bool(incoming)
        else:
            self.value = incoming


class OutputPort(Port):
    pass


class Wire:
    """A run between two ports.

    A material wire is a real pipe: it has a resistance, so a long or
    thin run genuinely costs pressure. The kernel stays geometry-free —
    whoever builds the run works out the number and hands it over.
    """

    #: Pa per (L/s)^2 for a short, generously sized run: about
    #: 45 kPa at 3 L/s, which is what a sensibly sized line costs. Too
    #: small a number here and nothing in the plant limits anything.
    DEFAULT_K = 5_000.0

    def __init__(self, src: OutputPort, dst: InputPort) -> None:
        if src.kind is not dst.kind:
            raise ValueError(
                f"cannot wire {src.path} ({src.kind.value}) to "
                f"{dst.path} ({dst.kind.value})"
            )
        if src.kind is PortKind.POWER and src.spec != dst.spec:
            raise ValueError(
                f"voltage mismatch: {src.path} is {src.spec or '?'}, "
                f"{dst.path} needs {dst.spec or '?'}"
            )
        if dst.wire_count > 0 and dst.kind not in _MULTI_WIRE_KINDS:
            raise ValueError(f"{dst.path} ({dst.kind.value}) accepts only one wire")
        self.src = src
        self.dst = dst
        self.k_pa_per_lps2 = self.DEFAULT_K
        self.branch = None  # the hydraulic branch, for material runs
        dst.wire_count += 1

    @property
    def is_material(self) -> bool:
        return self.src.kind is PortKind.PROCESS_MATERIAL

    def propagate(self) -> None:
        # Material does not propagate along a wire: the wire is a pipe,
        # and what moves through it is whatever the network solved.
        if not self.is_material:
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

    def add_input(self, name: str, kind: PortKind, spec: str = "") -> InputPort:
        port = InputPort(self.name, name, kind, spec)
        self.inputs[name] = port
        return port

    def add_output(self, name: str, kind: PortKind, spec: str = "") -> OutputPort:
        port = OutputPort(self.name, name, kind, spec)
        self.outputs[name] = port
        return port

    def add_observable(self, name: str, attr: str) -> None:
        self.observables[name] = attr

    # -- hydraulics ---------------------------------------------------
    #
    # Every material port is a node in the network. A component takes
    # part in the solve in one or both of two ways:
    #
    #   * It *sets a pressure* at a nozzle. A supply header holds its
    #     rated pressure; a vessel holds headspace plus static head.
    #     Such a node is a boundary: it absorbs whatever flow arrives
    #     and its inventory changes to match.
    #   * It *carries flow between its own nozzles* — a pump adding
    #     head, a valve resisting. Those become branches.
    #
    # A component that does neither has no nozzles and never appears.

    def material_ports(self) -> dict[str, Port]:
        return {
            name: port
            for name, port in list(self.inputs.items()) + list(self.outputs.items())
            if port.kind is PortKind.PROCESS_MATERIAL
        }

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        """Declare internal branches. Called when topology changes, not
        every scan; keep references to what you add so you can adjust it
        in ``update_hydraulics``."""

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        """Refresh boundary pressures and branch settings before each
        solve — a vessel's head as it fills, a valve's opening, whether
        a pump is turning."""

    def standing_ports(self) -> set[str]:
        """Ports whose node carries this component's own supplied stream
        even when nothing moves through them: a vessel's contents tap,
        which a probe on the shell reads. Nothing flows there, so the
        composition pass would otherwise leave it holding whatever it
        held at start."""
        return set()

    def tap_ports(self) -> set[str]:
        """Nozzles that observe without carrying anything: a thermowell,
        an analyser tapping. A run to a tap creates no branch, so the
        instrument reads the line without being a hole in it."""
        return set()

    def shared_node_ports(self) -> list[list[str]]:
        """Groups of nozzles that are one hydraulic node: a tee's three
        (director, 2026-09-12: a nozzle takes one line, so joining and
        splitting is a fitting with its own separated nozzles). The
        layout gives every port in a group the same node."""
        return []

    def supplied_stream(self, port_name: str) -> Optional[Stream]:
        """What this component pushes out of that nozzle, when it is a
        source of material rather than a pass-through. A vessel supplies
        its contents; a header supplies what it carries. Returning None
        means "whatever the network brings me", which is right for a
        pump, a valve, or a length of pipe."""
        return None

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
        self.unconverged_scans = 0
        self.unconverged_worst_lps = 0.0
        self.components: list[Component] = []
        self.wires: list[Wire] = []
        self.historian: Optional[Historian] = None
        self._names: set[str] = set()
        self._network: Optional[Network] = None
        self._network_stale = True
        self._node_streams: list[Stream] = []
        self._taps: set[int] = set()
        self._tap_source: dict[int, int] = {}

    def add(self, component: Component) -> Component:
        if component.name in self._names:
            raise ValueError(f"duplicate component name {component.name!r}")
        self._names.add(component.name)
        self.components.append(component)
        self._network_stale = True
        return component

    # -- the hydraulic pass -------------------------------------------

    def _rebuild_network(self) -> None:
        """Lay out the network: one node per nozzle, one branch per pipe
        run, plus whatever each component puts between its own nozzles.

        Only topology lives here. Pressures and settings are refreshed
        every scan, which is far cheaper than rebuilding.
        """
        net = Network()
        for component in self.components:
            shared: dict[str, int] = {}
            for group in component.shared_node_ports():
                node = net.add_node()
                for name in group:
                    shared[name] = node
            for name, port in component.material_ports().items():
                port.node = shared[name] if name in shared else net.add_node()
        taps = set()
        for component in self.components:
            for name in component.tap_ports():
                port = component.material_ports().get(name)
                if port is not None:
                    taps.add(port.node)
        self._taps = taps
        self._tap_source = {}
        for wire in self.wires:
            if not wire.is_material:
                continue
            if wire.src.node in taps or wire.dst.node in taps:
                # An instrument tap draws nothing, so it gets no branch.
                # It reads whatever the line it is tapped into holds.
                if wire.dst.node in taps:
                    self._tap_source[wire.dst.node] = wire.src.node
                else:
                    self._tap_source[wire.src.node] = wire.dst.node
                continue
            wire.branch = net.add_branch(
                Resistance(wire.src.node, wire.dst.node,
                           wire.k_pa_per_lps2,
                           f"{wire.src.path}->{wire.dst.path}"))
        for component in self.components:
            ports = component.material_ports()
            if ports:
                component.build_hydraulics(
                    net, {name: port.node for name, port in ports.items()})
        self._network = net
        self._node_streams = [Stream.empty() for _ in net.pressures]
        self._network_stale = False

    def _solve_hydraulics(self) -> None:
        if self._network_stale or self._network is None:
            self._rebuild_network()
        net = self._network
        if not net.branches:
            return
        for component in self.components:
            ports = component.material_ports()
            if ports:
                component.update_hydraulics(
                    net, {name: port.node for name, port in ports.items()})
        net.solve()
        if not net.converged:
            # Solves that did not land (2026-09-22): their flows do not
            # balance, so they are counted where they cannot be missed.
            self.unconverged_scans += 1
            self.unconverged_worst_lps = max(self.unconverged_worst_lps, net.residual_lps)

        # What each component sees at each nozzle: the net flow arriving
        # from the pipe runs attached to it. At a boundary the vessel
        # absorbs that; at a free node it equals what passes through the
        # component, by conservation. One rule covers both.
        for component in self.components:
            for port in component.material_ports().values():
                port.flow_lps = 0.0
        for wire in self.wires:
            if wire.branch is None:
                continue
            q = wire.branch.flow_lps
            wire.src.flow_lps -= q
            wire.dst.flow_lps += q

        self._resolve_compositions()

    def _resolve_compositions(self) -> None:
        """Work out what is in each node, then hand it to the ports.

        Composition moves one node per scan, the same one-scan latency
        every other hop in this kernel costs. That is what lets a
        recycle loop close without a simultaneous solve: the ring simply
        fills up over a few scans, exactly as a real one does.
        """
        net = self._network
        previous = self._node_streams
        arriving: list[list[Stream]] = [[] for _ in net.pressures]
        for branch in net.branches:
            q = branch.flow_lps
            if abs(q) < 1e-12:
                continue
            if q > 0.0:
                arriving[branch.node_b].append(previous[branch.node_a].with_flow(q))
            else:
                arriving[branch.node_a].append(previous[branch.node_b].with_flow(-q))
        fresh = [Stream.mix_all(parts) for parts in arriving]

        # A source of material overrides what the pipes brought: a
        # vessel discharging supplies its own contents, not whatever
        # happened to be in the line.
        for component in self.components:
            for name, port in component.material_ports().items():
                supplied = component.supplied_stream(name)
                if supplied is not None and port.flow_lps < -1e-12:
                    fresh[port.node] = supplied.with_flow(-port.flow_lps)

        # A line with nothing moving in it still holds what it last
        # held. Forgetting would make a restarted pump briefly deliver
        # water it never contained.
        for i, stream in enumerate(fresh):
            if not stream.is_flowing:
                fresh[i] = previous[i].with_flow(0.0)
        # A vessel's contents tap holds the contents whether or not
        # anything moves: a probe on the shell reads what is in the
        # vessel. After the memory step, because nothing flows there.
        for component in self.components:
            for name in component.standing_ports():
                port = component.material_ports().get(name)
                supplied = component.supplied_stream(name)
                if port is not None and supplied is not None and port.flow_lps > -1e-12:
                    fresh[port.node] = supplied.with_flow(0.0)
        for tap_node, watched in self._tap_source.items():
            fresh[tap_node] = fresh[watched]
            net.pressures[tap_node] = net.pressures[watched]
        self._node_streams = fresh

        for component in self.components:
            taps = component.tap_ports()
            for name, port in component.material_ports().items():
                if name in taps:
                    # A tap reports the line, rate included, without
                    # taking any of it.
                    port.value = fresh[port.node]
                else:
                    port.value = fresh[port.node].with_flow(abs(port.flow_lps))

    def connect(
        self, src: Component, out_name: str, dst: Component, in_name: str
    ) -> Wire:
        wire = Wire(src.outputs[out_name], dst.inputs[in_name])
        self.wires.append(wire)
        self._network_stale = True
        return wire

    def disconnect(
        self, src: Component, out_name: str, dst: Component, in_name: str
    ) -> bool:
        """Remove one wire between two ports (the physical act of
        pulling a run). Frees the input's single-source slot; the input
        reverts to its default on the next scan. False if no such wire."""
        out_port = src.outputs.get(out_name)
        in_port = dst.inputs.get(in_name)
        if out_port is None or in_port is None:
            return False
        for wire in self.wires:
            if wire.src is out_port and wire.dst is in_port:
                self.wires.remove(wire)
                in_port.wire_count -= 1
                self._network_stale = True
                return True
        return False

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
        self._network_stale = True
        if self.historian is not None:
            active = set(self.historian.active_tags)
            for tag, _read in self._tags_of(component):
                if tag in active:
                    self.historian.retire(tag)
        return True

    @staticmethod
    def _tags_of(component: Component) -> list[tuple[str, Callable[[], float]]]:
        """Every historian tag one component contributes.

        Scalar outputs are one tag each. A stream output is not a
        number, so it fans out into the numbers an operator would
        actually trend: its rate, its temperature, how much of it is
        solid, and the fraction of each species in it. Composition
        becomes real historized data rather than something a display
        has to infer.
        """
        tags: list[tuple[str, Callable[[], float]]] = []
        for port in component.outputs.values():
            if port.kind is PortKind.PROCESS_MATERIAL:
                path = port.path
                tags.append((f"{path}.flow", lambda p=port: float(p.flow_lps)))
                tags.append((f"{path}.temp", lambda p=port: float(p.value.temp_c)))
                tags.append(
                    (f"{path}.solids", lambda p=port: float(p.value.solids_frac))
                )
                for key in SPECIES_KEYS:
                    tags.append(
                        (f"{path}.x_{key}", lambda p=port, k=key: float(p.value.frac(k)))
                    )
            else:
                tags.append((port.path, lambda p=port: float(p.value)))
        for obs_name, attr in component.observables.items():
            tags.append(
                (
                    f"{component.name}.{obs_name}",
                    lambda c=component, a=attr: float(getattr(c, a)),
                )
            )
        return tags

    def register_with_historian(self, component: Component) -> None:
        """Register one component's tags (for equipment added after the
        historian was attached — mid-run placement)."""
        if self.historian is None:
            return
        for tag, read in self._tags_of(component):
            self.historian.register(tag, read)

    def attach_historian(self, historian: Historian) -> Historian:
        """Register every output port and observable as a tag, then take
        the t=0 baseline sample. Attach after the graph is built."""
        for component in self.components:
            for tag, read in self._tags_of(component):
                historian.register(tag, read)
        self.historian = historian
        historian.sample(self.time)
        return historian

    def tick(self) -> None:
        # Signals first, so a valve knows its command and a pump knows
        # whether it is running before the network is solved on them.
        for component in self.components:
            for port in component.inputs.values():
                port.reset()
        for wire in self.wires:
            wire.propagate()
        # Then solve the hydraulics: what actually flows, and which way.
        self._solve_hydraulics()
        # Then let the components act on it.
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
