"""Tests for the power layer: feeds, voltage classes, dead equipment."""
from __future__ import annotations

import pytest

from sim.components import MainsFeed, PowerDistribution, PowerSupply, Pump
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
        sim.connect(mains, "way1", pump, "power")
        sim.run(1.0)
        assert pump.running

    def test_distribution_strip_feeds_each_way_from_one_supply(self) -> None:
        sim = Simulation(dt=0.05)
        mains = sim.add(MainsFeed("mains"))
        psu = sim.add(PowerSupply("psu"))
        strip = sim.add(PowerDistribution("pd", ways=3))
        plcs = [sim.add(PLC(f"plc{i}")) for i in range(3)]
        sim.connect(mains, "way1", psu, "ac_in")
        sim.connect(psu, "dc_out", strip, "in")
        for i, plc in enumerate(plcs):
            sim.connect(strip, f"way{i + 1}", plc, "power")
        sim.run(1.0)
        assert all(plc.scans > 0 for plc in plcs)
        # The supply lost: every way goes dead.
        sim.disconnect(mains, "way1", psu, "ac_in")
        sim.run(1.0)
        assert all(port.value == 0.0 for port in strip.way_ports)

    def test_distribution_strip_is_24v_only(self) -> None:
        sim = Simulation(dt=0.05)
        mains = sim.add(MainsFeed("mains"))
        strip = sim.add(PowerDistribution("pd"))
        with pytest.raises(ValueError, match="voltage mismatch"):
            sim.connect(mains, "way1", strip, "in")

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
        sim.connect(mains, "way1", psu, "ac_in")
        sim.connect(psu, "dc_out", plc, "power")
        plc.set_program([{"coil": "do_0", "logic": [[{"ref": "di_0", "nc": True}]]}])
        sim.run(1.0)
        assert plc.do_ports[0].value       # NC of a dead input passes
        assert plc.scans > 0
        # Pull the feeder: the PSU output collapses and the PLC halts
        # with its outputs dropped.
        sim.disconnect(mains, "way1", psu, "ac_in")
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
        sim.connect(mains_a, "way1", pump, "power")
        with pytest.raises(ValueError, match="one wire"):
            sim.connect(mains_b, "way1", pump, "power")
