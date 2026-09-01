"""The first four components: tank, float switch, relay, pump.

Together they close the loop from build-order step 1: the pump fills the
tank, the float switch reads the level, the relay carries the switch's
contact to the pump motor. The float switch's two trip levels are the
hysteresis lesson — set them apart and the pump cycles calmly, set them
equal and it chatters (watch the relay's cycle counter climb).
"""
from __future__ import annotations

import math

from sim.core import Component, PortKind
from sim.hydraulics import ControlResistance, PumpCurve, static_head_pa
from sim.library import Equation, EquipmentSpec, Param
from sim.stream import AMBIENT_C, Stream


class Tank(Component):
    """Holds liquid, and knows what the liquid is.

    Two nozzles, and the difference between them is where they are. The
    outlet is at the bottom, so it carries the static head of whatever
    is standing above it — which is why a full tank will drain into an
    empty one through nothing but a pipe. The inlet is at the top, at
    headspace pressure, so filling it never has to fight the level.

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
    ) -> None:
        super().__init__(name)
        if capacity_l <= 0.0:
            raise ValueError("capacity_l must be positive")
        if level_l < 0.0:
            raise ValueError("level_l must be non-negative")
        self.capacity_l = capacity_l
        self.level_l = level_l
        self.drain_lps = drain_lps
        self.headspace_kpa = headspace_kpa
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

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        headspace_pa = self.headspace_kpa * 1000.0
        net.set_pressure(node["inlet"], headspace_pa, fixed=True)
        net.set_pressure(node["outlet"],
                         headspace_pa + static_head_pa(self.depth_m), fixed=True)

    def supplied_stream(self, port_name: str) -> Stream:
        return self.contents.with_flow(1.0)

    def tick(self, dt: float) -> None:
        # Both nozzles are signed into the vessel, so one balance covers
        # filling, draining, and a line that reversed on us.
        net_lps = self.inlet.flow_lps + self.outlet.flow_lps
        arriving = Stream.mix_all([
            port.stream.with_flow(port.flow_lps)
            for port in (self.inlet, self.outlet) if port.flow_lps > 0.0
        ])
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
      - "flow": inline flow indication, L/s, off the stream in the pipe.
      - "temp_c": inline temperature, read off the same stream.
      - "conc_pct": inline composition — the percentage of one species
        in the line. This is the analyser the AI needs before it can
        say anything true about quality.
      - "dp_pa": differential pressure between two pressure taps
        (process_a - process_b), Pa — the cleanroom Magnehelic.
      - "press_kpa": a single pressure tap. PROCESS_PRESSURE ports
        carry Pa everywhere; this dial is scaled in kPa.

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
    }
    UNITS = {
        "level_kpa": "kPa",
        "flow": "L/s",
        "temp_c": "C",
        "conc_pct": "%",
        "dp_pa": "Pa",
        "press_kpa": "kPa",
    }
    WATER_KPA_PER_M = 9.81
    #: The kinds that tap a line rather than a signal. A tap observes
    #: without carrying: piping a thermowell into a header must not put
    #: a hole in it.
    TAP_KINDS = {"flow", "temp_c", "conc_pct"}

    def __init__(
        self,
        name: str,
        kind: str,
        liters_per_meter: float = 45.45,
        species: str = "product",
    ) -> None:
        super().__init__(name)
        if kind not in self.KINDS:
            raise ValueError(f"kind must be one of {sorted(self.KINDS)}")
        if liters_per_meter <= 0.0:
            raise ValueError("liters_per_meter must be positive")
        self.kind = kind
        self.liters_per_meter = liters_per_meter
        self.species = species  # which species a "conc_pct" analyser reads
        self.reading = 0.0
        if kind == "dp_pa":
            self.process_a = self.add_input("process_a", self.KINDS[kind])
            self.process_b = self.add_input("process_b", self.KINDS[kind])
        else:
            self.process = self.add_input("process", self.KINDS[kind])
        self.signal = self.add_output("signal", PortKind.SIGNAL_ANALOG)
        self.add_observable("reading", "reading")

    def tap_ports(self) -> set[str]:
        return {"process"} if self.kind in self.TAP_KINDS else set()

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
        elif self.kind == "flow":
            self.reading = self.process.stream.flow_lps
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
    ) -> None:
        super().__init__(name)
        self.temp_c = float(temp_c)
        self.pressure_kpa = float(pressure_kpa)
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
        net.set_pressure(node["outlet"], self.pressure_kpa * 1000.0, fixed=True)

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

    def __init__(self, name: str, rate_lps: float = 1.0) -> None:
        super().__init__(name)
        if rate_lps <= 0.0:
            raise ValueError("rate_lps must be positive")
        self.rate_lps = rate_lps
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
        # it will take whatever it is given.
        sewer = net.add_node(0.0, fixed=True)
        self._branch = net.add_branch(ControlResistance(
            node["inlet"], sewer, self.rate_lps, self.name))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
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

    def __init__(self, name: str, spec: str = "480VAC") -> None:
        super().__init__(name)
        self.spec = spec
        self.power = self.add_output("power", PortKind.POWER, spec)
        self.power.value = 1.0

    def tick(self, dt: float) -> None:
        self.power.value = 1.0


class PowerSupply(Component):
    """Control power supply: 480VAC in, 24VDC out. The cabinet's PSU —
    controllers ride on it, and it dies with its feeder."""

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.ac_in = self.add_input("ac_in", PortKind.POWER, "480VAC")
        self.dc_out = self.add_output("dc_out", PortKind.POWER, "24VDC")

    def tick(self, dt: float) -> None:
        self.dc_out.value = 1.0 if float(self.ac_in.value) > 0.5 else 0.0


class ControlValve(Component):
    """Air-actuated control valve: a 0-100 % command through a
    first-order positioner onto a trim that follows the valve equation.

        Q = Cv * f(x) * sqrt(dP / dP_ref)

    Which means its authority is real. Put it in a line whose own
    resistance dominates and opening it further buys almost nothing --
    the classic badly-sized valve, and now a thing the player can
    actually diagnose.
    """

    def __init__(self, name: str, cv_lps: float = 6.0, tau_s: float = 1.0) -> None:
        super().__init__(name)
        if cv_lps <= 0.0:
            raise ValueError("cv_lps must be positive")
        if tau_s <= 0.0:
            raise ValueError("tau_s must be positive")
        self.cv_lps = cv_lps
        self.tau_s = tau_s
        self.position = 0.0  # percent, follows the command with a lag
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

    def tick(self, dt: float) -> None:
        target = max(0.0, min(100.0, float(self.cmd.value)))
        self.position += (target - self.position) * dt / self.tau_s


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
                 head_m: float = 30.0) -> None:
        super().__init__(name)
        if rated_lps <= 0.0:
            raise ValueError("rated_lps must be positive")
        if head_m <= 0.0:
            raise ValueError("head_m must be positive")
        self.rated_lps = rated_lps
        self.head_m = head_m
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
        if self._branch is not None:
            self._branch.running = self.running
            self._branch.head_pa = max(static_head_pa(self.head_m), 1e-12)
            self._branch.max_lps = max(self.rated_lps, 1e-12)
        self.suction_pa = net.pressures[node["inlet"]]
        self.discharge_pa = net.pressures[node["outlet"]]

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
        "What is drawn off leaves at whatever the contents currently "
        "are. Overfill it and it spills, and the spill is counted."
    ),
    ports={
        "inlet": "Material delivered into the vessel. Several lines may "
                 "land here and they blend.",
        "draw": "What downstream equipment is pulling off the outlet.",
        "level": "Level tap, in litres, for a switch or a transmitter.",
        "outlet": "The contents, offered to whatever pulls on them.",
    },
    equations=(
        Equation(
            "dV/dt = F_in - F_draw",
            "Plain inventory balance.",
        ),
        Equation(
            "x_new = (V*x + F_in*dt*x_in) / (V + F_in*dt)",
            "Incoming material blends by volume. Draw-off and overflow "
            "leave at the contents composition, so neither changes it -- "
            "only the inflow does.",
        ),
        Equation(
            "T_new = (V*T + F_in*dt*T_in) / (V + F_in*dt)",
            "Temperature blends the same way.",
        ),
        Equation(
            "offered = min(V / dt, nozzle_max)",
            "What the outlet advertises. A nearly empty tank offers "
            "almost nothing, which is what throttles a pump on it "
            "instead of letting the level go negative.",
        ),
    ),
    params=(
        Param("capacity_l", "L", "Volume before it overflows. Follows the "
                                 "geometry if you give height and diameter."),
        Param("level_l", "L", "Starting inventory."),
        Param("drain_lps", "L/s", "A fixed background consumption, for "
                                  "standing in for downstream demand."),
        Param("height_m", "m", "Shell height. Sets capacity with diameter."),
        Param("diameter_m", "m", "Shell diameter."),
        Param("temp_c", "C", "Starting temperature of the contents."),
        Param("comp", "-", "Starting composition, as species fractions."),
    ),
    assumptions=(
        "Perfectly mixed: one temperature and one composition throughout, "
        "so there is no stratification and no settling.",
        "Heat loss is a single first-order term, not an insulation model.",
    ),
)

Pump.SPEC = EquipmentSpec(
    key="pump",
    title="Fixed-Rate Transfer Pump",
    tier="process",
    summary=(
        "Moves material at its rating, or at whatever the suction can "
        "actually give it. A Hand-Off-Auto selector decides where the "
        "run command comes from, exactly like the switch on a real motor "
        "starter -- and none of the three positions do anything without "
        "480 V at the starter. Run it against an empty vessel and the "
        "motor spins, nothing moves, and the seal wears."
    ),
    ports={
        "run": "Run command in Auto. Ignored in Hand and Off.",
        "power": "480 V to the starter. No power, no motor, Hand included.",
        "inlet": "Suction. Wire it to the vessel or header it pulls from.",
        "outlet": "Discharge, at the same temperature and composition as "
                  "the suction.",
        "draw": "What it is actually taking, metered back to the source.",
    },
    equations=(
        Equation(
            "running = (Hand) or (Auto and run) , and powered",
            "The selector, then the starter.",
        ),
        Equation(
            "F = min(rated, offered) if running else 0",
            "It cannot pull what is not there, so an emptying tank "
            "throttles it smoothly rather than going negative.",
        ),
        Equation(
            "dry_run_s += dt   when running with nothing to pull",
            "The wear metric that makes a mistake provable afterwards.",
        ),
    ),
    params=(
        Param("rated_lps", "L/s", "Flow when running with a wet suction."),
        Param("mode", "-", "Hand, Off, or Auto."),
    ),
    assumptions=(
        "No pump curve: flow does not fall off with discharge pressure, "
        "because the kernel has no hydraulic network.",
        "No start ramp -- it is at full rate on the scan it starts.",
    ),
)

ControlValve.SPEC = EquipmentSpec(
    key="control_valve",
    title="Control Valve",
    tier="control",
    summary=(
        "An air-actuated valve that follows a 0-100 % command with a "
        "positioner lag. It passes only what its upstream header offers, "
        "so a wide open valve on a dead header still flows nothing."
    ),
    ports={
        "cmd": "Position command, 0-100 %, from a controller or an HMI.",
        "inlet": "Upstream header.",
        "outlet": "Downstream line, at the header's temperature and "
                  "composition.",
        "draw": "What it is passing, metered back to the header.",
    },
    equations=(
        Equation(
            "dx/dt = (cmd - x) / tau",
            "The positioner chases the command first-order. This lag is "
            "what a controller has to tune around.",
        ),
        Equation(
            "F = min(x/100 * Cv, offered)",
            "Linear trim, capped by what the header can supply.",
        ),
    ),
    params=(
        Param("cv_lps", "L/s", "Flow at 100 % open with supply available."),
        Param("tau_s", "s", "Positioner time constant."),
    ),
    assumptions=(
        "Linear trim and no pressure drop: flow is proportional to "
        "position, not to the square root of dP.",
        "No seat leakage, no hysteresis, no stiction.",
    ),
)

Source.SPEC = EquipmentSpec(
    key="source",
    title="Supply Header",
    tier="utility",
    summary=(
        "A utility tie-in at the edge of the modelled plant -- the "
        "honest root of every flow path, the way a mains feeder is for "
        "power. Supply is unlimited because the rest of the utility "
        "system is off-plot, but everything drawn through it is metered. "
        "A header is what it carries: this is where a species enters the "
        "plant, and everything downstream finds out by being piped to it."
    ),
    ports={
        "draw": "What equipment is pulling from the header. Totalized.",
        "supply": "The material on offer, at its storage temperature.",
    },
    equations=(
        Equation(
            "total += F_draw * dt",
            "The meter. This is the number a mass balance is checked "
            "against.",
        ),
    ),
    params=(
        Param("species", "-", "What the header carries."),
        Param("temp_c", "C", "Storage temperature."),
        Param("comp", "-", "Full composition, for a premixed feed."),
    ),
    assumptions=(
        "Infinite availability and no supply pressure: the header never "
        "runs out and never sags.",
    ),
)

Drain.SPEC = EquipmentSpec(
    key="drain",
    title="Drain / Sewer Connection",
    tier="utility",
    summary=(
        "Where material leaves the plant. It pulls from a vessel when "
        "open, accepts a discharge line dumped straight into it, and "
        "meters everything it swallows -- including how much product "
        "you sent down it, which is the number that hurts."
    ),
    ports={
        "inlet": "The vessel it drains, when open.",
        "flow_in": "A discharge line dumped straight to sewer: a "
                   "separator's waste, a relief blowdown.",
        "draw": "What it is pulling from the vessel.",
    },
    equations=(
        Equation(
            "F = min(rated, offered) if open else 0",
            "It cannot swallow faster than its rating or faster than the "
            "vessel can give.",
        ),
        Equation(
            "lost_product += (F * x_product + F_in * x_product_in) * dt",
            "Yield to sewer, on a trend. Nothing else in the plant will "
            "tell you about this.",
        ),
    ),
    params=(
        Param("rate_lps", "L/s", "Maximum drain rate."),
    ),
    assumptions=(
        "No back pressure and no sewer capacity: an open drain always "
        "takes its rating.",
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
        "process": "The tap. What it means depends on the kind of gauge.",
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
            "Rate straight off the stream in the line.",
        ),
        Equation(
            "reading = T                      [temp_c]",
            "Temperature of the stream in the line.",
        ),
        Equation(
            "reading = x_species * 100        [conc_pct]",
            "The analyser. This is what the AI needs before it can say "
            "anything true about quality.",
        ),
        Equation(
            "reading = P_a - P_b              [dp_pa]",
            "Differential pressure across two taps.",
        ),
    ),
    params=(
        Param("kind", "-", "level_kpa, flow, temp_c, conc_pct, dp_pa, or "
                           "press_kpa."),
        Param("liters_per_meter", "L/m", "Vessel cross-section, for "
                                         "turning level into head."),
        Param("species", "-", "Which species an analyser reads."),
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
        "The plant's electrical supply: one always-energized output at "
        "its voltage class. The honest root of every power circuit -- "
        "nothing in the plant runs without a cable back to one of these."
    ),
    ports={"power": "Energized supply at the feeder's voltage class."},
    equations=(
        Equation("power = 1 always", "No load accounting or breakers yet."),
    ),
    params=(Param("spec", "-", "Voltage class, e.g. 480VAC."),),
    assumptions=(
        "Infinite capacity: no breaker, no load accounting, no volt drop. "
        "Every feeder carries whatever you hang on it.",
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
