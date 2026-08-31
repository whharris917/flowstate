"""Tests for the power layer: feeds, voltage classes, dead equipment."""
from __future__ import annotations

import pytest

from sim.components import MainsFeed, PowerSupply, Pump
from sim.control import PLC
from sim.core import Simulation


class TestPower:
    def test_unpowered_pump_is_dead_even_in_hand(self) -> None:
        sim = Simulation(dt=0.05)
        pump = sim.add(Pump("p", rated_lps=4.0, mode="hand"))
        sim.run(1.0)
        assert not pump.running
        assert pump.outlet.value.flow_lps == 0.0

    def test_powered_pump_runs(self) -> None:
        sim = Simulation(dt=0.05)
        pump = sim.add(Pump("p", rated_lps=4.0, mode="hand"))
        mains = sim.add(MainsFeed("mains"))
        sim.connect(mains, "power", pump, "power")
        sim.run(1.0)
        assert pump.running

    def test_voltage_mismatch_refused(self) -> None:
        sim = Simulation(dt=0.05)
        pump = sim.add(Pump("p", rated_lps=4.0))          # needs 480VAC
        psu = sim.add(PowerSupply("psu"))                  # provides 24VDC
        with pytest.raises(ValueError, match="voltage mismatch"):
            sim.connect(psu, "dc_out", pump, "power")

    def test_psu_chain_powers_plc_and_dies_with_feeder(self) -> None:
        sim = Simulation(dt=0.05)
        mains = sim.add(MainsFeed("mains"))
        psu = sim.add(PowerSupply("psu"))
        plc = sim.add(PLC("plc"))
        sim.connect(mains, "power", psu, "ac_in")
        sim.connect(psu, "dc_out", plc, "power")
        plc.set_program([{"coil": "do_0", "logic": [[{"ref": "di_0", "nc": True}]]}])
        sim.run(1.0)
        assert plc.do_ports[0].value       # NC of a dead input passes
        assert plc.scans > 0
        # Pull the feeder: the PSU output collapses and the PLC halts
        # with its outputs dropped.
        sim.disconnect(mains, "power", psu, "ac_in")
        scans_at_loss = plc.scans
        sim.run(1.0)
        assert not plc.do_ports[0].value
        # One stale-wire scan may land before the loss propagates.
        assert plc.scans <= scans_at_loss + 1

    def test_power_not_orred_single_source(self) -> None:
        sim = Simulation(dt=0.05)
        pump = sim.add(Pump("p", rated_lps=4.0))
        mains_a = sim.add(MainsFeed("ma"))
        mains_b = sim.add(MainsFeed("mb"))
        sim.connect(mains_a, "power", pump, "power")
        with pytest.raises(ValueError, match="one wire"):
            sim.connect(mains_b, "power", pump, "power")
