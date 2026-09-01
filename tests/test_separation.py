"""Tests for the separation train: crystallizer, dryer, still.

The point of these units is that they compose. Each one is checked on
its own equations, and then the whole downstream sequence is run end to
end to prove the material balance closes across all of them.

Since the kernel went over to pressure, none of these machines can be
handed a throughput. Each has its own feed pump, so what it processes is
that pump's curve against the vessel above it -- which is why the tests
that care about a rate build a network, and the tests that care about
the equations stand material at the nozzle with ``feed()`` and read the
discharge back through ``supplied_stream``.
"""
from __future__ import annotations

import pytest

from conftest import Duty, feed, wire_power
from sim.components import Drain, Tank
from sim.core import Simulation
from sim.process import Centrifuge
from sim.separation import Crystallizer, Dryer, Still
from sim.stream import Stream


class TestCrystallizer:
    def _charged(self, temp_c: float = 80.0, product: float = 0.35) -> Crystallizer:
        cx = Crystallizer("cx", capacity_l=3000.0)
        cx.charge(
            2000.0,
            {"product": product, "solvent": 1.0 - product - 0.05, "impurity": 0.05},
            temp_c,
        )
        return cx

    def test_hot_solution_holds_everything_dissolved(self) -> None:
        """At 80 C the product is well inside its solubility, so there
        is nothing to crystallize."""
        cx = self._charged(temp_c=80.0, product=0.35)
        cx.power.value = 1.0
        for _ in range(2000):
            cx.tick(0.05)
        assert cx.supersaturation < 0.0
        assert cx.solids_frac == pytest.approx(0.0)

    def test_cooling_drops_crystals(self) -> None:
        cx = self._charged(temp_c=80.0, product=0.35)
        cx.power.value = 1.0
        for _ in range(20000):              # 1000 s of cooling
            cx.cool_duty.value = 200.0
            cx.tick(0.05)
        assert cx.temp_c < 40.0
        assert cx.solids_frac > 0.2
        # Crystals are product, and there can never be more solid than
        # there is product to be solid.
        assert cx.solids_frac <= cx.contents.frac("product") + 1e-9

    def test_crystals_redissolve_when_reheated(self) -> None:
        """The same equation runs both ways -- warm it back up and the
        solids go back into solution."""
        cx = self._charged(temp_c=80.0, product=0.35)
        cx.power.value = 1.0
        for _ in range(20000):
            cx.cool_duty.value = 200.0
            cx.tick(0.05)
        cold_solids = cx.solids_frac
        assert cold_solids > 0.2
        for _ in range(20000):
            cx.cool_duty.value = -250.0     # heating instead
            cx.tick(0.05)
        assert cx.temp_c > 60.0
        assert cx.solids_frac < cold_solids / 2.0

    def test_unagitated_crystallizes_slowly(self) -> None:
        stirred = self._charged(temp_c=30.0, product=0.35)
        still = self._charged(temp_c=30.0, product=0.35)
        stirred.power.value = 1.0
        for _ in range(1200):               # 60 s, one time constant
            stirred.tick(0.05)
            still.tick(0.05)
        assert stirred.solids_frac > still.solids_frac * 3.0

    def test_volume_conserved_through_crystallization(self) -> None:
        """Crystallizing moves product between phases. It does not
        change how much is in the vessel."""
        cx = self._charged(temp_c=30.0, product=0.35)
        cx.power.value = 1.0
        for _ in range(4000):
            cx.tick(0.05)
        assert cx.volume_l == pytest.approx(2000.0, abs=0.5)
        assert cx.contents.frac("product") == pytest.approx(0.35, abs=0.01)

    def test_it_fills_and_discharges_like_a_vessel(self) -> None:
        """Piped up rather than poked: the feed nozzle is at the roof
        and the outlet at the floor, so it fills from a header and the
        slurry leaves under its own head."""
        sim = Simulation(dt=0.05)
        from sim.components import Source
        header = sim.add(Source("hdr", species="solvent", pressure_kpa=300.0))
        cx = sim.add(Crystallizer("cx", capacity_l=3000.0, height_m=2.4))
        drain = sim.add(Drain("d", rate_lps=1.0))
        wire_power(sim, cx)
        sim.connect(header, "outlet", cx, "inlet")
        sim.connect(cx, "outlet", drain, "inlet")
        sim.run(300.0)
        assert cx.volume_l > 0.0
        assert drain.total_l > 0.0
        assert header.total_l == pytest.approx(
            cx.volume_l + drain.total_l, abs=1.0)


class TestDryer:
    """The dryer works out what evaporates from what actually arrived at
    its nozzle, so these stand material at the nozzle. What leaves is
    published by the network, so the cake is read back through
    ``supplied_stream`` -- the same value the port would carry."""

    def _wet_cake(self, flow: float = 2.0) -> Stream:
        # 60 % crystal, the rest mother liquor.
        return Stream(
            flow, 40.0,
            {"product": 0.7, "solvent": 0.25, "impurity": 0.05},
            solids_frac=0.6,
        )

    def test_needs_power_and_being_switched_on(self) -> None:
        """Switched on but unpowered, its feed pump does not turn, so
        nothing is drawn and nothing comes out."""
        sim = Simulation(dt=0.05)
        hopper = sim.add(Tank("ct", capacity_l=3000.0, level_l=2000.0,
                              height_m=3.0, comp={"product": 1.0}))
        dryer = sim.add(Dryer("dr", rate_lps=2.0))
        sim.connect(hopper, "outlet", dryer, "inlet")
        sim.connect(sim.add(Duty("q", 500.0)), "out", dryer, "heat_duty")
        dryer.is_on = True
        sim.run(5.0)
        assert dryer.running is False
        assert dryer.draw_lps == pytest.approx(0.0)
        assert dryer.product_lps == pytest.approx(0.0)

    def test_evaporates_the_solvent_first(self) -> None:
        dryer = Dryer("dr", rate_lps=2.0)
        dryer.is_on = True
        dryer.power.value = 1.0
        feed(dryer.inlet, self._wet_cake(flow=2.0))
        dryer.heat_duty.value = 180.0       # 0.2 L/s of evaporation
        dryer.tick(0.05)
        assert dryer.evap_lps == pytest.approx(0.2)
        # Conservation: what did not evaporate leaves as cake.
        assert dryer.product_lps + dryer.evap_lps == pytest.approx(2.0)
        # The solvent went and the product stayed. The cake stream is
        # published at the rate it actually leaves, so its species rates
        # are directly comparable with the feed.
        cake = dryer.supplied_stream("product")
        assert cake.flow_lps == pytest.approx(dryer.product_lps)
        assert cake.species_lps("solvent") == pytest.approx(
            2.0 * 0.25 - 0.2, abs=1e-6)
        assert cake.species_lps("product") == pytest.approx(2.0 * 0.7, abs=1e-6)

    def test_drying_concentrates_the_cake(self) -> None:
        dryer = Dryer("dr", rate_lps=2.0)
        dryer.is_on = True
        dryer.power.value = 1.0
        wet = self._wet_cake(flow=2.0)
        feed(dryer.inlet, wet)
        dryer.heat_duty.value = 450.0
        dryer.tick(0.05)
        cake = dryer.supplied_stream("product")
        assert cake.solids_frac > wet.solids_frac
        assert cake.frac("product") > wet.frac("product")

    def test_cannot_evaporate_more_liquid_than_it_has(self) -> None:
        """A huge duty on a nearly dry cake evaporates the liquid and
        stops, rather than eating the crystals."""
        dryer = Dryer("dr", rate_lps=2.0)
        dryer.is_on = True
        dryer.power.value = 1.0
        feed(dryer.inlet, Stream(
            2.0, 40.0, {"product": 0.95, "solvent": 0.05}, solids_frac=0.9
        ))
        dryer.heat_duty.value = 100000.0
        dryer.tick(0.05)
        # Only the 10 % that was liquid can go.
        assert dryer.evap_lps == pytest.approx(0.2, abs=0.01)
        assert dryer.product_lps == pytest.approx(1.8, abs=0.01)
        assert dryer.supplied_stream("product").solids_frac == pytest.approx(
            1.0, abs=0.01)

    def test_impurity_stays_behind_in_the_cake(self) -> None:
        """The uncomfortable truth about drying: what was dissolved in
        the retained liquor is still there when the solvent leaves. A
        dryer concentrates impurity exactly as well as product."""
        dryer = Dryer("dr", rate_lps=2.0)
        dryer.is_on = True
        dryer.power.value = 1.0
        wet = self._wet_cake(flow=2.0)
        feed(dryer.inlet, wet)
        dryer.heat_duty.value = 450.0
        dryer.tick(0.05)
        cake = dryer.supplied_stream("product")
        assert cake.frac("impurity") > wet.frac("impurity")
        # Not a drop of it left: the impurity is all still there, just
        # in less liquid.
        assert cake.species_lps("impurity") == pytest.approx(
            wet.species_lps("impurity"), abs=1e-6)

    def test_it_dries_what_a_hopper_can_give_it(self) -> None:
        sim = Simulation(dt=0.05)
        hopper = sim.add(Tank("ct", capacity_l=3000.0, level_l=2000.0,
                              height_m=3.0, comp={"product": 0.7, "solvent": 0.3}))
        dryer = sim.add(Dryer("dr", rate_lps=2.0))
        dry_tank = sim.add(Tank("dt", capacity_l=3000.0, height_m=3.0))
        wire_power(sim, dryer)
        sim.connect(hopper, "outlet", dryer, "inlet")
        sim.connect(dryer, "product", dry_tank, "inlet")
        sim.connect(sim.add(Duty("q", 400.0)), "out", dryer, "heat_duty")
        dryer.is_on = True
        sim.run(300.0)
        assert dryer.dried_l > 0.0
        assert dry_tank.level_l > 0.0
        # Everything that left the hopper is either in the dry tank or
        # went up the vent, and the vent total is on a counter.
        left = 2000.0 - hopper.level_l
        assert left == pytest.approx(dry_tank.level_l + dryer.dried_l, abs=1.0)


class TestStill:
    def _liquor(self, flow: float = 3.0) -> Stream:
        return Stream(flow, 60.0, {"solvent": 0.8, "product": 0.1, "impurity": 0.1})

    def _running(self, **kwargs) -> Still:
        """A still on its own bench. ``running`` is normally decided in
        the hydraulic pass, so a bare-tick test has to set it."""
        still = Still("st", **kwargs)
        still.is_on = True
        still.power.value = 1.0
        still.running = True
        return still

    def test_no_duty_means_no_separation(self) -> None:
        still = self._running(rate_lps=3.0)
        feed(still.inlet, self._liquor())
        still.heat_duty.value = 0.0
        still.tick(0.05)
        assert still.distillate_lps == pytest.approx(0.0)
        assert still.bottoms_lps == pytest.approx(3.0)

    def test_light_ends_go_overhead(self) -> None:
        still = self._running(rate_lps=3.0, cut_c=150.0, sharpness=0.95)
        feed(still.inlet, self._liquor(flow=3.0))
        still.heat_duty.value = 5000.0      # plenty of boilup
        still.tick(0.05)
        top = still.supplied_stream("distillate")
        bottom = still.supplied_stream("bottoms")
        # Solvent boils at 111, below the cut, so 95 % of it goes over.
        assert top.species_lps("solvent") == pytest.approx(3.0 * 0.8 * 0.95)
        # Product boils at 320, well above: it stays down.
        assert bottom.species_lps("product") > top.species_lps("product") * 10.0
        assert top.frac("solvent") > 0.9

    def test_material_balance_closes(self) -> None:
        still = self._running(rate_lps=3.0)
        liquor = self._liquor(flow=3.0)
        feed(still.inlet, liquor)
        still.heat_duty.value = 5000.0
        still.tick(0.05)
        top = still.supplied_stream("distillate")
        bottom = still.supplied_stream("bottoms")
        assert still.distillate_lps + still.bottoms_lps == pytest.approx(3.0)
        for key in ("solvent", "product", "impurity"):
            assert top.species_lps(key) + bottom.species_lps(key) == pytest.approx(
                liquor.species_lps(key))

    def test_reboiler_duty_throttles_the_overhead(self) -> None:
        still = self._running(rate_lps=3.0)
        feed(still.inlet, self._liquor(flow=3.0))
        still.heat_duty.value = 900.0       # exactly 1.0 L/s of boilup
        still.tick(0.05)
        assert still.boilup_lps == pytest.approx(1.0)
        assert still.distillate_lps == pytest.approx(1.0)

    def test_crystals_never_distill(self) -> None:
        still = self._running(rate_lps=3.0)
        feed(still.inlet, Stream(
            3.0, 60.0, {"solvent": 0.5, "product": 0.5}, solids_frac=0.4
        ))
        still.heat_duty.value = 5000.0
        still.tick(0.05)
        solids_in = 3.0 * 0.4
        bottom = still.supplied_stream("bottoms")
        assert bottom.solids_frac * still.bottoms_lps == pytest.approx(
            solids_in, abs=1e-6)

    def test_an_unpowered_still_boils_nothing(self) -> None:
        """Switched on, fed, and dark. Its feed pump does not turn, so
        it never gets a drop to work on."""
        from sim.components import Source
        sim = Simulation(dt=0.05)
        vessel = sim.add(Tank("lt", capacity_l=5000.0, level_l=3000.0,
                              height_m=3.0, comp={"solvent": 1.0}))
        still = sim.add(Still("st", rate_lps=3.0))
        sim.connect(vessel, "outlet", still, "inlet")
        sim.connect(sim.add(Duty("reb", 1800.0)), "out", still, "heat_duty")
        still.is_on = True                      # on, but no 480 V
        sim.run(10.0)
        assert still.running is False
        assert still.draw_lps == pytest.approx(0.0)
        assert still.recovered_l == pytest.approx(0.0)
        assert vessel.level_l == pytest.approx(3000.0, abs=1e-6)


class TestDownstreamTrain:
    def test_downstream_sequence_conserves_material(self) -> None:
        """Crystallizer -> centrifuge -> dryer for the product, with the
        mother liquor going to a still for solvent recovery.

        Every join here is now a single pipe: there is no draw wire to
        pair with it, and no tee component either. The hoppers between
        the machines are here because a real plant has them, not because
        the kernel demands them.
        """
        sim = Simulation(dt=0.05)
        cx = sim.add(Crystallizer("cx", capacity_l=3000.0))
        fuge = sim.add(Centrifuge("cf", rate_lps=2.0))
        cake_tank = sim.add(Tank("ct", capacity_l=5000.0, height_m=3.0))
        dryer = sim.add(Dryer("dr", rate_lps=2.0))
        dry_tank = sim.add(Tank("dt", capacity_l=5000.0, height_m=3.0))
        liquor_tank = sim.add(Tank("lt", capacity_l=5000.0, height_m=3.0))
        still = sim.add(Still("st", rate_lps=3.0))
        recovered = sim.add(Tank("rt", capacity_l=5000.0, height_m=3.0))
        heavies = sim.add(Drain("hv", rate_lps=5.0))
        wire_power(sim, cx, fuge, dryer, still)

        # A hot, dilute batch to work on.
        cx.charge(2500.0, {"product": 0.35, "solvent": 0.60, "impurity": 0.05}, 80.0)

        sim.connect(cx, "outlet", fuge, "inlet")
        sim.connect(fuge, "product", cake_tank, "inlet")
        sim.connect(fuge, "waste", liquor_tank, "inlet")
        sim.connect(cake_tank, "outlet", dryer, "inlet")
        sim.connect(dryer, "product", dry_tank, "inlet")
        sim.connect(liquor_tank, "outlet", still, "inlet")
        sim.connect(still, "distillate", recovered, "inlet")
        sim.connect(still, "bottoms", heavies, "inlet")

        # Utilities, wired rather than poked.
        sim.connect(sim.add(Duty("chill", 300.0)), "out", cx, "cool_duty")
        sim.connect(sim.add(Duty("dry_q", 400.0)), "out", dryer, "heat_duty")
        sim.connect(sim.add(Duty("reb_q", 1800.0)), "out", still, "heat_duty")

        fuge.is_on = True
        dryer.is_on = True
        still.is_on = True
        sim.run(600.0)

        assert cx.solids_frac > 0.1                 # crystals formed
        assert dry_tank.level_l > 0.0               # dry product landed
        assert recovered.level_l > 0.0              # solvent came back
        assert recovered.comp.get("solvent", 0.0) > 0.8   # and it is clean

        # Nothing invented, nothing lost: the original charge is spread
        # across the vessels, the drain, and what evaporated.
        accounted = (
            cx.volume_l
            + cake_tank.level_l
            + dry_tank.level_l
            + liquor_tank.level_l
            + recovered.level_l
            + heavies.total_l
            + dryer.dried_l
        )
        assert accounted == pytest.approx(2500.0, abs=15.0)
