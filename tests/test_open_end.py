"""An open cap is an atmospheric end that spills what the line delivers
(director, 2026-09-20); closed, it holds pressure and moves nothing."""

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
