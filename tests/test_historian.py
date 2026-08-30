"""Historian fidelity tests: what the trend shows is what the sim did."""
from __future__ import annotations

import pytest

from sim.components import FloatSwitch, Pump, Relay, Tank
from sim.core import Simulation
from sim.historian import Historian


def _build_plant(low_l: float = 40.0, high_l: float = 80.0) -> tuple[Simulation, Tank]:
    sim = Simulation(dt=0.05)
    tank = sim.add(Tank("tank", capacity_l=100.0, level_l=70.0, drain_lps=1.5))
    switch = sim.add(FloatSwitch("switch", low_l=low_l, high_l=high_l))
    relay = sim.add(Relay("relay"))
    pump = sim.add(Pump("pump", rated_lps=4.0))
    sim.connect(tank, "level", switch, "level")
    sim.connect(switch, "contact", relay, "coil")
    sim.connect(relay, "contact", pump, "run")
    sim.connect(pump, "flow", tank, "in_flow")
    return sim, tank


def test_registers_ports_and_observables_as_tags() -> None:
    sim, _ = _build_plant()
    hist = sim.attach_historian(Historian())
    assert set(hist.tags) == {
        "tank.level",
        "tank.overflowed_l",
        "tank.ran_dry_ticks",
        "switch.contact",
        "relay.contact",
        "relay.cycles",
        "pump.flow",
        "pump.starts",
    }


def test_samples_every_scan_including_t0_baseline() -> None:
    sim, tank = _build_plant()
    hist = sim.attach_historian(Historian())
    assert len(hist) == 1                      # t=0 initial conditions
    assert hist.time[0] == 0.0
    assert hist.series("tank.level")[0] == 70.0
    sim.run(10.0)
    assert len(hist) == 1 + 200                # 10 s at 20 Hz


def test_historized_values_match_live_sim_exactly() -> None:
    """Two identical plants: one historized, one probed live each tick.
    The historian must record exactly what the live sim computed — the
    'no faked data' contract, bit for bit."""
    sim_h, tank_h = _build_plant()
    hist = sim_h.attach_historian(Historian())
    sim_live, tank_live = _build_plant()

    live_levels = [tank_live.level_l]
    for _ in range(round(120.0 / sim_live.dt)):
        sim_live.tick()
        live_levels.append(tank_live.level_l)
    sim_h.run(120.0)

    assert hist.series("tank.level") == live_levels  # exact, no approx


def test_discrete_tags_recorded_as_zero_one() -> None:
    sim, _ = _build_plant(low_l=200.0, high_l=300.0)  # switch always closed
    hist = sim.attach_historian(Historian())
    sim.run(1.0)
    contact = hist.series("switch.contact")
    assert set(contact) <= {0.0, 1.0}
    assert contact[-1] == 1.0


def test_duplicate_tag_rejected() -> None:
    dup = Historian()
    dup.register("a", lambda: 1.0)
    with pytest.raises(ValueError):
        dup.register("a", lambda: 1.0)


def test_late_registration_starts_mid_run() -> None:
    """Equipment installed mid-run: its record starts now, aligned to
    the shared time axis by start index."""
    hist = Historian()
    hist.register("a", lambda: 1.0)
    hist.sample(0.0)
    hist.sample(1.0)
    hist.register("b", lambda: 2.0)
    hist.sample(2.0)
    assert hist.start_index("b") == 2
    assert hist.series("b") == [2.0]
    assert hist.value_at("b", 1) is None
    assert hist.value_at("b", 2) == 2.0
    assert hist.value_at("a", 2) == 1.0


def test_retire_keeps_history_but_stops_growth() -> None:
    hist = Historian()
    hist.register("a", lambda: 1.0)
    hist.sample(0.0)
    hist.retire("a")
    hist.sample(1.0)
    assert hist.series("a") == [1.0]
    assert "a" in hist.tags
    assert "a" not in hist.active_tags
    with pytest.raises(ValueError):
        hist.retire("a")


def test_csv_leaves_honest_gaps() -> None:
    hist = Historian()
    hist.register("a", lambda: 1.0)
    hist.sample(0.0)
    hist.register("b", lambda: 2.0)
    hist.retire("a")
    hist.sample(1.0)
    lines = hist.to_csv_text().strip().split("\n")
    assert lines[0] == "time_s,a,b"
    assert lines[1] == "0,1,"     # b did not exist yet
    assert lines[2] == "1,,2"     # a was retired


def test_csv_round_trips_header_and_rows() -> None:
    sim, _ = _build_plant()
    hist = sim.attach_historian(Historian())
    sim.run(1.0)
    text = hist.to_csv_text()
    lines = text.strip().split("\n")
    assert lines[0].startswith("time_s,")
    assert len(lines) == 1 + len(hist)
    assert len(lines[1].split(",")) == 1 + len(hist.tags)
