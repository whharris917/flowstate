"""Tests for the process units: boiler, exchanger, reactor, centrifuge.

These hold the line the whole synthesis train stands on: material is
conserved through every unit, heat cannot appear from nowhere or exceed
its source, and quality is derived from what is actually in the vessel
rather than asserted on a signal wire.
"""
from __future__ import annotations

import pytest

from conftest import wire_power
from sim.components import Drain, Pump, Source, Tank
from sim.core import Simulation
from sim.process import Centrifuge, HeatExchanger, Reactor, SteamGen
from sim.stream import Stream

REAGENTS = {"reagent_a": 0.5, "reagent_b": 0.5}


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
        assert boiler.steam.value.flow_lps == pytest.approx(0.5)
        assert boiler.press_pa == pytest.approx(SteamGen.PRESS_FULL_PA, rel=0.02)

    def test_steam_is_water_at_saturation_temperature(self) -> None:
        """Steam is material, not a number. Downstream learns how hot
        it is by being piped to it."""
        sim, boiler = self._boiler()
        boiler.is_on = True
        sim.run(60.0)
        steam = boiler.steam.value
        assert steam.frac("water") == pytest.approx(1.0)
        assert steam.temp_c == pytest.approx(SteamGen.SAT_C_AT_FULL, rel=0.03)

    def test_cold_dark_and_dry_cases(self) -> None:
        sim, boiler = self._boiler()
        sim.run(5.0)
        assert boiler.steam.value.flow_lps == 0.0   # not fired
        boiler.is_on = True
        sim.disconnect(sim.get_component("mains_1"), "power", boiler, "power")
        sim.run(5.0)
        assert boiler.steam.value.flow_lps == 0.0   # no power

    def test_firing_dry_accrues_starve_time(self) -> None:
        sim = Simulation(dt=0.05)
        boiler = sim.add(SteamGen("sg"))
        wire_power(sim, boiler)
        boiler.is_on = True                     # no feedwater wired at all
        sim.run(10.0)
        assert boiler.steam.value.flow_lps == 0.0
        assert boiler.starve_s > 9.0


class TestHeatExchanger:
    def test_duty_heats_the_stream_it_is_given(self) -> None:
        hx = HeatExchanger("hx", max_duty_kw=1200.0)
        hx.steam_in.value = Stream.pure("water", 0.4, 180.0)
        hx.cold_in.value = Stream.pure("water", 3.0, 20.0)
        hx.tick(0.05)
        # 0.4 kg/s * 2000 kJ/kg = 800 kW into 3 kg/s of water
        assert hx.duty.value == pytest.approx(800.0)
        expected_rise = 800.0 / (3.0 * 4.18)
        assert hx.cold_out.value.temp_c == pytest.approx(20.0 + expected_rise)
        assert hx.cold_out.value.flow_lps == pytest.approx(3.0)

    def test_duty_is_capped_by_area(self) -> None:
        hx = HeatExchanger("hx", max_duty_kw=1200.0)
        hx.steam_in.value = Stream.pure("water", 5.0, 180.0)
        hx.cold_in.value = Stream.pure("water", 3.0, 20.0)
        hx.tick(0.05)
        assert hx.duty.value == pytest.approx(1200.0)

    def test_cannot_heat_past_the_steam_temperature(self) -> None:
        """A weak header shows up as a process that will not come up to
        heat, however long it runs."""
        hx = HeatExchanger("hx", max_duty_kw=100000.0)
        hx.steam_in.value = Stream.pure("water", 50.0, 105.0)
        hx.cold_in.value = Stream.pure("water", 1.0, 20.0)
        hx.tick(0.05)
        assert hx.cold_out.value.temp_c == pytest.approx(
            105.0 - HeatExchanger.APPROACH_C
        )
        # Duty is recomputed from what the stream actually absorbed.
        assert hx.duty.value == pytest.approx(1.0 * 4.18 * 80.0)

    def test_composition_passes_through_untouched(self) -> None:
        hx = HeatExchanger("hx")
        feed = Stream(2.0, 20.0, {"solvent": 0.7, "reagent_a": 0.3})
        hx.steam_in.value = Stream.pure("water", 0.2, 180.0)
        hx.cold_in.value = feed
        hx.tick(0.05)
        out = hx.cold_out.value
        assert out.frac("solvent") == pytest.approx(0.7)
        assert out.frac("reagent_a") == pytest.approx(0.3)
        assert out.flow_lps == pytest.approx(2.0)
        assert out.temp_c > feed.temp_c

    def test_everything_admitted_condenses(self) -> None:
        """Mass has to close across the shell. Steam the process could
        not absorb leaves hot down the condensate line rather than
        disappearing from the plant."""
        hx = HeatExchanger("hx", max_duty_kw=1200.0)
        hx.steam_in.value = Stream.pure("water", 0.4, 180.0)
        hx.cold_in.value = Stream.pure("water", 3.0, 20.0)
        hx.tick(0.05)
        assert hx.condensate.value.flow_lps == pytest.approx(0.4)
        assert hx.condensate.value.frac("water") == pytest.approx(1.0)

    def test_over_steaming_is_wasted_not_destroyed(self) -> None:
        """Far more steam than the duty cap can use: the surplus still
        has to come out of the condensate nozzle."""
        hx = HeatExchanger("hx", max_duty_kw=200.0)
        hx.steam_in.value = Stream.pure("water", 5.0, 180.0)
        hx.cold_in.value = Stream.pure("water", 3.0, 20.0)
        hx.tick(0.05)
        assert hx.duty_kw == pytest.approx(200.0)
        assert hx.condensate.value.flow_lps == pytest.approx(5.0)


class TestReactor:
    def _charged(self, temp_c: float = 20.0) -> Reactor:
        reactor = Reactor("rx", capacity_l=4000.0, rate_lps=6.0)
        reactor.charge(2000.0, REAGENTS, temp_c)
        return reactor

    def test_cold_or_unstirred_barely_reacts(self) -> None:
        cold = self._charged()
        cold.power.value = 1.0                  # stirred but cold
        for _ in range(1200):
            cold.tick(0.05)
        assert cold.purity_frac < 0.01
        hot_still = self._charged(temp_c=95.0)
        for _ in range(200):                    # hot but unstirred
            hot_still.tick(0.05)
        assert hot_still.purity_frac < 0.05

    def test_hot_and_stirred_converts(self) -> None:
        reactor = self._charged(temp_c=60.0)
        for _ in range(12000):                  # 600 s at a working duty
            reactor.heat_duty.value = 300.0
            reactor.power.value = 1.0
            reactor.tick(0.05)
        assert 70.0 < reactor.temp_c < 95.0     # in the operating window
        assert reactor.purity_frac > 0.85
        assert reactor.purity.value == pytest.approx(reactor.purity_frac)
        assert reactor.temp.value == pytest.approx(reactor.temp_c)

    def test_reaction_conserves_volume(self) -> None:
        """A + B -> 2 products. Nothing appears and nothing is lost."""
        reactor = self._charged(temp_c=90.0)
        reactor.power.value = 1.0
        for _ in range(2000):
            reactor.tick(0.05)
        assert reactor.volume_l == pytest.approx(2000.0, abs=0.5)
        assert reactor.boiled_off_l == 0.0
        assert sum(reactor.contents.comp.values()) == pytest.approx(1.0)

    def test_running_hot_costs_selectivity(self) -> None:
        """The trade the whole loop exists to manage: temperature buys
        conversion rate and spends selectivity. The hot batch finishes
        its reagents sooner and carries more impurity for it."""
        cool = self._charged(temp_c=60.0)
        hot = self._charged(temp_c=60.0)
        for _ in range(12000):
            cool.heat_duty.value = 300.0
            cool.power.value = 1.0
            cool.tick(0.05)
            hot.heat_duty.value = 700.0
            hot.power.value = 1.0
            hot.tick(0.05)
        assert hot.temp_c > cool.temp_c + 20.0
        # Bought: conversion. The hot batch has less reagent left.
        hot_left = hot.contents.frac("reagent_a") + hot.contents.frac("reagent_b")
        cool_left = cool.contents.frac("reagent_a") + cool.contents.frac("reagent_b")
        assert hot_left < cool_left
        # Spent: selectivity. Impurity per unit of product is worse.
        assert hot.impurity_frac > cool.impurity_frac * 2.0
        assert (hot.impurity_frac / hot.purity_frac) > (
            cool.impurity_frac / cool.purity_frac
        )

    def test_impurity_yield_rises_with_temperature(self) -> None:
        reactor = self._charged()
        reactor.temp_c = Reactor.IMPURITY_REF_C
        assert reactor.impurity_yield() == pytest.approx(Reactor.IMPURITY_BASE)
        reactor.temp_c = Reactor.IMPURITY_REF_C + 30.0
        assert reactor.impurity_yield() == pytest.approx(
            Reactor.IMPURITY_BASE + 30.0 * Reactor.IMPURITY_SLOPE_PER_K
        )

    def test_cannot_be_driven_past_its_bubble_point(self) -> None:
        """Surplus duty boils the most volatile thing in the vessel
        instead of inventing an impossible temperature."""
        reactor = Reactor("rx", capacity_l=4000.0, rate_lps=6.0)
        reactor.charge(2000.0, {"solvent": 1.0}, 60.0)
        for _ in range(4000):
            reactor.heat_duty.value = 4000.0
            reactor.power.value = 1.0
            reactor.tick(0.05)
        assert reactor.temp_c == pytest.approx(111.0, abs=1.0)  # solvent boils
        assert reactor.boiled_off_l > 0.0
        assert reactor.vapor.value.frac("solvent") == pytest.approx(1.0)
        # What left the vessel left through the vapor nozzle.
        assert reactor.volume_l == pytest.approx(
            2000.0 - reactor.boiled_off_l, abs=0.5
        )

    def test_feed_blends_into_the_inventory(self) -> None:
        """Hot feed genuinely warms the batch; reagent feed genuinely
        changes what is in it."""
        reactor = Reactor("rx", capacity_l=4000.0)
        reactor.charge(1000.0, {"water": 1.0}, 20.0)
        for _ in range(200):                    # 10 s of hot solvent
            reactor.inlet_a.value = Stream.pure("solvent", 10.0, 80.0)
            reactor.tick(0.05)
        assert reactor.volume_l == pytest.approx(1100.0, abs=0.5)
        assert reactor.contents.frac("solvent") == pytest.approx(100.0 / 1100.0,
                                                                 abs=0.01)
        assert 20.0 < reactor.temp_c < 80.0

    def test_inventory_conserved_with_feeds_and_draw(self) -> None:
        reactor = self._charged()
        for _ in range(200):
            reactor.inlet_a.value = Stream.pure("water", 2.0)
            reactor.inlet_b.value = Stream.pure("water", 1.0)
            reactor.draw.value = 1.5
            reactor.tick(0.05)
        assert reactor.volume_l == pytest.approx(2000.0 + (3.0 - 1.5) * 10.0, abs=0.5)
        assert reactor.overflowed_l == 0.0


class TestCentrifuge:
    def _slurry(self) -> Stream:
        return Stream(10.0, 30.0, {"product": 0.4, "solvent": 0.6}, solids_frac=0.3)

    def test_needs_power_to_spin(self) -> None:
        fuge = Centrifuge("cf", rate_lps=4.0)
        fuge.inlet.value = self._slurry()
        fuge.is_on = True
        fuge.tick(0.05)
        assert fuge.product.value.flow_lps == 0.0   # unpowered bowl
        assert fuge.draw.value == 0.0

    def test_splits_crystals_from_mother_liquor(self) -> None:
        fuge = Centrifuge("cf", rate_lps=4.0, capture_eff=0.95, cake_wetness=0.25)
        fuge.inlet.value = self._slurry()
        fuge.is_on = True
        fuge.power.value = 1.0
        fuge.tick(0.05)
        assert fuge.draw.value == pytest.approx(4.0)
        # Conservation: what came in leaves by one nozzle or the other.
        total_out = fuge.product.value.flow_lps + fuge.waste.value.flow_lps
        assert total_out == pytest.approx(4.0)
        # The cake is mostly crystal; the liquor is nearly clear.
        assert fuge.product.value.solids_frac > 0.7
        assert fuge.waste.value.solids_frac < 0.05
        # Product ends up on the cake side, not down the drain.
        assert fuge.product.value.species_lps("product") > (
            fuge.waste.value.species_lps("product")
        )

    def test_clear_feed_all_goes_to_liquor(self) -> None:
        """No crystals in, nothing on the cake nozzle. The machine does
        not invent a separation it was not given."""
        fuge = Centrifuge("cf", rate_lps=4.0)
        fuge.inlet.value = Stream(10.0, 30.0, {"product": 0.4, "solvent": 0.6})
        fuge.is_on = True
        fuge.power.value = 1.0
        fuge.tick(0.05)
        assert fuge.product.value.flow_lps == pytest.approx(0.0)
        assert fuge.waste.value.flow_lps == pytest.approx(4.0)

    def test_starved_bowl_moves_nothing(self) -> None:
        fuge = Centrifuge("cf", rate_lps=4.0)
        fuge.is_on = True
        fuge.power.value = 1.0
        fuge.inlet.value = Stream.empty()
        fuge.tick(0.05)
        assert fuge.draw.value == 0.0
        assert fuge.product.value.flow_lps == 0.0


class TestSynthesisTrain:
    def test_reactants_become_product_in_the_big_tank(self) -> None:
        """Two reagent headers -> pumps -> (A through the preheater)
        -> reactor -> centrifuge -> product tank + waste drain, with
        steam from the boiler. The whole chain, conserving mass."""
        sim = Simulation(dt=0.05)
        source_a = sim.add(Source("sa", species="reagent_a"))
        source_b = sim.add(Source("sb", species="reagent_b"))
        bfw = sim.add(Source("bfw", species="water"))
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
        sim.connect(reactor, "outlet", fuge, "inlet")
        sim.connect(fuge, "draw", reactor, "draw")
        sim.connect(fuge, "product", tank, "inlet")
        sim.connect(fuge, "waste", drain, "flow_in")

        boiler.is_on = True
        fuge.is_on = True
        sim.run(900.0)

        assert reactor.temp_c > 60.0
        assert reactor.purity_frac > 0.2            # product is forming
        assert drain.total_l > 10.0                 # liquor is leaving
        # Conservation: everything pumped in is inventory somewhere.
        pumped = source_a.total_l + source_b.total_l
        held = (
            reactor.volume_l + tank.level_l + drain.total_l + reactor.boiled_off_l
        )
        assert pumped == pytest.approx(held, abs=10.0)

    def test_quality_is_derived_not_asserted(self) -> None:
        """The separator is never told what its feed contains. Wire a
        clean feed and a dirty one to identical machines and they
        behave differently on their own."""
        clean = Centrifuge("clean", rate_lps=4.0)
        dirty = Centrifuge("dirty", rate_lps=4.0)
        for fuge, solids in ((clean, 0.5), (dirty, 0.1)):
            fuge.is_on = True
            fuge.power.value = 1.0
            fuge.inlet.value = Stream(
                8.0, 25.0, {"product": 0.6, "impurity": 0.4}, solids_frac=solids
            )
            fuge.tick(0.05)
        assert clean.product.value.flow_lps > dirty.product.value.flow_lps


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
            drained += lock.drain_flow.value.flow_lps * 0.05
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


class TestVialFiller:
    def _filler(self, species: str = "product") -> tuple:
        from sim.process import VialFiller
        sim = Simulation(dt=0.05)
        filler = sim.add(VialFiller("vf"))
        wire_power(sim, filler)
        source = sim.add(Source("product", species=species))
        sim.connect(source, "supply", filler, "inlet")
        sim.connect(filler, "draw", source, "draw")
        return sim, filler, source

    def test_cycles_and_meters_every_millilitre(self) -> None:
        sim, filler, source = self._filler()
        filler.is_on = True
        sim.run(120.0)
        cycle = filler.INDEX_S + filler.FILL_S + filler.CAP_S
        assert filler.vials_done == pytest.approx(120.0 / cycle, abs=2)
        # Conservation: the header metered out what the vials hold.
        expected_l = filler.vials_done * filler.VIAL_ML / 1000.0
        assert source.total_l == pytest.approx(expected_l, abs=0.03)

    def test_records_what_actually_went_into_the_vials(self) -> None:
        """Fill from a solvent header and the machine happily fills
        vials with solvent — and the record proves it afterwards."""
        sim, filler, source = self._filler(species="solvent")
        filler.is_on = True
        sim.run(60.0)
        assert filler.vials_done > 0
        assert filler.fill_purity == pytest.approx(0.0)
        assert filler.product_filled_l == pytest.approx(0.0)
        assert filler.filled_l > 0.0

    def test_good_feed_is_recorded_as_product(self) -> None:
        sim, filler, source = self._filler(species="product")
        filler.is_on = True
        sim.run(60.0)
        assert filler.fill_purity == pytest.approx(1.0)
        assert filler.product_filled_l == pytest.approx(filler.filled_l)

    def test_stops_dead_unfed_or_unpowered(self) -> None:
        sim, filler, source = self._filler()
        filler.is_on = True
        sim.run(10.0)
        assert filler.vials_done > 0
        done = filler.vials_done
        sim.disconnect(sim.get_component("mains_1"), "power", filler, "power")
        sim.run(10.0)
        assert filler.vials_done == done
        assert filler.state == "idle"
        assert filler.draw.value == 0.0
