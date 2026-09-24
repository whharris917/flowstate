"""Tests for the hydraulic network.

These are the behaviours that separate a solved network from asserted
flow. If a pump does not dead-head, if two in parallel double the flow,
if a tee does not split by resistance, or if a tank does not drain
downhill on its own, then pressure is decorative and we are back to
bookkeeping.
"""
from __future__ import annotations

import pytest

from sim.hydraulics import (
    ATMOSPHERIC_PA,
    ControlResistance,
    FixedFlow,
    HEAD_PA_PER_M,
    MIN_PRESSURE_PA,
    Network,
    PumpCurve,
    Resistance,
    static_head_pa,
)


def _line(net: Network, a: int, b: int, k: float = 1000.0) -> Resistance:
    return net.add_branch(Resistance(a, b, k))


class TestConservation:
    def test_flow_into_a_node_equals_flow_out(self) -> None:
        """The whole point of the solve: every free node balances."""
        net = Network()
        supply = net.add_node(300_000.0, fixed=True)
        middle = net.add_node()
        sink_a = net.add_node(ATMOSPHERIC_PA, fixed=True)
        sink_b = net.add_node(ATMOSPHERIC_PA, fixed=True)
        feed = _line(net, supply, middle, 2000.0)
        out_a = _line(net, middle, sink_a, 8000.0)
        out_b = _line(net, middle, sink_b, 8000.0)
        net.solve()
        assert net.residual_lps < Network.TOLERANCE_LPS
        assert feed.flow_lps == pytest.approx(out_a.flow_lps + out_b.flow_lps,
                                              abs=Network.TOLERANCE_LPS)

    def test_converges_in_a_handful_of_iterations(self) -> None:
        net = Network()
        supply = net.add_node(400_000.0, fixed=True)
        node = net.add_node()
        drain = net.add_node(ATMOSPHERIC_PA, fixed=True)
        _line(net, supply, node, 1500.0)
        _line(net, node, drain, 1500.0)
        net.solve()
        assert net.iterations <= 12
        # Warm-started, the next scan is nearly free.
        net.solve()
        assert net.iterations <= 3


class TestResistance:
    def test_square_law(self) -> None:
        """Four times the pressure is twice the flow, not four times."""
        net = Network()
        high = net.add_node(40_000.0, fixed=True)
        low = net.add_node(ATMOSPHERIC_PA, fixed=True)
        line = _line(net, high, low, 10_000.0)
        net.solve()
        two_kpa_flow = line.flow_lps
        net.set_pressure(high, 160_000.0)
        net.solve()
        assert line.flow_lps == pytest.approx(2.0 * two_kpa_flow, rel=1e-3)

    def test_flow_runs_downhill_and_reverses_with_the_gradient(self) -> None:
        net = Network()
        left = net.add_node(50_000.0, fixed=True)
        right = net.add_node(ATMOSPHERIC_PA, fixed=True)
        line = _line(net, left, right)
        net.solve()
        assert line.flow_lps > 0.0
        net.set_pressure(left, -50_000.0)
        net.solve()
        assert line.flow_lps < 0.0

    def test_a_thinner_line_passes_less(self) -> None:
        net = Network()
        high = net.add_node(100_000.0, fixed=True)
        low = net.add_node(ATMOSPHERIC_PA, fixed=True)
        fat = _line(net, high, low, 1_000.0)
        net2 = Network()
        high2 = net2.add_node(100_000.0, fixed=True)
        low2 = net2.add_node(ATMOSPHERIC_PA, fixed=True)
        thin = _line(net2, high2, low2, 100_000.0)
        net.solve()
        net2.solve()
        assert fat.flow_lps > thin.flow_lps * 5.0


class TestTee:
    def test_a_node_splits_flow_by_resistance(self) -> None:
        """There is no splitter component. A tee is a node where three
        branches meet, and the split falls out of their resistances."""
        net = Network()
        supply = net.add_node(200_000.0, fixed=True)
        tee = net.add_node()
        easy_end = net.add_node(ATMOSPHERIC_PA, fixed=True)
        hard_end = net.add_node(ATMOSPHERIC_PA, fixed=True)
        feed = _line(net, supply, tee, 500.0)
        easy = _line(net, tee, easy_end, 1_000.0)
        hard = _line(net, tee, hard_end, 9_000.0)
        net.solve()
        assert feed.flow_lps == pytest.approx(easy.flow_lps + hard.flow_lps,
                                              abs=Network.TOLERANCE_LPS)
        # Square law: nine times the k is a third of the flow.
        assert easy.flow_lps == pytest.approx(3.0 * hard.flow_lps, rel=0.02)

    def test_closing_one_branch_pushes_flow_down_the_other(self) -> None:
        net = Network()
        supply = net.add_node(200_000.0, fixed=True)
        tee = net.add_node()
        a_end = net.add_node(ATMOSPHERIC_PA, fixed=True)
        b_end = net.add_node(ATMOSPHERIC_PA, fixed=True)
        _line(net, supply, tee, 500.0)
        valve = net.add_branch(ControlResistance(tee, a_end, 6.0))
        valve.opening = 1.0
        other = _line(net, tee, b_end, 4_000.0)
        net.solve()
        before = other.flow_lps
        valve.opening = 0.0
        net.solve()
        assert valve.flow_lps == 0.0
        assert other.flow_lps > before


class TestPumpCurve:
    def _rig(self, head_pa: float, max_lps: float, lift_pa: float):
        net = Network()
        suction = net.add_node(ATMOSPHERIC_PA, fixed=True)
        discharge = net.add_node(lift_pa, fixed=True)
        pump = net.add_branch(PumpCurve(suction, discharge, head_pa, max_lps))
        pump.running = True
        return net, pump

    def test_free_discharge_gives_the_rated_flow(self) -> None:
        net, pump = self._rig(300_000.0, 4.0, ATMOSPHERIC_PA)
        net.solve()
        assert pump.flow_lps == pytest.approx(4.0, rel=1e-3)

    def test_flow_falls_as_discharge_pressure_rises(self) -> None:
        flows = []
        for lift in [0.0, 100_000.0, 200_000.0, 280_000.0]:
            net, pump = self._rig(300_000.0, 4.0, lift)
            net.solve()
            flows.append(pump.flow_lps)
        assert flows == sorted(flows, reverse=True)
        assert flows[0] > flows[-1] * 3.0

    def test_dead_heads_against_too_much_head(self) -> None:
        """The motor spins, the discharge valve is open, and nothing
        moves. No amount of fiddling downstream changes it."""
        net, pump = self._rig(300_000.0, 4.0, 320_000.0)
        net.solve()
        assert pump.flow_lps == 0.0

    def test_stopped_pump_passes_nothing(self) -> None:
        net, pump = self._rig(300_000.0, 4.0, ATMOSPHERIC_PA)
        pump.running = False
        net.solve()
        assert pump.flow_lps == 0.0

    def test_two_in_parallel_do_not_double_the_flow(self) -> None:
        """The classic. Both pumps ride up their curves against the
        extra line loss, so the second one buys far less than the
        first."""
        def rig(pump_count: int) -> float:
            net = Network()
            suction = net.add_node(ATMOSPHERIC_PA, fixed=True)
            header = net.add_node()
            outlet = net.add_node(ATMOSPHERIC_PA, fixed=True)
            for _ in range(pump_count):
                pump = net.add_branch(PumpCurve(suction, header, 300_000.0, 4.0))
                pump.running = True
            line = _line(net, header, outlet, 20_000.0)
            net.solve()
            return line.flow_lps

        one = rig(1)
        two = rig(2)
        assert two > one                 # it does help
        assert two < 2.0 * one           # but nowhere near double


class TestStaticHead:
    def test_a_tank_drains_downhill_without_a_pump(self) -> None:
        """Two vessels and a pipe. No pump anywhere, and the full one
        empties into the empty one."""
        net = Network()
        full = net.add_node(static_head_pa(6.0), fixed=True)
        empty = net.add_node(ATMOSPHERIC_PA, fixed=True)
        line = _line(net, full, empty, 5_000.0)
        net.solve()
        assert line.flow_lps > 0.0

    def test_head_scales_with_depth(self) -> None:
        assert static_head_pa(1.0) == pytest.approx(HEAD_PA_PER_M)
        assert static_head_pa(10.0) == pytest.approx(98_100.0, rel=1e-3)
        assert static_head_pa(-2.0) == 0.0

    def test_a_pump_cannot_lift_past_its_head(self) -> None:
        """30 m of head will not fill a tank 40 m up."""
        net = Network()
        suction = net.add_node(ATMOSPHERIC_PA, fixed=True)
        top = net.add_node(static_head_pa(40.0), fixed=True)
        pump = net.add_branch(
            PumpCurve(suction, top, static_head_pa(30.0), 4.0))
        pump.running = True
        net.solve()
        assert pump.flow_lps == 0.0


class TestFixedFlow:
    def test_a_metering_machine_takes_what_it_takes(self) -> None:
        net = Network()
        supply = net.add_node(200_000.0, fixed=True)
        node = net.add_node()
        out = net.add_node(ATMOSPHERIC_PA, fixed=True)
        _line(net, supply, node, 1_000.0)
        machine = net.add_branch(FixedFlow(node, out, 1.5))
        net.solve()
        assert machine.flow_lps == pytest.approx(1.5)
        assert net.residual_lps < Network.TOLERANCE_LPS

    def test_starving_a_fixed_flow_pulls_its_suction_down(self) -> None:
        """Demand the network cannot meet drags the suction node toward
        vacuum instead of inventing material -- which is the signal a
        component should read as cavitation."""
        net = Network()
        dead = net.add_node(ATMOSPHERIC_PA, fixed=True)
        node = net.add_node()
        out = net.add_node(ATMOSPHERIC_PA, fixed=True)
        _line(net, dead, node, 5_000_000.0)   # a nearly blocked line
        net.add_branch(FixedFlow(node, out, 3.0))
        net.solve()
        assert net.pressures[node] < -50_000.0
        assert net.pressures[node] >= MIN_PRESSURE_PA


class TestRobustness:
    def test_an_isolated_node_does_not_break_the_solve(self) -> None:
        net = Network()
        net.add_node(ATMOSPHERIC_PA, fixed=True)
        lonely = net.add_node()
        net.solve()
        assert net.pressures[lonely] == net.pressures[lonely]  # not NaN

    def test_a_network_with_no_free_nodes_is_fine(self) -> None:
        net = Network()
        a = net.add_node(100_000.0, fixed=True)
        b = net.add_node(ATMOSPHERIC_PA, fixed=True)
        line = _line(net, a, b)
        net.solve()
        assert line.flow_lps > 0.0

    def test_zero_flow_at_equal_pressures(self) -> None:
        net = Network()
        a = net.add_node(50_000.0, fixed=True)
        b = net.add_node(50_000.0, fixed=True)
        line = _line(net, a, b)
        net.solve()
        assert line.flow_lps == pytest.approx(0.0, abs=1e-9)
