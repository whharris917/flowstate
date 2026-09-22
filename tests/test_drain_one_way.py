"""An open drain is one-way (2026-09-22): it takes what it is given and
gives nothing back. Under suction a real open drain draws air; the model
had passed sewer water backwards onto a pump's suction, material from
nowhere that the drain's meter, which counts only forward flow, never
saw."""
from __future__ import annotations

import pytest

from conftest import open_drain, wire_power
from sim.components import Drain, Pump, Source, Tee
from sim.core import Simulation


class TestDrainOneWay:
    def test_a_pump_cannot_draw_from_a_sewer(self) -> None:
        # A pump's suction shares a tee with a drain and nothing else:
        # nothing supplies that node, so the pump must move nothing.
        sim = Simulation(dt=0.05)
        tee = sim.add(Tee("t", "split"))
        sewer = sim.add(Drain("sewer", rate_lps=50.0))
        pump = sim.add(Pump("p", rated_lps=4.0, mode="hand", head_m=30.0))
        sim.connect(tee, "a", pump, "inlet")
        sim.connect(tee, "b", sewer, "inlet")
        out = open_drain(sim, pump)
        wire_power(sim, pump)
        sim.run(5.0)
        assert out.total_l == pytest.approx(0.0, abs=1e-9)
        assert sewer.inlet.flow_lps >= 0.0

    def test_it_still_takes_what_it_is_given(self) -> None:
        sim = Simulation(dt=0.05)
        header = sim.add(Source("hdr", pressure_kpa=200.0))
        drain = sim.add(Drain("dr", rate_lps=2.0))
        sim.connect(header, "outlet", drain, "inlet")
        sim.run(5.0)
        assert drain.total_l > 0.0
        assert drain.total_l == pytest.approx(header.total_l, rel=1e-6)
