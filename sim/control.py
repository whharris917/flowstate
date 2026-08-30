"""Control-layer components: PLC with a scanned ladder program, and a
PID controller.

The PLC is the heart of the game's automation tier. It exposes real
I/O channels as ports (di_N / do_N discrete, ai_N / ao_N analog) and
executes a ladder program once per sim scan, in rung order, exactly
like a real controller: rungs evaluated top to bottom, coils written
immediately (later rungs see earlier results in the same scan), and
outputs that no rung drives stay off.

Program model (validated by ``set_program``):

    rungs = [
        {"coil": "m_0",                      # do_N, m_N, or t_N
         "logic": [                          # parallel branches (OR)
             [{"ref": "di_0", "nc": False},  # series elements (AND)
              {"ref": "di_1", "nc": True}],
             [{"ref": "m_0", "nc": False},
              {"ref": "di_1", "nc": True}],
         ]},
    ]

Element refs may read di_N, do_N (readback), m_N (memory), or t_N
(timer done bit). Driving coil t_N runs TON timer N: it accumulates
while driven, resets when released, and its done bit trips at the
preset. Analog channels move through ``ao_moves``: scaled straight-
through maps {"dst": "ao_0", "src": "ai_1", "k": 1.0, "b": 0.0}.
"""
from __future__ import annotations

import re

from sim.core import Component, PortKind

_REF_PATTERN = re.compile(r"^(di|do|m|t)_(\d+)$")
_COIL_PATTERN = re.compile(r"^(do|m|t)_(\d+)$")


class PLC(Component):
    """Rack PLC: discrete and analog I/O plus a scanned ladder program."""

    def __init__(
        self,
        name: str,
        di: int = 8,
        do: int = 8,
        ai: int = 4,
        ao: int = 4,
        memories: int = 16,
        timers: int = 4,
    ) -> None:
        super().__init__(name)
        if min(di, do) < 1 or min(ai, ao) < 0:
            raise ValueError("channel counts out of range")
        self.n_di, self.n_do, self.n_ai, self.n_ao = di, do, ai, ao
        self.di_ports = [self.add_input(f"di_{i}", PortKind.SIGNAL_DISCRETE) for i in range(di)]
        self.ai_ports = [self.add_input(f"ai_{i}", PortKind.SIGNAL_ANALOG) for i in range(ai)]
        self.do_ports = [self.add_output(f"do_{i}", PortKind.SIGNAL_DISCRETE) for i in range(do)]
        self.ao_ports = [self.add_output(f"ao_{i}", PortKind.SIGNAL_ANALOG) for i in range(ao)]
        self.mem = [False] * memories
        self.timer_acc = [0.0] * timers
        self.timer_run = [False] * timers
        self.timer_done = [False] * timers
        self.timer_presets = [1.0] * timers
        self.program: list[dict] = []
        self.ao_moves: list[dict] = []
        self.scans = 0
        self.power = self.add_input("power", PortKind.POWER, "24VDC")
        self.add_observable("scans", "scans")

    # ---- program management -------------------------------------------------

    def set_program(self, rungs: list[dict]) -> None:
        """Validate and install a ladder program."""
        for rung in rungs:
            coil = rung.get("coil", "")
            match = _COIL_PATTERN.match(coil)
            if not match:
                raise ValueError(f"bad coil target {coil!r}")
            self._check_index(match.group(1), int(match.group(2)))
            branches = rung.get("logic", [])
            if not branches or not all(branch for branch in branches):
                raise ValueError(f"rung for {coil!r} needs at least one element per branch")
            for branch in branches:
                for element in branch:
                    ref = element.get("ref", "")
                    ref_match = _REF_PATTERN.match(ref)
                    if not ref_match:
                        raise ValueError(f"bad element ref {ref!r}")
                    self._check_index(ref_match.group(1), int(ref_match.group(2)))
        self.program = [
            {"coil": r["coil"],
             "logic": [[{"ref": e["ref"], "nc": bool(e.get("nc", False))}
                        for e in branch] for branch in r["logic"]]}
            for r in rungs
        ]

    def set_ao_moves(self, moves: list[dict]) -> None:
        for move in moves:
            if not re.match(r"^ao_\d+$", move.get("dst", "")):
                raise ValueError(f"bad move dst {move.get('dst')!r}")
            if not re.match(r"^ai_\d+$", move.get("src", "")):
                raise ValueError(f"bad move src {move.get('src')!r}")
            self._check_index("ao", int(move["dst"].split("_")[1]))
            self._check_index("ai", int(move["src"].split("_")[1]))
        self.ao_moves = [
            {"dst": m["dst"], "src": m["src"],
             "k": float(m.get("k", 1.0)), "b": float(m.get("b", 0.0))}
            for m in moves
        ]

    def set_timer_preset(self, index: int, seconds: float) -> None:
        if seconds <= 0.0:
            raise ValueError("preset must be positive")
        self.timer_presets[index] = seconds

    def _check_index(self, family: str, index: int) -> None:
        limits = {"di": self.n_di, "do": self.n_do, "ai": self.n_ai,
                  "ao": self.n_ao, "m": len(self.mem), "t": len(self.timer_acc)}
        if index >= limits[family]:
            raise ValueError(f"{family}_{index} out of range (max {limits[family] - 1})")

    # ---- scan ---------------------------------------------------------------

    def _read(self, ref: str) -> bool:
        family, index_s = ref.split("_")
        index = int(index_s)
        if family == "di":
            return bool(self.di_ports[index].value)
        if family == "do":
            return bool(self.do_ports[index].value)
        if family == "m":
            return self.mem[index]
        return self.timer_done[index]

    def tick(self, dt: float) -> None:
        if float(self.power.value) <= 0.5:
            # De-energized: outputs drop, timers reset, memory holds
            # (battery-backed), no scan runs.
            for port in self.do_ports:
                port.value = False
            for port in self.ao_ports:
                port.value = 0.0
            for i in range(len(self.timer_run)):
                self.timer_run[i] = False
                self.timer_acc[i] = 0.0
                self.timer_done[i] = False
            return
        self.scans += 1
        # Outputs no rung drives stay off; timers must be re-driven
        # every scan or they release (TON semantics).
        for port in self.do_ports:
            port.value = False
        driven_timers = [False] * len(self.timer_run)
        for rung in self.program:
            value = any(
                all(self._read(e["ref"]) != e["nc"] for e in branch)
                for branch in rung["logic"]
            )
            family, index_s = rung["coil"].split("_")
            index = int(index_s)
            if family == "do":
                self.do_ports[index].value = value
            elif family == "m":
                self.mem[index] = value
            else:
                self.timer_run[index] = value
                driven_timers[index] = True
        for i in range(len(self.timer_run)):
            if not driven_timers[i]:
                self.timer_run[i] = False
            if self.timer_run[i]:
                self.timer_acc[i] = min(self.timer_acc[i] + dt, self.timer_presets[i])
            else:
                self.timer_acc[i] = 0.0
            # Epsilon absorbs float accumulation (real PLCs count ms).
            self.timer_done[i] = self.timer_acc[i] >= self.timer_presets[i] - 1e-9
        for move in self.ao_moves:
            src = self.ai_ports[int(move["src"].split("_")[1])]
            dst = self.ao_ports[int(move["dst"].split("_")[1])]
            dst.value = float(src.value) * move["k"] + move["b"]

    # ---- save/load ----------------------------------------------------------

    def state_dict(self) -> dict:
        return {
            "program": self.program, "ao_moves": self.ao_moves,
            "mem": list(self.mem), "timer_acc": list(self.timer_acc),
            "timer_presets": list(self.timer_presets),
        }

    def apply_state(self, state: dict) -> None:
        if state.get("program"):
            self.set_program(state["program"])
        if state.get("ao_moves"):
            self.set_ao_moves(state["ao_moves"])
        for i, value in enumerate(state.get("mem", [])[: len(self.mem)]):
            self.mem[i] = bool(value)
        for i, value in enumerate(state.get("timer_acc", [])[: len(self.timer_acc)]):
            self.timer_acc[i] = float(value)
        for i, value in enumerate(state.get("timer_presets", [])[: len(self.timer_presets)]):
            self.timer_presets[i] = float(value)


class PID(Component):
    """Positional PID on analog signals, derivative on PV, clamped
    integrator for anti-windup, bumpless manual/auto via integrator
    tracking. Output is 0-100 % by default — a valve command.
    """

    MODES = ("auto", "manual")

    def __init__(
        self,
        name: str,
        kp: float = 1.0,
        ki: float = 0.0,
        kd: float = 0.0,
        sp: float = 0.0,
        out_min: float = 0.0,
        out_max: float = 100.0,
    ) -> None:
        super().__init__(name)
        if out_max <= out_min:
            raise ValueError("out_max must exceed out_min")
        self.kp, self.ki, self.kd = kp, ki, kd
        self.sp = sp
        self.out_min, self.out_max = out_min, out_max
        self.mode = "auto"
        self.manual_out = 0.0
        self.output = 0.0
        self.error = 0.0
        self._integrator = 0.0
        self._prev_pv = 0.0
        self._seen_pv = False
        self.pv = self.add_input("pv", PortKind.SIGNAL_ANALOG)
        self.out = self.add_output("out", PortKind.SIGNAL_ANALOG)
        self.add_observable("sp", "sp")
        self.add_observable("output", "output")
        self.add_observable("error", "error")

    def set_mode(self, mode: str) -> None:
        if mode not in self.MODES:
            raise ValueError(f"mode must be one of {self.MODES}")
        self.mode = mode

    def tick(self, dt: float) -> None:
        pv = float(self.pv.value)
        if not self._seen_pv:
            self._prev_pv = pv
            self._seen_pv = True
        self.error = self.sp - pv
        if self.mode == "manual":
            self.output = max(self.out_min, min(self.out_max, self.manual_out))
            # Track so a later auto transfer is bumpless.
            self._integrator = self.output - self.kp * self.error
        else:
            self._integrator += self.ki * self.error * dt
            derivative = -self.kd * (pv - self._prev_pv) / dt if dt > 0.0 else 0.0
            raw = self.kp * self.error + self._integrator + derivative
            self.output = max(self.out_min, min(self.out_max, raw))
            if raw != self.output:  # clamped: hold the integrator back
                self._integrator = self.output - self.kp * self.error - derivative
        self._prev_pv = pv
        self.out.value = self.output

    def state_dict(self) -> dict:
        return {
            "kp": self.kp, "ki": self.ki, "kd": self.kd, "sp": self.sp,
            "mode": self.mode, "manual_out": self.manual_out,
            "integrator": self._integrator, "output": self.output,
        }

    def apply_state(self, state: dict) -> None:
        self.kp = float(state.get("kp", self.kp))
        self.ki = float(state.get("ki", self.ki))
        self.kd = float(state.get("kd", self.kd))
        self.sp = float(state.get("sp", self.sp))
        self.mode = str(state.get("mode", self.mode))
        self.manual_out = float(state.get("manual_out", self.manual_out))
        self._integrator = float(state.get("integrator", self._integrator))
        self.output = float(state.get("output", self.output))
        self.out.value = self.output
