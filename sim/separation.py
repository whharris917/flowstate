"""Separation units: crystallizer, dryer, and solvent recovery still.

These are what turn a reactor full of dilute product into something in
a vial, and what closes the loop by sending the solvent back to the
front of the train.

Same standing rule as the rest of the kernel: rich streams between the
units, five-equation models inside them. A crystallizer is a
supersaturation driving force with a time constant. A dryer is an
energy balance against a latent heat. A still is a split ratio per
species with a boilup cap. None of them pretend to be more.
"""
from __future__ import annotations

from sim.core import Component, PortKind
from sim.hydraulics import (
    CheckResistance, ControlResistance, FixedFlow, PumpCurve,
    static_head_pa,
)
from sim.library import Equation, EquipmentSpec, Param
from sim.species import get as get_species
from sim.stream import AMBIENT_C, SOLID_KEY, Stream, comp_from_amounts


class Crystallizer(Component):
    """Cooled, agitated vessel that drops product out of solution.

    A vessel, so its outlet carries static head and its inlet sits at
    headspace. Cool the batch below saturation and crystals grow toward
    equilibrium with a time constant; warm it back up and they
    redissolve, because the same equation runs in both directions.
    Without a powered agitator the process crawls -- nucleation needs
    the shear.

    The cooling duty is a positive number on ``cool_duty``: kilowatts
    *removed*.
    """

    TAU_S = 60.0
    UNMIXED_FACTOR = 0.1
    LOSS_PER_S = 0.0004
    MIN_THERMAL_MASS_KG = 50.0
    COOLANT_C = 5.0

    def __init__(self, name: str, capacity_l: float = 3000.0,
                 height_m: float = 2.2, elevation_m: float = 0.0) -> None:
        super().__init__(name)
        if capacity_l <= 0.0:
            raise ValueError("capacity_l must be positive")
        self.capacity_l = capacity_l
        self.height_m = height_m
        self.elevation_m = elevation_m
        self.volume_l = 0.0
        self.temp_c = AMBIENT_C
        self.agitating = False
        self.overflowed_l = 0.0
        self.contents = Stream(0.0, AMBIENT_C, None)
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.cool_duty = self.add_input("cool_duty", PortKind.SIGNAL_ANALOG)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.outlet = self.add_output("outlet", PortKind.PROCESS_MATERIAL)
        self.level = self.add_output("level", PortKind.PROCESS_LEVEL)
        self.solids = self.add_output("solids", PortKind.SIGNAL_ANALOG)
        self.temp = self.add_output("temp", PortKind.SIGNAL_ANALOG)
        self.add_observable("temp_c", "temp_c")
        self.add_observable("volume_l", "volume_l")
        self.add_observable("solids_frac", "solids_frac")
        self.add_observable("supersaturation", "supersaturation")
        self.add_observable("overflowed_l", "overflowed_l")

    @property
    def solids_frac(self) -> float:
        return self.contents.solids_frac

    @property
    def cross_section_m2(self) -> float:
        return (self.capacity_l / 1000.0) / max(self.height_m, 1e-9)

    @property
    def depth_m(self) -> float:
        return (self.volume_l / 1000.0) / max(self.cross_section_m2, 1e-9)

    def charge(self, volume_l: float, comp: dict[str, float],
               temp_c: float = AMBIENT_C, solids_frac: float = 0.0) -> None:
        self.volume_l = min(max(volume_l, 0.0), self.capacity_l)
        self.temp_c = temp_c
        self.contents = Stream(self.volume_l, temp_c, comp, solids_frac)
        self.level.value = self.volume_l

    def saturation_frac(self) -> float:
        """Equilibrium dissolved fraction of the crystallizing species
        at the current temperature. Grams per litre becomes a volume
        fraction directly on the kernel 1 L = 1 kg basis."""
        return get_species(SOLID_KEY).solubility_g_per_l(self.temp_c) / 1000.0

    @property
    def supersaturation(self) -> float:
        dissolved = self.contents.frac(SOLID_KEY) - self.contents.solids_frac
        return dissolved - self.saturation_frac()

    def _feed_ports(self):
        return ("inlet",)

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
        nozzles = (self.inlet, self.outlet)
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
        self.temp_c -= float(self.cool_duty.value) / (mass * cp) * dt
        self.temp_c -= (self.temp_c - AMBIENT_C) * self.LOSS_PER_S * dt
        if float(self.cool_duty.value) > 0.0:
            self.temp_c = max(self.temp_c, self.COOLANT_C)

        mix_factor = 1.0 if self.agitating else self.UNMIXED_FACTOR
        total_product = self.contents.frac(SOLID_KEY)
        solid = self.contents.solids_frac
        excess = (total_product - solid) - self.saturation_frac()
        solid = min(max(solid + excess * mix_factor * dt / self.TAU_S, 0.0),
                    total_product)

        self.contents = Stream(
            self.volume_l, self.temp_c, self.contents.comp, solid
        )
        self.level.value = self.volume_l
        self.solids.value = self.contents.solids_frac
        self.temp.value = self.temp_c


class Dryer(Component):
    """Drives the last of the liquid off a wet filter cake.

    It has its own feed, so what it takes depends on what the hopper
    above it can give. What evaporates is the most volatile liquid
    present, so the solvent goes first and the crystals stay -- which
    means anything dissolved in the retained mother liquor is still
    there when the solvent leaves. The vapour goes out of the vent
    rather than a nozzle; ``dried_l`` totalizes it.
    """

    LATENT_KJ_PER_KG = 900.0
    FEED_HEAD_M = 12.0

    def __init__(self, name: str, rate_lps: float = 2.0) -> None:
        super().__init__(name)
        if rate_lps <= 0.0:
            raise ValueError("rate_lps must be positive")
        self.rate_lps = rate_lps
        self.is_on = False
        self.running = False
        self.evap_lps = 0.0
        self.dried_l = 0.0
        self.product_lps = 0.0
        self._cake = Stream.empty()
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.heat_duty = self.add_input("heat_duty", PortKind.SIGNAL_ANALOG)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.product = self.add_output("product", PortKind.PROCESS_MATERIAL)
        self._feed = None
        self._out = None
        self.add_observable("evap_lps", "evap_lps")
        self.add_observable("dried_l", "dried_l")
        self.add_observable("draw_lps", "draw_lps")

    @property
    def draw_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        drum = net.add_node(0.0)
        self._feed = net.add_branch(PumpCurve(
            node["inlet"], drum, static_head_pa(self.FEED_HEAD_M),
            self.rate_lps, self.name + ".feed"))
        self._out = net.add_branch(
            FixedFlow(drum, node["product"], 0.0, self.name + ".cake"))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        self.running = self.is_on and float(self.power.value) > 0.5
        if self._feed is not None:
            self._feed.running = self.running
        if self._out is not None:
            self._out.lps = self.product_lps

    def supplied_stream(self, port_name: str):
        return self._cake if port_name == "product" else None

    def tick(self, dt: float) -> None:
        feed = self.inlet.stream.clamped_solids()
        rate = self.draw_lps
        if rate <= 1e-9:
            self.evap_lps = 0.0
            self.product_lps = 0.0
            return

        amounts = {key: rate * frac for key, frac in feed.comp.items()}
        solid_lps = rate * feed.solids_frac
        liquid_lps = rate - solid_lps
        capacity = max(float(self.heat_duty.value), 0.0) / self.LATENT_KJ_PER_KG
        to_evaporate = min(capacity, liquid_lps)

        remaining = to_evaporate
        for key in sorted(
                (k for k in amounts if amounts[k] > 0.0),
                key=lambda k: get_species(k).boil_c):
            if remaining <= 0.0:
                break
            liquid_here = amounts[key] - (solid_lps if key == SOLID_KEY else 0.0)
            take = min(remaining, max(liquid_here, 0.0))
            if take > 0.0:
                amounts[key] -= take
                remaining -= take
        evaporated = to_evaporate - remaining

        self.evap_lps = evaporated
        self.dried_l += evaporated * dt
        self.product_lps = rate - evaporated
        self._cake = Stream(
            max(self.product_lps, 1e-9), feed.temp_c, comp_from_amounts(amounts),
            solid_lps / self.product_lps if self.product_lps > 0.0 else 0.0)


class Still(Component):
    """Continuous solvent recovery still: light ends overhead, heavy
    ends out the bottom.

    The reboiler duty is the throttle: no duty, no boilup, no
    separation, and everything it is fed leaves through the bottoms.
    The cut is never perfect, which is why recycled solvent is never
    quite as clean as fresh. Crystals never distill.

    This is the unit that closes the loop: pipe the distillate back to a
    feed header and the solvent goes round again.
    """

    LATENT_KJ_PER_KG = 900.0
    FEED_HEAD_M = 20.0

    def __init__(self, name: str, rate_lps: float = 3.0, cut_c: float = 150.0,
                 sharpness: float = 0.95, condenser_c: float = 40.0) -> None:
        super().__init__(name)
        if rate_lps <= 0.0:
            raise ValueError("rate_lps must be positive")
        if not 0.5 <= sharpness <= 1.0:
            raise ValueError("sharpness must be within [0.5, 1]")
        self.rate_lps = rate_lps
        self.cut_c = cut_c
        self.sharpness = sharpness
        self.condenser_c = condenser_c
        self.is_on = False
        self.running = False
        self.boilup_lps = 0.0
        self.distillate_lps = 0.0
        self.bottoms_lps = 0.0
        self.recovered_l = 0.0
        self._top = Stream.empty()
        self._bottom = Stream.empty()
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.heat_duty = self.add_input("heat_duty", PortKind.SIGNAL_ANALOG)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.distillate = self.add_output("distillate", PortKind.PROCESS_MATERIAL)
        self.bottoms = self.add_output("bottoms", PortKind.PROCESS_MATERIAL)
        self._feed = None
        self._to_top = None
        self._to_bottom = None
        self.add_observable("boilup_lps", "boilup_lps")
        self.add_observable("distillate_lps", "distillate_lps")
        self.add_observable("recovered_l", "recovered_l")
        self.add_observable("draw_lps", "draw_lps")

    @property
    def draw_lps(self) -> float:
        return max(self.inlet.flow_lps, 0.0)

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        sump = net.add_node(0.0)
        self._feed = net.add_branch(PumpCurve(
            node["inlet"], sump, static_head_pa(self.FEED_HEAD_M),
            self.rate_lps, self.name + ".feed"))
        self._to_top = net.add_branch(
            FixedFlow(sump, node["distillate"], 0.0, self.name + ".overhead"))
        self._to_bottom = net.add_branch(
            FixedFlow(sump, node["bottoms"], 0.0, self.name + ".bottoms"))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        self.running = self.is_on and float(self.power.value) > 0.5
        if self._feed is not None:
            self._feed.running = self.running
        if self._to_top is not None:
            self._to_top.lps = self.distillate_lps
            self._to_bottom.lps = self.bottoms_lps

    def supplied_stream(self, port_name: str):
        if port_name == "distillate":
            return self._top
        if port_name == "bottoms":
            return self._bottom
        return None

    def tick(self, dt: float) -> None:
        feed = self.inlet.stream.clamped_solids()
        rate = self.draw_lps
        self.boilup_lps = (
            max(float(self.heat_duty.value), 0.0) / self.LATENT_KJ_PER_KG
            if self.running else 0.0
        )
        if rate <= 1e-9:
            self.distillate_lps = 0.0
            self.bottoms_lps = 0.0
            return

        solid_lps = rate * feed.solids_frac
        wanted: dict[str, float] = {}
        for key, frac in feed.comp.items():
            available = rate * frac - (solid_lps if key == SOLID_KEY else 0.0)
            if available <= 0.0:
                continue
            light = get_species(key).boil_c < self.cut_c
            wanted[key] = available * (
                self.sharpness if light else 1.0 - self.sharpness
            )

        wanted_total = sum(wanted.values())
        scale = 1.0
        if wanted_total > self.boilup_lps:
            scale = self.boilup_lps / wanted_total if wanted_total > 0.0 else 0.0
        top_amounts = {k: v * scale for k, v in wanted.items()}
        top_total = sum(top_amounts.values())
        bottom_amounts = {
            key: rate * frac - top_amounts.get(key, 0.0)
            for key, frac in feed.comp.items()
        }
        bottom_total = rate - top_total

        self.distillate_lps = top_total
        self.bottoms_lps = bottom_total
        self.recovered_l += top_total * dt
        self._top = Stream(max(top_total, 1e-9), self.condenser_c,
                           comp_from_amounts(top_amounts))
        self._bottom = Stream(
            max(bottom_total, 1e-9), feed.temp_c,
            comp_from_amounts(bottom_amounts),
            solid_lps / bottom_total if bottom_total > 0.0 else 0.0)


# ---------------------------------------------------------------------
# Library pages. The only copy of these equations; see sim/library.py.
# ---------------------------------------------------------------------

Crystallizer.SPEC = EquipmentSpec(
    key="crystallizer",
    title="Cooling Crystallizer",
    tier="separation",
    summary=(
        "A cooled, agitated vessel that drops product out of solution "
        "by taking it below its solubility. Cool it and crystals grow; "
        "warm it back up and they dissolve again, because it is the same "
        "equation running in both directions. It needs the agitator: "
        "nucleation wants the shear."
    ),
    ports={
        "inlet": "Hot, dilute solution from upstream.",
        "cool_duty": "Kilowatts *removed*, as an analog signal. Wire a "
                     "chiller or a controller output.",
        "power": "480 V to the agitator.",
        "draw": "What downstream equipment is pulling off the outlet.",
        "level": "Contents level tap.",
        "outlet": "Slurry, offered to whatever pulls on it.",
        "solids": "Fraction of the contents present as crystal, as an "
                  "analog signal.",
        "temp": "Batch temperature, as an analog signal.",
    },
    equations=(
        Equation(
            "S(T) = (S20 + m * (T - 20)) / 1000",
            "Solubility as a straight line in temperature. Dividing by "
            "1000 turns grams per litre into a volume fraction, because "
            "the kernel takes 1 L as 1 kg.",
        ),
        Equation(
            "excess = x_dissolved - S(T)",
            "The driving force. Positive means crystals will grow; "
            "negative means they will redissolve.",
        ),
        Equation(
            "dx_solid/dt = excess * f_mix / tau",
            "First-order approach to equilibrium, slowed twentyfold "
            "without agitation.",
        ),
        Equation(
            "dT/dt = -Q_cool / (m * cp) - (T - T_ambient) * k_loss",
            "Energy balance. Duty is heat removed, so it subtracts.",
        ),
        Equation(
            "T >= T_coolant",
            "A jacket cannot chill the batch below the coolant feeding "
            "it, whatever duty you ask for.",
        ),
    ),
    params=(
        Param("capacity_l", "L", "Working volume before it overflows."),
    ),
    assumptions=(
        "One crystallizing species, and crystals are pure -- no "
        "co-precipitation and no inclusion of impurity in the lattice.",
        "No crystal size distribution: the solid is a single number, so "
        "there is no fines/growth behaviour and nothing for a mill.",
        "Solubility is linear in temperature, not a real curve.",
    ),
)

Dryer.SPEC = EquipmentSpec(
    key="dryer",
    title="Cake Dryer",
    tier="separation",
    summary=(
        "Drives the last of the liquid off a wet filter cake. What "
        "evaporates is whatever is most volatile, so the solvent goes "
        "and the crystals stay. Note what that means: anything dissolved "
        "in the retained mother liquor is still there when the solvent "
        "leaves. A dryer concentrates impurity exactly as well as it "
        "concentrates product."
    ),
    ports={
        "inlet": "Wet cake, pulled from a hopper or a vessel.",
        "heat_duty": "Drying duty in kW, as an analog signal.",
        "power": "480 V to the tumbler.",
        "product": "Dried cake.",
        "vapor": "What was driven off, as a real stream to condense or vent.",
        "draw": "Cake actually taken, metered back upstream.",
    },
    equations=(
        Equation(
            "liquid_in = F * (1 - s)",
            "Only the liquid part of the cake can evaporate.",
        ),
        Equation(
            "evap = min(Q / latent, liquid_in)",
            "Energy sets the ceiling; the liquid present sets the other "
            "one. A huge duty on a dry cake does nothing.",
        ),
        Equation(
            "product = F - evap",
            "Everything that did not leave as vapour leaves as cake.",
        ),
    ),
    params=(
        Param("rate_lps", "L/s", "Cake throughput."),
    ),
    assumptions=(
        "No drying curve: no constant-rate period, no falling-rate "
        "period, no bound moisture. Duty divided by latent heat, capped.",
        "Evaporation is strictly in order of boiling point.",
    ),
)

Still.SPEC = EquipmentSpec(
    key="still",
    title="Solvent Recovery Still",
    tier="separation",
    summary=(
        "Takes mother liquor and sends the light ends overhead and the "
        "heavy ends out the bottom. The reboiler duty is the throttle: "
        "no duty, no boilup, no separation, and everything you feed it "
        "leaves through the bottoms. This is the unit that closes the "
        "loop -- pipe the distillate back to a feed header and the "
        "solvent goes round again."
    ),
    ports={
        "inlet": "Feed, pulled from an upstream vessel.",
        "heat_duty": "Reboiler duty in kW, as an analog signal.",
        "power": "480 V to the reboiler.",
        "distillate": "Overhead product, condensed. Usually the recycle.",
        "bottoms": "Heavy ends, including every crystal in the feed.",
        "draw": "Feed actually taken, metered back upstream.",
    },
    equations=(
        Equation(
            "boilup = Q / latent",
            "The reboiler sets how much can go overhead at all.",
        ),
        Equation(
            "to_top(i) = f_i * eta          if boil(i) <  cut",
            "A species lighter than the cut mostly goes over.",
        ),
        Equation(
            "to_top(i) = f_i * (1 - eta)    if boil(i) >= cut",
            "A heavy one mostly stays down -- but not entirely. A real "
            "column is never a perfect cut, and that leak is why "
            "recycled solvent is never quite clean.",
        ),
        Equation(
            "distillate = min(sum(to_top), boilup)",
            "Scaled back proportionally if the reboiler cannot keep up.",
        ),
    ),
    params=(
        Param("rate_lps", "L/s", "Feed throughput."),
        Param("cut_c", "C", "Boiling point dividing light from heavy."),
        Param("sharpness", "-", "How clean the cut is. 1.0 would be "
                                "perfect separation."),
        Param("condenser_c", "C", "Temperature the distillate leaves at."),
    ),
    assumptions=(
        "No trays, no reflux ratio, no McCabe-Thiele: a single split "
        "ratio per species about one cut temperature.",
        "No column holdup -- feed in becomes products out on the same "
        "scan.",
        "Solids never distill; they always report to the bottoms.",
    ),
)
