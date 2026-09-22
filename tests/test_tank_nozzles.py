"""A tank's nozzles stand where they were welded (director, 2026-09-22:
"the tank's nozzle position should certainly be in the kernel"), and
each takes the size of the line on it.

What a nozzle feels is where it stands against the liquid: under the
surface it carries the head of everything above it and passes flow
either way; above it, it sits at headspace pressure, lets a line fall
in, and passes nothing out. The two defaults -- the outlet on the
floor, the inlet at the roof -- are the tank as it always was.
"""
from __future__ import annotations

import pytest

from sim.components import Drain, MixTee, Source, SplitTee, Tank
from sim.core import Simulation
from sim.hydraulics import HEAD_PA_PER_M, NozzleResistance
from tests.conftest import open_drain


def _small_tank(nozzle_cv_lps: float = 5.0) -> Tank:
    """A metre tall and 30 cm across: about 70 L, so gravity empties it
    within a couple of minutes of sim time."""
    return Tank("t", capacity_l=1.0, height_m=1.0, diameter_m=0.3,
                nozzle_cv_lps=nozzle_cv_lps)


def _tank_draining_to_a_drain(outlet_h_m: float, seconds: float = 180.0) -> Tank:
    """A small tank charged to the brim, its outlet welded outlet_h_m
    above the base, draining by gravity to a sewer."""
    sim = Simulation()
    tank = sim.add(_small_tank())
    tank.charge(tank.capacity_l, {"water": 1.0})
    tank.set_nozzle("outlet", height_m=outlet_h_m)
    open_drain(sim, tank)
    sim.run(seconds)
    return tank


class TestNozzleHeight:
    def test_the_default_outlet_drains_the_vessel_dry(self) -> None:
        tank = _tank_draining_to_a_drain(0.0)
        assert tank.depth_m < 0.02

    def test_an_outlet_welded_up_the_shell_leaves_a_heel(self) -> None:
        # The liquid stops at the nozzle, give or take the 3 cm it
        # uncovers over.
        tank = _tank_draining_to_a_drain(0.3)
        assert tank.depth_m == pytest.approx(0.3, abs=0.035)
        assert tank.level_l > 0.25 * tank.capacity_l

    def test_a_nozzle_at_the_roof_never_passes_anything_out(self) -> None:
        tank = _tank_draining_to_a_drain(Tank.AT_ROOF)
        assert tank.level_l == pytest.approx(tank.capacity_l)

    def test_the_roof_follows_a_resize(self) -> None:
        tank = Tank("t", capacity_l=1.0, height_m=1.0, diameter_m=1.0)
        assert tank.nozzle_height("inlet") == pytest.approx(1.0)
        tank.set_size(2.0, 1.0)
        assert tank.nozzle_height("inlet") == pytest.approx(2.0)
        # A welded nozzle is clamped to the shell it is on.
        tank.set_nozzle("outlet", height_m=5.0)
        assert tank.nozzle_height("outlet") == pytest.approx(2.0)

    def test_a_submerged_nozzle_reads_the_same_head_at_any_height(self) -> None:
        # Piezometric: two nozzles under the liquid see one pressure,
        # however far apart they stand on the shell.
        sim = Simulation()
        tank = sim.add(Tank("t", capacity_l=1.0, height_m=2.0, diameter_m=1.0))
        tank.charge(tank.capacity_l, {"water": 1.0})
        tank.set_nozzle("inlet", height_m=1.0)
        tank.set_nozzle("outlet", height_m=0.0)
        open_drain(sim, tank)
        sim.run(0.1)
        net = sim._network
        p_in = net.pressures[tank._nozzle_nodes["inlet"]]
        p_out = net.pressures[tank._nozzle_nodes["outlet"]]
        assert p_in == pytest.approx(p_out)
        # And an uncovered nozzle reads headspace at its own height.
        tank.set_nozzle("inlet", height_m=Tank.AT_ROOF)
        sim.run(0.1)
        p_roof = net.pressures[tank._nozzle_nodes["inlet"]]
        assert p_roof == pytest.approx(2.0 * HEAD_PA_PER_M, rel=1e-6)


class TestNozzleDirection:
    def _tank_with_a_drain_on_its_inlet(self, inlet_h_m: float) -> Tank:
        """A half-charged tank whose *inlet* line runs to an open drain:
        with the nozzle under the liquid the vessel drains out through
        it, with the nozzle above the liquid nothing can leave."""
        sim = Simulation()
        tank = sim.add(_small_tank())
        tank.charge(0.5 * tank.capacity_l, {"water": 1.0})
        tank.set_nozzle("inlet", height_m=inlet_h_m)
        # A kernel wire runs output to input, so the inlet's line comes
        # off a tee whose other leg feeds the sewer.
        tee = sim.add(SplitTee("tee"))
        drain = sim.add(Drain("d", rate_lps=50.0))
        sim.connect(tee, "a", tank, "inlet")
        sim.connect(tee, "b", drain, "inlet")
        sim.run(120.0)
        return tank

    def test_a_submerged_inlet_can_flow_back_out(self) -> None:
        tank = self._tank_with_a_drain_on_its_inlet(0.2)
        assert tank.depth_m == pytest.approx(0.2, abs=0.035)

    def test_an_inlet_above_the_liquid_cannot(self) -> None:
        tank = self._tank_with_a_drain_on_its_inlet(0.8)
        # To within the solver's tolerance on a still line (a few
        # microlitres a second, inward).
        assert tank.level_l == pytest.approx(0.5 * tank.capacity_l, abs=0.01)

    def test_a_dry_nozzle_still_lets_a_line_fill_the_vessel(self) -> None:
        # Charging up through a bottom nozzle that starts uncovered: a
        # header pushes into the tank's outlet line through a tee whose
        # third leg goes to a sewer too small to take it all.
        sim = Simulation()
        header = sim.add(Source("hdr", pressure_kpa=100.0))
        tank = sim.add(_small_tank())
        tee = sim.add(MixTee("tee"))
        sink = sim.add(Drain("d", rate_lps=0.01))
        sim.connect(header, "outlet", tee, "a")
        sim.connect(tank, "outlet", tee, "b")
        sim.connect(tee, "out", sink, "inlet")
        sim.run(20.0)
        assert tank.level_l > 0.2 * tank.capacity_l


class TestNozzleSize:
    def test_a_small_nozzle_passes_less(self) -> None:
        big = _tank_draining_to_a_drain(0.0, seconds=2.0)
        sim = Simulation()
        small = sim.add(_small_tank())
        small.charge(small.capacity_l, {"water": 1.0})
        small.set_nozzle("outlet", dn=15)
        open_drain(sim, small)
        sim.run(2.0)
        assert small.nozzle_cv("outlet") == pytest.approx(5.0 * (15 / 50) ** 2)
        assert small.capacity_l - small.level_l < 0.5 * (big.capacity_l - big.level_l)

    def test_the_branch_itself(self) -> None:
        # Dry: a check seen from the vessel. Submerged: a valve open by
        # the submergence for outflow, wide open for inflow.
        n = NozzleResistance(0, 1, cv_lps=10.0)
        n.submergence = 0.0
        assert n.flow(50_000.0) == 0.0
        assert not n.is_conducting(50_000.0)
        assert n.conductance(50_000.0) > 0.0          # the open side's slope
        assert n.flow(-100_000.0) == pytest.approx(-10.0)
        assert n.is_conducting(-100_000.0)
        n.submergence = 0.5
        assert n.flow(100_000.0) == pytest.approx(5.0)
        assert n.flow(-100_000.0) == pytest.approx(-10.0)
        n.set_cv(20.0)
        assert n.flow(-100_000.0) == pytest.approx(-20.0)
