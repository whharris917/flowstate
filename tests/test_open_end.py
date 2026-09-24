"""An open cap is an atmospheric end that spills what the line delivers;
closed, it holds pressure and moves nothing."""

from sim.components import Cap, Source
from sim.core import Simulation


def _header_to_cap(open_end: bool) -> tuple[Simulation, Cap, Source]:
    sim = Simulation()
    source = sim.add(Source("supply", species="water", pressure_kpa=300.0))
    cap = sim.add(Cap("end"))
    cap.open = open_end
    sim.connect(source, "outlet", cap, "a")
    return sim, cap, source


def test_a_closed_cap_spills_nothing() -> None:
    sim, cap, _source = _header_to_cap(False)
    sim.run(20.0)
    assert cap.spilled_l == 0.0
    assert cap.spill_lps() == 0.0


def test_an_open_end_spills_what_the_header_delivers() -> None:
    sim, cap, source = _header_to_cap(True)
    sim.run(20.0)
    assert cap.spill_lps() > 0.1
    assert abs(cap.spilled_l - source.total_l) < 0.05 * source.total_l


def test_capping_an_open_end_stops_the_spill() -> None:
    sim, cap, _source = _header_to_cap(True)
    sim.run(10.0)
    spilled = cap.spilled_l
    cap.open = False
    sim.run(10.0)
    assert abs(cap.spilled_l - spilled) < 1e-6


def test_open_state_round_trips() -> None:
    sim, cap, _source = _header_to_cap(True)
    sim.run(5.0)
    state = cap.state_dict()
    fresh = Cap("end")
    fresh.apply_state(state)
    assert fresh.open is True
    assert fresh.spilled_l == cap.spilled_l


def _header_over_tank(open_top: bool) -> tuple[Simulation, Cap, Source, "Tank"]:
    """An open end standing over a vessel. The plant names
    the vessel under the end; the kernel lands the stream."""
    from sim.components import Tank
    sim = Simulation()
    source = sim.add(Source("supply", species="water", pressure_kpa=300.0))
    cap = sim.add(Cap("end", elevation_m=2.0))
    cap.open = True
    tank = sim.add(Tank("t", capacity_l=10000.0, level_l=10.0, height_m=2.0, open_top=open_top))
    cap.catch = tank
    sim.connect(source, "outlet", cap, "a")
    return sim, cap, source, tank


def test_an_open_end_over_an_open_tank_fills_it() -> None:
    sim, cap, source, tank = _header_over_tank(True)
    sim.run(20.0)
    assert cap.delivered_l > 1.0
    assert cap.spilled_l == 0.0
    assert abs(tank.level_l - 10.0 - cap.delivered_l) < 1e-6
    assert abs(cap.delivered_l - source.total_l) < 0.05 * source.total_l


def test_a_closed_tank_under_an_open_end_catches_nothing() -> None:
    sim, cap, _source, tank = _header_over_tank(False)
    sim.run(20.0)
    assert cap.delivered_l == 0.0
    assert cap.spilled_l > 1.0
    assert tank.level_l == 10.0


def test_what_lands_blends_into_the_contents() -> None:
    from sim.components import Tank
    sim = Simulation()
    source = sim.add(Source("supply", species="solvent", pressure_kpa=300.0))
    cap = sim.add(Cap("end", elevation_m=2.0))
    cap.open = True
    tank = sim.add(Tank("t", capacity_l=100.0, level_l=10.0, height_m=1.0, open_top=True))
    cap.catch = tank
    sim.connect(source, "outlet", cap, "a")
    sim.run(20.0)
    assert tank.contents.comp.get("solvent", 0.0) > 0.3
