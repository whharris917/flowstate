"""Process-unit components: steam generation, heat exchange, reaction,
and separation — the machinery of an actual synthesis train.

All temperature/conversion dynamics are first-order and deterministic;
every number a view or gauge shows comes from these records.
"""
from __future__ import annotations

from sim.core import Component, PortKind


class SteamGen(Component):
    """Electrically fired steam generator. Feedwater comes through the
    ``inlet`` facade pair (wire a supply header's outlet to it); the
    burner needs 480 V and is toggled with ``is_on``. Produces
    ``steam`` at the rated rate and holds a header ``press`` that
    rises and falls first-order with firing — tap it with a gauge.
    """

    PRESS_FULL_PA = 8.0e5
    PRESS_TAU_S = 10.0

    def __init__(self, name: str, rated_kgps: float = 0.5) -> None:
        super().__init__(name)
        if rated_kgps <= 0.0:
            raise ValueError("rated_kgps must be positive")
        self.rated_kgps = rated_kgps
        self.is_on = False
        self.making = False
        self.press_pa = 0.0
        self.starve_s = 0.0
        self.inlet = self.add_input("inlet", PortKind.PROCESS_LEVEL)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.steam = self.add_output("steam", PortKind.PROCESS_FLOW)
        self.press = self.add_output("press", PortKind.PROCESS_PRESSURE)
        self.draw = self.add_output("draw", PortKind.PROCESS_FLOW)
        self.add_observable("press_pa", "press_pa")
        self.add_observable("starve_s", "starve_s")

    def tick(self, dt: float) -> None:
        wet = float(self.inlet.value) > 0.05
        firing = self.is_on and float(self.power.value) > 0.5
        if firing and not wet:
            self.starve_s += dt  # firing dry: the operator's problem
        self.making = firing and wet
        rate = self.rated_kgps if self.making else 0.0
        self.steam.value = rate
        self.draw.value = rate
        target = self.PRESS_FULL_PA * (rate / self.rated_kgps)
        self.press_pa += (target - self.press_pa) * dt / self.PRESS_TAU_S
        self.press.value = self.press_pa


class HeatExchanger(Component):
    """Shell-and-tube preheater: steam on the shell, the process
    stream through the tubes (``cold_in`` -> ``cold_out``, one scan).
    The transferred ``duty`` (kW) is a real analog output — wire it to
    whatever the heat serves.
    """

    LATENT_KJ_PER_KG = 2000.0

    def __init__(self, name: str, max_duty_kw: float = 1200.0) -> None:
        super().__init__(name)
        if max_duty_kw <= 0.0:
            raise ValueError("max_duty_kw must be positive")
        self.max_duty_kw = max_duty_kw
        self.duty_kw = 0.0
        self.steam_in = self.add_input("steam_in", PortKind.PROCESS_FLOW)
        self.cold_in = self.add_input("cold_in", PortKind.PROCESS_FLOW)
        self.cold_out = self.add_output("cold_out", PortKind.PROCESS_FLOW)
        self.duty = self.add_output("duty", PortKind.SIGNAL_ANALOG)
        self.add_observable("duty_kw", "duty_kw")

    def tick(self, dt: float) -> None:
        self.duty_kw = min(float(self.steam_in.value) * self.LATENT_KJ_PER_KG,
                           self.max_duty_kw)
        self.cold_out.value = float(self.cold_in.value)
        self.duty.value = self.duty_kw


class Reactor(Component):
    """Jacketed stirred reactor. Reactants arrive on two feed nozzles
    (``inlet_a``/``inlet_b``, plain flow); heat arrives as an analog
    ``heat_duty`` in kW (a heat exchanger's duty output); the agitator
    is a 480 V load — unmixed contents barely react. Inventory
    converts from reactant to product first-order above the reaction
    temperature; ``purity`` (0..1) is a live analog output, and the
    vessel's outlet is the standard facade pair.
    """

    AMBIENT_C = 20.0
    REACT_MIN_C = 60.0
    REACT_FULL_C = 100.0
    CP_KJ_PER_KG_K = 4.0
    LOSS_PER_S = 0.0008
    UNMIXED_FACTOR = 0.05

    def __init__(self, name: str, capacity_l: float = 4000.0,
                 rate_lps: float = 6.0) -> None:
        super().__init__(name)
        if capacity_l <= 0.0 or rate_lps <= 0.0:
            raise ValueError("capacity and rate must be positive")
        self.capacity_l = capacity_l
        self.rate_lps = rate_lps      # max conversion rate at full temp
        self.volume_l = 0.0
        self.product_l = 0.0
        self.temp_c = self.AMBIENT_C
        self.overflowed_l = 0.0
        self.agitating = False
        self.inlet_a = self.add_input("inlet_a", PortKind.PROCESS_FLOW)
        self.inlet_b = self.add_input("inlet_b", PortKind.PROCESS_FLOW)
        self.heat_duty = self.add_input("heat_duty", PortKind.SIGNAL_ANALOG)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.draw = self.add_input("draw", PortKind.PROCESS_FLOW)
        self.level = self.add_output("level", PortKind.PROCESS_LEVEL)
        self.purity = self.add_output("purity", PortKind.SIGNAL_ANALOG)
        self.add_observable("temp_c", "temp_c")
        self.add_observable("volume_l", "volume_l")
        self.add_observable("purity_frac", "purity_frac")
        self.add_observable("overflowed_l", "overflowed_l")

    @property
    def purity_frac(self) -> float:
        return self.product_l / self.volume_l if self.volume_l > 1e-6 else 0.0

    def tick(self, dt: float) -> None:
        inflow = (float(self.inlet_a.value) + float(self.inlet_b.value)) * dt
        outflow = min(float(self.draw.value) * dt, self.volume_l + inflow)
        # Outflow removes mix at current purity.
        if self.volume_l > 1e-6:
            self.product_l -= outflow * self.purity_frac
        new_volume = self.volume_l + inflow - outflow
        if new_volume > self.capacity_l:
            spilled = new_volume - self.capacity_l
            self.overflowed_l += spilled
            self.product_l -= spilled * self.purity_frac
            new_volume = self.capacity_l
        self.volume_l = max(new_volume, 0.0)
        self.product_l = max(min(self.product_l, self.volume_l), 0.0)

        # Temperature: duty in, first-order losses; fresh feed dilutes.
        self.agitating = float(self.power.value) > 0.5
        mass = max(self.volume_l, 50.0)
        self.temp_c += float(self.heat_duty.value) / (mass * self.CP_KJ_PER_KG_K) * dt
        self.temp_c -= (self.temp_c - self.AMBIENT_C) * self.LOSS_PER_S * dt

        # Conversion: first-order in reactant, gated by temperature and
        # agitation.
        reactant = self.volume_l - self.product_l
        temp_factor = min(max((self.temp_c - self.REACT_MIN_C)
                              / (self.REACT_FULL_C - self.REACT_MIN_C), 0.0), 1.0)
        mix_factor = 1.0 if self.agitating else self.UNMIXED_FACTOR
        converted = min(reactant, self.rate_lps * temp_factor * mix_factor * dt)
        self.product_l += converted

        self.level.value = self.volume_l
        self.purity.value = self.purity_frac


class Centrifuge(Component):
    """Disc-stack separator: pulls mix from an upstream vessel through
    the ``inlet`` facade pair, splits it into ``product`` and
    ``waste`` streams using the wired ``purity_in`` quality signal.
    The bowl is a 480 V drive toggled with ``is_on``.
    """

    def __init__(self, name: str, rate_lps: float = 4.0) -> None:
        super().__init__(name)
        if rate_lps <= 0.0:
            raise ValueError("rate_lps must be positive")
        self.rate_lps = rate_lps
        self.is_on = False
        self.spinning = False
        self.starts = 0
        self.inlet = self.add_input("inlet", PortKind.PROCESS_LEVEL)
        self.purity_in = self.add_input("purity_in", PortKind.SIGNAL_ANALOG)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.product = self.add_output("product", PortKind.PROCESS_FLOW)
        self.waste = self.add_output("waste", PortKind.PROCESS_FLOW)
        self.draw = self.add_output("draw", PortKind.PROCESS_FLOW)
        self.add_observable("starts", "starts")

    def tick(self, dt: float) -> None:
        spinning = self.is_on and float(self.power.value) > 0.5
        if spinning and not self.spinning:
            self.starts += 1
        self.spinning = spinning
        wet = float(self.inlet.value) > 0.5
        rate = self.rate_lps if (spinning and wet) else 0.0
        purity = min(max(float(self.purity_in.value), 0.0), 1.0)
        self.draw.value = rate
        self.product.value = rate * purity
        self.waste.value = rate * (1.0 - purity)
