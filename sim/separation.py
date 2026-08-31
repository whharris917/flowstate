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
from sim.species import get as get_species
from sim.stream import AMBIENT_C, SOLID_KEY, Stream, comp_from_amounts


class Crystallizer(Component):
    """Cooled, agitated vessel that drops product out of solution.

        S(T)   = (S20 + m*(T - 20)) / 1000      (volume fraction)
        excess = x_dissolved - S(T)
        dx/dt  = excess * f_mix / tau

    Cool the batch below saturation and crystals grow toward
    equilibrium with a time constant; warm it back up and they
    redissolve, because the same equation runs in both directions.
    Without a powered agitator the process crawls -- nucleation needs
    the shear.

    The cooling duty is a positive number on ``cool_duty``: kilowatts
    *removed*. Wire a chiller loop or a controller output to it.
    """

    TAU_S = 60.0
    UNMIXED_FACTOR = 0.1
    LOSS_PER_S = 0.0004
    OUTLET_MAX_LPS = 250.0
    MIN_THERMAL_MASS_KG = 50.0
    # A jacket cannot chill the batch below the coolant feeding it.
    # Without this a duty left on drives the vessel to nonsense.
    COOLANT_C = 5.0

    def __init__(self, name: str, capacity_l: float = 3000.0) -> None:
        super().__init__(name)
        if capacity_l <= 0.0:
            raise ValueError("capacity_l must be positive")
        self.capacity_l = capacity_l
        self.volume_l = 0.0
        self.temp_c = AMBIENT_C
        self.agitating = False
        self.overflowed_l = 0.0
        self.contents = Stream(0.0, AMBIENT_C, None)
        self.inlet = self.add_input("inlet", PortKind.PROCESS_STREAM)
        self.cool_duty = self.add_input("cool_duty", PortKind.SIGNAL_ANALOG)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.draw = self.add_input("draw", PortKind.PROCESS_FLOW)
        self.level = self.add_output("level", PortKind.PROCESS_LEVEL)
        self.outlet = self.add_output("outlet", PortKind.PROCESS_SUPPLY)
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

    def charge(self, volume_l: float, comp: dict[str, float],
               temp_c: float = AMBIENT_C, solids_frac: float = 0.0) -> None:
        self.volume_l = min(max(volume_l, 0.0), self.capacity_l)
        self.temp_c = temp_c
        self.contents = Stream(self.volume_l, temp_c, comp, solids_frac)

    def saturation_frac(self) -> float:
        """Equilibrium dissolved fraction of the crystallizing species
        at the current temperature. Grams per litre becomes a volume
        fraction directly on the kernel's 1 L = 1 kg basis."""
        return get_species(SOLID_KEY).solubility_g_per_l(self.temp_c) / 1000.0

    @property
    def supersaturation(self) -> float:
        """How far past saturation the dissolved product is. Negative
        means there is room for more, and crystals will redissolve."""
        dissolved = self.contents.frac(SOLID_KEY) - self.contents.solids_frac
        return dissolved - self.saturation_frac()

    def tick(self, dt: float) -> None:
        incoming: Stream = self.inlet.value
        added_l = incoming.flow_lps * dt
        outflow_l = min(float(self.draw.value) * dt, self.volume_l + added_l)

        if added_l > 0.0:
            self.contents = Stream.mix(
                self.contents.with_flow(self.volume_l), incoming.with_flow(added_l)
            )
        new_volume = self.volume_l + added_l - outflow_l
        if new_volume > self.capacity_l:
            self.overflowed_l += new_volume - self.capacity_l
            new_volume = self.capacity_l
        self.volume_l = max(new_volume, 0.0)

        # Energy: duty is heat removed, so it subtracts.
        self.temp_c = self.contents.temp_c
        self.agitating = float(self.power.value) > 0.5
        mass = max(self.volume_l, self.MIN_THERMAL_MASS_KG)
        cp = self.contents.cp_kj_per_kg_k()
        self.temp_c -= float(self.cool_duty.value) / (mass * cp) * dt
        self.temp_c -= (self.temp_c - AMBIENT_C) * self.LOSS_PER_S * dt
        # The jacket can only take the batch down to its coolant.
        if float(self.cool_duty.value) > 0.0:
            self.temp_c = max(self.temp_c, self.COOLANT_C)

        # Crystallize toward equilibrium, in both directions.
        mix_factor = 1.0 if self.agitating else self.UNMIXED_FACTOR
        total_product = self.contents.frac(SOLID_KEY)
        solid = self.contents.solids_frac
        dissolved = total_product - solid
        excess = dissolved - self.saturation_frac()
        change = excess * mix_factor * dt / self.TAU_S
        # Never more solid than there is product, never less than none.
        solid = min(max(solid + change, 0.0), total_product)

        self.contents = Stream(
            self.volume_l, self.temp_c, self.contents.comp, solid
        )
        self.level.value = self.volume_l
        offered = min(self.volume_l / dt, self.OUTLET_MAX_LPS) if dt > 0.0 else 0.0
        self.outlet.value = self.contents.with_flow(offered)
        self.solids.value = self.contents.solids_frac
        self.temp.value = self.temp_c


class Dryer(Component):
    """Drives the last of the liquid off a wet filter cake.

        liquid_in = F * (1 - s)
        evap      = min(Q / latent, liquid_in)
        product   = F - evap

    What evaporates is the most volatile liquid present, so the solvent
    goes first and the crystals stay. Note what that means: anything
    that was *dissolved* in the retained mother liquor is left behind in
    the cake as the solvent leaves. A dryer concentrates impurity as
    surely as it concentrates product, which is why the wash matters
    upstream. Needs 480 V for the tumbler.
    """

    LATENT_KJ_PER_KG = 900.0

    def __init__(self, name: str, rate_lps: float = 2.0) -> None:
        super().__init__(name)
        if rate_lps <= 0.0:
            raise ValueError("rate_lps must be positive")
        self.rate_lps = rate_lps
        self.is_on = False
        self.running = False
        self.evap_lps = 0.0
        self.dried_l = 0.0
        self.inlet = self.add_input("inlet", PortKind.PROCESS_SUPPLY)
        self.heat_duty = self.add_input("heat_duty", PortKind.SIGNAL_ANALOG)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.product = self.add_output("product", PortKind.PROCESS_STREAM)
        self.vapor = self.add_output("vapor", PortKind.PROCESS_STREAM)
        self.draw = self.add_output("draw", PortKind.PROCESS_FLOW)
        self.add_observable("evap_lps", "evap_lps")
        self.add_observable("dried_l", "dried_l")

    def tick(self, dt: float) -> None:
        feed: Stream = self.inlet.value.clamped_solids()
        self.running = self.is_on and float(self.power.value) > 0.5
        rate = min(self.rate_lps, feed.flow_lps) if self.running else 0.0
        self.draw.value = rate
        if rate <= 0.0:
            self.evap_lps = 0.0
            self.product.value = Stream.empty()
            self.vapor.value = Stream.empty()
            return

        amounts = {key: rate * frac for key, frac in feed.comp.items()}
        solid_lps = rate * feed.solids_frac
        liquid_lps = rate - solid_lps
        capacity = max(float(self.heat_duty.value), 0.0) / self.LATENT_KJ_PER_KG
        to_evaporate = min(capacity, liquid_lps)

        # Take it off the most volatile liquid species first, never
        # touching what is already crystal.
        vapor_amounts: dict[str, float] = {}
        remaining = to_evaporate
        liquid_keys = sorted(
            (k for k in amounts if amounts[k] > 0.0),
            key=lambda k: get_species(k).boil_c,
        )
        for key in liquid_keys:
            if remaining <= 0.0:
                break
            liquid_here = amounts[key] - (solid_lps if key == SOLID_KEY else 0.0)
            take = min(remaining, max(liquid_here, 0.0))
            if take > 0.0:
                amounts[key] -= take
                vapor_amounts[key] = take
                remaining -= take
        evaporated = to_evaporate - remaining

        self.evap_lps = evaporated
        self.dried_l += evaporated * dt
        product_lps = rate - evaporated
        self.product.value = Stream(
            product_lps,
            feed.temp_c,
            comp_from_amounts(amounts),
            solid_lps / product_lps if product_lps > 0.0 else 0.0,
        )
        self.vapor.value = Stream(
            evaporated, feed.temp_c, comp_from_amounts(vapor_amounts)
        )


class Still(Component):
    """Continuous solvent recovery still: takes mother liquor, sends
    the light ends overhead and the heavy ends out the bottom.

        boilup = Q / latent
        to_top(i) = f_i * eta       if boil(i) <  cut
                  = f_i * (1 - eta) if boil(i) >= cut
        distillate = min(sum(to_top), boilup)

    ``eta`` is the sharpness of the cut -- a real column is never
    perfect, so some solvent leaves in the bottoms and some heavy ends
    carry over. The reboiler duty is the throttle: no duty, no boilup,
    no separation, and everything the still is fed leaves through the
    bottoms nozzle. Crystals never distill; they always report to the
    bottoms.

    This is the unit that closes the loop. Pipe the distillate back to
    a reagent header and the solvent goes round again.
    """

    LATENT_KJ_PER_KG = 900.0

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
        self.recovered_l = 0.0
        self.inlet = self.add_input("inlet", PortKind.PROCESS_SUPPLY)
        self.heat_duty = self.add_input("heat_duty", PortKind.SIGNAL_ANALOG)
        self.power = self.add_input("power", PortKind.POWER, "480VAC")
        self.distillate = self.add_output("distillate", PortKind.PROCESS_STREAM)
        self.bottoms = self.add_output("bottoms", PortKind.PROCESS_STREAM)
        self.draw = self.add_output("draw", PortKind.PROCESS_FLOW)
        self.add_observable("boilup_lps", "boilup_lps")
        self.add_observable("distillate_lps", "distillate_lps")
        self.add_observable("recovered_l", "recovered_l")

    def tick(self, dt: float) -> None:
        feed: Stream = self.inlet.value.clamped_solids()
        self.running = self.is_on and float(self.power.value) > 0.5
        rate = min(self.rate_lps, feed.flow_lps) if self.running else 0.0
        self.draw.value = rate
        self.boilup_lps = (
            max(float(self.heat_duty.value), 0.0) / self.LATENT_KJ_PER_KG
            if self.running else 0.0
        )
        if rate <= 0.0:
            self.distillate_lps = 0.0
            self.distillate.value = Stream.empty()
            self.bottoms.value = Stream.empty()
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
        # The reboiler sets the ceiling: you cannot take more overhead
        # than you can boil.
        scale = 1.0
        if wanted_total > self.boilup_lps:
            scale = self.boilup_lps / wanted_total if wanted_total > 0.0 else 0.0
        top_amounts = {k: v * scale for k, v in wanted.items()}
        top_total = sum(top_amounts.values())

        bottom_amounts: dict[str, float] = {}
        for key, frac in feed.comp.items():
            bottom_amounts[key] = rate * frac - top_amounts.get(key, 0.0)
        bottom_total = rate - top_total

        self.distillate_lps = top_total
        self.recovered_l += top_total * dt
        self.distillate.value = Stream(
            top_total, self.condenser_c, comp_from_amounts(top_amounts)
        )
        self.bottoms.value = Stream(
            bottom_total,
            feed.temp_c,
            comp_from_amounts(bottom_amounts),
            solid_lps / bottom_total if bottom_total > 0.0 else 0.0,
        )
