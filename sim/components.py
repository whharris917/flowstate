"""The basic loop's components: tank, float switch, relay, pump.

Together they close the fill loop: the pump fills the
tank, the float switch reads the level, the relay carries the switch's
contact to the pump motor. The float switch's two trip levels are the
hysteresis lesson — set them apart and the pump cycles calmly, set them
equal and it chatters (watch the relay's cycle counter climb).
"""
from __future__ import annotations

import math

from sim.core import Component, PortKind
from sim.hydraulics import (
    ControlResistance, NozzleResistance, PumpCurve, Resistance, static_head_pa,
)
from sim.library import Equation, EquipmentSpec, Param
from sim.stream import AMBIENT_C, Stream


class Tank(Component):
    """Holds liquid, and knows what the liquid is.

    Two nozzles, and the difference between them is where they are.
    Each stands at a height on the shell, and what it feels is
    where it stands against the liquid: under the surface it carries
    the static head of whatever is standing above it -- which is why a
    full tank will drain into an empty one through nothing but a pipe
    -- and above it it sits at headspace pressure, so a line can fall
    in but nothing can come back out. The defaults put the outlet on
    the floor and the inlet at the roof; the game sets both where the
    player welded them, so a tank keeps a heel below its outlet.

    Inflow is blended into the inventory: the contents take a
    volume-weighted temperature and composition, which is what makes a
    hot stream genuinely warm a vessel. Whatever leaves does so at the
    current contents composition.
    """

    LOSS_PER_S = 0.0002

    def __init__(
        self,
        name: str,
        capacity_l: float,
        level_l: float = 0.0,
        drain_lps: float = 0.0,
        height_m: float = 0.0,
        diameter_m: float = 0.0,
        temp_c: float = AMBIENT_C,
        comp: dict[str, float] | None = None,
        headspace_kpa: float = 0.0,
        elevation_m: float = 0.0,
        nozzle_cv_lps: float = 20.0,
        open_top: bool = False,
        nozzle_h_m: dict[str, float] | None = None,
        nozzle_dn: dict[str, int] | None = None,
    ) -> None:
        super().__init__(name)
        if capacity_l <= 0.0:
            raise ValueError("capacity_l must be positive")
        # An open-topped vessel: a line ending in the air above it lands
        # what it spills here. Nothing else changes: the headspace is
        # atmospheric either way.
        self.open_top = bool(open_top)
        self._falling = Stream.empty()
        if level_l < 0.0:
            raise ValueError("level_l must be non-negative")
        if nozzle_cv_lps <= 0.0:
            raise ValueError("nozzle_cv_lps must be positive")
        self.capacity_l = capacity_l
        self.level_l = level_l
        self.drain_lps = drain_lps
        self.headspace_kpa = headspace_kpa
        self.elevation_m = elevation_m
        self.nozzle_cv_lps = nozzle_cv_lps  # both nozzles, at DN50
        # Where each nozzle stands on the shell, metres above the base
        # (AT_ROOF for the roof, whatever the height), and its nominal
        # size: a nozzle takes the size of the line on it, and its Cv
        # scales with the bore's area from the DN50 figure above.
        self.nozzle_h_m: dict[str, float] = {"inlet": self.AT_ROOF, "outlet": 0.0}
        self.nozzle_dn: dict[str, int] = {"inlet": 50, "outlet": 50}
        for port, h in (nozzle_h_m or {}).items():
            self.set_nozzle(port, height_m=h)
        for port, dn in (nozzle_dn or {}).items():
            self.set_nozzle(port, dn=dn)
        if height_m > 0.0 and diameter_m > 0.0:
            self.height_m = height_m
            self.diameter_m = diameter_m
            self.capacity_l = math.pi * (diameter_m / 2.0) ** 2 * height_m * 1000.0
            self.level_l = min(self.level_l, self.capacity_l)
        elif height_m > 0.0:
            self.height_m = height_m
            self.diameter_m = 2.0 * math.sqrt(
                capacity_l / 1000.0 / (math.pi * height_m))
        else:
            self.diameter_m = (4.0 * capacity_l / 1000.0 / (1.4 * math.pi)) ** (1.0 / 3.0)
            self.height_m = 1.4 * self.diameter_m
        if self.level_l > self.capacity_l:
            raise ValueError("level_l must be within [0, capacity_l]")
        self.temp_c = float(temp_c)
        self.contents = Stream(self.level_l, self.temp_c, comp)
        self.overflowed_l = 0.0
        self.ran_dry_ticks = 0
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self.level = self.add_output("level", PortKind.PROCESS_LEVEL)
        self.level.value = level_l
        # The contents tap: a probe mounted on the shell reads what the
        # vessel holds through it. No branch, no flow, just the contents.
        self.contents_tap = self.add_output("contents", PortKind.PROCESS_MATERIAL)
        self.add_observable("overflowed_l", "overflowed_l")
        self.add_observable("ran_dry_ticks", "ran_dry_ticks")
        self.add_observable("temp_c", "temp_c")
        self.add_observable("depth_m", "depth_m")

    @property
    def comp(self) -> dict[str, float]:
        return self.contents.comp

    @property
    def solids_frac(self) -> float:
        return self.contents.solids_frac

    @property
    def cross_section_m2(self) -> float:
        return math.pi * (self.diameter_m / 2.0) ** 2

    @property
    def depth_m(self) -> float:
        """How deep the liquid stands. This is what the outlet nozzle
        feels, and what a level transmitter is really measuring."""
        return (self.level_l / 1000.0) / max(self.cross_section_m2, 1e-9)

    def species_l(self, key: str) -> float:
        return self.level_l * self.contents.frac(key)

    def set_size(self, height_m: float, diameter_m: float) -> None:
        if height_m <= 0.0 or diameter_m <= 0.0:
            raise ValueError("height and diameter must be positive")
        self.height_m = height_m
        self.diameter_m = diameter_m
        self.capacity_l = math.pi * (diameter_m / 2.0) ** 2 * height_m * 1000.0
        self.level_l = min(self.level_l, self.capacity_l)

    def charge(self, volume_l: float, comp: dict[str, float],
               temp_c: float = AMBIENT_C) -> None:
        self.level_l = min(max(volume_l, 0.0), self.capacity_l)
        self.temp_c = temp_c
        self.contents = Stream(self.level_l, temp_c, comp)
        self.level.value = self.level_l

    def standing_ports(self) -> set[str]:
        return {"contents"}

    def _feed_ports(self):
        return ("inlet",)

    def _headspace_pa(self) -> float:
        return self.headspace_kpa * 1000.0

    #: Flow a DN50 nozzle passes at the reference drop.
    OUTLET_CV_LPS = 20.0
    #: Depth over which a nozzle uncovers as the level falls past it.
    #: Smooth, so an emptying vessel tails off instead of chattering
    #: shut.
    UNCOVER_M = 0.03
    #: A nozzle height meaning "at the roof", whatever the height is.
    AT_ROOF = -1.0
    #: The reference bore: the size nozzle_cv_lps is quoted at.
    NOZZLE_DN_REF = 50

    def nozzle_ports(self) -> tuple[str, ...]:
        return self._feed_ports() + ("outlet",)

    def set_nozzle(self, port: str, height_m: float | None = None,
                   dn: int | None = None) -> None:
        """Where a nozzle stands on the shell, metres above the base,
        and its nominal size. Either may be left as it is."""
        if port not in self.nozzle_ports():
            raise ValueError("no nozzle %r" % port)
        if height_m is not None:
            self.nozzle_h_m[port] = (self.AT_ROOF if height_m == self.AT_ROOF
                                     else max(float(height_m), 0.0))
        if dn is not None:
            if dn <= 0:
                raise ValueError("dn must be positive")
            self.nozzle_dn[port] = int(dn)

    def nozzle_height(self, port: str) -> float:
        """Metres above the base, never above the roof."""
        h = self.nozzle_h_m.get(port, 0.0)
        if h == self.AT_ROOF:
            return self.height_m
        return min(h, self.height_m)

    def nozzle_cv(self, port: str) -> float:
        """What the nozzle passes wide open across the reference drop:
        the DN50 figure scaled by the bore's area."""
        return self.nozzle_cv_lps * (self.nozzle_dn.get(port, 50) / self.NOZZLE_DN_REF) ** 2

    def nozzle_submergence(self, port: str) -> float:
        """0 with the level below the nozzle, 1 with it well above,
        ramping over UNCOVER_M between."""
        return min(max((self.depth_m - self.nozzle_height(port)) / self.UNCOVER_M, 0.0), 1.0)

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        # One boundary node per nozzle, at the pressure the nozzle
        # feels where it stands; one nozzle branch each.
        self._nozzle_nodes: dict[str, int] = {}
        self._nozzle_branches: dict[str, NozzleResistance] = {}
        for port in self.nozzle_ports():
            self._nozzle_nodes[port] = net.add_node(0.0, fixed=True)
            self._nozzle_branches[port] = net.add_branch(NozzleResistance(
                self._nozzle_nodes[port], node[port], self.nozzle_cv(port),
                "%s.%s" % (self.name, port)))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        # Piezometric, so a submerged nozzle at any height reads the
        # same as the floor: headspace plus the head of the whole
        # depth. Above the liquid it reads headspace at its own height,
        # and passes nothing out.
        headspace_pa = self._headspace_pa()
        depth = self.depth_m
        for port in self.nozzle_ports():
            h = self.nozzle_height(port)
            net.set_pressure(self._nozzle_nodes[port],
                             headspace_pa + static_head_pa(self.elevation_m + max(depth, h)),
                             fixed=True)
            branch = self._nozzle_branches[port]
            branch.set_cv(self.nozzle_cv(port))
            branch.submergence = self.nozzle_submergence(port)


    def supplied_stream(self, port_name: str) -> Stream:
        return self.contents.with_flow(1.0)

    def receive(self, stream: Stream) -> None:
        """Material falling in through the open top this scan, L/s at a
        composition: an open pipe end above the vessel hands its spill
        here, and the next tick blends it in like any other arrival."""
        if stream.flow_lps > 0.0:
            self._falling = Stream.mix(self._falling, stream)

    def tick(self, dt: float) -> None:
        # Both nozzles are signed into the vessel, so one balance covers
        # filling, draining, and a line that reversed on us.
        net_lps = self.inlet.flow_lps + self.outlet.flow_lps
        arriving = Stream.mix_all([
            port.stream.with_flow(port.flow_lps)
            for port in (self.inlet, self.outlet) if port.flow_lps > 0.0
        ])
        if self._falling.flow_lps > 0.0:
            arriving = Stream.mix(arriving, self._falling)
            net_lps += self._falling.flow_lps
            self._falling = Stream.empty()
        added_l = arriving.flow_lps * dt
        leaving_l = max(-net_lps + arriving.flow_lps, 0.0) * dt
        demand_l = (self.drain_lps * dt) + leaving_l
        if demand_l > self.level_l + added_l + 1e-9:
            self.ran_dry_ticks += 1

        if added_l > 0.0:
            self.contents = Stream.mix(
                self.contents.with_flow(self.level_l),
                arriving.with_flow(added_l),
            )
        new_level = self.level_l + added_l - min(demand_l, self.level_l + added_l)
        if new_level > self.capacity_l:
            self.overflowed_l += new_level - self.capacity_l
            new_level = self.capacity_l
        self.level_l = max(new_level, 0.0)

        self.temp_c = self.contents.temp_c
        self.temp_c -= (self.temp_c - AMBIENT_C) * self.LOSS_PER_S * dt
        self.contents = self.contents.with_flow(self.level_l).with_temp(self.temp_c)
        self.level.value = self.level_l


class Gauge(Component):
    """Local indicator plus analog transmitter output.

    Four kinds, all honest derivations of existing process state:
      - "level_kpa": hydrostatic head at a vessel bottom. The process
        level (liters) becomes height via liters_per_meter, and
        P = rho*g*h (water) in kPa.
      - "flow": an inline meter the line runs through: inlet and outlet
        nozzles, a little resistance, and the flow that passes as the
        reading. A flow element has to sit in the line.
      - "temp_c": inline temperature, read off the same stream.
      - "conc_pct": inline composition — the percentage of one species
        in the line. Until one of these is on the line, nobody can say
        anything true about quality.
      - "dp_pa": differential pressure between two pressure taps
        (process_a - process_b), Pa — the cleanroom Magnehelic.
      - "press_kpa": a single pressure tap. PROCESS_PRESSURE ports
        carry Pa everywhere; this dial is scaled in kPa.
      - "line_kpa": a pressure gauge tapped into a pipe at any point
        along it. It is cut into the line like
        the flow element, but its inlet and outlet are one hydraulic
        node, so it costs the line nothing; it reads that node's static
        pressure at its own height, kPa gauge.

    The reading is mirrored on an analog signal output so it can later
    feed controllers — a gauge today, a transmitter when wired.
    """

    KINDS = {
        "level_kpa": PortKind.PROCESS_LEVEL,
        "flow": PortKind.PROCESS_MATERIAL,
        "temp_c": PortKind.PROCESS_MATERIAL,
        "conc_pct": PortKind.PROCESS_MATERIAL,
        "dp_pa": PortKind.PROCESS_PRESSURE,
        "press_kpa": PortKind.PROCESS_PRESSURE,
        "line_kpa": PortKind.PROCESS_MATERIAL,
    }
    UNITS = {
        "level_kpa": "kPa",
        "flow": "L/s",
        "temp_c": "C",
        "conc_pct": "%",
        "dp_pa": "Pa",
        "press_kpa": "kPa",
        "line_kpa": "kPa",
    }
    WATER_KPA_PER_M = 9.81
    #: The kinds that tap a line rather than a signal. A tap observes
    #: without carrying: piping a thermowell into a header must not put
    #: a hole in it. The flow kind is not one: its element sits in the
    #: line, so it has an inlet and an outlet and costs a little head.
    TAP_KINDS = {"temp_c", "conc_pct"}
    #: What an inline meter costs the line, Pa per (L/s)^2.
    METER_K = 1000.0

    def __init__(
        self,
        name: str,
        kind: str,
        liters_per_meter: float = 45.45,
        species: str = "product",
        meter_k: float = METER_K,
        elevation_m: float = 0.0,
        range_kpa: float = 600.0,
    ) -> None:
        super().__init__(name)
        if kind not in self.KINDS:
            raise ValueError(f"kind must be one of {sorted(self.KINDS)}")
        if liters_per_meter <= 0.0:
            raise ValueError("liters_per_meter must be positive")
        if meter_k <= 0.0:
            raise ValueError("meter_k must be positive")
        self.kind = kind
        self.liters_per_meter = liters_per_meter
        self.meter_k = meter_k  # the flow kind: size the element to its line
        self.species = species  # which species a "conc_pct" analyser reads
        self.reading = 0.0
        self.total_l = 0.0  # the flow kind totalizes forward flow
        # The line kind: where it stands, for the static pressure it
        # reads, and the top of its dial.
        self.elevation_m = float(elevation_m)
        self.range_kpa = float(range_kpa)
        self._net = None
        self._node = -1
        if kind == "dp_pa":
            self.process_a = self.add_input("process_a", self.KINDS[kind])
            self.process_b = self.add_input("process_b", self.KINDS[kind])
        elif kind in ("flow", "line_kpa"):
            self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
            self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        else:
            self.process = self.add_input("process", self.KINDS[kind])
        self.signal = self.add_output("signal", PortKind.SIGNAL_ANALOG)
        self.add_observable("reading", "reading")
        if kind == "flow":
            self.add_observable("total_l", "total_l")

    def tap_ports(self) -> set[str]:
        return {"process"} if self.kind in self.TAP_KINDS else set()

    def shared_node_ports(self) -> list[list[str]]:
        # A tapping is a hole in the pipe wall, not a restriction: the
        # line either side of it is one node.
        return [["inlet", "outlet"]] if self.kind == "line_kpa" else []

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        if self.kind == "flow":
            net.add_branch(Resistance(node["inlet"], node["outlet"],
                                      self.meter_k, self.name))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        if self.kind == "line_kpa":
            # Read after the solve, in tick, so the dial is this scan's.
            self._net = net
            self._node = node["inlet"]

    def units(self) -> str:
        return self.UNITS[self.kind]

    def tick(self, dt: float) -> None:
        if self.kind == "dp_pa":
            self.reading = float(self.process_a.value) - float(self.process_b.value)
        elif self.kind == "level_kpa":
            self.reading = (
                float(self.process.value) / self.liters_per_meter * self.WATER_KPA_PER_M
            )
        elif self.kind == "press_kpa":
            self.reading = float(self.process.value) / 1000.0
        elif self.kind == "line_kpa":
            # Static, at the gauge's own height (every gauge shows static
            # pressure): the node is piezometric.
            if self._net is not None and 0 <= self._node < len(self._net.pressures):
                pa = self._net.pressures[self._node] - static_head_pa(self.elevation_m)
                self.reading = pa / 1000.0
        elif self.kind == "flow":
            # Signed: positive is forward through the meter.
            self.reading = self.inlet.flow_lps
            self.total_l += max(self.reading, 0.0) * dt
        elif self.kind == "temp_c":
            self.reading = self.process.stream.temp_c
        else:  # conc_pct
            self.reading = self.process.stream.frac(self.species) * 100.0
        self.signal.value = self.reading


class Source(Component):
    """Supply header: a utility tie-in at the edge of the modelled
    plant — the honest root of every flow path, the way MainsFeed is for
    power.

    A header is three things and nothing else: what it carries, how hot
    it is, and what pressure it holds. There is no inlet, because from
    the plant's point of view there is nothing upstream — just a
    reservoir deep enough to hold the pressure whatever you draw. And
    there is no draw port either: what leaves is whatever the network
    pulls out of it, and the meter reads that.
    """

    def __init__(
        self,
        name: str,
        species: str = "water",
        temp_c: float = AMBIENT_C,
        pressure_kpa: float = 400.0,
        comp: dict[str, float] | None = None,
        elevation_m: float = 0.0,
    ) -> None:
        super().__init__(name)
        self.temp_c = float(temp_c)
        self.pressure_kpa = float(pressure_kpa)
        self.elevation_m = float(elevation_m)
        # A single species by default; ``comp`` overrides it for a
        # header that carries a premixed feed.
        self.comp = dict(comp) if comp else {species: 1.0}
        self.total_l = 0.0
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self.add_observable("total_l", "total_l")
        self.add_observable("delivered_lps", "delivered_lps")

    @property
    def delivered_lps(self) -> float:
        """What the plant is drawing right now. Negative flow at the
        nozzle means material leaving, which is the normal direction."""
        return max(-self.outlet.flow_lps, 0.0)

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        net.set_pressure(
            node["outlet"],
            self.pressure_kpa * 1000.0 + static_head_pa(self.elevation_m),
            fixed=True)

    def supplied_stream(self, port_name: str) -> Stream:
        return Stream(1.0, self.temp_c, self.comp)

    def tick(self, dt: float) -> None:
        self.total_l += self.delivered_lps * dt


class Drain(Component):
    """Where material leaves the plant: a nozzle, a valve, and a pipe to
    sewer.

    It has no magic rate. Its valve has a Cv like any other, and what
    goes down it is whatever the head above it pushes through -- so a
    nearly empty vessel drains slowly, as one does. Shut it and it
    passes nothing.
    """

    def __init__(self, name: str, rate_lps: float = 1.0,
                 elevation_m: float = 0.0) -> None:
        super().__init__(name)
        if rate_lps <= 0.0:
            raise ValueError("rate_lps must be positive")
        self.rate_lps = rate_lps
        self.elevation_m = elevation_m
        self.is_open = True
        self.total_l = 0.0
        self.lost_product_l = 0.0
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self._branch = None
        self.add_observable("total_l", "total_l")
        self.add_observable("lost_product_l", "lost_product_l")
        self.add_observable("flow_lps", "flow_lps")

    @property
    def flow_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        # The far side of the drain valve is the sewer: atmospheric, and
        # it will take whatever it is given, and give nothing back: an
        # open drain under suction draws air.
        self._sewer = net.add_node(static_head_pa(self.elevation_m), fixed=True)
        self._branch = net.add_branch(ControlResistance(
            node["inlet"], self._sewer, self.rate_lps, self.name, one_way=True))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        # The sewer's height is refreshed every scan, like every other
        # boundary, so a drain moved after it was built vents where it
        # now stands rather than where it stood when the network was
        # laid out.
        net.set_pressure(self._sewer, static_head_pa(self.elevation_m), fixed=True)
        if self._branch is not None:
            self._branch.cv_lps = self.rate_lps
            self._branch.opening = 1.0 if self.is_open else 0.0

    def tick(self, dt: float) -> None:
        taken = self.flow_lps
        self.total_l += taken * dt
        # The product it swallows is the number that hurts: yield lost
        # to sewer, on a trend, where nothing else will tell you.
        self.lost_product_l += taken * self.inlet.stream.frac("product") * dt


class MainsFeed(Component):
    """The plant's electrical feeder: one always-energized POWER output
    at its voltage class. Load accounting and breakers arrive with the
    power-monitoring tier; for now this is the honest root of every
    power circuit — nothing runs without a cable back to a feed.
    """

    def __init__(self, name: str, spec: str = "480VAC", ways: int = 8) -> None:
        super().__init__(name)
        if ways < 1:
            raise ValueError("ways must be at least 1")
        self.spec = spec
        self.ways = ways
        # One numbered way per load: a terminal
        # takes one cable, so a feeder that serves N loads has N ways.
        self.way_ports = [self.add_output(f"way{i + 1}", PortKind.POWER, spec)
                          for i in range(ways)]
        for port in self.way_ports:
            port.value = 1.0

    def tick(self, dt: float) -> None:
        for port in self.way_ports:
            port.value = 1.0


class Tee(Component):
    """A pipe fitting whose nozzles are one hydraulic node: pressures
    equal, flows summing to zero, composition the flow-weighted blend
    of what arrives. A splitter has one inlet and three outlets, a
    mixer three inlets and one outlet, on four separated nozzles; an
    unused nozzle is capped. It exists because a nozzle takes one
    line: joining and splitting is a fitting's
    job, with its own connection points.
    """

    MODES = ("split", "mix")

    def __init__(self, name: str, mode: str = "split") -> None:
        super().__init__(name)
        if mode not in self.MODES:
            raise ValueError("mode must be 'split' or 'mix'")
        self.mode = mode
        if mode == "split":
            self.add_input("in", PortKind.PROCESS_MATERIAL)
            for leg in ("a", "b", "c"):
                self.add_output(leg, PortKind.PROCESS_MATERIAL)
        else:
            for leg in ("a", "b", "c"):
                self.add_input(leg, PortKind.PROCESS_MATERIAL)
            self.add_output("out", PortKind.PROCESS_MATERIAL)

    def shared_node_ports(self) -> list[list[str]]:
        return [list(self.material_ports().keys())]

    def tick(self, dt: float) -> None:
        pass


class Cap(Component):
    """A pipe cap: a two-nozzle fitting that is one hydraulic node, a
    blind end while only one nozzle carries a line and a plain
    coupling once both do. A cut leaves one on each side of the cut,
    so a cut line is capped until it is connected again. A node with one branch carries no
    flow, so a capped line stands at pressure and moves nothing.
    """

    VENT_CV_LPS = 60.0  # an open bore: the line's own resistance limits the spill

    def __init__(self, name: str, elevation_m: float = 0.0) -> None:
        super().__init__(name)
        self.add_input("a", PortKind.PROCESS_MATERIAL)
        self.add_output("b", PortKind.PROCESS_MATERIAL)
        # Open: an open pipe end, venting to the
        # air at its own height, spilling and totalling what arrives.
        self.open = False
        self.elevation_m = elevation_m
        self.spilled_l = 0.0
        # What lands in an open vessel below. The plant names the vessel; the kernel hands it the stream.
        self.catch = None
        self.delivered_l = 0.0
        self._vent = None
        self.add_observable("spilled_l", "spilled_l")
        self.add_observable("delivered_l", "delivered_l")

    def shared_node_ports(self) -> list[list[str]]:
        return [list(self.material_ports().keys())]

    def spill_lps(self) -> float:
        if not self.open or self._vent is None:
            return 0.0
        return max(self._vent.flow_lps, 0.0)

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        self._air = net.add_node(static_head_pa(self.elevation_m), fixed=True)
        # One-way: below the air at its height an open end draws air,
        # not water; two-way, a raised end would draw water in from
        # nowhere.
        self._vent = net.add_branch(ControlResistance(
            node["a"], self._air, self.VENT_CV_LPS, self.name, one_way=True))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        # The air the end vents to is at the end's height as it stands
        # now, refreshed every scan like every other boundary.
        net.set_pressure(self._air, static_head_pa(self.elevation_m), fixed=True)
        if self._vent is not None:
            self._vent.cv_lps = self.VENT_CV_LPS
            self._vent.opening = 1.0 if self.open else 0.0

    def lands(self) -> bool:
        """Whether the spill has somewhere to go: an open-topped vessel
        under the end. Otherwise it is lost to the ground and counted."""
        return self.catch is not None and getattr(self.catch, "open_top", False)

    def tick(self, dt: float) -> None:
        q = self.spill_lps()
        if q <= 0.0:
            return
        if self.lands():
            self.catch.receive(self.inputs["a"].stream.with_flow(q))
            self.delivered_l += q * dt
        else:
            self.spilled_l += q * dt

    def state_dict(self) -> dict:
        return {"open": self.open, "spilled_l": self.spilled_l,
                "delivered_l": self.delivered_l, "elevation_m": self.elevation_m}

    def apply_state(self, state: dict) -> None:
        self.open = bool(state.get("open", self.open))
        self.spilled_l = float(state.get("spilled_l", self.spilled_l))
        self.delivered_l = float(state.get("delivered_l", self.delivered_l))
        self.elevation_m = float(state.get("elevation_m", self.elevation_m))


class SplitTee(Tee):
    """A tee with one inlet and three outlets: the library's splitter."""

    def __init__(self, name: str) -> None:
        super().__init__(name, mode="split")


class MixTee(Tee):
    """A tee with three inlets and one outlet: the library's mixer."""

    def __init__(self, name: str) -> None:
        super().__init__(name, mode="mix")


class PowerSupply(Component):
    """Control power supply: 480VAC in, 24VDC out. The cabinet's PSU —
    controllers ride on it, and it dies with its feeder."""

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.ac_in = self.add_input("ac_in", PortKind.POWER, "480VAC")
        self.dc_out = self.add_output("dc_out", PortKind.POWER, "24VDC")

    def tick(self, dt: float) -> None:
        self.dc_out.value = 1.0 if float(self.ac_in.value) > 0.5 else 0.0


class PowerDistribution(Component):
    """A fused 24 V distribution strip: one supply in, a numbered fused
    way per load out. A terminal takes one cable, so a supply that serves
    N loads does it through N ways of one of these.
    """

    def __init__(self, name: str, ways: int = 8) -> None:
        super().__init__(name)
        if ways < 1:
            raise ValueError("ways must be at least 1")
        self.ways = ways
        self.dc_in = self.add_input("in", PortKind.POWER, "24VDC")
        self.way_ports = [self.add_output(f"way{i + 1}", PortKind.POWER, "24VDC")
                          for i in range(ways)]

    def tick(self, dt: float) -> None:
        live = 1.0 if float(self.dc_in.value) > 0.5 else 0.0
        for port in self.way_ports:
            port.value = live


class ControlValve(Component):
    """Air-actuated control valve: a 0-100 % command through a
    first-order positioner onto a trim that follows the valve equation.

        Q = Cv * f(x) * sqrt(dP / dP_ref)

    Which means its authority is real. Put it in a line whose own
    resistance dominates and opening it further buys almost nothing --
    the classic badly-sized valve, and a thing the player can
    actually diagnose.
    """

    def __init__(self, name: str, cv_lps: float = 6.0, tau_s: float = 1.0,
                 elevation_m: float = 0.0) -> None:
        super().__init__(name)
        if cv_lps <= 0.0:
            raise ValueError("cv_lps must be positive")
        if tau_s <= 0.0:
            raise ValueError("tau_s must be positive")
        self.cv_lps = cv_lps
        self.tau_s = tau_s
        self.position = 0.0  # percent, follows the command with a lag
        # The height of its nozzles above grade. The drop across a valve
        # is the same whichever way the pressures are reckoned, so the
        # elevation changes no flow; it is what makes the static
        # pressure at the valve, which a gauge there reads, honest.
        self.elevation_m = float(elevation_m)
        self.inlet_pa = 0.0    # static, at the valve's own height
        self.outlet_pa = 0.0
        self.cmd = self.add_input("cmd", PortKind.SIGNAL_ANALOG)
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self._branch = None
        self.add_observable("position", "position")
        self.add_observable("flow_lps", "flow_lps")

    @property
    def flow_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        self._branch = net.add_branch(ControlResistance(
            node["inlet"], node["outlet"], self.cv_lps, self.name))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        if self._branch is not None:
            self._branch.cv_lps = self.cv_lps
            self._branch.opening = self.position / 100.0
        datum = static_head_pa(self.elevation_m)
        self.inlet_pa = net.pressures[node["inlet"]] - datum
        self.outlet_pa = net.pressures[node["outlet"]] - datum

    def tick(self, dt: float) -> None:
        target = max(0.0, min(100.0, float(self.cmd.value)))
        self.position += (target - self.position) * dt / self.tau_s


class BlockValve(Component):
    """On/off block valve with a stroking actuator: one discrete command,
    a fixed travel time from seat to full open, and a trim that follows
    the valve equation the whole way.

        Q = Cv * (x/100) * sqrt(dP / dP_ref)

    This is the valve a sequence uses -- open it, wait for it to
    travel, move to the next step -- rather than one a controller
    throttles. For stroke_s after the command changes it is neither open
    nor shut, and a sequence that does not wait for that has a leak in
    it.
    """

    def __init__(self, name: str, cv_lps: float = 20.0, stroke_s: float = 4.0,
                 elevation_m: float = 0.0) -> None:
        super().__init__(name)
        if cv_lps <= 0.0:
            raise ValueError("cv_lps must be positive")
        if stroke_s <= 0.0:
            raise ValueError("stroke_s must be positive")
        self.cv_lps = cv_lps
        self.stroke_s = stroke_s
        self.position = 0.0  # percent of travel: 0 shut, 100 open
        self.hand_open = False  # the handwheel, when nothing is wired to "open"
        self.elevation_m = float(elevation_m)  # nozzle height; see ControlValve
        self.inlet_pa = 0.0    # static, at the valve's own height
        self.outlet_pa = 0.0
        self.open_cmd = self.add_input("open", PortKind.SIGNAL_DISCRETE)
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        # Limit switches on the actuator: dry contacts that make at the
        # ends of travel, so a sequence can wait for the valve to report
        # open rather than trusting the stroke time.
        self.zso = self.add_output("zso", PortKind.SIGNAL_DISCRETE)
        self.zsc = self.add_output("zsc", PortKind.SIGNAL_DISCRETE)
        self.zsc.value = 1.0
        self._branch = None
        self.add_observable("position", "position")
        self.add_observable("flow_lps", "flow_lps")

    LIMIT_BAND = 2.0  # percent of travel within which a limit contact makes

    @property
    def limit_open(self) -> bool:
        return self.position >= 100.0 - self.LIMIT_BAND

    @property
    def limit_closed(self) -> bool:
        return self.position <= self.LIMIT_BAND

    @property
    def flow_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    @property
    def commanded_open(self) -> bool:
        # Nothing wired to the command makes it a hand valve: the
        # operator's own setting is the command (Tier 0).
        if self.open_cmd.wire_count == 0:
            return self.hand_open
        return float(self.open_cmd.value) > 0.5

    @property
    def is_hand_operated(self) -> bool:
        return self.open_cmd.wire_count == 0

    @property
    def state(self) -> str:
        if self.position >= 99.5:
            return "OPEN"
        if self.position <= 0.5:
            return "CLOSED"
        return "OPENING" if self.commanded_open else "CLOSING"

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        self._branch = net.add_branch(ControlResistance(
            node["inlet"], node["outlet"], self.cv_lps, self.name))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        if self._branch is not None:
            self._branch.cv_lps = self.cv_lps
            self._branch.opening = self.position / 100.0
        datum = static_head_pa(self.elevation_m)
        self.inlet_pa = net.pressures[node["inlet"]] - datum
        self.outlet_pa = net.pressures[node["outlet"]] - datum

    def tick(self, dt: float) -> None:
        target = 100.0 if self.commanded_open else 0.0
        step = 100.0 * dt / self.stroke_s
        if self.position < target:
            self.position = min(target, self.position + step)
        elif self.position > target:
            self.position = max(target, self.position - step)
        self.zso.value = 1.0 if self.limit_open else 0.0
        self.zsc.value = 1.0 if self.limit_closed else 0.0


class Pushbutton(Component):
    """A pushbutton on a local control station. Momentary by default:
    the contact follows the button while it is held, which in a scanned
    plant means for a short hold after a press. A maintained button (a
    selector) toggles on each press. Normally closed for a STOP, so the
    circuit is made until someone presses it -- the seal-in a start/stop
    station relies on.
    """

    HOLD_S = 0.6

    def __init__(self, name: str, momentary: bool = True,
                 normally_closed: bool = False) -> None:
        super().__init__(name)
        self.momentary = momentary
        self.normally_closed = normally_closed
        self.pressed = False       # maintained: the latched position
        self._hold_left = 0.0      # momentary: seconds still held
        self.contact = self.add_output("contact", PortKind.SIGNAL_DISCRETE)
        self.add_observable("pressed", "pressed")
        self.presses = 0
        self.add_observable("presses", "presses")
        self.tick(0.0)

    def press(self) -> None:
        """A finger on the button: a hold for a momentary one, a toggle
        for a maintained one."""
        self.presses += 1
        if self.momentary:
            self._hold_left = self.HOLD_S
            self.pressed = True
        else:
            self.pressed = not self.pressed

    def tick(self, dt: float) -> None:
        if self.momentary:
            self._hold_left = max(0.0, self._hold_left - dt)
            self.pressed = self._hold_left > 0.0
        made = self.pressed != self.normally_closed
        self.contact.value = 1.0 if made else 0.0


class PilotLight(Component):
    """A pilot light: lit while its lamp circuit is energized, nothing
    more. The thing on a station that tells an operator what the PLC
    believes without a screen."""

    def __init__(self, name: str, color: str = "green") -> None:
        super().__init__(name)
        self.color = color
        self.lamp = self.add_input("lamp", PortKind.SIGNAL_DISCRETE)
        self.add_observable("lit", "lit")

    @property
    def lit(self) -> bool:
        return float(self.lamp.value) > 0.5

    def tick(self, dt: float) -> None:
        pass


class Terminal(Component):
    """One terminal block: in to out, one scan late — the honest cost
    of landing a wire on a strip. kind is "discrete" or "analog".
    """

    KINDS = {"discrete": PortKind.SIGNAL_DISCRETE, "analog": PortKind.SIGNAL_ANALOG}

    def __init__(self, name: str, kind: str = "discrete") -> None:
        super().__init__(name)
        if kind not in self.KINDS:
            raise ValueError(f"kind must be one of {sorted(self.KINDS)}")
        self.kind = kind
        self.t_in = self.add_input("in", self.KINDS[kind])
        self.t_out = self.add_output("out", self.KINDS[kind])

    def tick(self, dt: float) -> None:
        self.t_out.value = self.t_in.value


class Column(Component):
    """Batch distillation column at total reflux.

    The sump charge heats under the reboiler duty; at the boiling point
    the surplus duty becomes boilup, and vapor arriving faster than the
    condenser vent passes it raises the overhead pressure — a
    first-order lag that settles where boilup equals vent flow. Total
    reflux for now: the condenser returns everything, so the charge is
    conserved and the column is a pure temperature/pressure machine.
    Product draws arrive with composition modelling in a later tier.

    ``p_top`` is gauge pressure in Pa (PROCESS_PRESSURE ports carry Pa
    everywhere). At full duty the overhead settles near 40 kPa in a few
    pressure time constants; the sump ships in hot standby so the
    response is watchable within seconds of raising the duty.
    """

    DUTY_STEPS = (0.0, 0.5, 1.0)
    BOIL_C = 78.0
    AMBIENT_C = 20.0
    CP_KJ_PER_KG_K = 4.0
    LATENT_KJ_PER_KG = 850.0
    VENT_KG_PER_S_PA = 2.94e-6  # condenser/vent conductance
    PRESSURE_TAU_S = 30.0       # overhead pressure first-order lag
    COOL_TAU_S = 1800.0         # passive cooling with the duty off

    def __init__(
        self,
        name: str,
        charge_l: float = 60.0,
        max_duty_kw: float = 100.0,
        temp_c: float = 74.0,
    ) -> None:
        super().__init__(name)
        if charge_l <= 0.0:
            raise ValueError("charge_l must be positive")
        if max_duty_kw <= 0.0:
            raise ValueError("max_duty_kw must be positive")
        self.charge_l = charge_l
        self.max_duty_kw = max_duty_kw
        self.temp_c = temp_c
        self.duty_frac = 0.0
        self.duty_kw = 0.0
        self.boilup_kgps = 0.0
        self.p_top_pa = 0.0
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.p_top = self.add_output("p_top", PortKind.PROCESS_PRESSURE)
        self.add_observable("temp_c", "temp_c")
        self.add_observable("duty_kw", "duty_kw")
        self.add_observable("boilup_kgps", "boilup_kgps")

    def set_duty(self, frac: float) -> None:
        if not 0.0 <= frac <= 1.0:
            raise ValueError("duty fraction must be within [0, 1]")
        self.duty_frac = frac

    def tick(self, dt: float) -> None:
        powered = float(self.power.value) > 0.5
        self.duty_kw = self.duty_frac * self.max_duty_kw if powered else 0.0
        mass_kg = self.charge_l  # aqueous charge, ~1 kg/L
        if self.duty_kw > 0.0 and self.temp_c < self.BOIL_C:
            rise = self.duty_kw / (mass_kg * self.CP_KJ_PER_KG_K) * dt
            self.temp_c = min(self.BOIL_C, self.temp_c + rise)
            self.boilup_kgps = 0.0
        elif self.duty_kw > 0.0:
            self.boilup_kgps = self.duty_kw / self.LATENT_KJ_PER_KG
        else:
            self.temp_c += (self.AMBIENT_C - self.temp_c) * dt / self.COOL_TAU_S
            self.boilup_kgps = 0.0
        self.p_top_pa += (
            self.boilup_kgps / self.VENT_KG_PER_S_PA - self.p_top_pa
        ) / self.PRESSURE_TAU_S * dt
        self.p_top.value = self.p_top_pa


class AirCascade(Component):
    """Room-pressure cascade for a cleanroom suite.

    Rooms hold gauge pressure (Pa) fed by constant HVAC supply;
    air leaks between rooms (and to ambient) through doors. A closed
    door leaks a little; an open door leaks a lot — open both doors of
    an airlock and the cascade collapses, which the DP gauges will
    show. Linear leak model, one pressure output port per room.

    rooms: [{"id", "volume_m3", "supply_lps"}]
    doors: [{"id", "a", "b", "leak_closed", "leak_open"}]
           where a/b are room ids or "ambient" (0 Pa).
    """

    PRESSURE_RATE = 10.0  # Pa per (L/s imbalance) per m3, per second

    def __init__(self, name: str, rooms: list[dict], doors: list[dict]) -> None:
        super().__init__(name)
        if not rooms:
            raise ValueError("cascade needs at least one room")
        self.rooms = {r["id"]: dict(r) for r in rooms}
        self.doors = {d["id"]: dict(d) for d in doors}
        self.pressures: dict[str, float] = {rid: 0.0 for rid in self.rooms}
        self.door_open: dict[str, bool] = {did: False for did in self.doors}
        for door in self.doors.values():
            for end in (door["a"], door["b"]):
                if end != "ambient" and end not in self.rooms:
                    raise ValueError(f"door references unknown room {end!r}")
        self._ports = {
            rid: self.add_output(f"p_{rid}", PortKind.PROCESS_PRESSURE)
            for rid in self.rooms
        }

    def set_door(self, door_id: str, is_open: bool) -> None:
        if door_id not in self.door_open:
            raise ValueError(f"unknown door {door_id!r}")
        self.door_open[door_id] = is_open

    def is_door_open(self, door_id: str) -> bool:
        return self.door_open[door_id]

    def _pressure_of(self, end: str) -> float:
        return 0.0 if end == "ambient" else self.pressures[end]

    def tick(self, dt: float) -> None:
        # Semi-implicit update: each room's own pressure is implicit,
        # neighbors are explicit (Jacobi step). Unconditionally stable
        # even with the huge leak coefficient of an open door.
        sum_c = {rid: 0.0 for rid in self.rooms}
        sum_cp = {rid: 0.0 for rid in self.rooms}
        for did, door in self.doors.items():
            coeff = (
                float(door.get("leak_open", 80.0))
                if self.door_open[did]
                else float(door.get("leak_closed", 3.0))
            )
            a, b = door["a"], door["b"]
            if a != "ambient":
                sum_c[a] += coeff
                sum_cp[a] += coeff * self._pressure_of(b)
            if b != "ambient":
                sum_c[b] += coeff
                sum_cp[b] += coeff * self._pressure_of(a)
        new_pressures = {}
        for rid, room in self.rooms.items():
            gain = self.PRESSURE_RATE / float(room["volume_m3"]) * dt
            supply = float(room["supply_lps"])
            new_pressures[rid] = (
                self.pressures[rid] + gain * (supply + sum_cp[rid])
            ) / (1.0 + gain * sum_c[rid])
        for rid in self.rooms:
            self.pressures[rid] = new_pressures[rid]
            self._ports[rid].value = new_pressures[rid]

    def state_dict(self) -> dict:
        return {"pressures": dict(self.pressures), "doors": dict(self.door_open)}

    def apply_state(self, state: dict) -> None:
        for rid, value in state.get("pressures", {}).items():
            if rid in self.pressures:
                self.pressures[rid] = float(value)
                self._ports[rid].value = self.pressures[rid]
        for did, value in state.get("doors", {}).items():
            if did in self.door_open:
                self.door_open[did] = bool(value)


class FloatSwitch(Component):
    """Level switch with mechanical hysteresis, wired to call for fill.

    Contact closes when the level falls to ``low_l``, opens when it rises
    to ``high_l``, and holds its state in between. ``low_l == high_l``
    is a valid single-setpoint switch — the one that chatters.
    """

    def __init__(self, name: str, low_l: float, high_l: float) -> None:
        super().__init__(name)
        self.low_l = 0.0
        self.high_l = 0.0
        self.set_band(low_l, high_l)
        self.closed = False
        self.level_in = self.add_input("level", PortKind.PROCESS_LEVEL)
        self.contact = self.add_output("contact", PortKind.SIGNAL_DISCRETE)

    def set_band(self, low_l: float, high_l: float) -> None:
        if low_l > high_l:
            raise ValueError("low_l must be <= high_l")
        self.low_l = low_l
        self.high_l = high_l

    def tick(self, dt: float) -> None:
        level = float(self.level_in.value)
        if level <= self.low_l:
            self.closed = True
        elif level >= self.high_l:
            self.closed = False
        self.contact.value = self.closed


class Relay(Component):
    """Electromechanical relay: coil in, normally-open contact out.

    ``cycles`` counts energizations — the wear metric that makes chatter
    visible as a number instead of a feeling.
    """

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.energized = False
        self.cycles = 0
        self.coil = self.add_input("coil", PortKind.SIGNAL_DISCRETE)
        self.contact = self.add_output("contact", PortKind.SIGNAL_DISCRETE)
        self.add_observable("cycles", "cycles")

    def tick(self, dt: float) -> None:
        coil = bool(self.coil.value)
        if coil and not self.energized:
            self.cycles += 1
        self.energized = coil
        self.contact.value = self.energized


class Pump(Component):
    """Centrifugal transfer pump with a Hand-Off-Auto selector.

    It has a curve, so it does not simply deliver its rating: it finds
    its own operating point against whatever the system puts in front of
    it. Ask it to lift more than its shutoff head and it dead-heads --
    the motor turns, the discharge valve is open, and nothing moves.
    Two in parallel do not double the flow. Run it against a suction
    that cannot keep up and the suction node falls toward vacuum, which
    is what ``cavitating`` reports.
    """

    MODES = ("hand", "off", "auto")
    #: Suction pressure below which the pump is cavitating rather than
    #: pumping. Crude stand-in for NPSH.
    CAVITATION_PA = -60_000.0

    def __init__(self, name: str, rated_lps: float, mode: str = "auto",
                 head_m: float = 30.0, elevation_m: float = 0.0) -> None:
        super().__init__(name)
        if rated_lps <= 0.0:
            raise ValueError("rated_lps must be positive")
        if head_m <= 0.0:
            raise ValueError("head_m must be positive")
        self.rated_lps = rated_lps
        self.head_m = head_m
        # The height of its nozzles above grade. The network solves
        # piezometric pressures, so the static suction a gauge on the
        # pump reads, and prime and cavitation are judged on, is the
        # node's pressure less rho*g*elevation: a pump at the top of a
        # rise is not the pump at the bottom of it.
        self.elevation_m = float(elevation_m)
        self.mode = "auto"
        self.set_mode(mode)
        self.running = False
        self.starts = 0
        self.dry_run_s = 0.0
        self.cavitating = False
        self.suction_pa = 0.0
        self.discharge_pa = 0.0
        self.run = self.add_input("run", PortKind.SIGNAL_DISCRETE)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self._branch = None
        self.add_observable("starts", "starts")
        self.add_observable("dry_run_s", "dry_run_s")
        self.add_observable("flow_lps", "flow_lps")
        self.add_observable("head_pa", "head_pa")

    @property
    def flow_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    @property
    def head_pa(self) -> float:
        """The rise it is actually making right now."""
        return self.discharge_pa - self.suction_pa

    def set_mode(self, mode: str) -> None:
        if mode not in self.MODES:
            raise ValueError(f"mode must be one of {self.MODES}")
        self.mode = mode

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        self._branch = net.add_branch(PumpCurve(
            node["inlet"], node["outlet"],
            static_head_pa(self.head_m), self.rated_lps, self.name))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        if self.mode == "hand":
            wants = True
        elif self.mode == "off":
            wants = False
        else:
            wants = bool(self.run.value)
        # No 480 V at the starter, no motor — hand mode included.
        self.running = wants and float(self.power.value) > 0.5
        datum = static_head_pa(self.elevation_m)
        if self._branch is not None:
            self._branch.running = self.running
            self._branch.head_pa = max(static_head_pa(self.head_m), 1e-12)
            self._branch.max_lps = max(self.rated_lps, 1e-12)
            self._branch.datum_pa = datum
        # Static pressures at the pump's own height: what its gauges read.
        self.suction_pa = net.pressures[node["inlet"]] - datum
        self.discharge_pa = net.pressures[node["outlet"]] - datum

    def tick(self, dt: float) -> None:
        was_running = getattr(self, "_was_running", False)
        if self.running and not was_running:
            self.starts += 1
        self._was_running = self.running
        self.cavitating = self.running and self.suction_pa <= self.CAVITATION_PA
        if self.running and self.flow_lps < 1e-6:
            self.dry_run_s += dt


# ---------------------------------------------------------------------
# Library pages. The only copy of these equations; see sim/library.py.
# ---------------------------------------------------------------------

Tank.SPEC = EquipmentSpec(
    key="tank",
    title="Storage Tank",
    tier="process",
    summary=(
        "Holds liquid, and knows what the liquid is. Anything arriving "
        "blends into the contents, so a hot stream genuinely warms the "
        "vessel and a reagent charge genuinely changes what is in it. "
        "What leaves does so at whatever the contents currently are. "
        "Overfill it and it spills, and the spill is counted.\n\n"
        "Its two nozzles differ only in where they stand on the shell, "
        "and that is the whole of its hydraulic behaviour. A nozzle under "
        "the liquid carries the head of everything standing above it; "
        "one above the liquid sits at headspace pressure and passes "
        "nothing out. Which is why a full tank will drain into an empty "
        "one through nothing but a pipe, why filling one through a top "
        "nozzle never has to fight its own level, and why a vessel keeps "
        "a heel below its outlet."
    ),
    ports={
        "inlet": "A nozzle, at the roof unless it was welded lower. Above "
                 "the liquid it cannot flow backwards; once the level is "
                 "over it, it carries head like any other.",
        "level": "Level tap, in litres, for a switch or a transmitter.",
        "contents": "Internal tap of the contents that a temperature probe "
                    "mounted on the shell reads. Nothing flows through it; "
                    "it holds what the vessel holds.",
        "outlet": "A nozzle, on the floor unless it was welded higher. "
                  "Under the liquid it carries the static head; material "
                  "goes whichever way the network solves, and charging a "
                  "vessel up through it is normal. It stops passing "
                  "anything out once the level has fallen past it.",
    },
    equations=(
        Equation(
            "P_nozzle = P_headspace + rho*g*(z + max(depth, h))",
            "The boundary pressure the network sees at a nozzle standing "
            "h above the base. Piezometric, so a submerged nozzle reads "
            "the same at any height, and elevation costs head without "
            "the solver ever learning what elevation is.",
        ),
        Equation(
            "Cv_nozzle = nozzle_cv_lps * (DN / 50)^2",
            "A nozzle takes the size of the line on it, and passes flow "
            "in proportion to its bore's area.",
        ),
        Equation(
            "dV/dt = F_inlet + F_outlet  (both signed into the vessel)",
            "One balance covers filling, draining, and a line that "
            "reversed on you.",
        ),
        Equation(
            "x_new = (V*x + F_in*dt*x_in) / (V + F_in*dt)",
            "Incoming material blends by volume. What leaves and what "
            "overflows both go at the contents composition, so neither "
            "changes it -- only the inflow does.",
        ),
        Equation(
            "T_new = (V*T + F_in*dt*T_in) / (V + F_in*dt)",
            "Temperature blends the same way.",
        ),
        Equation(
            "submergence = clamp((depth - h) / 0.03 m, 0, 1)",
            "A nozzle uncovers as the level falls past it, so a vessel "
            "tails off instead of siphoning itself dry. Smooth, so it "
            "does not chatter shut. Inflow is never limited by it.",
        ),
    ),
    params=(
        Param("capacity_l", "L", "Volume before it overflows. Follows the "
                                 "geometry if you give height and diameter."),
        Param("level_l", "L", "Starting inventory."),
        Param("drain_lps", "L/s", "A standing leak off the inventory, for "
                                  "standing in for an unmodelled user. "
                                  "Not a nozzle: it takes no head."),
        Param("height_m", "m", "Shell height. Sets capacity with diameter, "
                               "and where a nozzle at the roof sits."),
        Param("diameter_m", "m", "Shell diameter."),
        Param("temp_c", "C", "Starting temperature of the contents."),
        Param("comp", "-", "Starting composition, as species fractions."),
        Param("headspace_kpa", "kPa", "Blanket pressure over the liquid. "
                                      "Adds to both nozzles equally."),
        Param("nozzle_cv_lps", "L/s", "What a DN50 nozzle passes wide open "
                                      "across a 1 bar drop; a nozzle of "
                                      "another size scales with its bore's "
                                      "area. The default suits a few litres "
                                      "a second; a line carrying tens needs "
                                      "a bigger vessel nozzle as much as a "
                                      "bigger pipe."),
        Param("nozzle_h_m", "m", "Where each nozzle stands on the shell, "
                                 "above the base: the outlet on the floor "
                                 "and the inlet at the roof unless set "
                                 "otherwise (set_nozzle)."),
        Param("nozzle_dn", "DN", "Each nozzle's nominal size, the size of "
                                 "the line on it."),
        Param("elevation_m", "m", "Height of the vessel floor above grade. "
                                  "This is what buys you gravity flow."),
        Param("open_top", "yes/no", "An open-topped vessel: a line ending in "
                                    "the air above it lands what it spills here."),
    ),
    assumptions=(
        "Perfectly mixed: one temperature and one composition throughout, "
        "so there is no stratification and no settling.",
        "Heat loss is a single first-order term, not an insulation model.",
        "The headspace is a fixed pressure, not a gas volume: filling the "
        "vessel does not compress it and draining does not pull vacuum.",
        "Only the two nozzles exist. There is no vent line, no overflow "
        "nozzle you can pipe, and a spill just leaves the model.",
        "A nozzle is a point at a height. It has no diameter of its own "
        "against the level: the 3 cm it uncovers over stands in for that.",
    ),
)

Pump.SPEC = EquipmentSpec(
    key="pump",
    title="Centrifugal Transfer Pump",
    tier="process",
    summary=(
        "Adds head to a line, and then finds its own operating point "
        "against whatever the system puts in front of it. It does not "
        "deliver its rating on demand: open the discharge and it runs "
        "out along its curve, throttle it and it walks back up. Ask it "
        "to lift more than its shutoff head and it dead-heads -- the "
        "motor turns, the valve is open, and nothing moves.\n\n"
        "A Hand-Off-Auto selector decides where the run command comes "
        "from, exactly like the switch on a real motor starter, and none "
        "of the three positions do anything without 480 V at the starter."
    ),
    ports={
        "run": "Run command in Auto. Ignored in Hand and Off.",
        "power": "480 V to the starter. No power, no motor, Hand included.",
        "inlet": "Suction nozzle. Pipe it to whatever it pulls from; the "
                 "pressure it finds there is what decides whether it "
                 "cavitates.",
        "outlet": "Discharge nozzle, one head rise above the suction, at "
                  "the same temperature and composition.",
    },
    equations=(
        Equation(
            "running = (Hand) or (Auto and run) , and powered",
            "The selector, then the starter.",
        ),
        Equation(
            "dP = H0 * (1 - (Q/Qmax)^2)",
            "The curve. Shutoff head at no flow, falling away as the "
            "square of flow, so two in parallel do not double the flow "
            "and a longer line genuinely costs you rate.",
        ),
        Equation(
            "H0 = rho*g*head_m ,  Qmax = 1.35 * rated_lps",
            "What you sized it for: shutoff head from the head rating, "
            "and a runout cap a third above rated flow.",
        ),
        Equation(
            "Q = 0 when not running",
            "A stopped pump shuts its line. That is not what a real one "
            "does -- see the assumptions.",
        ),
        Equation(
            "Q >= 0 always",
            "It never runs backwards, however the pressures fall out.",
        ),
        Equation(
            "dry_run_s += dt   when running with no flow",
            "The wear metric that makes a mistake provable afterwards.",
        ),
    ),
    params=(
        Param("rated_lps", "L/s", "Flow at the rated point. Runout is a "
                                  "third above it."),
        Param("head_m", "m", "Shutoff head, as metres of liquid. This is "
                             "the lift it cannot exceed however long you "
                             "run it."),
        Param("mode", "-", "Hand, Off, or Auto."),
        Param("elevation_m", "m", "Height of its nozzles above grade, taken "
                                  "from where it stands. Its suction gauge "
                                  "reads the static pressure there, and a "
                                  "pump high above its supply loses prime "
                                  "where the same pump at grade would not."),
    ),
    assumptions=(
        "One generic curve shape for every pump. No published curve, no "
        "impeller trim, no speed control.",
        "No efficiency and no best-efficiency point, so running far off "
        "rated costs nothing in power or in wear.",
        "Cavitation is a suction-pressure taper, not NPSH available "
        "against NPSH required -- the species table carries no vapour "
        "pressure to compute one from. It loses its curve over the last "
        "20 kPa above a hard vacuum and delivers nothing at the bottom, "
        "which is what makes a pump on an empty vessel stop rather than "
        "keep insisting. The `cavitating` flag trips earlier than that, "
        "so it warns before the flow has gone.",
        "No start ramp -- it is on its curve on the scan it starts.",
        "It is its own check valve, in both directions: stopped, it "
        "blocks the line completely, and running, it will not reverse "
        "however the pressures fall out. A real centrifugal does neither "
        "-- it freewheels backwards under discharge head, which is why "
        "real trains carry check valves this plant does not need.",
    ),
)

ControlValve.SPEC = EquipmentSpec(
    key="control_valve",
    title="Control Valve",
    tier="control",
    summary=(
        "An air-actuated valve that follows a 0-100 % command with a "
        "positioner lag, onto a trim that obeys the valve equation. "
        "Which means its authority is real: half open is not half the "
        "flow, and a valve sized far larger than the line it sits in "
        "buys you almost nothing for the last half of its travel. That "
        "is the classic badly-sized loop, and here it is something the "
        "player can actually diagnose from a trend."
    ),
    ports={
        "cmd": "Position command, 0-100 %, from a controller or an HMI.",
        "inlet": "Upstream nozzle.",
        "outlet": "Downstream nozzle, at the same temperature and "
                  "composition -- a valve changes rate, not material.",
    },
    equations=(
        Equation(
            "dx/dt = (cmd - x) / tau",
            "The positioner chases the command first-order. This lag is "
            "what a controller has to tune around.",
        ),
        Equation(
            "Q = Cv * (x/100) * sqrt(dP / 100 kPa)",
            "The valve equation. Flow follows the square root of the "
            "drop across the valve, so it is the rest of the system, not "
            "the command alone, that decides what gets through.",
        ),
        Equation(
            "Q = 0 when x = 0",
            "Shut is shut: it holds against any drop the network puts "
            "across it.",
        ),
    ),
    params=(
        Param("cv_lps", "L/s", "The size of the valve: what it passes "
                               "wide open across a 1 bar drop. Not US Cv "
                               "(gpm at 1 psi) and not metric Kv."),
        Param("tau_s", "s", "Positioner time constant."),
        Param("elevation_m", "m", "Height of its nozzles above grade, taken "
                                  "from where it stands. The drop across the "
                                  "valve does not depend on it; the static "
                                  "pressure a gauge at the valve reads does."),
    ),
    assumptions=(
        "Linear trim only -- no equal-percentage or quick-opening "
        "characteristic, so the installed characteristic comes entirely "
        "from the line it sits in.",
        "No seat leakage, no hysteresis, no stiction, no dead band.",
        "It resists in both directions equally and will not check "
        "reverse flow.",
        "No actuator fail position: cut the command and it goes to zero, "
        "rather than to fail-open or fail-closed.",
    ),
)

BlockValve.SPEC = EquipmentSpec(
    key="block_valve",
    title="Block Valve",
    tier="control",
    summary=(
        "An on/off valve with a stroking actuator: one discrete command, "
        "a fixed travel time from seat to full open, and a trim that "
        "follows the valve equation the whole way. It is the valve a "
        "sequence uses -- open it, wait for it to travel, move to the "
        "next step -- rather than one a controller throttles. Its "
        "position and flow are historized, so a valve that was told to "
        "open and did not is a fact on a trend rather than a mystery."
    ),
    ports={
        "open": "Discrete command: energized opens, de-energized closes. "
                "Land a PLC output, a relay contact or a switch here. "
                "Leave it unwired and this is a hand valve: the operator "
                "opens and shuts it at the handwheel.",
        "inlet": "Upstream nozzle.",
        "outlet": "Downstream nozzle, at the same temperature and "
                  "composition -- a valve changes rate, not material.",
        "zso": "Open limit switch: a dry contact that makes in the last "
               "2 % of travel. Wire it to a PLC input and a step can wait "
               "for the valve to report open.",
        "zsc": "Closed limit switch: makes in the first 2 % of travel. "
               "Both off means the valve is somewhere in between.",
    },
    equations=(
        Equation(
            "dx/dt = +100/stroke_s opening, -100/stroke_s closing",
            "The actuator travels at a fixed rate, so for stroke_s after "
            "the command changes the valve is neither open nor shut. A "
            "sequence that does not wait for that has a leak in it.",
        ),
        Equation(
            "Q = Cv * (x/100) * sqrt(dP / 100 kPa)",
            "The valve equation with the travel fraction as the opening. "
            "The head across it decides what flows, not the command.",
        ),
        Equation(
            "Q = 0 when x = 0",
            "Shut is shut: it holds against any drop the network puts "
            "across it.",
        ),
    ),
    params=(
        Param("cv_lps", "L/s", "The size of the valve: what it passes "
                               "wide open across a 1 bar drop. Not US Cv "
                               "(gpm at 1 psi) and not metric Kv."),
        Param("stroke_s", "s", "Seat to full open, and back."),
        Param("elevation_m", "m", "Height of its nozzles above grade, taken "
                                  "from where it stands. The drop across the "
                                  "valve does not depend on it; the static "
                                  "pressure a gauge at the valve reads does."),
    ),
    assumptions=(
        "Linear travel and a linear trim: a real ball or gate valve "
        "passes most of its flow in the first part of its travel.",
        "No limit switches, so a sequence trusts the stroke time rather "
        "than an open or closed contact.",
        "No seat leakage, no stiction, and no fail position: lose the "
        "signal and it closes at stroke speed.",
        "It resists in both directions equally and will not check "
        "reverse flow.",
    ),
)

Source.SPEC = EquipmentSpec(
    key="source",
    title="Supply Header",
    tier="utility",
    summary=(
        "A utility tie-in at the edge of the modelled plant -- the "
        "honest root of every flow path, the way a mains feeder is for "
        "power. A header is three things and nothing else: what it "
        "carries, how hot it is, and what pressure it holds.\n\n"
        "It has one nozzle. There is no inlet, because from the plant's "
        "point of view there is nothing upstream. And there is no draw "
        "port either: nothing announces what it took, because what "
        "leaves is whatever the network pulls out, and the meter simply "
        "reads that."
    ),
    ports={
        "outlet": "The tie-in nozzle. Holds its rated pressure whatever "
                  "you draw, and the meter keeps a running total of "
                  "what left through it.",
    },
    equations=(
        Equation(
            "P_outlet = pressure_kpa + rho*g*z   (fixed)",
            "A boundary node. The header holds this pressure no matter "
            "what is hung off it -- which is what makes a higher-pressure "
            "header genuinely deliver more.",
        ),
        Equation(
            "total += max(-F_outlet, 0) * dt",
            "The meter. Flow at a nozzle is signed into the component, "
            "so material leaving reads negative; this is the number a "
            "mass balance is checked against.",
        ),
    ),
    params=(
        Param("species", "-", "What the header carries."),
        Param("temp_c", "C", "Storage temperature."),
        Param("pressure_kpa", "kPa", "The pressure it holds at the tie-in. "
                                     "This, and the resistance of what you "
                                     "pipe to it, is what sets the flow."),
        Param("comp", "-", "Full composition, for a premixed feed."),
        Param("elevation_m", "m", "Height of the tie-in above grade."),
    ),
    assumptions=(
        "Infinite availability and a perfectly stiff pressure: the header "
        "never runs out and never sags, however much you pull.",
        "It cannot be pushed into. Piping a running pump at it will not "
        "back material up the utility system.",
        "One fixed composition and temperature -- a header does not "
        "change with the season or with what its own supply is doing.",
    ),
)

Drain.SPEC = EquipmentSpec(
    key="drain",
    title="Drain / Sewer Connection",
    tier="utility",
    summary=(
        "Where material leaves the plant: a nozzle, a valve, and a pipe "
        "to sewer. It has no magic rate -- its valve has a Cv like any "
        "other, and what goes down it is whatever the head above it "
        "pushes through. So a nearly empty vessel drains slowly, as one "
        "does, and a deep one runs fast and then tails off.\n\n"
        "It meters everything it swallows, and separately how much "
        "product you sent down it, which is the number that hurts."
    ),
    ports={
        "inlet": "The line to sewer. Pipe a vessel bottom, a separator's "
                 "waste, or a relief blowdown into it -- it is the same "
                 "nozzle either way.",
    },
    equations=(
        Equation(
            "Q = rate_lps * open * sqrt(dP / 100 kPa)",
            "The drain valve, following the same valve equation as any "
            "other. Shut it and it holds.",
        ),
        Equation(
            "P_sewer = rho*g*z   (fixed)",
            "The far side of the valve is atmosphere at the drain's own "
            "elevation, and it will take whatever it is given.",
        ),
        Equation(
            "lost_product += F * x_product * dt",
            "Yield to sewer, on a trend. Nothing else in the plant will "
            "tell you about this.",
        ),
    ),
    params=(
        Param("rate_lps", "L/s", "Size of the drain valve: what it passes "
                                 "wide open across a 1 bar drop, not a "
                                 "rate it is guaranteed to achieve."),
        Param("elevation_m", "m", "Height of the sewer connection. Put it "
                                  "below what you are draining."),
    ),
    assumptions=(
        "The sewer is an infinite sink at atmospheric pressure: it never "
        "backs up and never floods.",
        "The drain valve does not check. Set the sewer connection above "
        "what it serves and its own static head will push back up the "
        "line -- correct arithmetic, but not a drain any longer.",
        "Nothing is recovered and nothing is treated -- material down "
        "here is simply gone, and only the meters remember it.",
    ),
)

Gauge.SPEC = EquipmentSpec(
    key="gauge",
    title="Gauge / Transmitter",
    tier="control",
    summary=(
        "A local indicator that is also a transmitter. It reads one "
        "honest derivation of the process it is tapped into and mirrors "
        "it on an analog output, so it is a dial today and a measurement "
        "the moment you wire it. Every reading here is a real conversion "
        "of real sim state; nothing is smoothed or invented."
    ),
    ports={
        "process": "The tap, for the tapped kinds: a level, a thermowell, "
                   "an analyser sample, a pressure tapping.",
        "inlet": "Inline flow meter or line pressure gauge, upstream "
                 "side. The line runs through it.",
        "outlet": "Inline flow meter or line pressure gauge, downstream "
                  "side.",
        "process_a": "High-side tap on a differential gauge.",
        "process_b": "Low-side tap on a differential gauge.",
        "signal": "The reading, mirrored as a 4-20 mA analog output.",
    },
    equations=(
        Equation(
            "P = level / L_per_m * rho*g      [level_kpa]",
            "Hydrostatic head at a vessel bottom, in kPa.",
        ),
        Equation(
            "reading = F                      [flow]",
            "The flow that actually passes through the element, signed "
            "forward.",
        ),
        Equation(
            "dP = K * F^2                     [flow]",
            "An inline element costs the line a little pressure, like "
            "any fitting.",
        ),
        Equation(
            "total += max(F, 0) * dt          [flow]",
            "The totalizer: forward flow integrated since the meter was "
            "placed. What a batch was, not only what it is.",
        ),
        Equation(
            "reading = T                      [temp_c]",
            "Temperature of the stream in the line.",
        ),
        Equation(
            "reading = x_species * 100        [conc_pct]",
            "The analyser. Until one of these is on the line, nobody can "
            "say anything true about quality.",
        ),
        Equation(
            "reading = P_a - P_b              [dp_pa]",
            "Differential pressure across two taps.",
        ),
        Equation(
            "reading = (P_node - rho*g*z) / 1000   [line_kpa]",
            "A tapping in a pipe: the static pressure of the line at the "
            "point the gauge stands, kPa gauge. Its inlet and outlet are "
            "one node, so it costs the line nothing.",
        ),
    ),
    params=(
        Param("kind", "-", "level_kpa, flow, temp_c, conc_pct, dp_pa, "
                           "press_kpa or line_kpa."),
        Param("liters_per_meter", "L/m", "Vessel cross-section, for "
                                         "turning level into head."),
        Param("species", "-", "Which species an analyser reads."),
        Param("meter_k", "Pa/(L/s)^2", "What the inline element costs the "
                                       "line, for the flow kind. Size it to "
                                       "the line: about 10 to 30 kPa at "
                                       "design flow."),
        Param("elevation_m", "m", "The line kind's height, for the static "
                                  "pressure it reads."),
        Param("range_kpa", "kPa", "The line kind's dial: full scale."),
    ),
    assumptions=(
        "No sensor lag, no noise, no drift, no calibration error. The "
        "gauge reads the process exactly.",
    ),
)

FloatSwitch.SPEC = EquipmentSpec(
    key="float_switch",
    title="Level Switch",
    tier="control",
    summary=(
        "A mechanical level switch with two trip points. The contact "
        "closes on falling level at the low point and opens on rising "
        "level at the high one, holding its state in between. Set the "
        "two apart and a pump cycles calmly; set them equal and it "
        "chatters -- which is a valid configuration, and the lesson."
    ),
    ports={
        "level": "Level tap from the vessel it watches.",
        "contact": "Dry contact, closed when calling for fill.",
    },
    equations=(
        Equation(
            "closed = true   when level <= low",
            "Calls for fill on falling level.",
        ),
        Equation(
            "closed = false  when level >= high",
            "Drops out on rising level. Between the two it holds -- that "
            "gap is the hysteresis.",
        ),
    ),
    params=(
        Param("low_l", "L", "Level at which the contact closes."),
        Param("high_l", "L", "Level at which it opens again."),
    ),
    assumptions=("Instant, bounce-free switching at an exact level.",),
)

Relay.SPEC = EquipmentSpec(
    key="relay",
    title="Interposing Relay",
    tier="control",
    summary=(
        "Coil in, contact out, one scan later. It counts its own "
        "energizations, which is what turns pump chatter from a feeling "
        "into a number you can put on a trend."
    ),
    ports={
        "coil": "Coil. Several contacts landing here behave as parallel "
                "contacts and OR together.",
        "contact": "Normally-open contact, following the coil.",
    },
    equations=(
        Equation(
            "contact = coil   (one scan later)",
            "The scan delay is deliberate: it is what real relay and PLC "
            "latency looks like, and what makes chatter reproducible.",
        ),
        Equation(
            "cycles += 1  on each rising edge",
            "The wear counter.",
        ),
    ),
    assumptions=("No contact bounce, no pickup or dropout delay, no "
                 "welded contacts.",),
)

MainsFeed.SPEC = EquipmentSpec(
    key="mains_feed",
    title="Mains Feeder",
    tier="utility",
    summary=(
        "The plant's electrical supply: numbered always-energized ways at "
        "its voltage class, one per load. The honest root of every power "
        "circuit -- nothing in the plant runs without a cable back to one "
        "of these, and a way takes one cable."
    ),
    ports={f"way{i}": f"Way {i}: energized supply at the feeder's voltage "
                      "class, for one load."
           for i in range(1, 9)},
    equations=(
        Equation("way_n = 1 always", "No load accounting or breakers yet."),
    ),
    params=(
        Param("spec", "-", "Voltage class, e.g. 480VAC."),
        Param("ways", "-", "How many loads it can feed; set when placed."),
    ),
    assumptions=(
        "Infinite capacity: no breaker, no load accounting, no volt drop. "
        "Every way carries whatever you hang on it.",
    ),
)

SplitTee.SPEC = EquipmentSpec(
    key="tee_split",
    title="Tee -- Splitter",
    tier="utility",
    summary=(
        "A pipe fitting whose nozzles are one point in the network: the "
        "same pressure at every leg, flows that add to zero. One inlet "
        "and three outlets on separated nozzles; an unused leg is "
        "capped. It exists because a nozzle takes one line -- joining "
        "and splitting is a fitting's job, and the split is whatever the "
        "resistances downstream make of it."
    ),
    ports={
        "in": "Inlet: the line being split.",
        "a": "Outlet, straight through.",
        "b": "Outlet, the near side leg.",
        "c": "Outlet, the far side leg.",
    },
    equations=(
        Equation("P_in = P_a = P_b = P_c",
                 "One node: every leg sees the same pressure."),
        Equation("Q_in = Q_a + Q_b + Q_c",
                 "What comes in leaves; each leg takes what its own run's "
                 "resistance and destination allow."),
    ),
    params=(),
    assumptions=(
        "No pressure drop through the fitting itself: the legs' runs carry "
        "the resistance.",
        "A capped leg is a dead nozzle, not a leak.",
    ),
)

MixTee.SPEC = EquipmentSpec(
    key="tee_mix",
    title="Tee -- Mixer",
    tier="utility",
    summary=(
        "A pipe fitting whose nozzles are one point in the network: the "
        "same pressure at every leg, and the flow-weighted blend of "
        "whatever arrives. Three inlets on separated nozzles, one "
        "outlet; an unused leg is capped. It exists because a nozzle "
        "takes one line -- joining is a fitting's job."
    ),
    ports={
        "a": "Inlet, straight through.",
        "b": "Inlet, the near side leg.",
        "c": "Inlet, the far side leg.",
        "out": "Outlet: the blend.",
    },
    equations=(
        Equation("P_a = P_b = P_c = P_out",
                 "One node: every leg sees the same pressure."),
        Equation("x_out = sum(Q_i x_i) / sum(Q_i)",
                 "The blend, flow-weighted, one scan later like every "
                 "other hop. Temperature and solids blend the same way."),
    ),
    params=(),
    assumptions=(
        "No pressure drop through the fitting itself: the legs' runs carry "
        "the resistance.",
        "Perfect mixing at the node: no stratification, no dead leg.",
    ),
)

PowerSupply.SPEC = EquipmentSpec(
    key="power_supply",
    title="Control Power Supply",
    tier="utility",
    summary=(
        "The cabinet PSU: 480 V in, 24 V out. Controllers ride on it, "
        "and it dies with its feeder."
    ),
    ports={
        "ac_in": "480 V supply from a feeder.",
        "dc_out": "24 V control power.",
    },
    equations=(
        Equation("dc_out = 1 if ac_in else 0", "It passes through or it "
                                               "does not."),
    ),
    assumptions=("No current rating, no ride-through, no inrush.",),
)

PowerDistribution.SPEC = EquipmentSpec(
    key="power_distribution",
    title="24 V Distribution Strip",
    tier="utility",
    summary=(
        "A row of fused terminals on the cabinet rail: the cabinet's 24 V "
        "supply comes in once and leaves on a numbered way per field load, "
        "so one supply powers the whole line."
    ),
    ports={"in": "24 V from a power supply.",
           **{f"way{i}": f"Way {i}: 24 V to one field load." for i in range(1, 9)}},
    equations=(
        Equation("way_n = in", "Every way is live while the supply is."),
    ),
    params=(
        Param("ways", "-", "How many loads it can feed."),
    ),
    assumptions=(
        "No fuse ratings: a way never blows, and the supply has no current "
        "limit.",
    ),
)

Pushbutton.SPEC = EquipmentSpec(
    key="pushbutton",
    title="Pushbutton",
    tier="control",
    summary=(
        "A pushbutton on a local control station. Momentary by default: "
        "the contact follows the button while it is held, which in a "
        "scanned plant means for a short hold after a press. A maintained "
        "button, a selector, toggles on each press. Normally closed for "
        "a STOP, so the circuit is made until someone presses it, which "
        "is the seal-in a start/stop station relies on."
    ),
    ports={
        "contact": "Dry contact: made while pressed (normally open) or "
                   "while not pressed (normally closed).",
    },
    equations=(
        Equation(
            "contact = pressed XOR normally_closed",
            "A normally-open button makes on a press; a normally-closed "
            "one breaks on a press.",
        ),
        Equation(
            "pressed holds 0.6 s after a momentary press",
            "A finger stays on a button longer than one scan, so a "
            "momentary press is a short hold, not a single-scan blip a "
            "seal-in could miss.",
        ),
    ),
    params=(
        Param("momentary", "-", "True for a pushbutton that releases, "
                                "False for a selector that stays."),
        Param("normally_closed", "-", "True for a STOP-style button whose "
                                      "contact is made until pressed."),
    ),
    assumptions=(
        "No contact bounce, no wear, no illuminated buttons.",
    ),
)

PilotLight.SPEC = EquipmentSpec(
    key="pilot_light",
    title="Pilot Light",
    tier="control",
    summary=(
        "A pilot light: lit while its lamp circuit is energized, nothing "
        "more. The thing on a station that tells an operator what the "
        "PLC believes without a screen."
    ),
    ports={
        "lamp": "The lamp circuit, from a PLC output or a relay contact.",
    },
    equations=(
        Equation("lit = lamp > 0.5", "Energized is lit."),
    ),
    params=(
        Param("color", "-", "Lens colour: green, red, amber or white. "
                            "Meaning is convention, not the kernel's."),
    ),
    assumptions=(
        "The lamp never burns out and draws no accounted power.",
    ),
)

Terminal.SPEC = EquipmentSpec(
    key="terminal",
    title="Terminal Block",
    tier="control",
    summary=(
        "One terminal on a DIN rail: in to out, one scan later. The "
        "honest cost of landing a wire on a strip."
    ),
    ports={"in": "Field or panel side.", "out": "The other side."},
    equations=(
        Equation("out = in   (one scan later)", "A wire is not free."),
    ),
    params=(Param("kind", "-", "discrete or analog."),),
    assumptions=("No resistance, no loose terminals.",),
)

Column.SPEC = EquipmentSpec(
    key="column",
    title="Batch Distillation Column",
    tier="separation",
    summary=(
        "A batch column at total reflux: the sump charge heats under the "
        "reboiler, and past the boiling point the surplus duty becomes "
        "boilup. Vapour arriving faster than the vent can pass it raises "
        "the overhead pressure. The condenser returns everything, so the "
        "charge is conserved and this is a pure temperature and pressure "
        "machine. For a column that actually separates and draws "
        "product, see the Solvent Recovery Still."
    ),
    ports={
        "power": "480 V to the reboiler.",
        "p_top": "Overhead pressure tap for a gauge.",
    },
    equations=(
        Equation(
            "dT/dt = Q / (m * cp)      below the boiling point",
            "All the duty goes into sensible heat while it is coming up.",
        ),
        Equation(
            "boilup = Q / latent       at the boiling point",
            "Past boiling the temperature stops and the duty makes vapour "
            "instead.",
        ),
        Equation(
            "dP/dt = (boilup / C_vent - P) / tau",
            "Overhead pressure settles where boilup equals what the vent "
            "can pass.",
        ),
    ),
    params=(
        Param("charge_l", "L", "Sump charge."),
        Param("max_duty_kw", "kW", "Reboiler duty at full fire."),
        Param("temp_c", "C", "Starting sump temperature."),
    ),
    assumptions=(
        "Total reflux only -- no product draw and no composition change.",
        "A single fixed boiling point rather than a bubble point that "
        "moves with composition.",
    ),
)
