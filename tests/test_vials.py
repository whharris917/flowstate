"""The filling line: vials are conserved like litres, every
part does what its page says, and the liquid that goes into vials closes
against the header that supplied it."""
from __future__ import annotations

import pytest

from conftest import Contact
from sim.components import MainsFeed, PowerSupply, Source
from sim.core import Simulation
from sim.small_bore import SolenoidValve
from sim.vials import (
    Capper, FillNeedle, LoadCell, PhotoEye, StarWheel, StopGate, Vial, VialMagazine,
    VialTable, VialTrack, vial_size,
)


def _dc(sim: Simulation, *components) -> None:
    mains = sim.add(MainsFeed(sim.unique_name("mains"), ways=1))
    psu = sim.add(PowerSupply(sim.unique_name("psu")))
    sim.connect(mains, "way1", psu, "ac_in")
    for c in components:
        sim.connect(psu, "dc_out", c, "power")


def _line(sim: Simulation, length: float = 1.0, speed: float = 0.2, rate: float = 120.0):
    mag = sim.add(VialMagazine("vm_601", vial_ml=10, rate_per_min=rate))
    track = sim.add(VialTrack("vt_601", length_m=length, speed_mps=speed))
    table = sim.add(VialTable("vx_601"))
    sim.connect(mag, "outfeed", track, "infeed")
    sim.connect(track, "outfeed", table, "infeed")
    _dc(sim, track)
    track.hand_on = True
    return mag, track, table


class TestVials:
    def test_sizes_snap_to_a_standard_vial(self) -> None:
        assert vial_size(12) == 10
        assert Vial("v", 2).diameter_m == pytest.approx(0.016)

    def test_vials_are_conserved(self) -> None:
        sim = Simulation(dt=0.05)
        mag, track, table = _line(sim)
        sim.run(30.0)
        assert table.count > 10
        assert mag.supplied == table.count + track.vials_on

    def test_vials_never_overlap(self) -> None:
        sim = Simulation(dt=0.05)
        _, track, table = _line(sim)
        gate = sim.add(StopGate("xg_601"))
        track.mount(gate, 0.6)
        sim.run(20.0)
        positions = sorted(s for _, s in track.vials())
        assert len(positions) > 5
        for a, b in zip(positions, positions[1:]):
            assert b - a >= 0.024 - 1e-9
        assert table.count == 0

    def test_a_gate_holds_and_an_eye_sees(self) -> None:
        sim = Simulation(dt=0.05)
        _, track, table = _line(sim)
        gate = sim.add(StopGate("xg_601"))
        eye = sim.add(PhotoEye("ze_601"))
        release = sim.add(Contact("release"))
        sim.connect(release, "out", gate, "release")
        track.mount(gate, 0.6)
        track.mount(eye, 0.6 - 0.012)
        sim.run(10.0)
        front = max(s for _, s in track.vials())
        assert front == pytest.approx(0.6 - 0.012)
        assert eye.present.value
        assert table.count == 0
        release.closed = True
        sim.run(10.0)
        assert table.count > 0


def _fill_station(sim: Simulation, target_g: float = 10.0):
    mag, track, table = _line(sim, rate=30.0)
    hold = 0.5 - 0.012
    gate = sim.add(StopGate("xg_601"))
    eye = sim.add(PhotoEye("ze_601"))
    cell = sim.add(LoadCell("wt_601", target_g=target_g))
    needle = sim.add(FillNeedle("fn_601", cv_lps=0.01, elevation_m=0.2))
    header = sim.add(Source("supply_601", pressure_kpa=50.0))
    valve = sim.add(SolenoidValve("sv_601", cv_lps=0.3))
    dose = sim.add(Contact("dose"))
    release = sim.add(Contact("release"))
    sim.connect(header, "outlet", valve, "inlet")
    sim.connect(valve, "outlet", needle, "inlet")
    sim.connect(dose, "out", valve, "coil")
    sim.connect(release, "out", gate, "release")
    track.mount(gate, 0.5)
    track.mount(eye, hold)
    track.mount(cell, hold)
    track.mount(needle, hold)
    return header, track, table, eye, cell, needle, dose, release


class TestFilling:
    def test_a_gravimetric_fill_lands_on_target_and_the_balance_closes(self) -> None:
        sim = Simulation(dt=0.05)
        header, track, table, eye, cell, needle, dose, release = _fill_station(sim)
        # The controller a PLC would be: fill while a vial is held and
        # short of target, release it once it is there.
        for _ in range(round(60.0 / sim.dt)):
            full = bool(cell.at_target.value)
            dose.closed = bool(eye.present.value) and not full
            release.closed = full
            sim.run(sim.dt)
        assert table.count >= 5
        fills = [v.volume_l * 1000.0 for v in table.recent]
        assert all(abs(ml - 10.0) < 1.5 for ml in fills), fills
        held = sum(v.volume_l for v, _ in track.vials())
        assert header.total_l == pytest.approx(
            table.out_l + held + needle.spilled_l, abs=1e-6)

    def test_a_vial_left_under_the_needle_runs_over(self) -> None:
        sim = Simulation(dt=0.05)
        header, track, table, eye, cell, needle, dose, release = _fill_station(sim)
        dose.closed = True
        sim.run(20.0)
        vial = track.vial_near(0.5 - 0.012, 0.004)
        assert vial is not None
        assert vial.volume_l == pytest.approx(vial.brim_l)
        assert needle.spilled_l > 0.0
        held = sum(v.volume_l for v, _ in track.vials())
        assert header.total_l == pytest.approx(held + needle.spilled_l + table.out_l, abs=1e-6)

    def test_no_vial_means_the_stream_is_spilled(self) -> None:
        sim = Simulation(dt=0.05)
        header = sim.add(Source("supply_601", pressure_kpa=50.0))
        needle = sim.add(FillNeedle("fn_601", cv_lps=0.01, elevation_m=0.2))
        sim.connect(header, "outlet", needle, "inlet")
        sim.run(5.0)
        assert needle.delivered_l == 0.0
        assert needle.spilled_l == pytest.approx(header.total_l)


class TestStarWheel:
    def test_the_wheel_carries_vials_on_and_the_capper_caps_them(self) -> None:
        sim = Simulation(dt=0.05)
        mag = sim.add(VialMagazine("vm_601", rate_per_min=60.0))
        t1 = sim.add(VialTrack("vt_601", length_m=0.6, speed_mps=0.2))
        wheel = sim.add(StarWheel("sw_601", pockets=6, out_station=3))
        t2 = sim.add(VialTrack("vt_602", length_m=0.6, speed_mps=0.2))
        table = sim.add(VialTable("vx_601"))
        capper = sim.add(Capper("cp_601", cap_s=0.4))
        index = sim.add(Contact("index"))
        cap_on = sim.add(Contact("cap", closed=True))
        sim.connect(mag, "outfeed", t1, "infeed")
        sim.connect(t1, "outfeed", wheel, "infeed")
        sim.connect(wheel, "outfeed", t2, "infeed")
        sim.connect(t2, "outfeed", table, "infeed")
        sim.connect(index, "out", wheel, "index")
        sim.connect(cap_on, "out", capper, "cap")
        _dc(sim, t1, wheel, t2, capper)
        t1.hand_on = t2.hand_on = True
        wheel.mount(capper, 2)
        # Index every second: the capper has 0.6 s at rest per pocket.
        for i in range(round(60.0 / sim.dt)):
            index.closed = (i % 20) < 2
            sim.run(sim.dt)
        assert table.count > 10
        assert table.capped_count == table.count
        on_line = t1.vials_on + wheel.vials_on + t2.vials_on
        assert mag.supplied == table.count + on_line
        assert capper.caps_used >= table.count

    def test_an_unpowered_wheel_does_not_turn(self) -> None:
        sim = Simulation(dt=0.05)
        wheel = sim.add(StarWheel("sw_601"))
        index = sim.add(Contact("index", closed=True))
        sim.connect(index, "out", wheel, "index")
        sim.run(2.0)
        assert wheel.indexes == 0


class TestSaveLoad:
    def test_a_track_round_trips_its_vials(self) -> None:
        sim = Simulation(dt=0.05)
        _, track, _ = _line(sim)
        gate = sim.add(StopGate("xg_601"))
        track.mount(gate, 0.6)
        sim.run(8.0)
        track.vials()[0][0].add(__import__("sim.stream", fromlist=["Stream"]).Stream.pure("water", 1.0), 0.005)
        state = track.state_dict()
        other = VialTrack("vt_601", length_m=1.0, speed_mps=0.2)
        other.apply_state(state)
        assert [(v.serial, round(s, 6), round(v.volume_l, 9)) for v, s in other.vials()] == \
            [(v.serial, round(s, 6), round(v.volume_l, 9)) for v, s in track.vials()]
