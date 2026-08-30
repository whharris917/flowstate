"""The first four components: tank, float switch, relay, pump.

Together they close the loop from build-order step 1: the pump fills the
tank, the float switch reads the level, the relay carries the switch's
contact to the pump motor. The float switch's two trip levels are the
hysteresis lesson — set them apart and the pump cycles calmly, set them
equal and it chatters (watch the relay's cycle counter climb).
"""
from __future__ import annotations

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
    ) -> None:
        super().__init__(name)
        if capacity_l <= 0.0:
            raise ValueError("capacity_l must be positive")
        if not 0.0 <= level_l <= capacity_l:
            raise ValueError("level_l must be within [0, capacity_l]")
        self.capacity_l = capacity_l
        self.level_l = level_l
        self.drain_lps = drain_lps
        self.overflowed_l = 0.0
        self.ran_dry_ticks = 0
        self.in_flow = self.add_input("in_flow", PortKind.PROCESS_FLOW)
        self.level = self.add_output("level", PortKind.PROCESS_LEVEL)
        self.level.value = level_l
        self.add_observable("overflowed_l", "overflowed_l")
        self.add_observable("ran_dry_ticks", "ran_dry_ticks")

    def tick(self, dt: float) -> None:
        inflow = float(self.in_flow.value)
        # Can't drain more than the tank holds this tick.
        available = self.level_l + inflow * dt
        drained = min(self.drain_lps * dt, available)
        if drained < self.drain_lps * dt:
            self.ran_dry_ticks += 1
        new_level = self.level_l + inflow * dt - drained
        if new_level > self.capacity_l:
            self.overflowed_l += new_level - self.capacity_l
            new_level = self.capacity_l
        self.level_l = new_level
        self.level.value = self.level_l


class Gauge(Component):
    """Local indicator plus analog transmitter output.

    Two kinds, both honest derivations of existing process state:
      - "level_kpa": hydrostatic head at a vessel bottom. The process
        level (liters) becomes height via liters_per_meter, and
        P = rho*g*h (water) in kPa.
      - "flow": inline flow indication, L/s, read directly.

    The reading is mirrored on an analog signal output so it can later
    feed controllers — a gauge today, a transmitter when wired.
    """

    KINDS = {
        "level_kpa": PortKind.PROCESS_LEVEL,
        "flow": PortKind.PROCESS_FLOW,
    }
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
        self.process = self.add_input("process", self.KINDS[kind])
        self.signal = self.add_output("signal", PortKind.SIGNAL_ANALOG)
        self.add_observable("reading", "reading")

    def units(self) -> str:
        return "kPa" if self.kind == "level_kpa" else "L/s"

    def tick(self, dt: float) -> None:
        value = float(self.process.value)
        if self.kind == "level_kpa":
            self.reading = value / self.liters_per_meter * self.WATER_KPA_PER_M
        else:
            self.reading = value
        self.signal.value = self.reading


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
    motor starter. Draws from an unlimited supply main for now;
    suction-side modelling arrives when the process layer grows real
    sources. ``starts`` is the motor-wear counterpart to the relay's
    ``cycles``.
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
        self.run = self.add_input("run", PortKind.SIGNAL_DISCRETE)
        self.flow = self.add_output("flow", PortKind.PROCESS_FLOW)
        self.add_observable("starts", "starts")

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
        if run and not self.running:
            self.starts += 1
        self.running = run
        self.flow.value = self.rated_lps if self.running else 0.0
