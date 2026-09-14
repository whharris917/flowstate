"""A cap is a two-nozzle fitting on one node: a blind end while only
one nozzle carries a line, a coupling once both do.
"""

import pytest

from sim.components import Cap, Drain, Source
from sim.core import Simulation


def test_a_capped_line_stands_at_pressure_and_moves_nothing() -> None:
    sim = Simulation(dt=0.05)
    header = sim.add(Source("hdr", pressure_kpa=300.0))
    cap = sim.add(Cap("cap"))
    sim.connect(header, "outlet", cap, "a")
    sim.run(5.0)
    assert header.total_l == pytest.approx(0.0, abs=1e-6)
    assert cap.inputs["a"].flow_lps == pytest.approx(0.0, abs=1e-9)
    # One node, and it sees the header's pressure through a still line.
    nodes = {port.node for port in cap.material_ports().values()}
    assert len(nodes) == 1
    assert sim._network.pressures[cap.inputs["a"].node] == pytest.approx(300.0e3, rel=1e-3)


def test_two_caps_joined_pass_flow_like_a_coupling() -> None:
    sim = Simulation(dt=0.05)
    header = sim.add(Source("hdr", pressure_kpa=300.0))
    left = sim.add(Cap("left"))
    right = sim.add(Cap("right"))
    drain = sim.add(Drain("d", rate_lps=4.0))
    sim.connect(header, "outlet", left, "a")
    sim.connect(left, "b", right, "a")
    sim.connect(right, "b", drain, "inlet")
    sim.run(20.0)
    assert drain.total_l > 10.0
    assert header.total_l == pytest.approx(drain.total_l, rel=1e-6)
