"""Tests for the control layer: PLC ladder scan, PID, valve, terminal."""
from __future__ import annotations

import pytest

from conftest import wire_supply
from sim.components import ControlValve, Gauge, Tank, Terminal
from sim.control import PID, PLC
from sim.core import Simulation


def _plc() -> tuple[Simulation, PLC]:
    sim = Simulation(dt=0.05)
    plc = sim.add(PLC("plc"))
    plc.power.value = 1.0  # direct-tick tests: energize the rack
    return sim, plc


def _press(plc: PLC, channel: int, value: bool) -> None:
    plc.di_ports[channel].value = value


class TestLadder:
    def test_seal_in_start_stop(self) -> None:
        sim, plc = _plc()
        plc.set_program([
            {"coil": "m_0", "logic": [
                [{"ref": "di_0"}, {"ref": "di_1", "nc": True}],
                [{"ref": "m_0"}, {"ref": "di_1", "nc": True}],
            ]},
            {"coil": "do_0", "logic": [[{"ref": "m_0"}]]},
        ])
        _press(plc, 0, True)          # start button held for one scan
        plc.tick(0.05)
        _press(plc, 0, False)
        plc.tick(0.05)
        assert plc.do_ports[0].value  # sealed in
        plc.tick(0.05)
        assert plc.do_ports[0].value
        _press(plc, 1, True)          # stop
        plc.tick(0.05)
        assert not plc.do_ports[0].value
        _press(plc, 1, False)
        plc.tick(0.05)
        assert not plc.do_ports[0].value  # stays stopped

    def test_nc_contact_and_or_branch(self) -> None:
        _, plc = _plc()
        plc.set_program([
            {"coil": "do_1", "logic": [
                [{"ref": "di_2", "nc": True}],
                [{"ref": "di_3"}],
            ]},
        ])
        plc.tick(0.05)
        assert plc.do_ports[1].value          # NC passes when input off
        _press(plc, 2, True)
        plc.tick(0.05)
        assert not plc.do_ports[1].value      # NC opens
        _press(plc, 3, True)
        plc.tick(0.05)
        assert plc.do_ports[1].value          # OR branch carries it

    def test_undriven_do_stays_off_and_same_scan_ordering(self) -> None:
        _, plc = _plc()
        plc.set_program([
            {"coil": "m_1", "logic": [[{"ref": "di_0"}]]},
            {"coil": "do_2", "logic": [[{"ref": "m_1"}]]},  # sees m_1 same scan
        ])
        _press(plc, 0, True)
        plc.tick(0.05)
        assert plc.do_ports[2].value
        assert not plc.do_ports[3].value  # never driven, stays off

    def test_ton_timer(self) -> None:
        _, plc = _plc()
        plc.set_timer_preset(0, 0.5)
        plc.set_program([
            {"coil": "t_0", "logic": [[{"ref": "di_0"}]]},
            {"coil": "do_0", "logic": [[{"ref": "t_0"}]]},
        ])
        _press(plc, 0, True)
        for _ in range(9):  # 0.45 s — not yet
            plc.tick(0.05)
        assert not plc.do_ports[0].value
        plc.tick(0.05)      # 0.5 s — done
        plc.tick(0.05)      # done bit read next scan
        assert plc.do_ports[0].value
        _press(plc, 0, False)
        plc.tick(0.05)
        plc.tick(0.05)
        assert not plc.do_ports[0].value  # TON resets when released
        assert plc.timer_acc[0] == 0.0

    def test_program_validation(self) -> None:
        _, plc = _plc()
        with pytest.raises(ValueError):
            plc.set_program([{"coil": "di_0", "logic": [[{"ref": "di_0"}]]}])
        with pytest.raises(ValueError):
            plc.set_program([{"coil": "do_0", "logic": [[{"ref": "dq_9"}]]}])
        with pytest.raises(ValueError):
            plc.set_program([{"coil": "do_0", "logic": [[]]}])
        with pytest.raises(ValueError):
            plc.set_program([{"coil": "do_99", "logic": [[{"ref": "di_0"}]]}])

    def test_ao_move_scales(self) -> None:
        _, plc = _plc()
        plc.set_ao_moves([{"dst": "ao_0", "src": "ai_1", "k": 2.0, "b": 5.0}])
        plc.ai_ports[1].value = 10.0
        plc.tick(0.05)
        assert plc.ao_ports[0].value == pytest.approx(25.0)

    def test_state_roundtrip(self) -> None:
        _, plc = _plc()
        plc.set_timer_preset(1, 3.0)
        plc.set_program([{"coil": "m_0", "logic": [[{"ref": "di_0"}]]}])
        plc.mem[0] = True
        state = plc.state_dict()
        _, fresh = _plc()
        fresh.apply_state(state)
        assert fresh.program == plc.program
        assert fresh.mem[0]
        assert fresh.timer_presets[1] == 3.0


class TestPIDLoop:
    def _loop(self) -> tuple[Simulation, Tank, PID, ControlValve]:
        """Level control: valve fills the tank, PID holds hydrostatic
        head at setpoint against a constant 2 L/s drain."""
        sim = Simulation(dt=0.05)
        tank = sim.add(Tank("tank", 200.0, 50.0, drain_lps=2.0))
        gauge = sim.add(Gauge("lt", "level_kpa"))
        pid = sim.add(PID("lic", kp=8.0, ki=1.5, sp=15.0))
        valve = sim.add(ControlValve("lv", cv_lps=6.0))
        wire_supply(sim, valve)
        sim.connect(tank, "level", gauge, "process")
        sim.connect(gauge, "signal", pid, "pv")
        sim.connect(pid, "out", valve, "cmd")
        sim.connect(valve, "outlet", tank, "inlet")
        return sim, tank, pid, valve

    def test_pi_reaches_setpoint_without_offset(self) -> None:
        sim, tank, pid, valve = self._loop()
        sim.run(600.0)
        level_kpa = tank.level_l / 45.45 * Gauge.WATER_KPA_PER_M
        assert level_kpa == pytest.approx(15.0, abs=0.2)
        # Steady state: inflow matches the 2 L/s drain.
        assert valve.outlet.value == pytest.approx(2.0, abs=0.1)

    def test_manual_mode_holds_output(self) -> None:
        sim, tank, pid, valve = self._loop()
        pid.set_mode("manual")
        pid.manual_out = 50.0
        sim.run(30.0)
        assert pid.output == pytest.approx(50.0)
        assert valve.position == pytest.approx(50.0, abs=1.0)

    def test_output_clamps(self) -> None:
        sim, tank, pid, valve = self._loop()
        pid.sp = 1000.0  # unreachable — output must rail at 100
        sim.run(60.0)
        assert pid.output == pytest.approx(100.0)


class TestValveAndTerminal:
    def test_positioner_lag(self) -> None:
        sim = Simulation(dt=0.05)
        valve = sim.add(ControlValve("cv", cv_lps=10.0, tau_s=1.0))
        valve.inlet.value = 1.0e9
        valve.cmd.value = 100.0
        for _ in range(20):  # 1.0 s in scan steps: ~63 % of the way
            valve.tick(0.05)
        assert 55.0 < valve.position < 70.0

    def test_terminal_passthrough_kinds(self) -> None:
        sim = Simulation(dt=0.05)
        term_d = sim.add(Terminal("tb1", "discrete"))
        term_a = sim.add(Terminal("tb2", "analog"))
        term_d.t_in.value = True
        term_a.t_in.value = 4.2
        term_d.tick(0.05)
        term_a.tick(0.05)
        assert term_d.t_out.value is True
        assert term_a.t_out.value == pytest.approx(4.2)
        with pytest.raises(ValueError):
            Terminal("bad", "power")
