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


class _Header(Component):
    """Test fixture: one nozzle holding a fixed pressure, carrying a
    fixed material. A ``Source`` with the composition written out by
    hand, which is what a premixed feed needs.

    Note what it cannot do: name a flow rate. It holds a pressure and
    the network decides the rest, which is the whole point.
    """

    def __init__(self, name: str, stream: Stream,
                 pressure_kpa: float = 300.0) -> None:
        super().__init__(name)
        self.stream = stream
        self.pressure_kpa = pressure_kpa
        self.out = self.add_output("out", PortKind.PROCESS_MATERIAL)

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        net.set_pressure(node["out"], self.pressure_kpa * 1000.0, fixed=True)

    def supplied_stream(self, port_name: str) -> Stream:
        return self.stream

    def tick(self, dt: float) -> None:
        pass


class _Sink(Component):
    """A nozzle at atmosphere that swallows whatever reaches it, and
    remembers what that was."""

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.seen = Stream.empty()
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        net.set_pressure(node["inlet"], 0.0, fixed=True)

    def tick(self, dt: float) -> None:
        self.seen = self.inlet.stream.with_flow(max(self.inlet.flow_lps, 0.0))


class TestPortBehaviour:
    def test_material_input_defaults_to_dead(self) -> None:
        sink = _Sink("s")
        assert not sink.inlet.value.is_flowing
        assert sink.inlet.flow_lps == pytest.approx(0.0)

    def test_two_runs_into_one_nozzle_blend(self) -> None:
        """A tee is a node, so two runs landing on one nozzle meet and
        mix. Their rates are solved rather than declared, so what is
        checked here is that the blend is consistent with whatever they
        turned out to be."""
        sim = Simulation(dt=0.05)
        hot = sim.add(_Header("hot", Stream.pure("water", 1.0, 80.0)))
        cold = sim.add(_Header("cold", Stream.pure("solvent", 1.0, 20.0)))
        sink = sim.add(_Sink("sink"))
        # Different resistances, so the two arrive in different amounts
        # and the blend is not simply the midpoint.
        sim.connect(hot, "out", sink, "inlet").k_pa_per_lps2 = 4_000.0
        sim.connect(cold, "out", sink, "inlet").k_pa_per_lps2 = 16_000.0
        sim.run(1.0)

        q_hot = -hot.out.flow_lps
        q_cold = -cold.out.flow_lps
        assert q_hot > 0.0 and q_cold > 0.0
        assert q_hot > q_cold                       # the easier path wins
        total = q_hot + q_cold
        assert sink.seen.flow_lps == pytest.approx(total, rel=1e-6)
        assert sink.seen.temp_c == pytest.approx(
            (q_hot * 80.0 + q_cold * 20.0) / total, rel=1e-6)
        assert sink.seen.frac("solvent") == pytest.approx(
            q_cold / total, rel=1e-6)

    def test_a_nozzle_reports_a_rate_not_a_running_total(self) -> None:
        """Flow at a port is re-solved every scan, so it settles at a
        rate rather than accumulating into one."""
        sim = Simulation(dt=0.05)
        head = sim.add(_Header("a", Stream.pure("water", 1.0)))
        sink = sim.add(_Sink("sink"))
        sim.connect(head, "out", sink, "inlet")
        sim.run(1.0)
        early = sink.seen.flow_lps
        assert early > 0.0
        sim.run(5.0)
        assert sink.seen.flow_lps == pytest.approx(early, rel=1e-9)

    def test_a_line_remembers_what_it_last_held(self) -> None:
        """Shut the header in and the run stops, but what stands in it
        does not become water again. Forgetting would make a restarted
        pump briefly deliver material it never contained."""
        sim = Simulation(dt=0.05)
        head = sim.add(_Header("a", Stream.pure("solvent", 1.0, 70.0)))
        sink = sim.add(_Sink("sink"))
        sim.connect(head, "out", sink, "inlet")
        sim.run(1.0)
        assert sink.inlet.stream.frac("solvent") == pytest.approx(1.0)
        head.pressure_kpa = 0.0
        sim.run(1.0)
        assert sink.inlet.flow_lps == pytest.approx(0.0, abs=1e-6)
        assert sink.inlet.stream.frac("solvent") == pytest.approx(1.0)

    def test_there_is_only_one_material_kind(self) -> None:
        """With pressure solving direction, one nozzle kind is all there
        is: no pushed material, no offered material, and no arithmetic
        wire reconciling the two."""
        assert not hasattr(PortKind, "PROCESS_STREAM")
        assert not hasattr(PortKind, "PROCESS_SUPPLY")
        assert not hasattr(PortKind, "PROCESS_FLOW")

    def test_a_nozzle_still_cannot_be_wired_to_a_signal(self) -> None:
        sim = Simulation(dt=0.05)
        head = sim.add(_Header("a", Stream.pure("water", 1.0)))
        sink = sim.add(_Sink("sink"))
        sink.add_input("cmd", PortKind.SIGNAL_ANALOG)
        with pytest.raises(ValueError, match="cannot wire"):
            sim.connect(head, "out", sink, "cmd")


class TestHistorianTags:
    def test_material_port_fans_out_into_real_tags(self) -> None:
        sim = Simulation(dt=0.05)
        head = sim.add(
            _Header("a", Stream(1.0, 55.0, {"water": 0.7, "product": 0.3})))
        sink = sim.add(_Sink("sink"))
        sim.connect(head, "out", sink, "inlet")
        historian = sim.attach_historian(Historian())
        sim.run(0.5)
        assert historian.series("a.out.flow")[-1] == pytest.approx(
            head.out.flow_lps)
        assert historian.series("a.out.flow")[-1] < 0.0   # material leaving
        assert historian.series("a.out.temp")[-1] == pytest.approx(55.0)
        assert historian.series("a.out.x_product")[-1] == pytest.approx(0.3)
        assert historian.series("a.out.x_water")[-1] == pytest.approx(0.7)
        assert historian.series("a.out.x_solvent")[-1] == pytest.approx(0.0)
        assert historian.series("a.out.solids")[-1] == pytest.approx(0.0)

    def test_removing_equipment_retires_its_stream_tags(self) -> None:
        sim = Simulation(dt=0.05)
        sim.add(_Header("a", Stream.pure("water", 1.0)))
        historian = sim.attach_historian(Historian())
        sim.run(0.2)
        assert "a.out.x_water" in historian.active_tags
        assert sim.remove_component("a")
        assert "a.out.x_water" not in historian.active_tags
        assert "a.out.x_water" in historian.tags  # history is kept
