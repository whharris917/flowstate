"""The small-bore family: what a real plant fits on its little lines.

These are machines with their own equations, not the big valve drawn
small. Every one of them is a real branch in the hydraulic network,
sized in the game's own units (L/s at a 1 bar drop, the same basis as
the control valve), and follows the rich-streams, simple-insides rule:
a handful of algebraic relations each.

  Orifice        a restriction orifice: the flow limiter. One number.
  NeedleValve    a hand valve with a fine stem, opened turn by turn.
  BallValve      a quarter-turn hand valve: open or shut, half a second.
  SolenoidValve  a coil-operated valve, shut until energized, snaps.
  MeteringPump   a positive-displacement dosing pump: its flow barely
                 moves with the head until the head runs out.
  Regulator      a self-acting pressure-reducing valve.
  Rotameter      a variable-area flow indicator: a float in a glass tube.
"""
from __future__ import annotations

import math

from sim.core import Component, PortKind
from sim.hydraulics import (
    ControlResistance, PumpCurve, RegulatorResistance, Resistance, static_head_pa,
)
from sim.library import Equation, EquipmentSpec, Param

REF_DROP_PA = ControlResistance.REF_DROP_PA


class Orifice(Component):
    """A restriction orifice: a plate with a hole, the plant's flow
    limiter. It has one number, the flow it passes at the reference
    drop, and the square law does the rest.

        Q = Cv * sqrt(dP / 1 bar)

    Nothing to turn, nothing to wire. It limits by resistance alone, so
    the flow it lets through still rises with the pressure behind it --
    a limiter, not a regulator.
    """

    def __init__(self, name: str, cv_lps: float = 0.001) -> None:
        super().__init__(name)
        if cv_lps <= 0.0:
            raise ValueError("cv_lps must be positive")
        self.cv_lps = cv_lps
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self._branch = None
        self.add_observable("flow_lps", "flow_lps")

    @property
    def flow_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    @staticmethod
    def k_for(cv_lps: float) -> float:
        return REF_DROP_PA / max(cv_lps, 1e-12) ** 2

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        self._branch = net.add_branch(Resistance(
            node["inlet"], node["outlet"], self.k_for(self.cv_lps), self.name))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        if self._branch is not None:
            self._branch.k = self.k_for(self.cv_lps)

    def tick(self, dt: float) -> None:
        pass


class NeedleValve(Component):
    """A hand valve with a fine tapered stem: many turns from shut to
    open, so a fraction of a turn is a real adjustment. Linear in the
    turns, the valve equation across it.

        Q = Cv * (turns_open / turns) * sqrt(dP / 1 bar)

    No actuator and no command: the operator turns it, and that is
    the whole control system.
    """

    def __init__(self, name: str, cv_lps: float = 0.005, turns: float = 10.0,
                 elevation_m: float = 0.0) -> None:
        super().__init__(name)
        if cv_lps <= 0.0:
            raise ValueError("cv_lps must be positive")
        if turns <= 0.0:
            raise ValueError("turns must be positive")
        self.cv_lps = cv_lps
        self.turns = turns
        self.turns_open = 0.0
        # Nozzle height above grade: the drop across the valve does not
        # depend on it, the static pressure a gauge there reads does.
        self.elevation_m = float(elevation_m)
        self.inlet_pa = 0.0
        self.outlet_pa = 0.0
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self._branch = None
        self.add_observable("position", "position")
        self.add_observable("flow_lps", "flow_lps")

    @property
    def position(self) -> float:
        """Percent open."""
        return 100.0 * self.turns_open / self.turns

    @property
    def flow_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    def turn(self, turns: float) -> None:
        """Turn the stem: positive opens, negative shuts, clamped to the
        stem's travel."""
        self.turns_open = min(max(self.turns_open + turns, 0.0), self.turns)

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        self._branch = net.add_branch(ControlResistance(
            node["inlet"], node["outlet"], self.cv_lps, self.name))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        if self._branch is not None:
            self._branch.cv_lps = self.cv_lps
            self._branch.opening = self.turns_open / self.turns
        datum = static_head_pa(self.elevation_m)
        self.inlet_pa = net.pressures[node["inlet"]] - datum
        self.outlet_pa = net.pressures[node["outlet"]] - datum

    def tick(self, dt: float) -> None:
        pass

    def state_dict(self) -> dict:
        return {"turns_open": self.turns_open}

    def apply_state(self, state: dict) -> None:
        self.turns_open = float(state.get("turns_open", self.turns_open))


class BallValve(Component):
    """A quarter-turn hand valve: a lever, open or shut, and half a
    second of travel between. The valve equation while it travels, as
    the block valve, but there is no actuator and no limit switch --
    the lever's own position is the only indication.

        dx/dt = +-100 / stroke_s
        Q = Cv * (x/100) * sqrt(dP / 1 bar)
    """

    def __init__(self, name: str, cv_lps: float = 0.5, stroke_s: float = 0.5,
                 elevation_m: float = 0.0) -> None:
        super().__init__(name)
        if cv_lps <= 0.0:
            raise ValueError("cv_lps must be positive")
        if stroke_s <= 0.0:
            raise ValueError("stroke_s must be positive")
        self.cv_lps = cv_lps
        self.stroke_s = stroke_s
        self.open = False
        self.position = 0.0
        self.elevation_m = float(elevation_m)  # nozzle height; see NeedleValve
        self.inlet_pa = 0.0
        self.outlet_pa = 0.0
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
        target = 100.0 if self.open else 0.0
        step = 100.0 * dt / self.stroke_s
        if self.position < target:
            self.position = min(self.position + step, target)
        elif self.position > target:
            self.position = max(self.position - step, target)

    def state_dict(self) -> dict:
        return {"open": self.open, "position": self.position}

    def apply_state(self, state: dict) -> None:
        self.open = bool(state.get("open", self.open))
        self.position = float(state.get("position", self.position))


class SolenoidValve(Component):
    """A coil-operated valve: shut until its coil is energized, open
    while it is, and the plunger snaps in a few hundredths of a second.
    Normally closed, so a lost signal is a shut valve. The valve
    equation while the plunger travels, which is barely a scan.

        x -> 100 in snap_s when the coil is energized, -> 0 when not
        Q = Cv * (x/100) * sqrt(dP / 1 bar)

    The coil is a 24 V discrete input: a PLC output, a relay contact
    or a switch. There is no hand override.
    """

    SNAP_S = 0.05

    def __init__(self, name: str, cv_lps: float = 0.3, elevation_m: float = 0.0) -> None:
        super().__init__(name)
        if cv_lps <= 0.0:
            raise ValueError("cv_lps must be positive")
        self.cv_lps = cv_lps
        self.position = 0.0
        self.cycles = 0
        self.elevation_m = float(elevation_m)  # nozzle height; see NeedleValve
        self.inlet_pa = 0.0
        self.outlet_pa = 0.0
        self.coil = self.add_input("coil", PortKind.SIGNAL_DISCRETE)
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self._branch = None
        self._was_energized = False
        self.add_observable("position", "position")
        self.add_observable("flow_lps", "flow_lps")
        self.add_observable("cycles", "cycles")

    @property
    def energized(self) -> bool:
        return float(self.coil.value) > 0.5

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
        energized = self.energized
        if energized and not self._was_energized:
            self.cycles += 1
        self._was_energized = energized
        target = 100.0 if energized else 0.0
        step = 100.0 * dt / self.SNAP_S
        if self.position < target:
            self.position = min(self.position + step, target)
        elif self.position > target:
            self.position = max(self.position - step, target)

    def state_dict(self) -> dict:
        return {"position": self.position, "cycles": self.cycles}

    def apply_state(self, state: dict) -> None:
        self.position = float(state.get("position", self.position))
        self.cycles = int(state.get("cycles", self.cycles))
        self._was_energized = self.position > 50.0


class MeteringPump(Component):
    """A positive-displacement dosing pump: a diaphragm and two check
    valves, driven by a small motor. It delivers its stroke volume
    every stroke whatever the discharge pressure, until the pressure
    reaches what its drive can push against -- so its curve is nearly
    vertical, the opposite of the centrifugal pump's.

        Q = Q_stroke * (1 - (H / H_max)^8)^(1/8)     (running)
        Q_stroke = rated_lps * stroke / 100

    The stroke length is the dose adjustment, a knob on the pump or a
    4-20 mA signal on its stroke input. 24 V DC, a discrete run
    command, and with nothing wired to run it is a hand pump: E
    starts it.
    """

    CURVE_EXPONENT = 8.0

    def __init__(self, name: str, rated_lps: float = 0.01, max_head_m: float = 50.0,
                 elevation_m: float = 0.0) -> None:
        super().__init__(name)
        if rated_lps <= 0.0:
            raise ValueError("rated_lps must be positive")
        if max_head_m <= 0.0:
            raise ValueError("max_head_m must be positive")
        self.rated_lps = rated_lps
        self.max_head_m = max_head_m
        # Nozzle height above grade: prime is judged on the static
        # suction at the pump, the node's piezometric pressure less this.
        self.elevation_m = float(elevation_m)
        self.stroke_pct = 100.0    # the knob, when nothing is wired to "stroke"
        self.hand_on = False       # the switch, when nothing is wired to "run"
        self.running = False
        self.starts = 0
        self.suction_pa = 0.0
        self.discharge_pa = 0.0
        self.run = self.add_input("run", PortKind.SIGNAL_DISCRETE)
        self.stroke = self.add_input("stroke", PortKind.SIGNAL_ANALOG)
        self.power = self.add_input("power", PortKind.POWER, "24VDC")
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self._branch = None
        self._was_running = False
        self.add_observable("flow_lps", "flow_lps")
        self.add_observable("head_pa", "head_pa")
        self.add_observable("starts", "starts")
        self.add_observable("stroke_now", "stroke_now")

    @property
    def flow_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    @property
    def head_pa(self) -> float:
        return self.discharge_pa - self.suction_pa

    @property
    def stroke_now(self) -> float:
        """The stroke in use, percent: the signal if one is wired, else
        the knob."""
        if self.stroke.wire_count > 0:
            return min(max(float(self.stroke.value), 0.0), 100.0)
        return self.stroke_pct

    @property
    def is_hand_operated(self) -> bool:
        return self.run.wire_count == 0

    @property
    def wants_run(self) -> bool:
        if self.is_hand_operated:
            return self.hand_on
        return float(self.run.value) > 0.5

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        self._branch = net.add_branch(PumpCurve(
            node["inlet"], node["outlet"], static_head_pa(self.max_head_m),
            self.rated_lps, self.name, exponent=self.CURVE_EXPONENT))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        self.running = self.wants_run and float(self.power.value) > 0.5
        datum = static_head_pa(self.elevation_m)
        if self._branch is not None:
            self._branch.running = self.running and self.stroke_now > 0.0
            self._branch.head_pa = max(static_head_pa(self.max_head_m), 1e-12)
            self._branch.max_lps = max(self.rated_lps * self.stroke_now / 100.0, 1e-12)
            self._branch.datum_pa = datum
        self.suction_pa = net.pressures[node["inlet"]] - datum
        self.discharge_pa = net.pressures[node["outlet"]] - datum

    def tick(self, dt: float) -> None:
        if self.running and not self._was_running:
            self.starts += 1
        self._was_running = self.running

    def state_dict(self) -> dict:
        return {"hand_on": self.hand_on, "stroke_pct": self.stroke_pct,
                "running": self.running, "starts": self.starts}

    def apply_state(self, state: dict) -> None:
        self.hand_on = bool(state.get("hand_on", self.hand_on))
        self.stroke_pct = float(state.get("stroke_pct", self.stroke_pct))
        self.running = bool(state.get("running", self.running))
        self._was_running = self.running
        self.starts = int(state.get("starts", self.starts))


class Regulator(Component):
    """A self-acting pressure-reducing valve: a spring against a
    diaphragm that feels the downstream pressure, throttling the seat
    as it rises. No signal in or out. It holds its outlet near the set
    pressure while the inlet is higher and the flow is within its Cv;
    above the set pressure it shuts.

        x = clamp((P_set - P_out) / P_band, 0, 1)
        Q = Cv * x * sqrt(dP / 1 bar)

    The proportional band is a tenth of the setting (never under 5 kPa),
    so the outlet droops a little as the flow rises -- the droop of a
    real regulator, and the reason a gauge downstream never reads the
    setting exactly.
    """

    def __init__(self, name: str, set_kpa: float = 200.0, cv_lps: float = 0.5,
                 elevation_m: float = 0.0) -> None:
        super().__init__(name)
        if set_kpa <= 0.0:
            raise ValueError("set_kpa must be positive")
        if cv_lps <= 0.0:
            raise ValueError("cv_lps must be positive")
        self.set_kpa = set_kpa
        self.cv_lps = cv_lps
        # Nozzle height above grade. A regulator holds the *static*
        # pressure its diaphragm feels, at its own height; in the
        # network's piezometric terms that is the setting plus rho*g*z.
        self.elevation_m = float(elevation_m)
        self.opening = 0.0
        self.out_kpa = 0.0
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self._branch = None
        self.add_observable("opening", "opening")
        self.add_observable("out_kpa", "out_kpa")
        self.add_observable("flow_lps", "flow_lps")

    @property
    def flow_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    @property
    def band_pa(self) -> float:
        return max(self.set_kpa * 1000.0 * 0.1, 5000.0)

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        self._branch = net.add_branch(RegulatorResistance(
            node["inlet"], node["outlet"], self.cv_lps,
            self.set_kpa * 1000.0 + static_head_pa(self.elevation_m),
            self.band_pa, self.name))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        # The opening is solved with the network (a regulator's
        # downstream is stiff, and a scan-behind opening never settles);
        # here it is only read back for the face and the historian. The
        # setting is static, at the regulator's height: piezometric,
        # that is the setting plus rho*g*z.
        datum = static_head_pa(self.elevation_m)
        self.out_kpa = (net.pressures[node["outlet"]] - datum) / 1000.0
        if self._branch is not None:
            self._branch.cv_lps = self.cv_lps
            self._branch.set_pa = self.set_kpa * 1000.0 + datum
            self._branch.band_pa = self.band_pa
            self.opening = self._branch.opening_at(net.pressures[node["outlet"]])

    def tick(self, dt: float) -> None:
        pass


class Rotameter(Component):
    """A variable-area flow indicator: a float in a tapered glass tube,
    riding at the height where the drag balances its weight. A local
    indication and nothing else -- no signal out. The tube is a small
    resistance the line pays for the reading.

        float_frac = Q / Q_range        (clamped 0..1)
        dP = k * Q^2, k sized so Q_range costs 5 kPa
    """

    RANGE_DROP_PA = 5000.0

    def __init__(self, name: str, range_lps: float = 0.01) -> None:
        super().__init__(name)
        if range_lps <= 0.0:
            raise ValueError("range_lps must be positive")
        self.range_lps = range_lps
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self._branch = None
        self.add_observable("flow_lps", "flow_lps")
        self.add_observable("float_frac", "float_frac")

    @property
    def flow_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    @property
    def float_frac(self) -> float:
        return min(max(self.flow_lps / self.range_lps, 0.0), 1.0)

    def k_now(self) -> float:
        return self.RANGE_DROP_PA / max(self.range_lps, 1e-12) ** 2

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        self._branch = net.add_branch(Resistance(
            node["inlet"], node["outlet"], self.k_now(), self.name))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        if self._branch is not None:
            self._branch.k = self.k_now()

    def tick(self, dt: float) -> None:
        pass


# ---------------------------------------------------------------------
# Library pages: the Python kernel's own documentation. The in-game
# pages are hand-authored in game/sim/sim_library_data.gd.
# ---------------------------------------------------------------------

Orifice.SPEC = EquipmentSpec(
    key="orifice",
    title="Restriction Orifice",
    tier="utility",
    summary=(
        "A plate with a hole: the flow limiter. It has one number, the "
        "flow it passes at a 1 bar drop, and the square law does the "
        "rest. It limits by resistance alone, so what gets through still "
        "rises with the pressure behind it."
    ),
    ports={
        "inlet": "Upstream nozzle.",
        "outlet": "Downstream nozzle, the same material at a lower pressure.",
    },
    equations=(
        Equation("Q = Cv * sqrt(dP / 100 kPa)",
                 "The square law through a fixed hole."),
    ),
    params=(
        Param("cv_lps", "L/s at 1 bar", "The flow through the hole at the reference drop."),
    ),
    assumptions=(
        "No vena contracta, no recovery: the drop is the drop.",
        "It never clogs.",
    ),
)

NeedleValve.SPEC = EquipmentSpec(
    key="needle_valve",
    title="Needle Valve",
    tier="control",
    summary=(
        "A hand valve with a fine tapered stem: many turns from shut to "
        "open, so a fraction of a turn is a real adjustment. Linear in "
        "the turns, the valve equation across it. No actuator, no "
        "command: the operator is the control system."
    ),
    ports={
        "inlet": "Upstream nozzle.",
        "outlet": "Downstream nozzle.",
    },
    equations=(
        Equation("x = turns_open / turns", "The stem's travel as a fraction."),
        Equation("Q = Cv * x * sqrt(dP / 100 kPa)", "The valve equation."),
    ),
    params=(
        Param("cv_lps", "L/s at 1 bar", "Flow at full open across the reference drop."),
        Param("turns", "turns", "How many turns of the stem from shut to full open."),
        Param("elevation_m", "m", "Nozzle height above grade, from where it stands; "
                                  "the static pressure at the valve, not the drop across it."),
    ),
    assumptions=(
        "Linear characteristic: a needle valve's is closer to equal percentage.",
        "No packing leak, no seat wear.",
    ),
)

BallValve.SPEC = EquipmentSpec(
    key="ball_valve",
    title="Ball Valve",
    tier="control",
    summary=(
        "A quarter-turn hand valve: a lever, open or shut, half a second "
        "of travel between. The valve equation while it travels. No "
        "actuator and no limit switch: the lever is the only indication."
    ),
    ports={
        "inlet": "Upstream nozzle.",
        "outlet": "Downstream nozzle.",
    },
    equations=(
        Equation("dx/dt = +-100 / stroke_s", "The lever's own quarter turn."),
        Equation("Q = Cv * (x/100) * sqrt(dP / 100 kPa)", "The valve equation."),
    ),
    params=(
        Param("cv_lps", "L/s at 1 bar", "Flow at full open across the reference drop."),
        Param("stroke_s", "s", "How long the quarter turn takes."),
        Param("elevation_m", "m", "Nozzle height above grade, from where it stands; "
                                  "the static pressure at the valve, not the drop across it."),
    ),
    assumptions=(
        "A linear characteristic through the travel; a ball's is not.",
        "Bubble-tight shut.",
    ),
)

SolenoidValve.SPEC = EquipmentSpec(
    key="solenoid_valve",
    title="Solenoid Valve",
    tier="control",
    summary=(
        "A coil-operated valve: shut until its coil is energized, open "
        "while it is, and the plunger snaps in a few hundredths of a "
        "second. Normally closed, so a lost signal is a shut valve. "
        "There is no hand override."
    ),
    ports={
        "coil": "The coil: a 24 V discrete signal. Energized opens.",
        "inlet": "Upstream nozzle.",
        "outlet": "Downstream nozzle.",
    },
    equations=(
        Equation("x -> 100 in 0.05 s energized, -> 0 de-energized", "The plunger snaps."),
        Equation("Q = Cv * (x/100) * sqrt(dP / 100 kPa)", "The valve equation."),
    ),
    params=(
        Param("cv_lps", "L/s at 1 bar", "Flow at full open across the reference drop."),
        Param("elevation_m", "m", "Nozzle height above grade, from where it stands; "
                                  "the static pressure at the valve, not the drop across it."),
    ),
    assumptions=(
        "The coil draws nothing from the signal: no current, no heating.",
        "No minimum operating differential: it opens against any drop.",
    ),
)

MeteringPump.SPEC = EquipmentSpec(
    key="metering_pump",
    title="Metering Pump",
    tier="process",
    summary=(
        "A positive-displacement dosing pump: a diaphragm and two check "
        "valves driven by a small motor. It delivers its stroke volume "
        "every stroke whatever the discharge pressure, until the "
        "pressure reaches what its drive can push against, so its curve "
        "is nearly vertical. The stroke length is the dose adjustment."
    ),
    ports={
        "run": "Discrete run command. Unwired, the pump is hand-operated.",
        "stroke": "Analog stroke length, 0-100 %. Unwired, the knob on the pump.",
        "power": "24 V DC supply. No supply, no pump.",
        "inlet": "Suction nozzle.",
        "outlet": "Discharge nozzle.",
    },
    equations=(
        Equation("Q_stroke = rated_lps * stroke / 100", "The dose set at the knob or the signal."),
        Equation("Q = Q_stroke * (1 - (H / H_max)^8)^(1/8)",
                 "Nearly the full stroke until the head approaches the maximum, then nothing."),
    ),
    params=(
        Param("rated_lps", "L/s", "Delivery at full stroke against no head."),
        Param("max_head_m", "m", "The head the drive can push against."),
        Param("elevation_m", "m", "Nozzle height above grade, from where it stands: "
                                  "prime is judged on the static suction there."),
    ),
    assumptions=(
        "No pulsation: the flow is the average over the strokes.",
        "No check-valve leakage, no loss of prime beyond the suction taper every pump has.",
    ),
)

Regulator.SPEC = EquipmentSpec(
    key="regulator",
    title="Pressure Regulator",
    tier="control",
    summary=(
        "A self-acting pressure-reducing valve: a spring against a "
        "diaphragm that feels the downstream pressure and throttles the "
        "seat as it rises. No signal in or out. It holds its outlet near "
        "the setting while the inlet is higher and the flow within its "
        "Cv; above the setting it shuts."
    ),
    ports={
        "inlet": "Upstream nozzle, the higher pressure.",
        "outlet": "Downstream nozzle, held near the setting.",
    },
    equations=(
        Equation("x = clamp((P_set - P_out) / P_band, 0, 1)",
                 "The diaphragm against its spring, solved with the network."),
        Equation("Q = Cv * x * sqrt(dP / 100 kPa)", "The valve equation."),
        Equation("P_band = max(0.1 * P_set, 5 kPa)", "The droop: the outlet sags as flow rises."),
    ),
    params=(
        Param("set_kpa", "kPa", "The downstream pressure it holds, static, at its own height."),
        Param("cv_lps", "L/s at 1 bar", "Flow at full open across the reference drop."),
        Param("elevation_m", "m", "Nozzle height above grade, from where it stands. "
                                  "The diaphragm feels the static pressure there, so "
                                  "the outlet it holds is the setting at that height."),
    ),
    assumptions=(
        "Proportional only: a real regulator's droop curve is not a straight line.",
        "No relief: an outlet pushed above the setting from downstream is not vented.",
    ),
)

Rotameter.SPEC = EquipmentSpec(
    key="rotameter",
    title="Rotameter",
    tier="control",
    summary=(
        "A variable-area flow indicator: a float in a tapered glass tube, "
        "riding at the height where the drag balances its weight. A local "
        "indication and nothing else, no signal out. The tube is a small "
        "resistance the line pays for the reading."
    ),
    ports={
        "inlet": "Upstream nozzle, the bottom of the tube.",
        "outlet": "Downstream nozzle.",
    },
    equations=(
        Equation("float_frac = Q / Q_range", "The float's height, clamped to the tube."),
        Equation("dP = k * Q^2, k = 5 kPa / Q_range^2", "What the tube costs the line."),
    ),
    params=(
        Param("range_lps", "L/s", "Full-scale flow: the top of the tube."),
    ),
    assumptions=(
        "Linear scale: a real tube is calibrated for one fluid and reads wrong for another.",
        "No float bounce, no reading below a tenth of scale.",
    ),
)
