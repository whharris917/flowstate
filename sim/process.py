"""Process-unit components: steam generation, heat exchange, reaction,
and separation — the machinery of an actual synthesis train.

Every unit here obeys the standing rule of this kernel: the streams
*between* units are rich (rate, temperature, composition, phase), and
the equations *inside* a unit are few and legible. There is no
discretized transport, no VLE, no film coefficient anywhere. A vessel
is a lumped inventory with a first-order energy balance; a separator is
a split ratio; a reaction is a rate law with two gates on it. That is
deliberate: a unit operation you can describe in five equations is a
unit operation the player can be shown in five equations.

All temperature/conversion dynamics are deterministic; every number a
view or gauge shows comes from these records.
"""
from __future__ import annotations

from sim.core import Component, PortKind
from sim.hydraulics import (
    CheckResistance, ControlResistance, FixedFlow, PumpCurve, Resistance,
    static_head_pa,
)
from sim.library import Equation, EquipmentSpec, Param
from sim.species import get as get_species
from sim.stream import AMBIENT_C, SOLID_KEY, Stream, comp_from_amounts


class SteamGen(Component):
    """Electrically fired steam generator.

    Feedwater arrives through the ``inlet`` nozzle and the burner needs
    480 V. What it holds is a header *pressure*, and that pressure is
    what pushes steam through anything connected downstream -- so an
    exchanger only gets steam if its condensate has somewhere to go.
    """

    PRESS_FULL_PA = 8.0e5
    PRESS_TAU_S = 10.0
    SAT_C_AT_ZERO = 100.0
    SAT_C_AT_FULL = 180.0
    #: Feedwater the burner will pull in per second at full fire.
    FEED_HEAD_M = 25.0

    def __init__(self, name: str, rated_kgps: float = 0.5) -> None:
        super().__init__(name)
        if rated_kgps <= 0.0:
            raise ValueError("rated_kgps must be positive")
        self.rated_kgps = rated_kgps
        self.is_on = False
        self.making = False
        self.press_pa = 0.0
        self.starve_s = 0.0
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.steam = self.add_output("steam", PortKind.PROCESS_MATERIAL)
        self.press = self.add_output("press", PortKind.PROCESS_PRESSURE)
        self._feed = None
        self.add_observable("press_pa", "press_pa")
        self.add_observable("starve_s", "starve_s")
        self.add_observable("sat_temp_c", "sat_temp_c")
        self.add_observable("steam_lps", "steam_lps")

    @property
    def sat_temp_c(self) -> float:
        frac = self.press_pa / self.PRESS_FULL_PA
        return self.SAT_C_AT_ZERO + (self.SAT_C_AT_FULL - self.SAT_C_AT_ZERO) * frac

    @property
    def steam_lps(self) -> float:
        return max(-self.steam.flow_lps, 0.0)

    @property
    def feedwater_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        drum = net.add_node(0.0)
        self._feed = net.add_branch(PumpCurve(
            node["inlet"], drum, static_head_pa(self.FEED_HEAD_M),
            self.rated_kgps, self.name + ".feed"))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        firing = self.is_on and float(self.power.value) > 0.5
        if self._feed is not None:
            self._feed.running = firing
        # The steam nozzle holds header pressure: that is what drives
        # steam anywhere at all.
        net.set_pressure(node["steam"], self.press_pa, fixed=True)

    def supplied_stream(self, port_name: str):
        if port_name == "steam":
            return Stream.pure("water", 1.0, self.sat_temp_c)
        return None

    def tick(self, dt: float) -> None:
        wet = self.feedwater_lps > 1e-6
        firing = self.is_on and float(self.power.value) > 0.5
        if firing and not wet:
            self.starve_s += dt  # firing dry: the operator problem
        self.making = firing and wet
        rate = self.feedwater_lps if self.making else 0.0
        target = self.PRESS_FULL_PA * min(rate / self.rated_kgps, 1.0)
        self.press_pa += (target - self.press_pa) * dt / self.PRESS_TAU_S
        self.press.value = self.press_pa


class HeatExchanger(Component):
    """Shell-and-tube preheater: steam on the shell, process on the
    tubes.

    The shell is a real path, not a number. Steam flows from the header
    through the shell to the condensate nozzle, driven by the pressure
    across it -- so an exchanger whose condensate has nowhere to go
    passes no steam and delivers no duty, exactly as a shell with no
    trap fitted would. Duty follows the steam that actually condensed.
    """

    LATENT_KJ_PER_KG = 2000.0
    APPROACH_C = 5.0
    #: Shell resistance, Pa per (L/s)^2. Sized so a few hundred kPa of
    #: header pressure passes a sensible steam rate.
    SHELL_K = 400_000.0
    TUBE_K = 2_000.0

    def __init__(self, name: str, max_duty_kw: float = 1200.0) -> None:
        super().__init__(name)
        if max_duty_kw <= 0.0:
            raise ValueError("max_duty_kw must be positive")
        self.max_duty_kw = max_duty_kw
        self.duty_kw = 0.0
        self.outlet_temp_c = AMBIENT_C
        self.steam_in = self.add_input("steam_in", PortKind.PROCESS_MATERIAL)
        self.cold_in = self.add_input("cold_in", PortKind.PROCESS_MATERIAL)
        self.cold_out = self.add_output("cold_out", PortKind.PROCESS_MATERIAL)
        self.condensate = self.add_output("condensate", PortKind.PROCESS_MATERIAL)
        self.duty = self.add_output("duty", PortKind.SIGNAL_ANALOG)
        self.add_observable("duty_kw", "duty_kw")
        self.add_observable("outlet_temp_c", "outlet_temp_c")
        self.add_observable("steam_lps", "steam_lps")

    @property
    def steam_lps(self) -> float:
        return max(self.steam_in.flow_lps, 0.0)

    @property
    def process_lps(self) -> float:
        return max(self.cold_in.flow_lps, 0.0)

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        net.add_branch(Resistance(node["steam_in"], node["condensate"],
                                  self.SHELL_K, self.name + ".shell"))
        net.add_branch(Resistance(node["cold_in"], node["cold_out"],
                                  self.TUBE_K, self.name + ".tubes"))

    def supplied_stream(self, port_name: str):
        if port_name == "cold_out":
            return self.cold_in.stream.with_temp(self.outlet_temp_c)
        if port_name == "condensate":
            return Stream.pure("water", 1.0, self.steam_in.stream.temp_c)
        return None

    def tick(self, dt: float) -> None:
        steam = self.steam_in.stream
        cold = self.cold_in.stream
        offered_kw = min(self.steam_lps * self.LATENT_KJ_PER_KG, self.max_duty_kw)
        if self.process_lps > 1e-9 and offered_kw > 0.0:
            cp = cold.cp_kj_per_kg_k()
            ceiling_c = max(steam.temp_c - self.APPROACH_C, cold.temp_c)
            rise_c = offered_kw / (self.process_lps * cp)
            self.outlet_temp_c = min(cold.temp_c + rise_c, ceiling_c)
            self.duty_kw = self.process_lps * cp * (self.outlet_temp_c - cold.temp_c)
        else:
            self.outlet_temp_c = cold.temp_c
            self.duty_kw = offered_kw if self.process_lps <= 1e-9 else 0.0
        self.duty.value = self.duty_kw


class Reactor(Component):
    """Jacketed stirred reactor: A + B -> product, plus an impurity.

    A vessel, so its nozzles behave like one: the feeds enter at the top
    against headspace pressure, and the outlet at the bottom carries the
    static head of the batch standing above it. Heat arrives as an
    analog duty; the agitator is a 480 V load.

    Conversion rate climbs with temperature and so does the impurity
    yield, so there is no single right setpoint. Running hot fills the
    vessel faster and dirtier, and that trade is the whole reason to
    instrument the thing.
    """

    REACT_MIN_C = 60.0
    REACT_FULL_C = 100.0
    LOSS_PER_S = 0.0008
    UNMIXED_FACTOR = 0.05
    MIN_THERMAL_MASS_KG = 50.0
    VAPOR_LATENT_KJ_PER_KG = 900.0
    IMPURITY_REF_C = 70.0
    IMPURITY_BASE = 0.02
    IMPURITY_SLOPE_PER_K = 0.004

    def __init__(self, name: str, capacity_l: float = 4000.0,
                 rate_lps: float = 6.0, height_m: float = 2.4,
                 elevation_m: float = 0.0) -> None:
        super().__init__(name)
        if capacity_l <= 0.0 or rate_lps <= 0.0:
            raise ValueError("capacity and rate must be positive")
        self.capacity_l = capacity_l
        self.rate_lps = rate_lps
        self.height_m = height_m
        self.elevation_m = elevation_m
        self.volume_l = 0.0
        self.temp_c = AMBIENT_C
        self.overflowed_l = 0.0
        self.boiled_off_l = 0.0
        self.boiling = False
        self.agitating = False
        self.contents = Stream(0.0, AMBIENT_C, None)
        self.inlet_a = self.add_input("inlet_a", PortKind.PROCESS_MATERIAL)
        self.inlet_b = self.add_input("inlet_b", PortKind.PROCESS_MATERIAL)
        self.heat_duty = self.add_input("heat_duty", PortKind.SIGNAL_ANALOG)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self.level = self.add_output("level", PortKind.PROCESS_LEVEL)
        self.purity = self.add_output("purity", PortKind.SIGNAL_ANALOG)
        self.temp = self.add_output("temp", PortKind.SIGNAL_ANALOG)
        self.add_observable("temp_c", "temp_c")
        self.add_observable("volume_l", "volume_l")
        self.add_observable("purity_frac", "purity_frac")
        self.add_observable("impurity_frac", "impurity_frac")
        self.add_observable("overflowed_l", "overflowed_l")
        self.add_observable("boiled_off_l", "boiled_off_l")

    @property
    def purity_frac(self) -> float:
        return self.contents.frac("product")

    @property
    def impurity_frac(self) -> float:
        return self.contents.frac("impurity")

    @property
    def product_l(self) -> float:
        return self.volume_l * self.purity_frac

    @property
    def cross_section_m2(self) -> float:
        return (self.capacity_l / 1000.0) / max(self.height_m, 1e-9)

    @property
    def depth_m(self) -> float:
        return (self.volume_l / 1000.0) / max(self.cross_section_m2, 1e-9)

    def charge(self, volume_l: float, comp: dict[str, float],
               temp_c: float = AMBIENT_C) -> None:
        self.volume_l = min(max(volume_l, 0.0), self.capacity_l)
        self.temp_c = temp_c
        self.contents = Stream(self.volume_l, temp_c, comp)
        self.level.value = self.volume_l

    def bubble_point_c(self) -> float:
        present = [
            get_species(key).boil_c
            for key, frac in self.contents.comp.items()
            if frac > 0.01
        ]
        return min(present) if present else 100.0

    def impurity_yield(self) -> float:
        y = self.IMPURITY_BASE + self.IMPURITY_SLOPE_PER_K * (
            self.temp_c - self.IMPURITY_REF_C
        )
        return min(max(y, 0.0), 1.0)

    def _feed_ports(self):
        return ("inlet_a", "inlet_b")

    def _headspace_pa(self) -> float:
        return 0.0

    #: The nozzle and its stub, Pa per (L/s)^2.
    NOZZLE_K = 800.0
    #: Flow the bottom nozzle passes at the reference drop.
    OUTLET_CV_LPS = 20.0
    #: Depth over which the bottom nozzle uncovers as the level falls
    #: past it. Smooth, so an emptying vessel tails off instead of
    #: chattering shut.
    UNCOVER_M = 0.03

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        self._roof = net.add_node(0.0, fixed=True)
        self._floor = net.add_node(0.0, fixed=True)
        for feed in self._feed_ports():
            net.add_branch(CheckResistance(
                node[feed], self._roof, self.NOZZLE_K,
                "%s.%s" % (self.name, feed)))
        self._outlet_branch = net.add_branch(ControlResistance(
            self._floor, node["outlet"], self.OUTLET_CV_LPS,
            self.name + ".outlet"))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        headspace_pa = self._headspace_pa()
        roof = headspace_pa + static_head_pa(self.elevation_m + self.height_m)
        floor = headspace_pa + static_head_pa(self.elevation_m + self.depth_m)
        net.set_pressure(self._roof, roof, fixed=True)
        net.set_pressure(self._floor, floor, fixed=True)
        # The bottom nozzle uncovers as the level drops past it. Filling
        # back in through it is always allowed -- that is how you charge
        # a vessel from below.
        # Which way it went last scan, read off the branch itself: a
        # node pressure can be floating, a solved flow cannot.
        filling = self._outlet_branch.flow_lps < -1e-9
        self._outlet_branch.opening = (
            1.0 if filling else min(self.depth_m / self.UNCOVER_M, 1.0))


    def supplied_stream(self, port_name: str):
        return self.contents.with_flow(1.0)

    def tick(self, dt: float) -> None:
        nozzles = (self.inlet_a, self.inlet_b, self.outlet)
        arriving = Stream.mix_all([
            port.stream.with_flow(port.flow_lps)
            for port in nozzles if port.flow_lps > 0.0
        ])
        leaving_lps = sum(-p.flow_lps for p in nozzles if p.flow_lps < 0.0)
        added_l = arriving.flow_lps * dt
        removed_l = min(leaving_lps * dt, self.volume_l + added_l)

        if added_l > 0.0:
            self.contents = Stream.mix(
                self.contents.with_flow(self.volume_l), arriving.with_flow(added_l)
            )
        new_volume = self.volume_l + added_l - removed_l
        if new_volume > self.capacity_l:
            self.overflowed_l += new_volume - self.capacity_l
            new_volume = self.capacity_l
        self.volume_l = max(new_volume, 0.0)
        self.temp_c = self.contents.temp_c

        self.agitating = float(self.power.value) > 0.5
        mass = max(self.volume_l, self.MIN_THERMAL_MASS_KG)
        cp = self.contents.cp_kj_per_kg_k()
        self.temp_c += float(self.heat_duty.value) / (mass * cp) * dt
        self.temp_c -= (self.temp_c - AMBIENT_C) * self.LOSS_PER_S * dt

        amounts = {
            key: self.volume_l * frac for key, frac in self.contents.comp.items()
        }

        # An atmospheric vessel cannot be driven past its bubble point:
        # surplus duty boils the most volatile thing in it and that
        # vapour leaves through the vent, which is why it comes off the
        # inventory rather than out of a nozzle.
        boil_c = self.bubble_point_c()
        self.boiling = self.temp_c > boil_c
        if self.boiling and self.volume_l > 0.0:
            surplus_kj = (self.temp_c - boil_c) * mass * cp
            self.temp_c = boil_c
            lightest = min(
                (k for k, v in amounts.items() if v > 0.0),
                key=lambda k: get_species(k).boil_c,
                default=None,
            )
            if lightest is not None:
                boiled_l = min(
                    surplus_kj / self.VAPOR_LATENT_KJ_PER_KG, amounts[lightest]
                )
                amounts[lightest] -= boiled_l
                self.volume_l -= boiled_l
                self.boiled_off_l += boiled_l

        temp_factor = min(
            max((self.temp_c - self.REACT_MIN_C)
                / (self.REACT_FULL_C - self.REACT_MIN_C), 0.0), 1.0)
        mix_factor = 1.0 if self.agitating else self.UNMIXED_FACTOR
        consumed = min(
            self.rate_lps * temp_factor * mix_factor * dt,
            amounts.get("reagent_a", 0.0),
            amounts.get("reagent_b", 0.0),
        )
        if consumed > 0.0:
            produced = 2.0 * consumed
            bad = self.impurity_yield()
            amounts["reagent_a"] = amounts.get("reagent_a", 0.0) - consumed
            amounts["reagent_b"] = amounts.get("reagent_b", 0.0) - consumed
            amounts["product"] = amounts.get("product", 0.0) + produced * (1.0 - bad)
            amounts["impurity"] = amounts.get("impurity", 0.0) + produced * bad

        self.contents = Stream(
            self.volume_l, self.temp_c, comp_from_amounts(amounts)
        )
        self.level.value = self.volume_l
        self.purity.value = self.purity_frac
        self.temp.value = self.temp_c


class Centrifuge(Component):
    """Disc-stack separator: crystals out of the liquor they formed in.

    It has its own feed pump, so what it draws is set by its curve
    against the suction it is given -- starve it and the rate falls
    away rather than the machine inventing material. What it does with
    what it drew is its own business: the split is set by the phase
    actually present in the feed, and nothing tells it what that is.
    """

    FEED_HEAD_M = 18.0

    def __init__(self, name: str, rate_lps: float = 4.0,
                 capture_eff: float = 0.95, cake_wetness: float = 0.25) -> None:
        super().__init__(name)
        if rate_lps <= 0.0:
            raise ValueError("rate_lps must be positive")
        if not 0.0 <= capture_eff <= 1.0:
            raise ValueError("capture_eff must be within [0, 1]")
        if cake_wetness < 0.0:
            raise ValueError("cake_wetness must be non-negative")
        self.rate_lps = rate_lps
        self.capture_eff = capture_eff
        self.cake_wetness = cake_wetness
        self.is_on = False
        self.spinning = False
        self.starts = 0
        self.cake_lps = 0.0
        self.liquor_lps = 0.0
        self._cake = Stream.empty()
        self._liquor = Stream.empty()
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.product = self.add_output("product", PortKind.PROCESS_MATERIAL)
        self.waste = self.add_output("waste", PortKind.PROCESS_MATERIAL)
        self._feed = None
        self._to_cake = None
        self._to_liquor = None
        self.add_observable("starts", "starts")
        self.add_observable("cake_lps", "cake_lps")
        self.add_observable("liquor_lps", "liquor_lps")
        self.add_observable("draw_lps", "draw_lps")

    @property
    def draw_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        bowl = net.add_node(0.0)
        self._feed = net.add_branch(PumpCurve(
            node["inlet"], bowl, static_head_pa(self.FEED_HEAD_M),
            self.rate_lps, self.name + ".feed"))
        self._to_cake = net.add_branch(
            FixedFlow(bowl, node["product"], 0.0, self.name + ".cake"))
        self._to_liquor = net.add_branch(
            FixedFlow(bowl, node["waste"], 0.0, self.name + ".liquor"))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        spinning = self.is_on and float(self.power.value) > 0.5
        if self._feed is not None:
            self._feed.running = spinning
        # The split is worked out from what actually came in, so the
        # discharges follow the draw by one scan.
        if self._to_cake is not None:
            self._to_cake.lps = self.cake_lps
            self._to_liquor.lps = self.liquor_lps

    def supplied_stream(self, port_name: str):
        if port_name == "product":
            return self._cake
        if port_name == "waste":
            return self._liquor
        return None

    def tick(self, dt: float) -> None:
        spinning = self.is_on and float(self.power.value) > 0.5
        if spinning and not self.spinning:
            self.starts += 1
        self.spinning = spinning
        feed = self.inlet.stream.clamped_solids()
        rate = self.draw_lps
        if rate <= 1e-9:
            self.cake_lps = 0.0
            self.liquor_lps = 0.0
            return

        liquid_comp = feed.liquid_comp()
        solids_lps = rate * feed.solids_frac
        captured = solids_lps * self.capture_eff
        cake_liquid = min(captured * self.cake_wetness, rate - solids_lps)
        cake_total = captured + cake_liquid
        liquor_total = rate - cake_total

        cake_amounts = {SOLID_KEY: captured}
        for key, frac in liquid_comp.items():
            cake_amounts[key] = cake_amounts.get(key, 0.0) + cake_liquid * frac
        liquor_amounts = {SOLID_KEY: solids_lps - captured}
        remaining_liquid = rate - solids_lps - cake_liquid
        for key, frac in liquid_comp.items():
            liquor_amounts[key] = (
                liquor_amounts.get(key, 0.0) + remaining_liquid * frac
            )

        self.cake_lps = cake_total
        self.liquor_lps = liquor_total
        self._cake = Stream(
            max(cake_total, 1e-9), feed.temp_c, comp_from_amounts(cake_amounts),
            captured / cake_total if cake_total > 0.0 else 0.0)
        self._liquor = Stream(
            max(liquor_total, 1e-9), feed.temp_c,
            comp_from_amounts(liquor_amounts),
            (solids_lps - captured) / liquor_total if liquor_total > 0.0 else 0.0)


class VacuumLock(Component):
    """Cyclic vacuum transfer lock: a chamber that pulls down to rough
    vacuum, dwells, re-pressurizes through its main air valve in
    discrete bursts, then dumps the condensate each cycle knocks out
    of the humid vented air through an automatic drainer. The cycle is
    a real state machine; ``press`` is a gauge-able output and
    ``drain_flow`` a real water stream to pipe to a drain. Needs 480 V
    for the vacuum pump; ``is_on`` starts the cycle.
    """

    PRESS_ATM_PA = 101300.0
    PRESS_VAC_PA = 18000.0
    EVAC_TAU_S = 6.0
    HOLD_S = 3.0
    VENT_BURSTS = 5
    VENT_PAUSE_S = 1.4
    CONDENSATE_PER_CYCLE_L = 5.0
    DRAIN_LPS = 1.2
    IDLE_EQUALIZE_TAU_S = 20.0

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.is_on = False
        self.state = "idle"          # idle/evacuate/hold/vent/drain
        self.press_pa = self.PRESS_ATM_PA
        self.condensate_l = 0.0
        self.draining_lps = 0.0
        self.cycles = 0
        self.vent_bursts_done = 0    # lifetime counter; views watch edges
        self.timer_s = 0.0
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.press = self.add_output("press", PortKind.PROCESS_PRESSURE)
        self.drain_flow = self.add_output("drain_flow", PortKind.PROCESS_MATERIAL)
        self._drainer = None
        self.add_observable("press_pa", "press_pa")
        self.add_observable("condensate_l", "condensate_l")
        self.add_observable("cycles", "cycles")

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        # The drainer pushes condensate out; where it goes is the
        # plant's problem, which is what a drain line is for.
        chamber = net.add_node(0.0, fixed=True)
        self._drainer = net.add_branch(
            FixedFlow(chamber, node["drain_flow"], 0.0, self.name + ".drainer"))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        if self._drainer is not None:
            self._drainer.lps = self.draining_lps

    def supplied_stream(self, port_name: str):
        return Stream.pure("water", 1.0, 40.0)

    def tick(self, dt: float) -> None:
        rate = 0.0
        if not (self.is_on and float(self.power.value) > 0.5):
            self.state = "idle"
            self.press_pa += ((self.PRESS_ATM_PA - self.press_pa)
                              * dt / self.IDLE_EQUALIZE_TAU_S)
        else:
            if self.state == "idle":
                self.state = "evacuate"
            if self.state == "evacuate":
                self.press_pa += ((self.PRESS_VAC_PA - self.press_pa)
                                  * dt / self.EVAC_TAU_S)
                if self.press_pa < self.PRESS_VAC_PA * 1.15:
                    self.state = "hold"
                    self.timer_s = self.HOLD_S
            elif self.state == "hold":
                self.timer_s -= dt
                if self.timer_s <= 0.0:
                    self.state = "vent"
                    self.timer_s = self.VENT_PAUSE_S
            elif self.state == "vent":
                self.timer_s -= dt
                if self.timer_s <= 0.0:
                    step = (self.PRESS_ATM_PA - self.PRESS_VAC_PA) / self.VENT_BURSTS
                    self.press_pa = min(self.PRESS_ATM_PA, self.press_pa + step)
                    self.vent_bursts_done += 1
                    self.timer_s = self.VENT_PAUSE_S
                    if self.press_pa >= self.PRESS_ATM_PA - 100.0:
                        self.condensate_l += self.CONDENSATE_PER_CYCLE_L
                        self.state = "drain"
            elif self.state == "drain":
                rate = self.DRAIN_LPS if self.condensate_l > 0.0 else 0.0
                self.condensate_l = max(self.condensate_l - rate * dt, 0.0)
                if self.condensate_l <= 0.0:
                    self.cycles += 1
                    self.state = "evacuate"
        self.press.value = self.press_pa
        self.draining_lps = rate


class VialFiller(Component):
    """Automated vial filler/capper in an isolator: index, fill, cap.

    Every millilitre it puts in a vial is genuinely pulled through its
    inlet, and only while the fill station is actually filling -- which
    is what gives the machine its rhythm. It fills vials with whatever
    it is piped to and keeps an honest record of what that was.
    """

    VIAL_ML = 10.0
    INDEX_S = 0.5
    FILL_S = 1.1
    CAP_S = 0.8

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.is_on = False
        self.state = "idle"          # idle/index/fill/cap
        self.timer_s = 0.0
        self.vials_done = 0
        self.fill_purity = 0.0
        self.filled_l = 0.0
        self.product_filled_l = 0.0
        self.starved = False
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self._draw = None
        self.add_observable("vials_done", "vials_done")
        self.add_observable("fill_purity", "fill_purity")
        self.add_observable("product_filled_l", "product_filled_l")

    @property
    def needed_lps(self) -> float:
        return self.VIAL_ML / 1000.0 / self.FILL_S

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        # Filled vials leave the modelled system.
        away = net.add_node(0.0, fixed=True)
        self._draw = net.add_branch(
            FixedFlow(node["inlet"], away, 0.0, self.name + ".fill"))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        filling = self.state == "fill" and self.is_on \
            and float(self.power.value) > 0.5
        if self._draw is not None:
            self._draw.lps = self.needed_lps if filling else 0.0

    def tick(self, dt: float) -> None:
        feed = self.inlet.stream
        drawn = max(self.inlet.flow_lps, 0.0)
        # A dosing pump that cannot get its charge is starved, and the
        # suction going toward vacuum is how it finds out.
        self.starved = self.state == "fill" and drawn < self.needed_lps * 0.9
        running = self.is_on and float(self.power.value) > 0.5
        if not running:
            self.state = "idle"
        else:
            if self.state == "idle":
                self.state = "index"
                self.timer_s = self.INDEX_S
            self.timer_s -= dt
            if self.timer_s <= 0.0:
                if self.state == "index":
                    self.state = "fill"
                    self.timer_s = self.FILL_S
                elif self.state == "fill":
                    self.state = "cap"
                    self.timer_s = self.CAP_S
                elif self.state == "cap":
                    self.vials_done += 1
                    self.state = "index"
                    self.timer_s = self.INDEX_S
        self.fill_purity = feed.frac("product")
        self.filled_l += drawn * dt
        self.product_filled_l += drawn * self.fill_purity * dt


# ---------------------------------------------------------------------
# Library pages for the units above.
#
# These are the only copy of the equations. They sit in the same file as
# the tick() that implements them so the two are read and reviewed
# together. Port names, kinds and directions are NOT written here --
# the library reads those off a real component.
# ---------------------------------------------------------------------

SteamGen.SPEC = EquipmentSpec(
    key="steam_gen",
    title="Steam Generator",
    tier="utility",
    summary=(
        "An electrically fired package boiler. Give it feedwater, 480 V "
        "and a run command and it makes saturated steam at a header "
        "pressure that rises and falls with firing. Fire it without "
        "water and it does not break, but it keeps a running total of "
        "how long you did it for."
    ),
    ports={
        "inlet": "Feedwater. Pipe a water header to it.",
        "power": "480 V to the burner. No power, no steam, ever.",
        "steam": "Saturated steam to the plant, at the header temperature.",
        "press": "Header pressure tap for a gauge.",
        "draw": "Feedwater actually consumed, metered back to the header.",
    },
    equations=(
        Equation(
            "m_steam = min(rated, feed) if fired and wet else 0",
            "It makes its rating, or whatever feedwater it can get.",
        ),
        Equation(
            "dP/dt = (P_target - P) / tau,  P_target = P_full * m/rated",
            "Header pressure lags firing with a first-order time constant.",
        ),
        Equation(
            "T_sat = 100 + (180 - 100) * P / P_full",
            "Saturation temperature, linearised across the range. This is "
            "the ceiling on anything the steam is used to heat.",
        ),
    ),
    params=(
        Param("rated_kgps", "kg/s", "Steam output at full fire."),
    ),
    assumptions=(
        "Saturation temperature is a straight line in pressure, not a "
        "steam table.",
        "No superheat, no blowdown, no boiler inventory: feedwater in "
        "becomes steam out on the same scan.",
    ),
)

HeatExchanger.SPEC = EquipmentSpec(
    key="heat_exchanger",
    title="Shell-and-Tube Exchanger",
    tier="process",
    summary=(
        "Steam on the shell, process on the tubes. It heats the stream "
        "you actually run through it, and it cannot heat that stream "
        "past the temperature of the steam supplying it -- so an "
        "undersized header shows up as a process that will not come up "
        "to heat however long you wait."
    ),
    ports={
        "steam_in": "Steam to the shell.",
        "cold_in": "Process stream into the tubes.",
        "cold_out": "The same stream, hotter. Composition is unchanged.",
        "condensate": "Condensed steam, for a trap or a return header.",
        "duty": "Heat actually transferred, kW, as an analog signal.",
    },
    equations=(
        Equation(
            "Q_available = m_steam * latent",
            "The heat the steam could give up if it all condensed.",
        ),
        Equation(
            "Q_offered = min(Q_available, Q_max)",
            "Capped by the area you bought.",
        ),
        Equation(
            "T_out = min(T_in + Q_offered / (m_cold * cp), T_steam - approach)",
            "The temperature rise, limited by the steam temperature. "
            "This is the line that matters.",
        ),
        Equation(
            "Q = m_cold * cp * (T_out - T_in)",
            "Duty is recomputed from the rise actually achieved, so the "
            "signal never claims heat the process did not take.",
        ),
        Equation(
            "m_condensate = m_steam",
            "Everything admitted to the shell condenses and leaves by "
            "the trap. Steam the process could not absorb is wasted, "
            "not destroyed -- pipe the condensate somewhere and the "
            "waste is on a totalizer.",
        ),
    ),
    params=(
        Param("max_duty_kw", "kW", "Duty at full steam: the area limit."),
    ),
    assumptions=(
        "No LMTD and no heat transfer coefficient: duty is capped by a "
        "flat maximum and by the steam temperature, nothing else.",
        "A fixed 5 C approach stands in for the pinch.",
        "Zero holdup and zero thermal mass -- the exchanger responds "
        "within one scan.",
        "Surplus heat in over-admitted steam leaves with the condensate "
        "rather than being tracked as an enthalpy.",
    ),
)

Reactor.SPEC = EquipmentSpec(
    key="reactor",
    title="Jacketed Stirred Reactor",
    tier="process",
    summary=(
        "The heart of the train. Two reagents blend into the inventory "
        "and combine into product, with an impurity alongside. It needs "
        "heat to run at all and an agitator to run properly, and the "
        "hotter you push it the faster it goes and the dirtier it gets. "
        "There is no correct setpoint; that argument is the game."
    ),
    ports={
        "inlet_a": "First feed nozzle. Anything piped here joins the batch.",
        "inlet_b": "Second feed nozzle.",
        "heat_duty": "Jacket duty in kW. Wire an exchanger or a controller.",
        "power": "480 V to the agitator. Unstirred, it barely reacts.",
        "draw": "What downstream equipment is pulling off the outlet.",
        "level": "Contents level tap, for a switch or a transmitter.",
        "outlet": "The batch, offered to whatever pulls on it.",
        "vapor": "What boils off when duty exceeds the bubble point.",
        "purity": "Product fraction of the contents, as an analog signal.",
        "temp": "Batch temperature, as an analog signal.",
    },
    equations=(
        Equation(
            "f_T = clamp((T - 60) / (100 - 60), 0, 1)",
            "Temperature gate: nothing below 60 C, flat out at 100 C.",
        ),
        Equation(
            "f_mix = 1 if agitating else 0.05",
            "An unstirred vessel reacts at a twentieth of the rate.",
        ),
        Equation(
            "consumed = min(k * f_T * f_mix * dt, V*x_A, V*x_B)",
            "First-order in rate, limited by whichever reagent runs out "
            "first. The two combine one for one by volume.",
        ),
        Equation(
            "produced = 2 * consumed",
            "A litre of A and a litre of B make two litres of products, "
            "so the volume balance closes exactly.",
        ),
        Equation(
            "y_impurity = clamp(0.02 + 0.004 * (T - 70), 0, 1)",
            "Selectivity. Every degree above 70 C costs a little more "
            "of the batch to the impurity.",
        ),
        Equation(
            "dT/dt = Q / (m * cp) - (T - T_ambient) * k_loss",
            "Lumped energy balance: jacket duty in, ambient loss out. "
            "Incoming feed blends its own temperature in as it arrives.",
        ),
        Equation(
            "T <= bubble point of the contents",
            "Surplus duty boils the most volatile species present "
            "instead of raising the temperature further.",
        ),
    ),
    params=(
        Param("capacity_l", "L", "Working volume before it overflows."),
        Param("rate_lps", "L/s", "Reagent consumed per second at full "
                                 "temperature and full agitation."),
    ),
    assumptions=(
        "Perfectly mixed: one temperature and one composition for the "
        "whole vessel.",
        "The reaction is first-order in rate and gated, not a real rate "
        "law with an activation energy.",
        "No heat of reaction -- all the heat comes from the jacket.",
        "The bubble point is the lowest boiling species present, not a "
        "real vapour-liquid equilibrium.",
    ),
)

Centrifuge.SPEC = EquipmentSpec(
    key="centrifuge",
    title="Disc-Stack Centrifuge",
    tier="separation",
    summary=(
        "Spins crystals out of the liquor they formed in. It reads the "
        "solid phase actually present in its feed -- nothing tells it "
        "what it is separating. Feed it clear liquid and it honestly "
        "sends everything out the liquor nozzle. The cake comes off wet, "
        "which is why there is a dryer after it."
    ),
    ports={
        "inlet": "Slurry, pulled from an upstream vessel.",
        "power": "480 V to the bowl drive.",
        "product": "Wet cake: captured crystals plus clinging liquor.",
        "waste": "Mother liquor, plus any crystals the bowl missed.",
        "draw": "Slurry actually taken, metered back upstream.",
    },
    equations=(
        Equation(
            "F = min(rated, offered)",
            "It processes its rating or whatever the vessel can give it.",
        ),
        Equation(
            "captured = F * s * eta",
            "Of the solid in the feed, the bowl catches a fixed fraction.",
        ),
        Equation(
            "cake_liquid = captured * w",
            "Cake wetness: liquor retained per unit of crystal, carrying "
            "everything dissolved in it along for the ride.",
        ),
        Equation(
            "liquor = F - (captured + cake_liquid)",
            "Everything else leaves the other nozzle. The two add to F.",
        ),
    ),
    params=(
        Param("rate_lps", "L/s", "Throughput of the bowl."),
        Param("capture_eff", "-", "Fraction of incoming solid caught."),
        Param("cake_wetness", "-", "Litres of liquor retained per litre "
                                   "of crystal."),
    ),
    assumptions=(
        "A fixed capture efficiency: no g-force, no residence time, no "
        "particle size.",
        "The cake retains liquor at the feed composition -- there is no "
        "wash step yet.",
    ),
)

VacuumLock.SPEC = EquipmentSpec(
    key="vacuum_lock",
    title="Cyclic Vacuum Transfer Lock",
    tier="utility",
    summary=(
        "A chamber that pulls down to rough vacuum, dwells, lets air "
        "back in through the main valve in discrete bursts, and drains "
        "the condensate each cycle knocks out of the humid air. A real "
        "state machine on a real timer."
    ),
    ports={
        "power": "480 V to the vacuum pump. Lose it and the lock "
                 "equalizes back to atmosphere.",
        "press": "Chamber pressure tap for a gauge.",
        "drain_flow": "Condensate to a drain, delivered as it is made.",
    },
    equations=(
        Equation(
            "dP/dt = (P_vac - P) / tau      [evacuate]",
            "First-order pull-down toward the pump's blank-off pressure.",
        ),
        Equation(
            "P += (P_atm - P_vac) / n       [each vent burst]",
            "Re-pressurization happens in n discrete steps, not smoothly.",
        ),
        Equation(
            "condensate += V_cycle          [end of vent]",
            "Each completed cycle knocks a fixed volume out of the air.",
        ),
    ),
    assumptions=(
        "A fixed condensate volume per cycle rather than a humidity "
        "calculation.",
        "No gas composition and no leak rate: the chamber is either "
        "being pumped, holding, venting, or draining.",
    ),
)

VialFiller.SPEC = EquipmentSpec(
    key="vial_filler",
    title="Vial Filler / Capper",
    tier="process",
    summary=(
        "A three-station machine: index the conveyor, fill a vial, press "
        "the cap. Every millilitre it puts in a vial is genuinely pulled "
        "through its inlet. It will fill vials with whatever you pipe to "
        "it and keep an honest record of what that was."
    ),
    ports={
        "inlet": "Product, pulled from an upstream vessel.",
        "power": "480 V to the machine.",
        "draw": "Fill rate, metered back upstream. Zero except while "
                "actually filling.",
    },
    equations=(
        Equation(
            "rate = V_vial / t_fill    [fill station only]",
            "Draw is not continuous: it is zero while indexing and "
            "capping, which is what gives the machine its rhythm.",
        ),
        Equation(
            "cycle = t_index + t_fill + t_cap",
            "One vial per cycle, so throughput follows directly.",
        ),
        Equation(
            "product_filled += rate * x_product * dt",
            "What actually reached the vials, as opposed to what was "
            "supposed to.",
        ),
    ),
    assumptions=(
        "No reject station, no fill-weight variation, no stoppering "
        "distinct from capping.",
    ),
)
