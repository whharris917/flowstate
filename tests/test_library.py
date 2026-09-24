"""Tests for the equipment library.

The library makes a promise: a page never describes a machine that does
not exist. These tests are what keep that promise mechanical rather than
aspirational. Add a port to a component and forget to document it, or
document one you later removed, and the suite fails.
"""
from __future__ import annotations

import json

import pytest

from sim import library
from sim.components import Gauge
from sim.core import Component
from sim.library import catalog, describe, sample_components, spec_of


def _by_class() -> dict[type, list[Component]]:
    grouped: dict[type, list[Component]] = {}
    for component in sample_components():
        grouped.setdefault(type(component), []).append(component)
    # Gauges are configured per kind, so cover the variants: the ports a
    # gauge has depend on what it is measuring.
    grouped[Gauge] = [
        Gauge("g_level", "level_kpa"),
        Gauge("g_dp", "dp_pa"),
        Gauge("g_conc", "conc_pct"),
        Gauge("g_flow", "flow"),
    ]
    return grouped


class TestEveryMachineIsDocumented:
    def test_every_sample_component_has_a_page(self) -> None:
        undocumented = [
            type(c).__name__ for c in sample_components() if spec_of(type(c)) is None
        ]
        assert undocumented == []

    def test_pages_have_equations_and_own_up_to_assumptions(self) -> None:
        """A page with no equations teaches nothing, and a page with no
        stated assumptions is lying by omission about a model this
        simplified."""
        for page in catalog(sample_components()):
            assert page["equations"], f"{page['title']} has no equations"
            assert page["assumptions"], f"{page['title']} states no assumptions"
            assert page["summary"].strip(), f"{page['title']} has no summary"

    def test_keys_are_unique(self) -> None:
        keys = [page["key"] for page in catalog(sample_components())]
        assert len(keys) == len(set(keys))


class TestPortTablesMatchReality:
    def test_every_real_port_has_a_meaning(self) -> None:
        """Add a nozzle and forget to document it: this fails."""
        missing: list[str] = []
        for component in sample_components():
            page = describe(component)
            for row in page["ports"]:
                if not row.get("meaning"):
                    missing.append(f"{page['title']}.{row['name']}")
        assert missing == []

    def test_no_meaning_describes_a_port_that_does_not_exist(self) -> None:
        """Remove a nozzle and forget to undocument it: this fails."""
        orphans: list[str] = []
        for cls, instances in _by_class().items():
            spec = spec_of(cls)
            if spec is None:
                continue
            real: set[str] = set()
            for component in instances:
                real |= set(component.inputs) | set(component.outputs)
            for name in spec.ports:
                if name not in real:
                    orphans.append(f"{spec.title}.{name}")
        assert orphans == []

    def test_port_kinds_come_from_the_component_not_the_page(self) -> None:
        """The kind shown is read off the live port, so it cannot be
        stale. Check a couple of known ones."""
        from sim.process import Reactor

        page = describe(Reactor("rx"))
        kinds = {row["name"]: row["kind"] for row in page["ports"]}
        assert kinds["inlet_a"] == "process_material"
        assert kinds["outlet"] == "process_material"
        assert kinds["power"] == "power"
        assert kinds["purity"] == "signal_analog"

    def test_there_is_only_one_material_kind(self) -> None:
        """A nozzle is a nozzle. With pressure deciding direction there
        is nothing left for a second material kind to protect against,
        so no page may show one."""
        material = {"process_material", "process_level", "process_pressure"}
        for page in catalog(sample_components()):
            for row in page["ports"]:
                assert not row["kind"].startswith("process_") or \
                    row["kind"] in material, \
                    f"{page['title']}.{row['name']} is {row['kind']}"

    def test_no_page_still_advertises_a_draw_port(self) -> None:
        """There is no draw wire. A page offering one would be inviting
        the player to wire up bookkeeping."""
        for page in catalog(sample_components()):
            names = {row["name"] for row in page["ports"]}
            assert "draw" not in names, page["title"]
            assert "supply" not in names, page["title"]

    def test_directions_are_right(self) -> None:
        from sim.separation import Still

        page = describe(Still("st"))
        directions = {row["name"]: row["direction"] for row in page["ports"]}
        assert directions["inlet"] == "in"
        assert directions["heat_duty"] == "in"
        assert directions["distillate"] == "out"
        assert directions["bottoms"] == "out"


class TestParameterTables:
    def test_every_construction_parameter_is_documented(self) -> None:
        missing: list[str] = []
        for cls, instances in _by_class().items():
            spec = spec_of(cls)
            if spec is None:
                continue
            documented = {p.name for p in spec.params}
            for name in library.constructor_params(cls):
                if name not in documented:
                    missing.append(f"{spec.title}.{name}")
        assert missing == []

    def test_no_documented_parameter_is_imaginary(self) -> None:
        orphans: list[str] = []
        for cls, instances in _by_class().items():
            spec = spec_of(cls)
            if spec is None:
                continue
            real = set(library.constructor_params(cls))
            for param in spec.params:
                if param.name not in real:
                    orphans.append(f"{spec.title}.{param.name}")
        assert orphans == []

    def test_defaults_are_the_real_defaults(self) -> None:
        from sim.process import Reactor

        page = describe(Reactor("rx"))
        params = {p["name"]: p["default"] for p in page["params"]}
        assert params["capacity_l"] == 4000.0
        assert params["rate_lps"] == 6.0


class TestPagesTravel:
    def test_a_page_is_json_serializable(self) -> None:
        """The in-game library and the browser GUI both read these, so a
        page has to survive the trip."""
        pages = catalog(sample_components())
        text = json.dumps(pages)
        assert json.loads(text) == pages

    def test_observables_are_listed(self) -> None:
        """The historian tags a page should tell you exist."""
        from sim.process import Reactor

        page = describe(Reactor("rx"))
        assert "purity_frac" in page["observables"]
        assert "temp_c" in page["observables"]

    def test_undocumented_component_still_renders(self) -> None:
        """A machine without a page is shown as undocumented rather than
        crashing the library -- and is visibly flagged as such."""
        from sim.core import PortKind

        class Gizmo(Component):
            def __init__(self, name: str) -> None:
                super().__init__(name)
                self.out = self.add_output("out", PortKind.SIGNAL_ANALOG)

            def tick(self, dt: float) -> None:
                pass

        page = describe(Gizmo("gz"))
        assert page["tier"] == "undocumented"
        assert page["ports"][0]["name"] == "out"


class TestTheSynthesisTrainIsCovered:
    """The units the player builds the train out of all have pages."""

    @pytest.mark.parametrize(
        "key",
        [
            "tank", "pump", "control_valve", "source", "drain", "gauge",
            "steam_gen", "heat_exchanger", "reactor", "centrifuge",
            "crystallizer", "dryer", "still", "vial_filler",
        ],
    )
    def test_page_exists(self, key: str) -> None:
        keys = {page["key"] for page in catalog(sample_components())}
        assert key in keys
