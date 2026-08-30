"""Tests for the build-mode kernel features: gauges, mid-run placement,
component removal."""
from __future__ import annotations

import pytest

from conftest import wire_power
from sim.components import Gauge, Pump, Relay, Tank
from sim.core import Simulation
from sim.historian import Historian


class TestGauge:
    def test_level_gauge_reads_hydrostatic_head(self) -> None:
        sim = Simulation(dt=1.0)
        tank = sim.add(Tank("tank", capacity_l=100.0, level_l=45.45))
        gauge = sim.add(Gauge("pi_1", "level_kpa", liters_per_meter=45.45))
        sim.connect(tank, "level", gauge, "process")
        sim.tick()
        sim.tick()  # one scan for the level to reach the gauge
        # 45.45 L / 45.45 L/m = 1 m of water = 9.81 kPa
        assert gauge.reading == pytest.approx(9.81)
        assert gauge.signal.value == pytest.approx(9.81)
        assert gauge.units() == "kPa"

    def test_flow_gauge_reads_flow(self) -> None:
        sim = Simulation(dt=1.0)
        pump = sim.add(Pump("pump", rated_lps=4.0, mode="hand"))
        wire_power(sim, pump)
        gauge = sim.add(Gauge("fi_1", "flow"))
        sim.connect(pump, "flow", gauge, "process")
        sim.tick()
        sim.tick()
        assert gauge.reading == pytest.approx(4.0)
        assert gauge.units() == "L/s"

    def test_rejects_bad_construction(self) -> None:
        with pytest.raises(ValueError):
            Gauge("g", "temperature")
        with pytest.raises(ValueError):
            Gauge("g", "level_kpa", liters_per_meter=0.0)


class TestMidRunPlacement:
    def test_component_added_mid_run_is_historized_from_then_on(self) -> None:
        sim = Simulation(dt=1.0)
        tank = sim.add(Tank("tank", capacity_l=100.0, level_l=50.0))
        hist = sim.attach_historian(Historian())
        sim.run(5.0)
        gauge = sim.add(Gauge("pi_1", "level_kpa"))
        sim.connect(tank, "level", gauge, "process")
        sim.register_with_historian(gauge)
        sim.run(3.0)
        assert hist.start_index("pi_1.reading") == 6
        assert len(hist.series("pi_1.reading")) == 3
        assert hist.series("pi_1.reading")[-1] == pytest.approx(gauge.reading)


class TestRemoval:
    def _plant(self) -> tuple[Simulation, Historian]:
        sim = Simulation(dt=1.0)
        pump = sim.add(Pump("pump", rated_lps=2.0, mode="hand"))
        wire_power(sim, pump)
        tank = sim.add(Tank("tank", capacity_l=100.0))
        sim.connect(pump, "flow", tank, "in_flow")
        hist = sim.attach_historian(Historian())
        return sim, hist

    def test_remove_drops_wires_and_retires_tags(self) -> None:
        sim, hist = self._plant()
        sim.run(2.0)
        assert sim.remove_component("pump") is True
        assert sim.remove_component("pump") is False
        assert len(sim.wires) == 0
        assert "pump.flow" not in hist.active_tags
        assert "pump.flow" in hist.tags  # history preserved
        sim.run(2.0)  # keeps ticking without the pump
        tank = sim.get_component("tank")
        assert tank is not None

    def test_removed_input_accepts_new_wire(self) -> None:
        sim, _ = self._plant()
        sim.remove_component("pump")
        pump2 = sim.add(Pump(sim.unique_name("pump"), rated_lps=3.0, mode="hand"))
        assert pump2.name == "pump_1"
        wire_power(sim, pump2)
        tank = sim.get_component("tank")
        sim.connect(pump2, "flow", tank, "in_flow")
        sim.run(2.0)
        assert tank.level_l > 0.0

    def test_unique_names_never_collide(self) -> None:
        sim = Simulation()
        names = set()
        for _ in range(5):
            name = sim.unique_name("tank")
            sim.add(Tank(name, capacity_l=10.0))
            names.add(name)
        assert len(names) == 5
