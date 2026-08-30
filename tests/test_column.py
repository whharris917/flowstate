"""Tests for the distillation column: heat-up, boilup, overhead pressure."""
from __future__ import annotations

import pytest

from sim.components import Column, Gauge
from sim.core import Simulation


def _column_sim() -> tuple[Simulation, Column]:
    sim = Simulation(dt=0.05)
    column = sim.add(Column("still"))
    return sim, column


class TestColumn:
    def test_cold_column_is_quiet(self) -> None:
        sim, column = _column_sim()
        sim.run(60.0)
        assert column.boilup_kgps == 0.0
        assert column.p_top_pa == pytest.approx(0.0)

    def test_heats_to_boiling_and_holds(self) -> None:
        sim, column = _column_sim()
        column.set_duty(1.0)
        sim.run(60.0)
        assert column.temp_c == pytest.approx(Column.BOIL_C)
        sim.run(300.0)
        assert column.temp_c == pytest.approx(Column.BOIL_C)

    def test_overhead_pressure_settles_at_vent_balance(self) -> None:
        sim, column = _column_sim()
        column.set_duty(1.0)
        sim.run(300.0)  # heat-up ~10 s, then many pressure time constants
        boilup = column.max_duty_kw / Column.LATENT_KJ_PER_KG
        expected = boilup / Column.VENT_KG_PER_S_PA
        assert column.p_top_pa == pytest.approx(expected, rel=0.02)
        assert column.p_top.value == column.p_top_pa

    def test_half_duty_gives_half_pressure(self) -> None:
        sim, column = _column_sim()
        column.set_duty(1.0)
        sim.run(300.0)
        full = column.p_top_pa
        column.set_duty(0.5)
        sim.run(300.0)
        assert column.p_top_pa == pytest.approx(full / 2.0, rel=0.03)

    def test_duty_off_decays_pressure_and_cools(self) -> None:
        sim, column = _column_sim()
        column.set_duty(1.0)
        sim.run(300.0)
        column.set_duty(0.0)
        sim.run(180.0)  # 6 pressure time constants
        assert column.p_top_pa < 200.0
        assert column.temp_c < Column.BOIL_C

    def test_duty_validation(self) -> None:
        _, column = _column_sim()
        with pytest.raises(ValueError):
            column.set_duty(1.2)
        with pytest.raises(ValueError):
            Column("bad", charge_l=0.0)


class TestPressureGauge:
    def test_press_kpa_reads_pascals_as_kilopascals(self) -> None:
        sim = Simulation(dt=0.05)
        column = sim.add(Column("still"))
        gauge = sim.add(Gauge("pi_top", "press_kpa"))
        sim.connect(column, "p_top", gauge, "process")
        column.set_duty(1.0)
        sim.run(300.0)
        assert gauge.units() == "kPa"
        # One-scan wire latency: compare against the port, loosely.
        assert gauge.reading == pytest.approx(column.p_top_pa / 1000.0, rel=0.01)
        assert 35.0 < gauge.reading < 45.0
        assert gauge.signal.value == gauge.reading
