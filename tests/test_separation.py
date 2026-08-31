"""Tests for the separation train: crystallizer, dryer, still.

The point of these units is that they compose. Each one is checked on
its own equations, and then the whole downstream sequence is run end to
end to prove the material balance closes across all of them.
"""
from __future__ import annotations

import pytest

from conftest import Duty, wire_power
from sim.core import Simulation
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


class TestDryer:
    def _wet_cake(self, flow: float = 2.0) -> Stream:
        # 60 % crystal, the rest mother liquor.
        return Stream(
            flow, 40.0,
            {"product": 0.7, "solvent": 0.25, "impurity": 0.05},
            solids_frac=0.6,
        )

    def test_needs_power_and_being_switched_on(self) -> None:
        dryer = Dryer("dr", rate_lps=2.0)
        dryer.inlet.value = self._wet_cake()
        dryer.heat_duty.value = 500.0
        dryer.tick(0.05)
        assert dryer.draw.value == 0.0
        assert dryer.product.value.flow_lps == 0.0

    def test_evaporates_the_solvent_first(self) -> None:
        dryer = Dryer("dr", rate_lps=2.0)
        dryer.is_on = True
        dryer.power.value = 1.0
        dryer.inlet.value = self._wet_cake(flow=2.0)
        dryer.heat_duty.value = 180.0       # 0.2 L/s of evaporation
        dryer.tick(0.05)
        vapor = dryer.vapor.value
        assert vapor.flow_lps == pytest.approx(0.2)
        assert vapor.frac("solvent") == pytest.approx(1.0)
        # Conservation across the two nozzles.
        assert dryer.product.value.flow_lps + vapor.flow_lps == pytest.approx(2.0)

    def test_drying_concentrates_the_cake(self) -> None:
        dryer = Dryer("dr", rate_lps=2.0)
        dryer.is_on = True
        dryer.power.value = 1.0
        feed = self._wet_cake(flow=2.0)
        dryer.inlet.value = feed
        dryer.heat_duty.value = 450.0
        dryer.tick(0.05)
        cake = dryer.product.value
        assert cake.solids_frac > feed.solids_frac
        assert cake.frac("product") > feed.frac("product")

    def test_cannot_evaporate_more_liquid_than_it_has(self) -> None:
        """A huge duty on a nearly dry cake evaporates the liquid and
        stops, rather than eating the crystals."""
        dryer = Dryer("dr", rate_lps=2.0)
        dryer.is_on = True
        dryer.power.value = 1.0
        dryer.inlet.value = Stream(
            2.0, 40.0, {"product": 0.95, "solvent": 0.05}, solids_frac=0.9
        )
        dryer.heat_duty.value = 100000.0
        dryer.tick(0.05)
        # Only the 10 % that was liquid can go.
        assert dryer.vapor.value.flow_lps == pytest.approx(0.2, abs=0.01)
        assert dryer.product.value.flow_lps == pytest.approx(1.8, abs=0.01)
        assert dryer.product.value.solids_frac == pytest.approx(1.0, abs=0.01)

    def test_impurity_stays_behind_in_the_cake(self) -> None:
        """The uncomfortable truth about drying: what was dissolved in
        the retained liquor is still there when the solvent leaves."""
        dryer = Dryer("dr", rate_lps=2.0)
        dryer.is_on = True
        dryer.power.value = 1.0
        feed = self._wet_cake(flow=2.0)
        dryer.inlet.value = feed
        dryer.heat_duty.value = 450.0
        dryer.tick(0.05)
        assert dryer.product.value.frac("impurity") > feed.frac("impurity")
        assert dryer.vapor.value.frac("impurity") == pytest.approx(0.0)


class TestStill:
    def _liquor(self, flow: float = 3.0) -> Stream:
        return Stream(flow, 60.0, {"solvent": 0.8, "product": 0.1, "impurity": 0.1})

    def test_no_duty_means_no_separation(self) -> None:
        still = Still("st", rate_lps=3.0)
        still.is_on = True
        still.power.value = 1.0
        still.inlet.value = self._liquor()
        still.heat_duty.value = 0.0
        still.tick(0.05)
        assert still.distillate.value.flow_lps == pytest.approx(0.0)
        assert still.bottoms.value.flow_lps == pytest.approx(3.0)

    def test_light_ends_go_overhead(self) -> None:
        still = Still("st", rate_lps=3.0, cut_c=150.0, sharpness=0.95)
        still.is_on = True
        still.power.value = 1.0
        still.inlet.value = self._liquor(flow=3.0)
        still.heat_duty.value = 5000.0      # plenty of boilup
        still.tick(0.05)
        top = still.distillate.value
        bottom = still.bottoms.value
        # Solvent boils at 111, below the cut, so 95 % of it goes over.
        assert top.species_lps("solvent") == pytest.approx(3.0 * 0.8 * 0.95)
        # Product boils at 320, well above: it stays down.
        assert bottom.species_lps("product") > top.species_lps("product") * 10.0
        assert top.frac("solvent") > 0.9

    def test_material_balance_closes(self) -> None:
        still = Still("st", rate_lps=3.0)
        still.is_on = True
        still.power.value = 1.0
        feed = self._liquor(flow=3.0)
        still.inlet.value = feed
        still.heat_duty.value = 5000.0
        still.tick(0.05)
        top = still.distillate.value
        bottom = still.bottoms.value
        assert top.flow_lps + bottom.flow_lps == pytest.approx(3.0)
        for key in ("solvent", "product", "impurity"):
            assert top.species_lps(key) + bottom.species_lps(key) == pytest.approx(
                feed.species_lps(key) * (3.0 / feed.flow_lps)
            )

    def test_reboiler_duty_throttles_the_overhead(self) -> None:
        still = Still("st", rate_lps=3.0)
        still.is_on = True
        still.power.value = 1.0
        still.inlet.value = self._liquor(flow=3.0)
        still.heat_duty.value = 900.0       # exactly 1.0 L/s of boilup
        still.tick(0.05)
        assert still.boilup_lps == pytest.approx(1.0)
        assert still.distillate.value.flow_lps == pytest.approx(1.0)

    def test_crystals_never_distill(self) -> None:
        still = Still("st", rate_lps=3.0)
        still.is_on = True
        still.power.value = 1.0
        still.inlet.value = Stream(
            3.0, 60.0, {"solvent": 0.5, "product": 0.5}, solids_frac=0.4
        )
        still.heat_duty.value = 5000.0
        still.tick(0.05)
        solids_in = 3.0 * 0.4
        assert still.bottoms.value.solids_lps() == pytest.approx(solids_in, abs=1e-6)


class TestDownstreamTrain:
    def test_downstream_sequence_conserves_material(self) -> None:
        """Crystallizer -> centrifuge -> dryer for the product, with the
        mother liquor going to a still for solvent recovery.

        Note the shape the kernel forces: a machine that *pushes*
        material cannot feed one that *pulls* it. A vessel goes between
        them, which is what a real plant does anyway -- a centrifuge
        discharges to a hopper, and the dryer takes from the hopper.
        """
        from sim.components import Drain, Tank
        from sim.process import Centrifuge

        sim = Simulation(dt=0.05)
        cx = sim.add(Crystallizer("cx", capacity_l=3000.0))
        fuge = sim.add(Centrifuge("cf", rate_lps=2.0))
        cake_tank = sim.add(Tank("ct", capacity_l=5000.0))
        dryer = sim.add(Dryer("dr", rate_lps=2.0))
        dry_tank = sim.add(Tank("dt", capacity_l=5000.0))
        liquor_tank = sim.add(Tank("lt", capacity_l=5000.0))
        still = sim.add(Still("st", rate_lps=3.0))
        recovered = sim.add(Tank("rt", capacity_l=5000.0))
        heavies = sim.add(Drain("hv", rate_lps=5.0))
        wire_power(sim, cx, fuge, dryer, still)

        # A hot, dilute batch to work on.
        cx.charge(2500.0, {"product": 0.35, "solvent": 0.60, "impurity": 0.05}, 80.0)

        sim.connect(cx, "outlet", fuge, "inlet")
        sim.connect(fuge, "draw", cx, "draw")
        sim.connect(fuge, "product", cake_tank, "inlet")
        sim.connect(fuge, "waste", liquor_tank, "inlet")
        sim.connect(cake_tank, "outlet", dryer, "inlet")
        sim.connect(dryer, "draw", cake_tank, "draw")
        sim.connect(dryer, "product", dry_tank, "inlet")
        sim.connect(liquor_tank, "outlet", still, "inlet")
        sim.connect(still, "draw", liquor_tank, "draw")
        sim.connect(still, "distillate", recovered, "inlet")
        sim.connect(still, "bottoms", heavies, "flow_in")

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
