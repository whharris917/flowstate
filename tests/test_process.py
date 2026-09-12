"""Tests for the process units: boiler, exchanger, reactor, centrifuge.

These hold the line the whole synthesis train stands on: material is
conserved through every unit, heat cannot appear from nowhere or exceed
its source, and quality is derived from what is actually in the vessel
rather than asserted on a signal wire.

Since the kernel went over to pressure, a unit cannot be handed a flow
rate. Where these tests need one they set it at the nozzle exactly the
way the hydraulic pass does -- a signed ``flow_lps`` plus the material
standing at the node -- and where the flow itself is the thing under
test they build a network and let it be solved.
"""
from __future__ import annotations

import pytest

from conftest import feed, wire_power
from sim.components import Drain, Pump, Source, Tank
from sim.core import Simulation
from sim.process import Centrifuge, HeatExchanger, Reactor, SteamGen
from sim.stream import Stream

REAGENTS = {"reagent_a": 0.5, "reagent_b": 0.5}


class TestSteamGen:
    def _boiler(self, header_kpa: float = 400.0,
                vent_lps: float = 0.3) -> tuple[Simulation, SteamGen, Source, Drain]:
        """A boiler needs both ends piped: a feedwater header to pull
        from, and somewhere for the steam to go. Dead-end the steam and
        it makes none, which is a real answer, not a broken rig."""
        sim = Simulation(dt=0.05)
        boiler = sim.add(SteamGen("sg", rated_kgps=0.5))
        wire_power(sim, boiler)
        bfw = sim.add(Source("bfw", pressure_kpa=header_kpa))
        sim.connect(bfw, "outlet", boiler, "inlet")
        vent = sim.add(Drain("vent", rate_lps=vent_lps))
        sim.connect(boiler, "steam", vent, "inlet")
        return sim, boiler, bfw, vent

    def test_makes_steam_when_fired_fed_and_powered(self) -> None:
        sim, boiler, bfw, vent = self._boiler()
        boiler.is_on = True
        sim.run(180.0)
        assert boiler.feedwater_lps > 0.0
        assert boiler.steam_lps > 0.0
        assert boiler.press_pa > 0.5 * SteamGen.PRESS_FULL_PA
        assert boiler.starve_s == pytest.approx(0.0)
        assert bfw.total_l > 0.0

    def test_the_feed_pump_has_to_beat_drum_pressure(self) -> None:
        """A hot boiler is harder to feed than a cold one, because the
        feed pump is pushing into its own drum. This is the reason a
        real BFW pump is the tallest thing in the plant."""
        sim, boiler, bfw, vent = self._boiler()
        boiler.is_on = True
        sim.run(2.0)                       # still cold, drum near zero
        cold_feed = boiler.feedwater_lps
        sim.run(180.0)                     # up to pressure
        assert boiler.press_pa > 0.5 * SteamGen.PRESS_FULL_PA
        assert boiler.feedwater_lps < cold_feed

    def test_a_weak_feedwater_header_shows_up_as_low_pressure(self) -> None:
        """Nothing tells the boiler its header is weak. It finds out by
        not being able to feed itself, and the operator finds out from
        the pressure gauge."""
        strong = self._boiler(header_kpa=600.0)
        weak = self._boiler(header_kpa=20.0)
        for sim, boiler, _, _ in (strong, weak):
            boiler.is_on = True
            sim.run(180.0)
        assert strong[1].feedwater_lps > weak[1].feedwater_lps
        assert strong[1].press_pa > weak[1].press_pa
        assert strong[1].sat_temp_c > weak[1].sat_temp_c

    def test_steam_is_water_at_saturation_temperature(self) -> None:
        """Steam is material, not a number. Downstream learns how hot it
        is by being piped to it."""
        sim, boiler, bfw, vent = self._boiler()
        boiler.is_on = True
        sim.run(180.0)
        steam = boiler.steam.value
        assert steam.frac("water") == pytest.approx(1.0)
        assert steam.temp_c == pytest.approx(boiler.sat_temp_c)
        assert boiler.sat_temp_c > SteamGen.SAT_C_AT_ZERO

    def test_cold_dark_and_dry_cases(self) -> None:
        sim, boiler, bfw, vent = self._boiler()
        sim.run(5.0)
        assert boiler.steam_lps == pytest.approx(0.0)   # not fired
        boiler.is_on = True
        sim.disconnect(sim.get_component("mains_1"), "way1", boiler, "power")
        sim.run(5.0)
        assert boiler.steam_lps == pytest.approx(0.0)   # no power
        assert boiler.feedwater_lps == pytest.approx(0.0)

    def test_firing_dry_accrues_starve_time(self) -> None:
        sim = Simulation(dt=0.05)
        boiler = sim.add(SteamGen("sg"))
        wire_power(sim, boiler)
        boiler.is_on = True                     # no feedwater wired at all
        sim.run(10.0)
        assert boiler.steam_lps == pytest.approx(0.0)
        assert boiler.starve_s > 9.0


class TestHeatExchanger:
    """Duty and temperature are worked out in ``tick`` off what arrived
    at the nozzles, so these set the nozzles directly. What comes *out*
    of cold_out and condensate is published by the network, so those are
    read through ``supplied_stream`` -- the same value the network
    would put on the port."""

    def test_duty_heats_the_stream_it_is_given(self) -> None:
        hx = HeatExchanger("hx", max_duty_kw=1200.0)
        feed(hx.steam_in, Stream.pure("water", 0.4, 180.0))
        feed(hx.cold_in, Stream.pure("water", 3.0, 20.0))
        hx.tick(0.05)
        # 0.4 kg/s * 2000 kJ/kg = 800 kW into 3 kg/s of water
        assert hx.duty.value == pytest.approx(800.0)
        expected_rise = 800.0 / (3.0 * 4.18)
        assert hx.outlet_temp_c == pytest.approx(20.0 + expected_rise)
        assert hx.supplied_stream("cold_out").temp_c == pytest.approx(
            20.0 + expected_rise)

    def test_duty_is_capped_by_area(self) -> None:
        hx = HeatExchanger("hx", max_duty_kw=1200.0)
        feed(hx.steam_in, Stream.pure("water", 5.0, 180.0))
        feed(hx.cold_in, Stream.pure("water", 3.0, 20.0))
        hx.tick(0.05)
        assert hx.duty.value == pytest.approx(1200.0)

    def test_cannot_heat_past_the_steam_temperature(self) -> None:
        """A weak header shows up as a process that will not come up to
        heat, however long it runs."""
        hx = HeatExchanger("hx", max_duty_kw=100000.0)
        feed(hx.steam_in, Stream.pure("water", 50.0, 105.0))
        feed(hx.cold_in, Stream.pure("water", 1.0, 20.0))
        hx.tick(0.05)
        assert hx.outlet_temp_c == pytest.approx(105.0 - HeatExchanger.APPROACH_C)
        # Duty is recomputed from what the stream actually absorbed.
        assert hx.duty.value == pytest.approx(1.0 * 4.18 * 80.0)

    def test_composition_passes_through_untouched(self) -> None:
        hx = HeatExchanger("hx")
        cold = Stream(2.0, 20.0, {"solvent": 0.7, "reagent_a": 0.3})
        feed(hx.steam_in, Stream.pure("water", 0.2, 180.0))
        feed(hx.cold_in, cold)
        hx.tick(0.05)
        out = hx.supplied_stream("cold_out")
        assert out.frac("solvent") == pytest.approx(0.7)
        assert out.frac("reagent_a") == pytest.approx(0.3)
        assert out.temp_c > cold.temp_c

    def test_condensate_is_water_at_the_steam_temperature(self) -> None:
        hx = HeatExchanger("hx", max_duty_kw=1200.0)
        feed(hx.steam_in, Stream.pure("water", 0.4, 180.0))
        feed(hx.cold_in, Stream.pure("water", 3.0, 20.0))
        hx.tick(0.05)
        assert hx.supplied_stream("condensate").frac("water") == pytest.approx(1.0)
        assert hx.supplied_stream("condensate").temp_c == pytest.approx(180.0)

    def test_over_steaming_is_wasted_not_destroyed(self) -> None:
        """Far more steam than the duty cap can use. The surplus is not
        absorbed by the process, so it has to leave down the condensate
        line -- which the shell being one branch guarantees."""
        hx = HeatExchanger("hx", max_duty_kw=200.0)
        feed(hx.steam_in, Stream.pure("water", 5.0, 180.0))
        feed(hx.cold_in, Stream.pure("water", 3.0, 20.0))
        hx.tick(0.05)
        assert hx.duty_kw == pytest.approx(200.0)

    def test_everything_admitted_condenses(self) -> None:
        """Mass has to close across the shell, and now it closes by
        construction: the shell is a single branch, so whatever enters
        the steam nozzle leaves the condensate nozzle."""
        sim, hx, boiler, trap, tank = self._train()
        sim.run(120.0)
        steam_in = max(hx.steam_in.flow_lps, 0.0)
        condensate_out = max(-hx.condensate.flow_lps, 0.0)
        assert steam_in > 0.0
        assert condensate_out == pytest.approx(steam_in, rel=1e-6)

    def test_a_shell_with_nowhere_for_condensate_passes_no_steam(self) -> None:
        """The exchanger with no trap fitted. It is a dead end, so
        nothing flows through the shell and no heat is delivered --
        which the old model could not express at all, because duty was
        a number handed over rather than steam that had to go
        somewhere."""
        sim, hx, boiler, trap, tank = self._train()
        sim.run(60.0)
        assert hx.duty_kw > 0.0
        blind, blind_hx, _, blind_trap, _ = self._train(trap_fitted=False)
        blind.run(60.0)
        assert max(blind_hx.steam_in.flow_lps, 0.0) == pytest.approx(0.0, abs=1e-9)
        assert blind_hx.duty_kw == pytest.approx(0.0)

    def _train(self, trap_fitted: bool = True):
        """Boiler -> shell -> trap, and header -> pump -> tubes -> tank."""
        sim = Simulation(dt=0.05)
        bfw = sim.add(Source("bfw", pressure_kpa=400.0))
        boiler = sim.add(SteamGen("sg", rated_kgps=0.5))
        hx = sim.add(HeatExchanger("hx", max_duty_kw=1200.0))
        header = sim.add(Source("proc", pressure_kpa=300.0))
        pump = sim.add(Pump("p", rated_lps=3.0, mode="hand"))
        tank = sim.add(Tank("t", capacity_l=9000.0, height_m=4.0))
        trap = sim.add(Drain("trap", rate_lps=1.0))
        wire_power(sim, boiler, pump)
        sim.connect(bfw, "outlet", boiler, "inlet")
        sim.connect(boiler, "steam", hx, "steam_in")
        if trap_fitted:
            sim.connect(hx, "condensate", trap, "inlet")
        sim.connect(header, "outlet", pump, "inlet")
        sim.connect(pump, "outlet", hx, "cold_in")
        sim.connect(hx, "cold_out", tank, "inlet")
        boiler.is_on = True
        return sim, hx, boiler, trap, tank

    def test_the_process_stream_comes_out_hotter_than_it_went_in(self) -> None:
        sim, hx, boiler, trap, tank = self._train()
        sim.run(180.0)
        assert hx.cold_in.stream.temp_c < hx.outlet_temp_c
        assert tank.level_l > 0.0
        assert tank.temp_c > hx.cold_in.stream.temp_c


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
        instead of inventing an impossible temperature. The vapour goes
        out of the vent, not a nozzle, so it comes off the inventory."""
        reactor = Reactor("rx", capacity_l=4000.0, rate_lps=6.0)
        reactor.charge(2000.0, {"solvent": 1.0}, 60.0)
        for _ in range(4000):
            reactor.heat_duty.value = 4000.0
            reactor.power.value = 1.0
            reactor.tick(0.05)
        assert reactor.temp_c == pytest.approx(111.0, abs=1.0)  # solvent boils
        assert reactor.boiled_off_l > 0.0
        assert reactor.volume_l == pytest.approx(
            2000.0 - reactor.boiled_off_l, abs=0.5
        )

    def test_feed_blends_into_the_inventory(self) -> None:
        """Hot feed genuinely warms the batch; reagent feed genuinely
        changes what is in it."""
        reactor = Reactor("rx", capacity_l=4000.0)
        reactor.charge(1000.0, {"water": 1.0}, 20.0)
        for _ in range(200):                    # 10 s of hot solvent
            feed(reactor.inlet_a, Stream.pure("solvent", 10.0, 80.0))
            reactor.tick(0.05)
        assert reactor.volume_l == pytest.approx(1100.0, abs=0.5)
        assert reactor.contents.frac("solvent") == pytest.approx(100.0 / 1100.0,
                                                                 abs=0.01)
        assert 20.0 < reactor.temp_c < 80.0

    def test_inventory_conserved_with_feeds_and_a_discharge(self) -> None:
        """Both nozzles are signed into the vessel, so one balance
        covers filling and draining at once."""
        reactor = self._charged()
        for _ in range(200):
            feed(reactor.inlet_a, Stream.pure("water", 2.0))
            feed(reactor.inlet_b, Stream.pure("water", 1.0))
            reactor.outlet.flow_lps = -1.5      # leaving through the bottom
            reactor.tick(0.05)
        assert reactor.volume_l == pytest.approx(2000.0 + (3.0 - 1.5) * 10.0, abs=0.5)
        assert reactor.overflowed_l == 0.0

    def test_it_fills_and_empties_in_a_real_network(self) -> None:
        """Piped up rather than poked: a header fills it through the top
        and it drains out of the bottom under its own head."""
        sim = Simulation(dt=0.05)
        header = sim.add(Source("hdr", species="reagent_a", pressure_kpa=300.0))
        reactor = sim.add(Reactor("rx", capacity_l=4000.0, height_m=2.4))
        drain = sim.add(Drain("d", rate_lps=1.0))
        wire_power(sim, reactor)
        sim.connect(header, "outlet", reactor, "inlet_a")
        sim.connect(reactor, "outlet", drain, "inlet")
        sim.run(300.0)
        assert reactor.volume_l > 0.0
        assert drain.total_l > 0.0
        assert header.total_l == pytest.approx(
            reactor.volume_l + drain.total_l + reactor.boiled_off_l, abs=1.0)


class TestCentrifuge:
    def _slurry(self, lps: float = 4.0) -> Stream:
        return Stream(lps, 30.0, {"product": 0.4, "solvent": 0.6},
                      solids_frac=0.3)

    def test_needs_power_to_spin(self) -> None:
        sim = Simulation(dt=0.05)
        fuge = sim.add(Centrifuge("cf", rate_lps=4.0))
        vessel = sim.add(Tank("t", capacity_l=4000.0, level_l=3000.0,
                              height_m=3.0, comp={"product": 1.0}))
        sim.connect(vessel, "outlet", fuge, "inlet")
        fuge.is_on = True                       # switched on but unpowered
        sim.run(5.0)
        assert fuge.spinning is False
        assert fuge.draw_lps == pytest.approx(0.0)
        assert fuge.cake_lps == pytest.approx(0.0)

    def test_splits_crystals_from_mother_liquor(self) -> None:
        fuge = Centrifuge("cf", rate_lps=4.0, capture_eff=0.95, cake_wetness=0.25)
        feed(fuge.inlet, self._slurry())
        fuge.is_on = True
        fuge.power.value = 1.0
        fuge.tick(0.05)
        # Conservation: what came in leaves by one nozzle or the other.
        assert fuge.cake_lps + fuge.liquor_lps == pytest.approx(4.0)
        cake = fuge.supplied_stream("product")
        liquor = fuge.supplied_stream("waste")
        # The cake is mostly crystal; the liquor is nearly clear.
        assert cake.solids_frac > 0.7
        assert liquor.solids_frac < 0.05
        # Product ends up on the cake side, not down the drain.
        assert cake.frac("product") * fuge.cake_lps > (
            liquor.frac("product") * fuge.liquor_lps)

    def test_clear_feed_all_goes_to_liquor(self) -> None:
        """No crystals in, nothing on the cake nozzle. The machine does
        not invent a separation it was not given."""
        fuge = Centrifuge("cf", rate_lps=4.0)
        feed(fuge.inlet, Stream(4.0, 30.0, {"product": 0.4, "solvent": 0.6}))
        fuge.is_on = True
        fuge.power.value = 1.0
        fuge.tick(0.05)
        assert fuge.cake_lps == pytest.approx(0.0)
        assert fuge.liquor_lps == pytest.approx(4.0)

    def test_a_wash_displaces_mother_liquor_from_the_cake(self) -> None:
        """Clean solvent sprayed on the cake takes the place of the
        liquor it would have kept, so impurity leaves with the wash and
        the cake gets cleaner. In and out still add up."""
        fuge = Centrifuge("cf", rate_lps=4.0, capture_eff=0.95, cake_wetness=0.25)
        dirty_feed = Stream(4.0, 30.0, {"product": 0.2, "impurity": 0.2, "solvent": 0.6},
                            solids_frac=0.3)
        feed(fuge.inlet, dirty_feed)
        fuge.is_on = True
        fuge.power.value = 1.0
        fuge.tick(0.05)
        unwashed = fuge.supplied_stream("product").frac("impurity")
        assert unwashed > 0.0
        # Two cake-liquid volumes of wash: cake liquid is 0.95*1.2*0.25 L/s.
        feed(fuge.wash, Stream(0.57, 30.0, {"solvent": 1.0}))
        fuge.tick(0.05)
        washed = fuge.supplied_stream("product").frac("impurity")
        assert washed < 0.2 * unwashed
        assert fuge.wash_lps == pytest.approx(0.57)
        assert fuge.cake_lps + fuge.liquor_lps == pytest.approx(4.0 + 0.57)
        # The impurity did not vanish: it went out with the liquor.
        liquor = fuge.supplied_stream("waste")
        total_impurity = (fuge.supplied_stream("product").frac("impurity") * fuge.cake_lps
                          + liquor.frac("impurity") * fuge.liquor_lps)
        assert total_impurity == pytest.approx(4.0 * 0.2, rel=1e-6)

    def test_the_wash_is_interlocked_to_the_bowl(self) -> None:
        """The wash nozzle is a valve into the bowl that only opens
        while it spins: pressure behind it moves nothing otherwise."""
        sim = Simulation(dt=0.05)
        vessel = sim.add(Tank("t", capacity_l=4000.0, level_l=3000.0,
                              height_m=3.0, comp={"product": 1.0}))
        fuge = sim.add(Centrifuge("cf", rate_lps=4.0))
        solvent = sim.add(Source("wash", pressure_kpa=200.0, species="solvent"))
        cake = sim.add(Drain("dc", rate_lps=5.0))
        liquor = sim.add(Drain("dl", rate_lps=5.0))
        wire_power(sim, fuge)
        sim.connect(vessel, "outlet", fuge, "inlet")
        sim.connect(solvent, "outlet", fuge, "wash")
        sim.connect(fuge, "product", cake, "inlet")
        sim.connect(fuge, "waste", liquor, "inlet")
        sim.run(5.0)
        assert fuge.wash_lps == pytest.approx(0.0)
        fuge.is_on = True
        sim.run(5.0)
        assert fuge.wash_lps > 0.5
        assert solvent.total_l > 0.0

    def test_starved_bowl_moves_nothing(self) -> None:
        fuge = Centrifuge("cf", rate_lps=4.0)
        fuge.is_on = True
        fuge.power.value = 1.0
        feed(fuge.inlet, Stream.empty())
        fuge.tick(0.05)
        assert fuge.draw_lps == pytest.approx(0.0)
        assert fuge.cake_lps == pytest.approx(0.0)

    def test_its_feed_pump_falls_away_on_a_thin_suction(self) -> None:
        """Nothing throttles it but the vessel above it. As that vessel
        empties the head falls, and so does the rate."""
        sim = Simulation(dt=0.05)
        vessel = sim.add(Tank("t", capacity_l=1200.0, level_l=1100.0,
                              height_m=3.0, comp={"product": 1.0}))
        fuge = sim.add(Centrifuge("cf", rate_lps=4.0))
        cake = sim.add(Drain("dc", rate_lps=5.0))
        liquor = sim.add(Drain("dl", rate_lps=5.0))
        wire_power(sim, fuge)
        sim.connect(vessel, "outlet", fuge, "inlet")
        sim.connect(fuge, "product", cake, "inlet")
        sim.connect(fuge, "waste", liquor, "inlet")
        fuge.is_on = True
        sim.run(30.0)
        full = fuge.draw_lps
        assert full > 0.0
        sim.run(400.0)
        assert vessel.level_l < 100.0
        assert fuge.draw_lps < full
        # Nothing was lost on the way: the vessel emptied into the two
        # discharges and the meters agree.
        assert cake.total_l + liquor.total_l + vessel.level_l == pytest.approx(
            1100.0, rel=0.01)


class TestSynthesisTrain:
    def test_reactants_become_product_in_the_big_tank(self) -> None:
        """Two reagent headers -> pumps -> (A through the preheater)
        -> reactor -> centrifuge -> product tank + waste drain, with
        steam from the boiler. The whole chain, conserving mass.

        One player pipe is one kernel wire now: there are no draw wires
        to pair with the material ones, and no tee component either --
        the two reagent lines simply land on their own nozzles.
        """
        sim = Simulation(dt=0.05)
        source_a = sim.add(Source("sa", species="reagent_a", pressure_kpa=250.0))
        source_b = sim.add(Source("sb", species="reagent_b", pressure_kpa=250.0))
        bfw = sim.add(Source("bfw", species="water", pressure_kpa=400.0))
        pump_a = sim.add(Pump("pa", rated_lps=2.0, mode="hand"))
        pump_b = sim.add(Pump("pb", rated_lps=1.0, mode="hand"))
        boiler = sim.add(SteamGen("sg", rated_kgps=0.5))
        hx = sim.add(HeatExchanger("hx"))
        trap = sim.add(Drain("trap", rate_lps=1.0))
        reactor = sim.add(Reactor("rx", capacity_l=4000.0, rate_lps=6.0))
        fuge = sim.add(Centrifuge("cf", rate_lps=2.5))
        tank = sim.add(Tank("pt", capacity_l=56000.0, height_m=7.0, diameter_m=3.2))
        drain = sim.add(Drain("dw", rate_lps=1.0))
        wire_power(sim, pump_a, pump_b, boiler, reactor, fuge)

        sim.connect(source_a, "outlet", pump_a, "inlet")
        sim.connect(source_b, "outlet", pump_b, "inlet")
        sim.connect(bfw, "outlet", boiler, "inlet")
        sim.connect(boiler, "steam", hx, "steam_in")
        sim.connect(hx, "condensate", trap, "inlet")
        sim.connect(pump_a, "outlet", hx, "cold_in")
        sim.connect(hx, "cold_out", reactor, "inlet_a")
        sim.connect(pump_b, "outlet", reactor, "inlet_b")
        sim.connect(hx, "duty", reactor, "heat_duty")
        sim.connect(reactor, "outlet", fuge, "inlet")
        sim.connect(fuge, "product", tank, "inlet")
        sim.connect(fuge, "waste", drain, "inlet")

        boiler.is_on = True
        fuge.is_on = True
        sim.run(900.0)

        assert reactor.temp_c > 60.0
        assert reactor.purity_frac > 0.2            # product is forming
        assert drain.total_l > 10.0                 # liquor is leaving
        # Conservation on the process side. The boiler is deliberately
        # left out of it: its drum is a pressure boundary, so steam and
        # condensate do not have to balance its feedwater.
        pumped = source_a.total_l + source_b.total_l
        held = (
            reactor.volume_l + tank.level_l + drain.total_l + reactor.boiled_off_l
        )
        assert pumped == pytest.approx(held, abs=10.0)

    def test_quality_is_derived_not_asserted(self) -> None:
        """The separator is never told what its feed contains. Give a
        rich feed and a thin one to identical machines and they behave
        differently on their own."""
        rich = Centrifuge("rich", rate_lps=4.0)
        thin = Centrifuge("thin", rate_lps=4.0)
        for fuge, solids in ((rich, 0.5), (thin, 0.1)):
            fuge.is_on = True
            fuge.power.value = 1.0
            feed(fuge.inlet, Stream(
                4.0, 25.0, {"product": 0.6, "impurity": 0.4}, solids_frac=solids
            ))
            fuge.tick(0.05)
        assert rich.cake_lps > thin.cake_lps


class TestVacuumLock:
    def _lock(self) -> tuple:
        from sim.process import VacuumLock
        sim = Simulation(dt=0.05)
        lock = sim.add(VacuumLock("vl"))
        wire_power(sim, lock)
        drain = sim.add(Drain("sump", rate_lps=5.0))
        sim.connect(lock, "drain_flow", drain, "inlet")
        return sim, lock, drain

    def test_idle_until_switched_on(self) -> None:
        sim, lock, drain = self._lock()
        sim.run(10.0)
        assert lock.state == "idle"
        assert lock.press.value == pytest.approx(lock.PRESS_ATM_PA, rel=0.01)

    def test_full_cycle_progression_and_condensate(self) -> None:
        sim, lock, drain = self._lock()
        lock.is_on = True
        seen = set()
        for _ in range(int(120.0 / 0.05)):
            sim.run(0.05)
            seen.add(lock.state)
        assert seen >= {"evacuate", "hold", "vent", "drain"}
        assert lock.cycles >= 2
        assert lock.vent_bursts_done >= lock.cycles * lock.VENT_BURSTS
        # Conservation: everything condensed has gone out the drain line.
        expected = lock.cycles * lock.CONDENSATE_PER_CYCLE_L
        assert drain.total_l == pytest.approx(
            expected, abs=lock.CONDENSATE_PER_CYCLE_L)
        # Pressure stays physical throughout.
        assert lock.PRESS_VAC_PA * 0.9 <= lock.press_pa <= lock.PRESS_ATM_PA + 1.0

    def test_power_loss_mid_cycle_equalizes(self) -> None:
        sim, lock, drain = self._lock()
        lock.is_on = True
        sim.run(15.0)          # well into evacuation
        assert lock.press_pa < 50000.0
        sim.disconnect(sim.get_component("mains_1"), "way1", lock, "power")
        sim.run(90.0)
        assert lock.state == "idle"
        assert lock.press_pa == pytest.approx(lock.PRESS_ATM_PA, rel=0.05)


class TestVialFiller:
    def _filler(self, species: str = "product") -> tuple:
        from sim.process import VialFiller
        sim = Simulation(dt=0.05)
        filler = sim.add(VialFiller("vf"))
        wire_power(sim, filler)
        source = sim.add(Source("product", species=species, pressure_kpa=300.0))
        sim.connect(source, "outlet", filler, "inlet")
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

    def test_the_fill_line_pulses_rather_than_running_continuously(self) -> None:
        """The rhythm of the machine is real: it draws only while the
        fill station is filling, and nothing at all while it indexes
        and caps."""
        sim, filler, source = self._filler()
        filler.is_on = True
        seen_flowing = False
        seen_stopped = False
        for _ in range(int(20.0 / 0.05)):
            sim.run(0.05)
            if filler.inlet.flow_lps > 1e-9:
                seen_flowing = True
            elif filler.state in ("index", "cap"):
                seen_stopped = True
        assert seen_flowing and seen_stopped

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
        """All but the very first slug: composition moves one node per
        scan, so on the scan the fill valve first cracks, the line still
        holds what it held before anything ran through it. The record
        counts that honestly rather than back-dating it."""
        sim, filler, source = self._filler(species="product")
        filler.is_on = True
        sim.run(60.0)
        assert filler.fill_purity == pytest.approx(1.0)
        assert filler.product_filled_l == pytest.approx(filler.filled_l, rel=0.01)
        assert filler.product_filled_l < filler.filled_l

    def test_stops_dead_unfed_or_unpowered(self) -> None:
        sim, filler, source = self._filler()
        filler.is_on = True
        sim.run(10.0)
        assert filler.vials_done > 0
        done = filler.vials_done
        sim.disconnect(sim.get_component("mains_1"), "way1", filler, "power")
        sim.run(10.0)
        assert filler.vials_done == done
        assert filler.state == "idle"
        assert filler.inlet.flow_lps == pytest.approx(0.0)
