"""The species this plant handles, and the few physical properties the
unit operations actually consult.

Deliberately shallow. Each species carries only what some equation in
`sim/process.py` needs to do its job: a heat capacity for energy
balances, a boiling point for the still, and a linear solubility curve
for the crystallizer. There is no activity model, no VLE, no enthalpy
of mixing. That is the standing rule for this kernel -- streams between
units are rich, the equations inside units are simple enough to print
on a page.

Everything is on an aqueous-ish volumetric basis: 1 L is taken as 1 kg
throughout the kernel, so mass fractions and volume fractions are the
same number and nothing has to carry a density.
"""
from __future__ import annotations


class Species:
    """One chemical the plant can hold, move, react, or separate."""

    def __init__(
        self,
        key: str,
        label: str,
        cp_kj_per_kg_k: float,
        boil_c: float,
        sol_g_per_l_20: float = 0.0,
        sol_slope_g_per_l_k: float = 0.0,
        crystallizes: bool = False,
    ) -> None:
        if cp_kj_per_kg_k <= 0.0:
            raise ValueError("cp must be positive")
        self.key = key
        self.label = label
        self.cp_kj_per_kg_k = cp_kj_per_kg_k
        self.boil_c = boil_c
        self.sol_g_per_l_20 = sol_g_per_l_20
        self.sol_slope_g_per_l_k = sol_slope_g_per_l_k
        self.crystallizes = crystallizes

    def solubility_g_per_l(self, temp_c: float) -> float:
        """Linear solubility curve, floored at zero:

            S(T) = S20 + m * (T - 20)

        Crude on purpose. It gives the crystallizer an honest,
        legible driving force (cool the batch, exceed saturation,
        drop crystals) without pretending to be a real solubility
        model.
        """
        s = self.sol_g_per_l_20 + self.sol_slope_g_per_l_k * (temp_c - 20.0)
        return max(s, 0.0)

    def __repr__(self) -> str:
        return f"<Species {self.key!r}>"


# The synthesis train's chemistry. Two reagents combine in solvent to
# make the product; the reaction also throws an impurity. The product
# is the only thing that crystallizes, which is what lets the
# crystallizer/filter/dryer sequence mean anything.
SPECIES: dict[str, Species] = {
    "water": Species("water", "Water", 4.18, 100.0),
    "solvent": Species("solvent", "Solvent", 1.70, 111.0),
    "reagent_a": Species("reagent_a", "Reagent A", 2.10, 205.0),
    "reagent_b": Species("reagent_b", "Reagent B", 2.00, 220.0),
    "product": Species(
        "product",
        "Product",
        2.20,
        320.0,
        sol_g_per_l_20=40.0,
        sol_slope_g_per_l_k=6.0,
        crystallizes=True,
    ),
    # A heavy byproduct on purpose: if it boiled off easily the reactor
    # would strip itself clean and the selectivity trade would vanish.
    # It has to be separated, not evaporated.
    "impurity": Species(
        "impurity", "Impurity", 2.00, 280.0,
        sol_g_per_l_20=300.0, sol_slope_g_per_l_k=4.0,
    ),
}

# Fixed order, so historian tags and save files are deterministic.
SPECIES_KEYS: list[str] = list(SPECIES)

DEFAULT_SPECIES = "water"


def get(key: str) -> Species:
    species = SPECIES.get(key)
    if species is None:
        raise KeyError(f"unknown species {key!r}")
    return species


def cp_of(key: str) -> float:
    return get(key).cp_kj_per_kg_k


def label_of(key: str) -> str:
    return get(key).label
