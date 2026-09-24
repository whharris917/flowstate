"""A material stream: how much, how hot, and what is in it.

This is the value that travels on every process connection in the
kernel. Because it carries what is in the flow, a separator reads the
purity of its own feed and a heat exchanger heats the stream itself;
no signal wire reconciles them, and a train composes in any order.

A Stream is treated as an immutable value. Operations return new
Streams rather than mutating, because one Stream object is published on
an output port and read by every wire that lands on it -- aliasing a
mutable object there would let one consumer corrupt another's feed.

Conventions, applied everywhere in the kernel:
  * Flow is volumetric, L/s. 1 L is taken as 1 kg (aqueous basis), so
    the composition fractions below are simultaneously mass and volume
    fractions and no density is ever needed.
  * ``comp`` maps species key -> fraction of the total stream, and
    always sums to 1.0.
  * ``solids_frac`` is the fraction of the total stream that is present
    as suspended solid (crystals) rather than dissolved. It is a phase
    split, not a species: the solid is always made of species that
    crystallize, and it may never exceed their combined fraction.
"""
from __future__ import annotations

from sim import species as species_table

AMBIENT_C = 20.0
_EPS = 1e-12

# Which species the suspended solid is made of. One crystallizing
# species keeps the phase split to a single number on the stream
# instead of a per-species phase table -- the standing simplification.
SOLID_KEY = "product"


def comp_from_amounts(amounts: dict[str, float]) -> dict[str, float]:
    """Build a composition from absolute quantities (litres, or any
    consistent unit). Unit operations do their bookkeeping in absolute
    terms -- so much reagent consumed, so much product made -- and come
    back to fractions through here."""
    return _normalize(amounts)


class Stream:
    """One material stream. Zero flow means no material is moving; the
    temperature and composition of a dead stream are meaningless and
    are ignored by every operation that combines streams."""

    __slots__ = ("flow_lps", "temp_c", "comp", "solids_frac")

    def __init__(
        self,
        flow_lps: float = 0.0,
        temp_c: float = AMBIENT_C,
        comp: dict[str, float] | None = None,
        solids_frac: float = 0.0,
    ) -> None:
        if flow_lps < 0.0:
            raise ValueError("flow_lps must be non-negative")
        self.flow_lps = float(flow_lps)
        self.temp_c = float(temp_c)
        self.comp = _normalize(comp)
        self.solids_frac = min(max(float(solids_frac), 0.0), 1.0)

    # -- construction -------------------------------------------------

    @staticmethod
    def empty() -> "Stream":
        """A dead connection: nothing is flowing."""
        return Stream(0.0, AMBIENT_C, None, 0.0)

    @staticmethod
    def pure(key: str, flow_lps: float, temp_c: float = AMBIENT_C) -> "Stream":
        """A single-species stream -- what a supply header delivers."""
        species_table.get(key)
        return Stream(flow_lps, temp_c, {key: 1.0}, 0.0)

    def with_flow(self, flow_lps: float) -> "Stream":
        """Same material, different rate. This is how a stream is split:
        two branches of the same composition and temperature, whose
        rates sum to the parent's."""
        return Stream(flow_lps, self.temp_c, self.comp, self.solids_frac)

    def with_temp(self, temp_c: float) -> "Stream":
        return Stream(self.flow_lps, temp_c, self.comp, self.solids_frac)

    def with_comp(
        self, comp: dict[str, float], solids_frac: float | None = None
    ) -> "Stream":
        return Stream(
            self.flow_lps,
            self.temp_c,
            comp,
            self.solids_frac if solids_frac is None else solids_frac,
        )

    # -- queries ------------------------------------------------------

    @property
    def is_flowing(self) -> bool:
        return self.flow_lps > _EPS

    def frac(self, key: str) -> float:
        return self.comp.get(key, 0.0)

    def species_lps(self, key: str) -> float:
        """Rate of one species alone, L/s."""
        return self.flow_lps * self.comp.get(key, 0.0)

    def solids_lps(self) -> float:
        return self.flow_lps * self.solids_frac

    def liquid_comp(self) -> dict[str, float]:
        """Composition of the liquid alone, with the crystals taken out.

        Crystals are always the solid species (see ``SOLID_KEY``), so
        removing ``solids_frac`` of that species and renormalizing what
        is left gives the mother liquor. A stream that is entirely
        solid has no liquid, and reports none.
        """
        if self.solids_frac <= _EPS:
            return dict(self.comp)
        liquid_total = 1.0 - self.solids_frac
        if liquid_total <= _EPS:
            return {}
        amounts = {}
        for key, frac in self.comp.items():
            amount = frac - (self.solids_frac if key == SOLID_KEY else 0.0)
            if amount > _EPS:
                amounts[key] = amount / liquid_total
        return amounts

    def clamped_solids(self) -> "Stream":
        """Enforce the standing invariant: there cannot be more solid
        than there is of the species the solid is made of."""
        limit = self.comp.get(SOLID_KEY, 0.0)
        if self.solids_frac <= limit:
            return self
        return Stream(self.flow_lps, self.temp_c, self.comp, limit)

    def cp_kj_per_kg_k(self) -> float:
        """Composition-weighted heat capacity: cp = sum(x_i * cp_i)."""
        if not self.comp:
            return species_table.cp_of(species_table.DEFAULT_SPECIES)
        total = 0.0
        for key, frac in self.comp.items():
            total += frac * species_table.cp_of(key)
        return total

    # -- combination --------------------------------------------------

    @staticmethod
    def mix(a: "Stream", b: "Stream") -> "Stream":
        """Join two streams at a tee. Flows add; temperature and
        composition are flow-weighted averages of the two:

            F   = F_a + F_b
            T   = (F_a*T_a + F_b*T_b) / F
            x_i = (F_a*x_ia + F_b*x_ib) / F

        Temperature is weighted by flow rather than by heat capacity --
        a deliberate simplification, exact when the streams share a cp
        and close enough when they do not. Mixing a dead stream with a
        live one returns the live one untouched.
        """
        if not a.is_flowing:
            return b
        if not b.is_flowing:
            return a
        total = a.flow_lps + b.flow_lps
        temp = (a.flow_lps * a.temp_c + b.flow_lps * b.temp_c) / total
        solids = (
            a.flow_lps * a.solids_frac + b.flow_lps * b.solids_frac
        ) / total
        comp: dict[str, float] = {}
        for key, frac in a.comp.items():
            comp[key] = comp.get(key, 0.0) + a.flow_lps * frac
        for key, frac in b.comp.items():
            comp[key] = comp.get(key, 0.0) + b.flow_lps * frac
        for key in comp:
            comp[key] /= total
        return Stream(total, temp, comp, solids)

    @staticmethod
    def mix_all(streams: list["Stream"]) -> "Stream":
        result = Stream.empty()
        for stream in streams:
            result = Stream.mix(result, stream)
        return result

    # -- serialization ------------------------------------------------

    def as_dict(self) -> dict:
        return {
            "flow_lps": self.flow_lps,
            "temp_c": self.temp_c,
            "comp": dict(self.comp),
            "solids_frac": self.solids_frac,
        }

    @staticmethod
    def from_dict(data: dict) -> "Stream":
        return Stream(
            float(data.get("flow_lps", 0.0)),
            float(data.get("temp_c", AMBIENT_C)),
            data.get("comp"),
            float(data.get("solids_frac", 0.0)),
        )

    def __repr__(self) -> str:
        if not self.is_flowing:
            return "<Stream dead>"
        parts = ", ".join(
            f"{k} {v * 100.0:.0f}%"
            for k, v in sorted(self.comp.items(), key=lambda kv: -kv[1])
            if v > 0.005
        )
        solids = f", {self.solids_frac * 100.0:.0f}% solids" if self.solids_frac > 0.005 else ""
        return f"<Stream {self.flow_lps:.3g} L/s at {self.temp_c:.1f}C: {parts}{solids}>"


def _normalize(comp: dict[str, float] | None) -> dict[str, float]:
    """Drop zero and negative entries, then scale what remains to sum
    to one. An empty or all-zero composition becomes pure water, so
    every stream in the kernel always has a defined material."""
    if not comp:
        return {species_table.DEFAULT_SPECIES: 1.0}
    kept = {k: float(v) for k, v in comp.items() if float(v) > 0.0}
    if not kept:
        return {species_table.DEFAULT_SPECIES: 1.0}
    total = sum(kept.values())
    return {k: v / total for k, v in kept.items()}
