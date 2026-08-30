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


class Tank(Component):
    """Holds liquid. Integrates inflow minus a fixed drain demand.

    The drain models downstream consumption (the reason the level ever
    falls). Liquid that arrives while full spills; ``overflowed_l`` and
    ``ran_dry_ticks`` are the failure evidence a player would trace.
    """

    def __init__(
        self,
        name: str,
        capacity_l: float,
        level_l: float = 0.0,
        drain_lps: float = 0.0,
        height_m: float = 0.0,
        diameter_m: float = 0.0,
    ) -> None:
        super().__init__(name)
        if capacity_l <= 0.0:
            raise ValueError("capacity_l must be positive")
        if level_l < 0.0:
            raise ValueError("level_l must be non-negative")
        self.capacity_l = capacity_l
        self.level_l = level_l
        self.drain_lps = drain_lps
        if height_m > 0.0 and diameter_m > 0.0:
            # Geometry given: capacity follows it honestly.
            self.height_m = height_m
            self.diameter_m = diameter_m
            self.capacity_l = math.pi * (diameter_m / 2.0) ** 2 * height_m * 1000.0
            self.level_l = min(self.level_l, self.capacity_l)
        elif height_m > 0.0:
            self.height_m = height_m
            self.diameter_m = 2.0 * math.sqrt(
                capacity_l / 1000.0 / (math.pi * height_m))
        else:
            # Capacity only: drum-like proportions (h = 1.4 d).
            self.diameter_m = (4.0 * capacity_l / 1000.0 / (1.4 * math.pi)) ** (1.0 / 3.0)
            self.height_m = 1.4 * self.diameter_m
        if self.level_l > self.capacity_l:
            raise ValueError("level_l must be within [0, capacity_l]")
        self.overflowed_l = 0.0
        self.ran_dry_ticks = 0
        self.inlet = self.add_input("inlet", PortKind.PROCESS_FLOW)
        self.draw = self.add_input("draw", PortKind.PROCESS_FLOW)
        self.level = self.add_output("level", PortKind.PROCESS_LEVEL)
        self.level.value = level_l
        self.add_observable("overflowed_l", "overflowed_l")
        self.add_observable("ran_dry_ticks", "ran_dry_ticks")

    def set_size(self, height_m: float, diameter_m: float) -> None:
        """Resize the vessel; capacity follows the geometry honestly
        and the inventory is clamped to what still fits."""
        if height_m <= 0.0 or diameter_m <= 0.0:
            raise ValueError("height and diameter must be positive")
        self.height_m = height_m
        self.diameter_m = diameter_m
        self.capacity_l = math.pi * (diameter_m / 2.0) ** 2 * height_m * 1000.0
        self.level_l = min(self.level_l, self.capacity_l)

    def tick(self, dt: float) -> None:
        inflow = float(self.inlet.value)
        # Demand: equipment drawing from the outlet (pumps, drains)
        # plus the legacy constant-drain parameter. Can't remove more
        # than it holds.
        demand = self.drain_lps + float(self.draw.value)
        available = self.level_l + inflow * dt
        drained = min(demand * dt, available)
        if drained < demand * dt - 1e-9:
            self.ran_dry_ticks += 1
        new_level = self.level_l + inflow * dt - drained
        if new_level > self.capacity_l:
            self.overflowed_l += new_level - self.capacity_l
            new_level = self.capacity_l
        self.level_l = new_level
        self.level.value = self.level_l


class Gauge(Component):
    """Local indicator plus analog transmitter output.

    Four kinds, all honest derivations of existing process state:
      - "level_kpa": hydrostatic head at a vessel bottom. The process
        level (liters) becomes height via liters_per_meter, and
        P = rho*g*h (water) in kPa.
      - "flow": inline flow indication, L/s, read directly.
      - "dp_pa": differential pressure between two pressure taps
        (process_a - process_b), Pa — the cleanroom Magnehelic.
      - "press_kpa": a single pressure tap. PROCESS_PRESSURE ports
        carry Pa everywhere; this dial is scaled in kPa.

    The reading is mirrored on an analog signal output so it can later
    feed controllers — a gauge today, a transmitter when wired.
    """

    KINDS = {
        "level_kpa": PortKind.PROCESS_LEVEL,
        "flow": PortKind.PROCESS_FLOW,
        "dp_pa": PortKind.PROCESS_PRESSURE,
        "press_kpa": PortKind.PROCESS_PRESSURE,
    }
    UNITS = {"level_kpa": "kPa", "flow": "L/s", "dp_pa": "Pa", "press_kpa": "kPa"}
    WATER_KPA_PER_M = 9.81

    def __init__(
        self, name: str, kind: str, liters_per_meter: float = 45.45
    ) -> None:
        super().__init__(name)
        if kind not in self.KINDS:
            raise ValueError(f"kind must be one of {sorted(self.KINDS)}")
        if liters_per_meter <= 0.0:
            raise ValueError("liters_per_meter must be positive")
        self.kind = kind
        self.liters_per_meter = liters_per_meter
        self.reading = 0.0
        if kind == "dp_pa":
            self.process_a = self.add_input("process_a", self.KINDS[kind])
            self.process_b = self.add_input("process_b", self.KINDS[kind])
        else:
            self.process = self.add_input("process", self.KINDS[kind])
        self.signal = self.add_output("signal", PortKind.SIGNAL_ANALOG)
        self.add_observable("reading", "reading")

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
        else:
            self.reading = float(self.process.value)
        self.signal.value = self.reading


class Source(Component):
    """Supply header: a utility tie-in at the edge of the modeled
    plant — the honest root of every flow path, the way MainsFeed is
    for power. Availability is unlimited (the wider utility system is
    off-plot), but everything drawn through it is metered
    (``total_l``). Pumps and valves wire their suction to ``supply``
    ("always wet") and their ``draw`` back here for the meter.
    """

    AVAILABLE_L = 1.0e9

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.total_l = 0.0
        self.draw = self.add_input("draw", PortKind.PROCESS_FLOW)
        self.supply = self.add_output("supply", PortKind.PROCESS_LEVEL)
        self.supply.value = self.AVAILABLE_L
        self.add_observable("total_l", "total_l")

    def tick(self, dt: float) -> None:
        self.total_l += float(self.draw.value) * dt
        self.supply.value = self.AVAILABLE_L


class Drain(Component):
    """Gravity drain to sewer or recovery: pulls up to ``rate_lps``
    whenever the connected vessel holds liquid and the drain is open,
    and meters everything it swallows. Wire vessel ``level`` in and
    ``draw`` back to the vessel's ``out_flow``.
    """

    def __init__(self, name: str, rate_lps: float = 1.0) -> None:
        super().__init__(name)
        if rate_lps <= 0.0:
            raise ValueError("rate_lps must be positive")
        self.rate_lps = rate_lps
        self.is_open = True
        self.total_l = 0.0
        self.inlet = self.add_input("inlet", PortKind.PROCESS_LEVEL)
        self.draw = self.add_output("draw", PortKind.PROCESS_FLOW)
        self.add_observable("total_l", "total_l")

    def tick(self, dt: float) -> None:
        lvl = float(self.inlet.value)
        rate = self.rate_lps if (self.is_open and lvl > 0.0) else 0.0
        rate = min(rate, lvl / dt) if dt > 0.0 else rate
        self.draw.value = rate
        self.total_l += rate * dt


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
    """Air-actuated control valve: 0-100 % analog command, first-order
    positioner lag, flow = position/100 * cv_lps. It passes only what
    its ``supply`` offers: wire an upstream ``level`` in and ``draw``
    back — an empty header means no flow no matter the command.
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
        self.inlet = self.add_input("inlet", PortKind.PROCESS_LEVEL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_FLOW)
        self.draw = self.add_output("draw", PortKind.PROCESS_FLOW)
        self.add_observable("position", "position")

    def tick(self, dt: float) -> None:
        target = max(0.0, min(100.0, float(self.cmd.value)))
        self.position += (target - self.position) * dt / self.tau_s
        wet = float(self.inlet.value) > 0.05
        delivered = self.position / 100.0 * self.cv_lps if wet else 0.0
        self.outlet.value = delivered
        self.draw.value = delivered


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
    """Fixed-rate transfer pump with a Hand-Off-Auto selector.

    In ``auto`` the motor follows the ``run`` input; ``hand`` forces it
    on and ``off`` forces it off, exactly like the selector on a real
    motor starter. The pump moves only fluid it actually pulls: wire
    ``suction`` to an upstream vessel's or source's ``level`` and
    ``draw`` back to its ``out_flow``/``draw`` — running against an
    empty suction delivers nothing and accrues ``dry_run_s`` wear.
    ``starts`` is the motor-wear counterpart to the relay's ``cycles``.
    """

    MODES = ("hand", "off", "auto")

    def __init__(self, name: str, rated_lps: float, mode: str = "auto") -> None:
        super().__init__(name)
        if rated_lps <= 0.0:
            raise ValueError("rated_lps must be positive")
        self.rated_lps = rated_lps
        self.mode = "auto"
        self.set_mode(mode)
        self.running = False
        self.starts = 0
        self.dry_run_s = 0.0
        self.run = self.add_input("run", PortKind.SIGNAL_DISCRETE)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.inlet = self.add_input("inlet", PortKind.PROCESS_LEVEL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_FLOW)
        self.draw = self.add_output("draw", PortKind.PROCESS_FLOW)
        self.add_observable("starts", "starts")
        self.add_observable("dry_run_s", "dry_run_s")

    def set_mode(self, mode: str) -> None:
        if mode not in self.MODES:
            raise ValueError(f"mode must be one of {self.MODES}")
        self.mode = mode

    def tick(self, dt: float) -> None:
        if self.mode == "hand":
            run = True
        elif self.mode == "off":
            run = False
        else:
            run = bool(self.run.value)
        # No 480 V at the starter, no motor — hand mode included.
        run = run and float(self.power.value) > 0.5
        if run and not self.running:
            self.starts += 1
        self.running = run
        # The motor can spin against an empty inlet, but nothing moves
        # and the seal wears.
        wet = float(self.inlet.value) > 0.05
        if self.running and not wet:
            self.dry_run_s += dt
        delivered = self.rated_lps if (self.running and wet) else 0.0
        self.outlet.value = delivered
        self.draw.value = delivered
