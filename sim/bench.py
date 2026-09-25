"""Chemistry at the bench: vessels, a hotplate stirrer, a meter and a
balance. Mirrors game/sim/sim_mixture.gd and the bench components.

A Mixture is what a vessel holds: moles of each library species, split
between the liquid (liquids and whatever is dissolved) and the solid
(undissolved or crystallized), at one temperature. Each scan it

1. reacts: every reaction whose reactants are present runs at its rate
   law, capped so no reactant goes negative and a reversible one does
   not overshoot its equilibrium; a fast one (neutralization,
   precipitation of ions) completes as quickly as the stirring mixes;
   a gas product leaves at once as bubbles;
2. dissolves and crystallizes each solid toward its solubility at the
   present temperature and solvent;
3. exchanges heat: the hotplate's heat in, loss to the room, heats of
   reaction and of solution;
4. boils: above the mixture's boiling point the surplus heat goes into
   vapour of the Raoult composition, which leaves.

Nothing is created or lost: what leaves as gas or vapour is counted in
``vented``, so the mass in plus reactions balances against contents
plus vented to rounding.
"""
from __future__ import annotations

import math
from typing import Optional

from .chemistry import KW, Library, library
from .core import Component

AMBIENT_C = 21.0
FAST_RATE = 20.0      # 1/s: a fast reaction completes as fast as it is mixed
K_DISSOLVE = 0.08     # 1/s toward saturation, stirred
K_CRYSTAL = 0.03      # 1/s toward saturation from above, just past it
MAX_DRIVE = 20.0      # the most supersaturation speeds crystallizing
GAS_ML_PER_MOL = 24465.0   # at 25 C and one atmosphere
GLASS_CP = 0.84       # J/(g K)
H_SURFACE = 15.0      # W/(m2 K), still air plus radiation off a warm vessel


def unstirred_mix() -> float:
    return 0.1


class Mixture:
    """Moles of each species, liquid and solid, at one temperature."""

    def __init__(self, lib: Optional[Library] = None, temp_c: float = AMBIENT_C) -> None:
        self.lib = lib or library()
        n = self.lib.count
        self.liquid: list[float] = [0.0] * n
        self.solid: list[float] = [0.0] * n
        self.vented: list[float] = [0.0] * n
        self.temp_c = temp_c
        self.gas_mol_s = 0.0      # gas made in the last step, per second
        self.boil_g_s = 0.0       # vapour boiled off in the last step, per second
        self.boiling = False

    # ---- building --------------------------------------------------------

    def add_grams(self, key: str, grams: float) -> None:
        s = self.lib.get(key)
        mol = grams / s.molar_mass
        if s.phase == "solid":
            self.solid[s.index] += mol
        elif s.phase == "gas":
            self.vented[s.index] += mol
        else:
            self.liquid[s.index] += mol

    @classmethod
    def from_stock(cls, stock_key: str, lib: Optional[Library] = None,
                   fill: float = 1.0) -> "Mixture":
        m = cls(lib)
        for key, grams in m.lib.stocks[stock_key].grams.items():
            m.add_grams(key, grams * fill)
        m.settle()
        return m

    def settle(self) -> None:
        """Put each solid species at its equilibrium split at once: a
        stock solution arrives dissolved, a stock powder dry."""
        for s in self.lib.species:
            if s.phase != "solid":
                continue
            total = self.liquid[s.index] + self.solid[s.index]
            cap = self.capacity_mol(s.index)
            self.liquid[s.index] = min(total, cap)
            self.solid[s.index] = total - self.liquid[s.index]

    # ---- what it is ------------------------------------------------------

    def mass_g(self) -> float:
        return sum((self.liquid[i] + self.solid[i]) * s.molar_mass
                   for i, s in enumerate(self.lib.species))

    def liquid_ml(self) -> float:
        return sum(self.liquid[i] * s.molar_mass / s.density
                   for i, s in enumerate(self.lib.species))

    def solid_ml(self) -> float:
        return sum(self.solid[i] * s.molar_mass / s.density
                   for i, s in enumerate(self.lib.species))

    def volume_ml(self) -> float:
        return self.liquid_ml() + self.solid_ml()

    def heat_capacity(self) -> float:
        """J/K of the contents."""
        return sum((self.liquid[i] + self.solid[i]) * s.molar_mass * s.cp
                   for i, s in enumerate(self.lib.species))

    def conc(self, i: int) -> float:
        litres = self.liquid_ml() / 1000.0
        return self.liquid[i] / litres if litres > 1e-9 else 0.0

    def _solvent_g(self) -> tuple[float, float]:
        water = organic = 0.0
        for i, s in enumerate(self.lib.species):
            if s.phase != "liquid":
                continue
            g = self.liquid[i] * s.molar_mass
            if s.solvent == "water":
                water += g
            else:
                organic += g
        return water, organic

    def capacity_mol(self, i: int) -> float:
        """How much of solid species i the liquid can hold dissolved."""
        s = self.lib.species[i]
        if s.phase != "solid":
            return math.inf
        water, organic = self._solvent_g()
        total = water + organic
        if total <= 1e-9:
            return 0.0
        grams = total * s.solubility(self.temp_c, water / total) / 100.0
        return grams / s.molar_mass

    def has_water(self) -> bool:
        water, organic = self._solvent_g()
        return water > 0.01 * (water + organic) and water > 1e-6

    def ph(self) -> Optional[float]:
        """By charge balance, or None with no water to speak of."""
        if not self.has_water():
            return None
        litres = self.liquid_ml() / 1000.0
        cations = anions = 0.0
        family_c: dict[str, float] = {}
        for i, s in enumerate(self.lib.species):
            c = self.liquid[i] / litres
            if c <= 0.0:
                continue
            cations += s.strong_cations * c
            anions += s.strong_anions * c
            if s.family:
                family_c[s.family] = family_c.get(s.family, 0.0) + c

        def excess(ph: float) -> float:
            h = 10.0 ** -ph
            q = h - KW / h + cations - anions
            for key, c in family_c.items():
                q += c * self.lib.families[key].mean_charge(h)
            return q

        lo, hi = -2.0, 16.0
        for _ in range(60):
            mid = 0.5 * (lo + hi)
            if excess(mid) > 0.0:
                lo = mid
            else:
                hi = mid
        return 0.5 * (lo + hi)

    def boiling_point(self) -> Optional[float]:
        """Where the liquid's vapour pressure reaches one atmosphere, or
        None when nothing in it boils."""
        total = sum(self.liquid)
        if total <= 1e-12:
            return None
        volatile = [(self.liquid[i] / total, s) for i, s in enumerate(self.lib.species)
                    if s.volatile and self.liquid[i] > 0.0]
        if not volatile:
            return None

        def pressure(t: float) -> float:
            return sum(x * s.vapour_kpa(t) for x, s in volatile)

        lo, hi = -50.0, 400.0
        if pressure(hi) < 101.325:
            return None
        for _ in range(50):
            mid = 0.5 * (lo + hi)
            if pressure(mid) < 101.325:
                lo = mid
            else:
                hi = mid
        return 0.5 * (lo + hi)

    # ---- moving it -------------------------------------------------------

    def take(self, liquid_frac: float, solid_frac: float) -> "Mixture":
        """Remove those fractions of the liquid and the solid; return them."""
        out = Mixture(self.lib, self.temp_c)
        lf = min(max(liquid_frac, 0.0), 1.0)
        sf = min(max(solid_frac, 0.0), 1.0)
        for i in range(self.lib.count):
            out.liquid[i] = self.liquid[i] * lf
            out.solid[i] = self.solid[i] * sf
            self.liquid[i] -= out.liquid[i]
            self.solid[i] -= out.solid[i]
        return out

    def add(self, other: "Mixture") -> None:
        """Pour other in; the temperature is the heat-capacity blend."""
        c_self = self.heat_capacity()
        c_other = other.heat_capacity()
        if c_self + c_other > 0.0:
            self.temp_c = (self.temp_c * c_self + other.temp_c * c_other) / (c_self + c_other)
        for i in range(self.lib.count):
            self.liquid[i] += other.liquid[i]
            self.solid[i] += other.solid[i]

    # ---- a scan ----------------------------------------------------------

    def step(self, dt: float, heat_w: float = 0.0, mix: float = 0.1,
             ua_w_k: float = 0.0, extra_cp_j_k: float = 0.0,
             ambient_c: float = AMBIENT_C) -> None:
        heat_j = 0.0
        gas = 0.0
        heat_j_r, gas = self._react(dt, mix)
        heat_j += heat_j_r
        heat_j += self._dissolve(dt, mix)
        c = self.heat_capacity() + extra_cp_j_k
        if c > 1e-9:
            self.temp_c += (heat_j + (heat_w - ua_w_k * (self.temp_c - ambient_c)) * dt) / c
        self.gas_mol_s = gas / dt if dt > 0.0 else 0.0
        self.boil_g_s = self._boil(dt, c) / dt if dt > 0.0 else 0.0

    def _react(self, dt: float, mix: float) -> tuple[float, float]:
        heat = 0.0
        gas = 0.0
        litres = self.liquid_ml() / 1000.0
        if litres <= 1e-9:
            return 0.0, 0.0
        h = -1.0    # found once, and only when an acid-catalysed reaction can run
        for r in self.lib.reactions:
            forward = all(self._available(r, i) > 0.0 for i in r.reactants)
            backward = r.equilibrium is not None and all(self.liquid[i] > 0.0 for i in r.products)
            if not forward and not backward:
                continue
            if r.h_order and h < 0.0:
                ph = self.ph()
                h = 10.0 ** -ph if ph is not None else 0.0
            extent = self._extent(r, dt, mix, litres, max(h, 0.0))
            if extent == 0.0:
                continue
            for i, nu in r.reactants.items():
                pool = self.solid if i in r.solid_reactants else self.liquid
                pool[i] = max(pool[i] - nu * extent, 0.0)
            for i, nu in r.products.items():
                s = self.lib.species[i]
                if s.phase == "gas":
                    self.vented[i] += nu * extent
                    gas += nu * extent
                else:
                    self.liquid[i] += nu * extent
                    if self.liquid[i] < 0.0:   # a reverse step took it
                        self.liquid[i] = 0.0
            heat += -r.dh * 1000.0 * extent
        return heat, gas

    def _available(self, r, i: int) -> float:
        return self.solid[i] if i in r.solid_reactants else self.liquid[i]

    def _extent(self, r, dt: float, mix: float, litres: float, h: float) -> float:
        forward_room = min(self._available(r, i) / nu for i, nu in r.reactants.items())
        if r.fast:
            if forward_room <= 0.0:
                return 0.0
            return forward_room * (1.0 - math.exp(-FAST_RATE * mix * dt))
        k = r.k(self.temp_c)
        rate = k * (h ** r.h_order if r.h_order else 1.0)
        for i, order in r.orders.items():
            rate *= (self._available(r, i) / litres) ** order
        for i, order in r.catalysts.items():
            rate *= (self.liquid[i] / litres) ** order
        # Only reactions between separate substances wait on stirring.
        if len(r.reactants) > 1 or r.catalysts:
            rate *= mix
        if r.equilibrium is None:
            return min(rate * litres * dt, forward_room * 0.999)
        # Reversible: the reverse rate from the equilibrium constant, and
        # a step that would cross equilibrium lands on it instead.
        back = k * (h ** r.h_order if r.h_order else 1.0) / r.equilibrium
        for i, nu in r.products.items():
            back *= self.liquid[i] / litres
        if len(r.reactants) > 1 or r.catalysts:
            back *= mix
        extent = (rate - back) * litres * dt
        reverse_room = min(self.liquid[i] / nu for i, nu in r.products.items())
        extent = min(max(extent, -reverse_room * 0.999), forward_room * 0.999)
        q_now = self._quotient_gap(r, 0.0, litres)
        q_new = self._quotient_gap(r, extent, litres)
        if q_now is not None and q_new is not None and (q_now > 0.0) != (q_new > 0.0):
            lo, hi = 0.0, extent
            for _ in range(30):
                mid = 0.5 * (lo + hi)
                g = self._quotient_gap(r, mid, litres)
                if g is None or (g > 0.0) == (q_now > 0.0):
                    lo = mid
                else:
                    hi = mid
            extent = lo
        return extent

    def _quotient_gap(self, r, extent: float, litres: float) -> Optional[float]:
        """log(Q / K) after advancing by extent; positive past equilibrium."""
        num = den = 0.0
        for i, nu in r.products.items():
            c = (self.liquid[i] + nu * extent) / litres
            if c <= 0.0:
                return -math.inf
            num += nu * math.log(c)
        for i, nu in r.reactants.items():
            c = (self._available(r, i) - nu * extent) / litres
            if c <= 0.0:
                return math.inf
            den += nu * math.log(c)
        return num - den - math.log(r.equilibrium)

    def _dissolve(self, dt: float, mix: float) -> float:
        heat = 0.0
        stirred = min(max(mix, 0.0), 1.0)
        for s in self.lib.species:
            if s.phase != "solid":
                continue
            i = s.index
            cap = self.capacity_mol(i)
            d = self.liquid[i]
            if self.solid[i] > 0.0 and d < cap:
                moved = min(self.solid[i], (cap - d) * (1.0 - math.exp(-K_DISSOLVE * stirred * dt)))
            elif d > cap:
                # The further past saturation, the faster it comes out: an
                # insoluble salt drops at once, a cooled solution slowly.
                drive = 1.0 + math.log(d / cap) if cap > 0.0 else MAX_DRIVE
                moved = -(d - cap) * (1.0 - math.exp(-K_CRYSTAL * min(drive, MAX_DRIVE) * dt))
            else:
                continue
            self.liquid[i] += moved
            self.solid[i] -= moved
            if self.solid[i] < 1e-15:
                self.solid[i] = 0.0
            heat += -s.dh_solution * 1000.0 * moved
        return heat

    def _boil(self, dt: float, c: float) -> float:
        """Boil off what is above the boiling point; returns grams."""
        self.boiling = False
        # An ideal mixture boils no lower than its lightest part does.
        lightest = min((s.bp for i, s in enumerate(self.lib.species)
                        if s.volatile and self.liquid[i] > 0.0), default=None)
        if lightest is None or self.temp_c <= lightest:
            return 0.0
        tb = self.boiling_point()
        if tb is None or self.temp_c <= tb:
            return 0.0
        total = sum(self.liquid)
        pressures = {}
        for i, s in enumerate(self.lib.species):
            if s.volatile and self.liquid[i] > 0.0:
                pressures[i] = self.liquid[i] / total * s.vapour_kpa(tb)
        p_sum = sum(pressures.values())
        if p_sum <= 0.0:
            return 0.0
        y = {i: p / p_sum for i, p in pressures.items()}
        latent = sum(y[i] * self.lib.species[i].dh_vap * 1000.0 for i in y)
        energy = (self.temp_c - tb) * c
        moles = energy / latent
        grams = 0.0
        for i, yi in y.items():
            gone = min(moles * yi, self.liquid[i])
            self.liquid[i] -= gone
            self.vented[i] += gone
            grams += gone * self.lib.species[i].molar_mass
        self.temp_c = tb
        self.boiling = grams > 0.0
        return grams

    # ---- save ------------------------------------------------------------

    def as_dict(self) -> dict:
        out = {"temp_c": self.temp_c, "liquid": {}, "solid": {}, "vented": {}}
        for s in self.lib.species:
            for pool in ("liquid", "solid", "vented"):
                v = getattr(self, pool)[s.index]
                if v != 0.0:
                    out[pool][s.key] = v
        return out

    @classmethod
    def from_dict(cls, d: dict, lib: Optional[Library] = None) -> "Mixture":
        m = cls(lib, float(d.get("temp_c", AMBIENT_C)))
        for pool in ("liquid", "solid", "vented"):
            for key, v in d.get(pool, {}).items():
                if key in m.lib.index_of:
                    getattr(m, pool)[m.lib.index_of[key]] = float(v)
        return m


# ---- vessel shapes ----------------------------------------------------------

# kind -> (reference capacity mL, diameter m, height m, glass g) at that
# capacity; other capacities scale the size by the cube root and the
# glass by the area.
SHAPES = {
    "beaker": (250.0, 0.070, 0.095, 100.0),
    "flask": (250.0, 0.085, 0.145, 110.0),
    "vial": (20.0, 0.0275, 0.057, 12.0),
    "bottle": (1000.0, 0.101, 0.220, 420.0),
}


def shape_of(kind: str, capacity_ml: float) -> tuple[float, float, float]:
    ref, d, h, g = SHAPES[kind]
    scale = (capacity_ml / ref) ** (1.0 / 3.0)
    return d * scale, h * scale, g * scale * scale


class LabVessel(Component):
    """A beaker, flask, sample vial or reagent bottle and what is in it.

    It has no ports: it is carried and poured by hand. Whatever it
    stands on acts on it: a hotplate sets ``heat_w`` and ``mix`` each
    scan, and clears them when the vessel leaves it.
    """

    def __init__(self, name: str, kind: str = "beaker", capacity_ml: float = 250.0,
                 stock: str = "") -> None:
        super().__init__(name)
        if kind not in SHAPES:
            raise ValueError(f"unknown vessel kind {kind!r}")
        self.kind = kind
        if stock and capacity_ml <= 0.0:
            capacity_ml = library().stocks[stock].capacity_ml
        self.capacity_ml = capacity_ml
        self.stock = stock
        self.diameter_m, self.height_m, self.tare_g = shape_of(kind, capacity_ml)
        self.contents = Mixture.from_stock(stock) if stock else Mixture()
        self.heat_w = 0.0
        self.mix = unstirred_mix()
        for tag, attr in (("temp_c", "temp_c"), ("volume_ml", "volume_ml"),
                          ("mass_g", "mass_g"), ("gas_ml_s", "gas_ml_s"),
                          ("boil_g_s", "boil_g_s")):
            self.add_observable(tag, attr)

    @property
    def temp_c(self) -> float:
        return self.contents.temp_c

    @property
    def volume_ml(self) -> float:
        return self.contents.volume_ml()

    @property
    def mass_g(self) -> float:
        return self.contents.mass_g()

    @property
    def gas_ml_s(self) -> float:
        return self.contents.gas_mol_s * GAS_ML_PER_MOL

    @property
    def boil_g_s(self) -> float:
        return self.contents.boil_g_s

    def room_ml(self) -> float:
        return max(self.capacity_ml - self.volume_ml, 0.0)

    def ua_w_k(self) -> float:
        """Loss to the room through the wetted wall and the open top."""
        area_top = math.pi * self.diameter_m ** 2 / 4.0
        fill = min(self.volume_ml / max(self.capacity_ml, 1e-9), 1.0)
        area_wall = math.pi * self.diameter_m * self.height_m * fill
        return H_SURFACE * (area_top + area_wall)

    def tick(self, dt: float) -> None:
        self.contents.step(dt, self.heat_w, self.mix, self.ua_w_k(),
                           self.tare_g * GLASS_CP)

    def state_dict(self) -> dict:
        return {"contents": self.contents.as_dict()}

    def apply_state(self, state: dict) -> None:
        if "contents" in state:
            self.contents = Mixture.from_dict(state["contents"])


def pour(src: LabVessel, dst: LabVessel, amount: float, stirred: bool) -> float:
    """Pour amount (mL of liquid, or g when the source holds only solid)
    from src into dst, as far as dst has room. An unstirred source
    decants: its settled solid stays behind. Returns what moved, in the
    amount's unit."""
    liquid_ml = src.contents.liquid_ml()
    if liquid_ml > 1e-6:
        want = min(amount, liquid_ml, dst.room_ml())
        frac = want / liquid_ml
        part = src.contents.take(frac, frac if stirred else 0.0)
    else:
        solid_g = src.contents.mass_g()
        if solid_g <= 1e-9:
            return 0.0
        room_g = dst.room_ml() * 1.5   # a powder packs at roughly this density
        want = min(amount, solid_g, room_g)
        part = src.contents.take(0.0, want / solid_g)
    dst.contents.add(part)
    return want


class Hotplate(Component):
    """A hotplate stirrer with a temperature probe.

    The element is on or off (a thermostat relay, so its lamp cycles as a
    real one does) and holds the plate at a target. With no vessel on it
    the target is the setpoint. With one, the probe is in the vessel and
    the target rises above the setpoint in proportion to how far the
    vessel is below it (a cascade, as a probe-mode hotplate does), so the
    plate does not store the heat that would carry the vessel past its
    setpoint. The plate is a lump of metal that heats and cools; heat
    reaches the vessel through its base.
    """

    POWER_W = 600.0
    PLATE_CP = 600.0          # J/K
    PLATE_LOSS = 1.2          # W/K
    TO_VESSEL = 0.8           # W/K, plate to a flat-bottomed vessel
    PLATE_MAX_C = 380.0
    BAND_C = 0.5
    CASCADE = 20.0            # plate degrees above setpoint per degree the vessel is short

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.setpoint_c = 0.0      # 0: heat off
        self.stir_rpm = 0.0
        self.plate_c = AMBIENT_C
        self.heater_on = False
        self.load: Optional[LabVessel] = None
        self.to_vessel_w = 0.0
        for tag in ("plate_c", "setpoint_c", "stir_rpm", "probe_c", "heating"):
            self.add_observable(tag, tag)

    @property
    def probe_c(self) -> float:
        return self.load.temp_c if self.load is not None else self.plate_c

    @property
    def heating(self) -> float:
        return 1.0 if self.heater_on else 0.0

    def plate_target_c(self) -> float:
        if self.load is None:
            return min(self.setpoint_c, self.PLATE_MAX_C)
        short = self.setpoint_c - self.load.temp_c
        return min(max(self.setpoint_c + self.CASCADE * short, self.setpoint_c), self.PLATE_MAX_C)

    def mix_factor(self) -> float:
        stir = min(max(self.stir_rpm / 400.0, 0.0), 1.0)
        return unstirred_mix() + (1.0 - unstirred_mix()) * stir

    def tick(self, dt: float) -> None:
        wanted = self.setpoint_c > AMBIENT_C
        target = self.plate_target_c()
        if not wanted or self.plate_c > target + self.BAND_C:
            self.heater_on = False
        elif self.plate_c < target - self.BAND_C:
            self.heater_on = True
        power = self.POWER_W if self.heater_on else 0.0
        self.to_vessel_w = 0.0
        if self.load is not None:
            self.to_vessel_w = self.TO_VESSEL * (self.plate_c - self.load.temp_c)
            self.load.heat_w = self.to_vessel_w
            self.load.mix = self.mix_factor()
        loss = self.PLATE_LOSS * (self.plate_c - AMBIENT_C)
        self.plate_c += (power - self.to_vessel_w - loss) * dt / self.PLATE_CP

    def state_dict(self) -> dict:
        return {"setpoint_c": self.setpoint_c, "stir_rpm": self.stir_rpm,
                "plate_c": self.plate_c, "heater_on": self.heater_on}

    def apply_state(self, state: dict) -> None:
        self.setpoint_c = float(state.get("setpoint_c", self.setpoint_c))
        self.stir_rpm = float(state.get("stir_rpm", self.stir_rpm))
        self.plate_c = float(state.get("plate_c", self.plate_c))
        self.heater_on = bool(state.get("heater_on", self.heater_on))


class LabMeter(Component):
    """A bench meter with a combined pH and temperature probe, dipped in
    the vessel beside it. Reads nothing with no vessel, and no pH in a
    liquid without water."""

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.target: Optional[LabVessel] = None
        self.ph = math.nan
        self.temp_c = math.nan
        self.add_observable("ph", "ph")
        self.add_observable("temp_c", "temp_c")

    def tick(self, dt: float) -> None:
        if self.target is None or self.target.contents.liquid_ml() < 1.0:
            self.ph = math.nan
            self.temp_c = math.nan
            return
        reading = self.target.contents.ph()
        self.ph = reading if reading is not None else math.nan
        self.temp_c = self.target.temp_c


class LabBalance(Component):
    """A bench balance: what stands on it, less the tare."""

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.load: Optional[LabVessel] = None
        self.tare_g = 0.0
        self.add_observable("reading_g", "reading_g")

    @property
    def gross_g(self) -> float:
        return self.load.tare_g + self.load.mass_g if self.load is not None else 0.0

    @property
    def reading_g(self) -> float:
        return self.gross_g - self.tare_g

    def tare(self) -> None:
        self.tare_g = self.gross_g

    def tick(self, dt: float) -> None:
        pass

    def state_dict(self) -> dict:
        return {"tare_g": self.tare_g}

    def apply_state(self, state: dict) -> None:
        self.tare_g = float(state.get("tare_g", self.tare_g))
