"""Tests for the material stream: what flows between unit operations.

The kernel promises that material is conserved and that a stream knows
what it is. These tests hold that line, because every unit operation
downstream of here trusts it.
"""
from __future__ import annotations

import pytest

from sim.core import Component, PortKind, Simulation
from sim.historian import Historian
from sim.stream import Stream


class TestStreamValue:
    def test_composition_normalizes_to_one(self) -> None:
        s = Stream(1.0, 50.0, {"water": 3.0, "solvent": 1.0})
        assert s.frac("water") == pytest.approx(0.75)
        assert s.frac("solvent") == pytest.approx(0.25)
        assert sum(s.comp.values()) == pytest.approx(1.0)

    def test_unspecified_material_is_water(self) -> None:
        assert Stream(1.0).frac("water") == 1.0
        assert Stream(1.0, comp={}).frac("water") == 1.0

    def test_absent_species_reads_zero(self) -> None:
        assert Stream.pure("solvent", 1.0).frac("product") == 0.0

    def test_pure_rejects_unknown_species(self) -> None:
        with pytest.raises(KeyError):
            Stream.pure("unobtainium", 1.0)

    def test_negative_flow_refused(self) -> None:
        with pytest.raises(ValueError):
            Stream(-1.0)

    def test_species_rate_is_flow_times_fraction(self) -> None:
        s = Stream(8.0, 20.0, {"water": 0.75, "product": 0.25})
        assert s.species_lps("product") == pytest.approx(2.0)
        assert s.species_lps("water") == pytest.approx(6.0)


class TestMixing:
    def test_mixing_conserves_flow(self) -> None:
        m = Stream.mix(Stream.pure("water", 2.0), Stream.pure("solvent", 6.0))
        assert m.flow_lps == pytest.approx(8.0)

    def test_temperature_is_flow_weighted(self) -> None:
        hot = Stream.pure("water", 2.0, 80.0)
        cold = Stream.pure("water", 6.0, 20.0)
        assert Stream.mix(hot, cold).temp_c == pytest.approx(35.0)

    def test_composition_is_flow_weighted(self) -> None:
        m = Stream.mix(Stream.pure("water", 2.0), Stream.pure("solvent", 6.0))
        assert m.frac("water") == pytest.approx(0.25)
        assert m.frac("solvent") == pytest.approx(0.75)

    def test_species_rates_are_conserved_through_a_mix(self) -> None:
        a = Stream(4.0, 20.0, {"water": 0.5, "product": 0.5})
        b = Stream(6.0, 20.0, {"water": 0.25, "impurity": 0.75})
        m = Stream.mix(a, b)
        for key in ("water", "product", "impurity"):
            assert m.species_lps(key) == pytest.approx(
                a.species_lps(key) + b.species_lps(key)
            )

    def test_dead_stream_changes_nothing(self) -> None:
        live = Stream.pure("solvent", 3.0, 70.0)
        for m in (Stream.mix(live, Stream.empty()), Stream.mix(Stream.empty(), live)):
            assert m.flow_lps == pytest.approx(3.0)
            assert m.temp_c == pytest.approx(70.0)
            assert m.frac("solvent") == pytest.approx(1.0)

    def test_two_dead_streams_stay_dead(self) -> None:
        assert not Stream.mix(Stream.empty(), Stream.empty()).is_flowing

    def test_mix_all_matches_pairwise(self) -> None:
        parts = [
            Stream.pure("water", 1.0, 10.0),
            Stream.pure("water", 2.0, 40.0),
            Stream.pure("water", 3.0, 70.0),
        ]
        m = Stream.mix_all(parts)
        assert m.flow_lps == pytest.approx(6.0)
        assert m.temp_c == pytest.approx((10.0 + 80.0 + 210.0) / 6.0)

    def test_solids_are_flow_weighted(self) -> None:
        slurry = Stream(2.0, 20.0, {"product": 1.0}, solids_frac=0.5)
        clear = Stream(2.0, 20.0, {"water": 1.0}, solids_frac=0.0)
        assert Stream.mix(slurry, clear).solids_frac == pytest.approx(0.25)


class TestSplitting:
    def test_split_conserves_flow_and_keeps_material(self) -> None:
        parent = Stream(10.0, 65.0, {"water": 0.6, "product": 0.4}, solids_frac=0.1)
        a = parent.with_flow(3.0)
        b = parent.with_flow(7.0)
        assert a.flow_lps + b.flow_lps == pytest.approx(parent.flow_lps)
        for branch in (a, b):
            assert branch.temp_c == pytest.approx(parent.temp_c)
            assert branch.frac("product") == pytest.approx(parent.frac("product"))
            assert branch.solids_frac == pytest.approx(parent.solids_frac)

    def test_split_then_remix_is_the_original(self) -> None:
        parent = Stream(10.0, 65.0, {"water": 0.6, "product": 0.4})
        m = Stream.mix(parent.with_flow(3.0), parent.with_flow(7.0))
        assert m.flow_lps == pytest.approx(parent.flow_lps)
        assert m.temp_c == pytest.approx(parent.temp_c)
        assert m.frac("product") == pytest.approx(parent.frac("product"))


class TestHeatCapacity:
    def test_cp_is_composition_weighted(self) -> None:
        s = Stream(1.0, 20.0, {"water": 0.5, "solvent": 0.5})
        assert s.cp_kj_per_kg_k() == pytest.approx((4.18 + 1.70) / 2.0)

    def test_pure_water_cp(self) -> None:
        assert Stream.pure("water", 1.0).cp_kj_per_kg_k() == pytest.approx(4.18)


class TestSerialization:
    def test_round_trip(self) -> None:
        s = Stream(3.5, 61.0, {"water": 0.4, "product": 0.6}, solids_frac=0.2)
        back = Stream.from_dict(s.as_dict())
        assert back.flow_lps == pytest.approx(s.flow_lps)
        assert back.temp_c == pytest.approx(s.temp_c)
        assert back.solids_frac == pytest.approx(s.solids_frac)
        assert back.comp == pytest.approx(s.comp)


# -- kernel integration ------------------------------------------------


class _Emitter(Component):
    """Test fixture: publishes a fixed stream every scan."""

    def __init__(self, name: str, stream: Stream) -> None:
        super().__init__(name)
        self.stream = stream
        self.out = self.add_output("out", PortKind.PROCESS_STREAM)

    def tick(self, dt: float) -> None:
        self.out.value = self.stream


class _Sink(Component):
    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.seen = Stream.empty()
        self.inlet = self.add_input("inlet", PortKind.PROCESS_STREAM)

    def tick(self, dt: float) -> None:
        self.seen = self.inlet.value


class TestPortBehaviour:
    def test_stream_input_defaults_to_dead(self) -> None:
        sink = _Sink("s")
        assert not sink.inlet.value.is_flowing

    def test_two_wires_into_one_inlet_mix(self) -> None:
        """A tee: two headers landing on one nozzle blend."""
        sim = Simulation(dt=0.05)
        a = sim.add(_Emitter("a", Stream.pure("water", 2.0, 80.0)))
        b = sim.add(_Emitter("b", Stream.pure("solvent", 6.0, 20.0)))
        sink = sim.add(_Sink("sink"))
        sim.connect(a, "out", sink, "inlet")
        sim.connect(b, "out", sink, "inlet")
        sim.run(0.5)
        assert sink.seen.flow_lps == pytest.approx(8.0)
        assert sink.seen.temp_c == pytest.approx(35.0)
        assert sink.seen.frac("solvent") == pytest.approx(0.75)

    def test_inlet_resets_between_scans(self) -> None:
        """Material does not accumulate on a port across scans."""
        sim = Simulation(dt=0.05)
        a = sim.add(_Emitter("a", Stream.pure("water", 2.0)))
        sink = sim.add(_Sink("sink"))
        sim.connect(a, "out", sink, "inlet")
        sim.run(1.0)
        assert sink.seen.flow_lps == pytest.approx(2.0)

    def test_supply_and_stream_cannot_be_crossed(self) -> None:
        """Offered material and pushed material stay distinct kinds."""
        sim = Simulation(dt=0.05)
        a = sim.add(_Emitter("a", Stream.pure("water", 1.0)))
        sink = sim.add(_Sink("sink"))
        sink.add_input("supply_in", PortKind.PROCESS_SUPPLY)
        with pytest.raises(ValueError, match="cannot wire"):
            sim.connect(a, "out", sink, "supply_in")


class TestHistorianTags:
    def test_stream_port_fans_out_into_real_tags(self) -> None:
        sim = Simulation(dt=0.05)
        sim.add(_Emitter("a", Stream(4.0, 55.0, {"water": 0.7, "product": 0.3})))
        historian = sim.attach_historian(Historian())
        sim.run(0.5)
        assert historian.series("a.out.flow")[-1] == pytest.approx(4.0)
        assert historian.series("a.out.temp")[-1] == pytest.approx(55.0)
        assert historian.series("a.out.x_product")[-1] == pytest.approx(0.3)
        assert historian.series("a.out.x_water")[-1] == pytest.approx(0.7)
        assert historian.series("a.out.x_solvent")[-1] == pytest.approx(0.0)
        assert historian.series("a.out.solids")[-1] == pytest.approx(0.0)

    def test_removing_equipment_retires_its_stream_tags(self) -> None:
        sim = Simulation(dt=0.05)
        sim.add(_Emitter("a", Stream.pure("water", 1.0)))
        historian = sim.attach_historian(Historian())
        sim.run(0.2)
        assert "a.out.x_water" in historian.active_tags
        assert sim.remove_component("a")
        assert "a.out.x_water" not in historian.active_tags
        assert "a.out.x_water" in historian.tags  # history is kept
