"""A pressure gauge tapped into a pipe at any point along it (director,
2026-09-22: "tap a pressure gauge into any point on a pipe").

The gauge is cut into the line like a flow element, but a tapping is a
hole in the pipe wall, not a restriction: its inlet and outlet are one
hydraulic node, so it costs the line nothing. The game splits the line's
resistance between the two pieces by length, so the pipe as a whole
passes what it passed before and the gauge reads the pressure at the
point it stands.
"""
from __future__ import annotations

import pytest

from sim.components import Drain, Gauge, Source
from sim.core import Simulation
from sim.hydraulics import HEAD_PA_PER_M

K = 20_000.0   # the whole line, Pa per (L/s)^2


def _line(fraction: float | None, elevation_m: float = 0.0) -> tuple[Drain, Gauge | None]:
    """A header at 400 kPa through one line into a drain; with a gauge
    cut in at `fraction` of the line's length when given."""
    sim = Simulation()
    header = sim.add(Source("hdr", pressure_kpa=400.0))
    drain = sim.add(Drain("dr", rate_lps=4.0))
    gauge = None
    if fraction is None:
        sim.connect(header, "outlet", drain, "inlet").k_pa_per_lps2 = K
    else:
        gauge = sim.add(Gauge("pi", "line_kpa", elevation_m=elevation_m))
        sim.connect(header, "outlet", gauge, "inlet").k_pa_per_lps2 = K * fraction
        sim.connect(gauge, "outlet", drain, "inlet").k_pa_per_lps2 = K * (1.0 - fraction)
    sim.run(3.0)
    return drain, gauge


class TestLineGauge:
    def test_a_tapping_costs_the_line_nothing(self) -> None:
        plain, _ = _line(None)
        tapped, _ = _line(0.3)
        assert tapped.inlet.flow_lps == pytest.approx(plain.inlet.flow_lps, rel=1e-6)

    def test_it_reads_the_pressure_where_it_stands(self) -> None:
        # The header's 400 kPa falls along the line: a gauge near the
        # header reads more than one near the drain, and each reads the
        # header less its piece's own loss.
        drain, near = _line(0.2)
        _, far = _line(0.8)
        q = drain.inlet.flow_lps
        assert q > 0.0
        assert near.reading > far.reading
        assert near.reading == pytest.approx(400.0 - K * 0.2 * q * q / 1000.0, rel=1e-3)
        assert far.reading == pytest.approx(400.0 - K * 0.8 * q * q / 1000.0, rel=1e-3)

    def test_it_reads_static_pressure_at_its_own_height(self) -> None:
        # The same point of the same line, the gauge 3 m higher: the node
        # is piezometric and unchanged, the dial reads rho*g*3 m less.
        _, low = _line(0.5, 0.0)
        _, high = _line(0.5, 3.0)
        assert low.reading - high.reading == pytest.approx(3.0 * HEAD_PA_PER_M / 1000.0, rel=1e-6)

    def test_its_signal_is_its_reading(self) -> None:
        _, gauge = _line(0.5)
        assert gauge.signal.value == gauge.reading
