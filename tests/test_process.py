"""Tests for the process units: boiler, exchanger, reactor, centrifuge."""
from __future__ import annotations

import pytest

from conftest import wire_power, wire_supply
from sim.components import Drain, Pump, Source, Tank
from sim.core import Simulation
from sim.process import Centrifuge, HeatExchanger, Reactor, SteamGen


class TestSteamGen:
    def _boiler(self) -> tuple[Simulation, SteamGen]:
        sim = Simulation(dt=0.05)
        boiler = sim.add(SteamGen("sg", rated_kgps=0.5))
        wire_power(sim, boiler)
        source = sim.add(Source("bfw"))
        sim.connect(source, "supply", boiler, "inlet")
        sim.connect(boiler, "draw", source, "draw")
        return sim, boiler

    def test_makes_steam_when_fired_fed_and_powered(self) -> None:
        sim, boiler = self._boiler()
        boiler.is_on = True
        sim.run(60.0)
        assert boiler.steam.value == pytest.approx(0.5)
        assert boiler.press_pa == pytest.approx(SteamGen.PRESS_FULL_PA, rel=0.02)

    def test_cold_dark_and_dry_cases(self) -> None:
        sim, boiler = self._boiler()
        sim.run(5.0)
        assert boiler.steam.value == 0.0        # not fired
        boiler.is_on = True
        sim.disconnect(sim.get_component("mains_1"), "power", boiler, "power")
        sim.run(5.0)
        assert boiler.steam.value == 0.0        # no power

    def test_firing_dry_accrues_starve_time(self) -> None:
        sim = Simulation(dt=0.05)
        boiler = sim.add(SteamGen("sg"))
        wire_power(sim, boiler)
        boiler.is_on = True                     # no feedwater wired at all
        sim.run(10.0)
        assert boiler.steam.value == 0.0
        assert boiler.starve_s > 9.0


class TestHeatExchanger:
    def test_duty_follows_steam_and_stream_passes(self) -> None:
        hx = HeatExchanger("hx", max_duty_kw=1200.0)
        hx.steam_in.value = 0.4
        hx.cold_in.value = 3.0
        hx.tick(0.05)
        assert hx.duty.value == pytest.approx(800.0)
        assert hx.cold_out.value == pytest.approx(3.0)
        hx.steam_in.value = 5.0                 # more steam than area
        hx.tick(0.05)
        assert hx.duty.value == pytest.approx(1200.0)


class TestReactor:
    def _charged(self) -> Reactor:
        reactor = Reactor("rx", capacity_l=4000.0, rate_lps=6.0)
        reactor.volume_l = 2000.0
        reactor.product_l = 0.0
        return reactor

    def test_cold_or_unstirred_barely_reacts(self) -> None:
        cold = self._charged()
        cold.power.value = 1.0                  # stirred but cold
        for _ in range(1200):
            cold.tick(0.05)
        assert cold.purity_frac < 0.01
        hot_still = self._charged()
        hot_still.temp_c = 100.0
        for _ in range(200):                    # hot but unstirred
            hot_still.heat_duty.value = 800.0
            hot_still.tick(0.05)
        assert hot_still.purity_frac < 0.05

    def test_hot_and_stirred_converts(self) -> None:
        reactor = self._charged()
        reactor.temp_c = 60.0                   # preheated charge
        for _ in range(12000):                  # 600 s at full preheater duty
            reactor.heat_duty.value = 1200.0
            reactor.power.value = 1.0
            reactor.tick(0.05)
        assert reactor.temp_c > 80.0
        assert reactor.purity_frac > 0.5
        assert reactor.purity.value == pytest.approx(reactor.purity_frac)

    def test_inventory_conserved_with_feeds_and_draw(self) -> None:
        reactor = self._charged()
        for _ in range(200):
            reactor.inlet_a.value = 2.0
            reactor.inlet_b.value = 1.0
            reactor.draw.value = 1.5
            reactor.tick(0.05)
        assert reactor.volume_l == pytest.approx(2000.0 + (3.0 - 1.5) * 10.0, abs=0.5)
        assert reactor.overflowed_l == 0.0


class TestCentrifuge:
    def test_splits_by_purity_and_needs_power(self) -> None:
        fuge = Centrifuge("cf", rate_lps=4.0)
        fuge.inlet.value = 1000.0
        fuge.purity_in.value = 0.75
        fuge.is_on = True
        fuge.tick(0.05)
        assert fuge.product.value == 0.0        # unpowered bowl
        fuge.power.value = 1.0
        fuge.tick(0.05)
        assert fuge.draw.value == pytest.approx(4.0)
        assert fuge.product.value == pytest.approx(3.0)
        assert fuge.waste.value == pytest.approx(1.0)
        fuge.inlet.value = 0.0                  # starved
        fuge.tick(0.05)
        assert fuge.draw.value == 0.0


class TestSynthesisTrain:
    def test_reactants_become_product_in_the_big_tank(self) -> None:
        """Two reactant headers -> pumps -> (A through the preheater)
        -> reactor -> centrifuge -> product tank + waste drain, with
        steam from the boiler. The whole chain, conserving mass."""
        sim = Simulation(dt=0.05)
        source_a = sim.add(Source("sa"))
        source_b = sim.add(Source("sb"))
        bfw = sim.add(Source("bfw"))
        pump_a = sim.add(Pump("pa", rated_lps=2.0, mode="hand"))
        pump_b = sim.add(Pump("pb", rated_lps=1.0, mode="hand"))
        boiler = sim.add(SteamGen("sg", rated_kgps=0.5))
        hx = sim.add(HeatExchanger("hx"))
        reactor = sim.add(Reactor("rx", capacity_l=4000.0, rate_lps=6.0))
        fuge = sim.add(Centrifuge("cf", rate_lps=2.5))
        tank = sim.add(Tank("pt", capacity_l=56000.0, height_m=7.0, diameter_m=3.2))
        drain = sim.add(Drain("dw", rate_lps=1.0))
        wire_power(sim, pump_a, pump_b, boiler, reactor, fuge)

        sim.connect(source_a, "supply", pump_a, "inlet")
        sim.connect(pump_a, "draw", source_a, "draw")
        sim.connect(source_b, "supply", pump_b, "inlet")
        sim.connect(pump_b, "draw", source_b, "draw")
        sim.connect(bfw, "supply", boiler, "inlet")
        sim.connect(boiler, "draw", bfw, "draw")
        sim.connect(boiler, "steam", hx, "steam_in")
        sim.connect(pump_a, "outlet", hx, "cold_in")
        sim.connect(hx, "cold_out", reactor, "inlet_a")
        sim.connect(pump_b, "outlet", reactor, "inlet_b")
        sim.connect(hx, "duty", reactor, "heat_duty")
        sim.connect(reactor, "level", fuge, "inlet")
        sim.connect(fuge, "draw", reactor, "draw")
        sim.connect(reactor, "purity", fuge, "purity_in")
        sim.connect(fuge, "product", tank, "inlet")
        sim.connect(fuge, "waste", drain, "flow_in")

        boiler.is_on = True
        fuge.is_on = True
        sim.run(900.0)

        assert reactor.temp_c > 75.0
        assert reactor.purity_frac > 0.5
        assert tank.level_l > 500.0             # product is landing
        assert drain.total_l > 10.0             # waste is leaving
        # Conservation: everything pumped in is inventory somewhere.
        pumped = source_a.total_l + source_b.total_l
        held = reactor.volume_l + tank.level_l + drain.total_l
        assert pumped == pytest.approx(held, abs=10.0)


class TestVacuumLock:
    def _lock(self) -> tuple:
        from sim.process import VacuumLock
        sim = Simulation(dt=0.05)
        lock = sim.add(VacuumLock("vl"))
        wire_power(sim, lock)
        return sim, lock

    def test_idle_until_switched_on(self) -> None:
        sim, lock = self._lock()
        sim.run(10.0)
        assert lock.state == "idle"
        assert lock.press.value == pytest.approx(lock.PRESS_ATM_PA, rel=0.01)

    def test_full_cycle_progression_and_condensate(self) -> None:
        sim, lock = self._lock()
        lock.is_on = True
        seen = set()
        drained = 0.0
        for _ in range(int(120.0 / 0.05)):
            sim.run(0.05)
            seen.add(lock.state)
            drained += float(lock.drain_flow.value) * 0.05
        assert seen >= {"evacuate", "hold", "vent", "drain"}
        assert lock.cycles >= 2
        assert lock.vent_bursts_done >= lock.cycles * lock.VENT_BURSTS
        # Conservation: everything condensed has gone out the drain port.
        expected = lock.cycles * lock.CONDENSATE_PER_CYCLE_L
        assert drained == pytest.approx(expected, abs=lock.CONDENSATE_PER_CYCLE_L)
        # Pressure stays physical throughout.
        assert lock.PRESS_VAC_PA * 0.9 <= lock.press_pa <= lock.PRESS_ATM_PA + 1.0

    def test_power_loss_mid_cycle_equalizes(self) -> None:
        sim, lock = self._lock()
        lock.is_on = True
        sim.run(15.0)          # well into evacuation
        assert lock.press_pa < 50000.0
        sim.disconnect(sim.get_component("mains_1"), "power", lock, "power")
        sim.run(90.0)
        assert lock.state == "idle"
        assert lock.press_pa == pytest.approx(lock.PRESS_ATM_PA, rel=0.05)
