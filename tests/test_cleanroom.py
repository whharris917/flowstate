"""Tests for the aseptic suite kernel: room-pressure cascade + DP gauge."""
from __future__ import annotations

import pytest

from sim.components import AirCascade, Gauge
from sim.core import Simulation

SUITE_ROOMS = [
    {"id": "al1", "volume_m3": 12.0, "supply_lps": 12.0},
    {"id": "gown", "volume_m3": 30.0, "supply_lps": 25.0},
    {"id": "al2", "volume_m3": 12.0, "supply_lps": 15.0},
    {"id": "core", "volume_m3": 80.0, "supply_lps": 60.0},
    {"id": "iso", "volume_m3": 2.0, "supply_lps": 4.0},
]
SUITE_DOORS = [
    {"id": "hall_al1", "a": "al1", "b": "ambient", "leak_closed": 3.0, "leak_open": 80.0},
    {"id": "al1_gown", "a": "gown", "b": "al1", "leak_closed": 3.0, "leak_open": 80.0},
    {"id": "gown_al2", "a": "al2", "b": "gown", "leak_closed": 3.0, "leak_open": 80.0},
    {"id": "al2_core", "a": "core", "b": "al2", "leak_closed": 3.0, "leak_open": 80.0},
    {"id": "iso_hatch", "a": "iso", "b": "core", "leak_closed": 0.12, "leak_open": 40.0},
]


def _cascade_sim() -> tuple[Simulation, AirCascade]:
    sim = Simulation(dt=0.05)
    cascade = sim.add(AirCascade("hvac", SUITE_ROOMS, SUITE_DOORS))
    return sim, cascade


class TestAirCascade:
    def test_cascade_settles_with_correct_ordering(self) -> None:
        sim, cascade = _cascade_sim()
        sim.run(120.0)
        p = cascade.pressures
        assert 0.0 < p["al1"] < p["gown"] < p["al2"] < p["core"] < p["iso"]
        # Each classified step holds a meaningful differential.
        assert p["gown"] - p["al1"] > 2.0
        assert p["al2"] - p["gown"] > 2.0
        assert p["core"] - p["al2"] > 2.0
        assert p["iso"] - p["core"] > 10.0

    def test_open_airlock_both_doors_collapses_the_step(self) -> None:
        sim, cascade = _cascade_sim()
        sim.run(120.0)
        healthy_dp = cascade.pressures["core"] - cascade.pressures["gown"]
        cascade.set_door("gown_al2", True)
        cascade.set_door("al2_core", True)
        sim.run(30.0)
        broken_dp = cascade.pressures["core"] - cascade.pressures["gown"]
        assert broken_dp < 5.0 < healthy_dp
        cascade.set_door("gown_al2", False)
        cascade.set_door("al2_core", False)
        sim.run(60.0)
        recovered_dp = cascade.pressures["core"] - cascade.pressures["gown"]
        assert recovered_dp > 0.8 * healthy_dp

    def test_single_open_door_keeps_cascade_mostly_intact(self) -> None:
        sim, cascade = _cascade_sim()
        sim.run(120.0)
        cascade.set_door("gown_al2", True)  # one door only, as trained
        sim.run(30.0)
        p = cascade.pressures
        assert p["core"] - p["gown"] > 3.0  # core still protected

    def test_rejects_bad_construction_and_unknown_door(self) -> None:
        with pytest.raises(ValueError):
            AirCascade("h", [], [])
        with pytest.raises(ValueError):
            AirCascade("h", SUITE_ROOMS[:1],
                [{"id": "d", "a": "al1", "b": "nowhere"}])
        _, cascade = _cascade_sim()
        with pytest.raises(ValueError):
            cascade.set_door("no_such_door", True)

    def test_state_roundtrip(self) -> None:
        sim, cascade = _cascade_sim()
        cascade.set_door("hall_al1", True)
        sim.run(20.0)
        state = cascade.state_dict()
        _, other = _cascade_sim()
        other.apply_state(state)
        assert other.pressures == cascade.pressures
        assert other.is_door_open("hall_al1") is True


class TestDpGauge:
    def test_reads_difference_between_taps(self) -> None:
        sim, cascade = _cascade_sim()
        gauge = sim.add(Gauge("pdi_1", "dp_pa"))
        sim.connect(cascade, "p_iso", gauge, "process_a")
        sim.connect(cascade, "p_core", gauge, "process_b")
        sim.run(120.0)
        expected = cascade.pressures["iso"] - cascade.pressures["core"]
        assert gauge.reading == pytest.approx(expected, abs=0.5)
        assert gauge.units() == "Pa"
