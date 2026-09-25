"""The bench chemistry library: species, reactions and reagent stocks.

Hand-authored data in ``game/data/chemistry.json``, which both kernels
read; this module loads it and answers the few property questions the
bench mixture asks. The plant's streams keep their own six species
(``sim/species.py``); this library is for work at the bench, on a mole
basis, with real substances.

Simple insides, by the standing rule:

* Solubility is two numbers per solvent class (water, organic), grams
  per 100 g of solvent at 20 and 80 C, interpolated log-linearly in
  temperature. In a mixed solvent it is log-linear in the solvent's mass
  fractions (the cosolvency rule of thumb).
* Vapour pressure is Clausius-Clapeyron from the normal boiling point
  and the heat of vaporization, and a mixture boils where the mole
  fractions times those pressures add to one atmosphere (Raoult).
* A rate constant follows Arrhenius from its value at 25 C.
* Acidity is a charge balance: strong ions, and acid families each with
  their pKa values.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Optional

DATA_PATH = Path(__file__).resolve().parent.parent / "game" / "data" / "chemistry.json"

R = 8.314          # J/(mol K)
ATM_KPA = 101.325
KW = 1.0e-14


class ChemSpecies:
    """One substance: what the bench mixture needs to know about it."""

    def __init__(self, index: int, d: dict) -> None:
        self.index = index
        self.key: str = d["key"]
        self.name: str = d["name"]
        self.formula: str = d.get("formula", "")
        self.molar_mass: float = float(d["molar_mass"])
        self.density: float = float(d["density"])
        self.phase: str = d["phase"]            # liquid, solid, dissolved, gas
        self.solvent: Optional[str] = d.get("solvent")
        self.mp: float = float(d.get("mp", 0.0))
        self.bp: float = float(d.get("bp", 100.0))
        self.cp: float = float(d.get("cp", 2.0))
        self.dh_vap: float = float(d.get("dh_vap", 40.0))
        sol = d.get("solubility", {})
        self.sol_water: tuple[float, float] = tuple(sol.get("water", [0.0, 0.0]))
        self.sol_organic: tuple[float, float] = tuple(sol.get("organic", [0.0, 0.0]))
        self.dh_solution: float = float(d.get("dh_solution", 0.0))
        self.family: Optional[str] = d.get("family")
        self.strong_cations: float = float(d.get("strong_cations", 0.0))
        self.strong_anions: float = float(d.get("strong_anions", 0.0))
        self.color: Optional[list[float]] = d.get("color")
        self.solid_color: Optional[list[float]] = d.get("solid_color")
        self.indicator: Optional[dict] = d.get("indicator")
        self.hazard: str = d.get("hazard", "")
        self.notes: str = d.get("notes", "")

    @property
    def volatile(self) -> bool:
        """Only a liquid boils off; a dissolved gas or salt stays."""
        return self.phase == "liquid"

    def vapour_kpa(self, temp_c: float) -> float:
        t = temp_c + 273.15
        tb = self.bp + 273.15
        return ATM_KPA * math.exp(-self.dh_vap * 1000.0 / R * (1.0 / t - 1.0 / tb))

    @staticmethod
    def _interp(pair: tuple[float, float], temp_c: float) -> float:
        a, b = max(pair[0], 1e-9), max(pair[1], 1e-9)
        f = (min(max(temp_c, 0.0), 100.0) - 20.0) / 60.0
        return math.exp(math.log(a) + (math.log(b) - math.log(a)) * f)

    def solubility(self, temp_c: float, water_frac: float) -> float:
        """Grams per 100 g of solvent, in a solvent that is water_frac
        water by mass and the rest organic."""
        lw = math.log(self._interp(self.sol_water, temp_c))
        lo = math.log(self._interp(self.sol_organic, temp_c))
        return math.exp(water_frac * lw + (1.0 - water_frac) * lo)

    def __repr__(self) -> str:
        return f"<ChemSpecies {self.key}>"


class Reaction:
    """One reaction as written, with its rate law."""

    def __init__(self, d: dict, index_of: dict[str, int]) -> None:
        self.key: str = d["key"]
        self.name: str = d["name"]
        self.equation: str = d.get("equation", "")
        self.reactants: dict[int, float] = {index_of[k]: float(v) for k, v in d["reactants"].items()}
        self.products: dict[int, float] = {index_of[k]: float(v) for k, v in d["products"].items()}
        self.fast: bool = bool(d.get("fast", False))
        self.k25: float = float(d.get("k25", 0.0))
        self.ea: float = float(d.get("ea", 0.0))
        self.orders: dict[int, float] = {index_of[k]: float(v) for k, v in d.get("orders", {}).items()}
        self.catalysts: dict[int, float] = {index_of[k]: float(v) for k, v in d.get("catalysts", {}).items()}
        self.h_order: float = float(d.get("h_order", 0.0))
        self.equilibrium: Optional[float] = d.get("equilibrium")
        self.solid_reactants: set[int] = {index_of[k] for k in d.get("solid_reactants", [])}
        self.dh: float = float(d.get("dh", 0.0))

    def k(self, temp_c: float) -> float:
        t = temp_c + 273.15
        return self.k25 * math.exp(-self.ea * 1000.0 / R * (1.0 / t - 1.0 / 298.15))


class Family:
    """An acid and its conjugate bases: pKa values, the charge of the
    fully deprotonated form."""

    def __init__(self, key: str, d: dict) -> None:
        self.key = key
        self.pka: list[float] = [float(x) for x in d["pka"]]
        self.z_base: float = float(d["z_base"])

    def mean_charge(self, h: float) -> float:
        """Mean charge of the family at hydrogen ion concentration h:
        form j carries j protons and charge z_base + j."""
        n = len(self.pka)
        # Cumulative association constants from the base up: the form
        # with j protons is proportional to h^j / (Ka_n ... Ka_{n-j+1}).
        weights = [1.0]
        for j in range(1, n + 1):
            ka = 10.0 ** (-self.pka[n - j])
            weights.append(weights[-1] * h / ka)
        total = sum(weights)
        return sum((self.z_base + j) * w for j, w in enumerate(weights)) / total


class Stock:
    def __init__(self, d: dict) -> None:
        self.key: str = d["key"]
        self.label: str = d["label"]
        self.capacity_ml: float = float(d["capacity_ml"])
        self.grams: dict[str, float] = {k: float(v) for k, v in d["grams"].items()}


class Library:
    def __init__(self, data: dict) -> None:
        self.species: list[ChemSpecies] = [ChemSpecies(i, d) for i, d in enumerate(data["species"])]
        self.index_of: dict[str, int] = {s.key: s.index for s in self.species}
        self.families: dict[str, Family] = {k: Family(k, v) for k, v in data["families"].items()}
        self.reactions: list[Reaction] = [Reaction(d, self.index_of) for d in data["reactions"]]
        self.stocks: dict[str, Stock] = {d["key"]: Stock(d) for d in data["stocks"]}

    @property
    def count(self) -> int:
        return len(self.species)

    def get(self, key: str) -> ChemSpecies:
        return self.species[self.index_of[key]]


_LIBRARY: Optional[Library] = None


def library() -> Library:
    global _LIBRARY
    if _LIBRARY is None:
        _LIBRARY = Library(json.loads(DATA_PATH.read_text(encoding="utf-8")))
    return _LIBRARY
