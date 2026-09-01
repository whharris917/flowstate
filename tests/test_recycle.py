"""The recycle loop: the proof that the kernel actually closes.

A recycle is the thing a bare-flow-rate kernel cannot express. Material
leaves the reactor, is worked on by four downstream units, and some of
it comes *back* to the reactor feed. For that to mean anything, every
unit in the ring has to agree about what is in the pipe, and the ring
has to conserve mass without anyone coordinating it.

This is the shape of the whole synthesis train:

    reagent A ---+
    reagent B ---+--> reactor --> crystallizer --> centrifuge --+
    solvent -----+       ^                                      |
                         |                         cake tank <--+
    makeup solvent       |                              |
         |               |                              v
         v               |                            dryer --> dry product
    solvent tank --------+                              |
         ^                                              v
         |                                        (solvent vapour)
         |
      still <-- liquor tank <-- (mother liquor from the centrifuge)
         |
         +--> bottoms --> drain

Every join drawn above is one pipe and one kernel wire. There is no
draw wire paired with any of them, and no tee component where the fresh
and recycled solvent lines meet the reactor -- they simply land on the
same nozzle, and the network splits them by what it costs to get there.
"""
from __future__ import annotations

import pytest

from conftest import Duty, wire_power
from sim.components import Drain, Pump, Source, Tank
from sim.core import Simulation
from sim.process import Centrifuge, Reactor
from sim.separation import Crystallizer, Dryer, Still


class RecyclePlant:
    """The full loop, built once and reused by the tests below."""

    def __init__(self) -> None:
        sim = Simulation(dt=0.05)
        self.sim = sim

        # Feeds
        self.src_a = sim.add(Source("hdr_a", species="reagent_a"))
        self.src_b = sim.add(Source("hdr_b", species="reagent_b"))
        self.makeup = sim.add(Source("hdr_solv", species="solvent"))
        self.pump_a = sim.add(Pump("p_a", rated_lps=0.6, mode="hand"))
        self.pump_b = sim.add(Pump("p_b", rated_lps=0.6, mode="hand"))
        self.pump_makeup = sim.add(Pump("p_mk", rated_lps=0.3, mode="hand"))

        # The ring
        self.reactor = sim.add(Reactor("rx", capacity_l=6000.0, rate_lps=1.2))
        self.pump_tx = sim.add(Pump("p_tx", rated_lps=1.5, mode="hand"))
        self.cx = sim.add(Crystallizer("cx", capacity_l=4000.0))
        self.fuge = sim.add(Centrifuge("cf", rate_lps=1.2))
        self.cake_tank = sim.add(Tank("t_cake", capacity_l=4000.0, height_m=3.0))
        self.dryer = sim.add(Dryer("dr", rate_lps=2.0))
        self.dry_tank = sim.add(Tank("t_dry", capacity_l=4000.0, height_m=3.0))
        self.liquor_tank = sim.add(Tank("t_liq", capacity_l=8000.0, height_m=4.0))
        self.still = sim.add(Still("st", rate_lps=3.0))
        self.solvent_tank = sim.add(Tank("t_solv", capacity_l=8000.0,
                                         level_l=500.0, height_m=4.0,
                                         comp={"solvent": 1.0}))
        self.pump_recycle = sim.add(Pump("p_rc", rated_lps=1.0, mode="hand"))
        self.heavies = sim.add(Drain("dr_hv", rate_lps=5.0))

        wire_power(
            sim, self.pump_a, self.pump_b, self.pump_makeup, self.pump_recycle,
            self.pump_tx, self.reactor, self.cx, self.fuge, self.dryer,
            self.still,
        )

        # Reagent feeds into the reactor
        for source, pump, nozzle in (
            (self.src_a, self.pump_a, "inlet_a"),
            (self.src_b, self.pump_b, "inlet_b"),
        ):
            sim.connect(source, "outlet", pump, "inlet")
            sim.connect(pump, "outlet", self.reactor, nozzle)

        # Makeup solvent tops up the solvent tank; the recycle pump
        # sends the tank contents to the reactor. Fresh and recovered
        # solvent mix in the tank, which is the whole point of it.
        sim.connect(self.makeup, "outlet", self.pump_makeup, "inlet")
        sim.connect(self.pump_makeup, "outlet", self.solvent_tank, "inlet")
        sim.connect(self.solvent_tank, "outlet", self.pump_recycle, "inlet")
        sim.connect(self.pump_recycle, "outlet", self.reactor, "inlet_a")

        # Reactor -> crystallizer -> centrifuge. A transfer pump between
        # the two vessels, because the reactor sits at grade and cannot
        # push its own batch up into the crystallizer. That is a
        # judgement about elevation now, not a rule the kernel enforces:
        # raise the reactor instead and the pipe alone would do it.
        sim.connect(self.reactor, "outlet", self.pump_tx, "inlet")
        sim.connect(self.pump_tx, "outlet", self.cx, "inlet")
        sim.connect(self.cx, "outlet", self.fuge, "inlet")

        # Cake side: hopper -> dryer -> dry product
        sim.connect(self.fuge, "product", self.cake_tank, "inlet")
        sim.connect(self.cake_tank, "outlet", self.dryer, "inlet")
        sim.connect(self.dryer, "product", self.dry_tank, "inlet")

        # Liquor side: the recycle. Still overheads go back to the
        # solvent tank and round again.
        sim.connect(self.fuge, "waste", self.liquor_tank, "inlet")
        sim.connect(self.liquor_tank, "outlet", self.still, "inlet")
        sim.connect(self.still, "distillate", self.solvent_tank, "inlet")
        sim.connect(self.still, "bottoms", self.heavies, "inlet")

        # Utilities
        sim.connect(sim.add(Duty("q_rx", 700.0)), "out", self.reactor, "heat_duty")
        sim.connect(sim.add(Duty("q_cx", 260.0)), "out", self.cx, "cool_duty")
        sim.connect(sim.add(Duty("q_dr", 400.0)), "out", self.dryer, "heat_duty")
        sim.connect(sim.add(Duty("q_st", 2200.0)), "out", self.still, "heat_duty")

        # Commissioned state: a hot working charge, so behaviour is
        # visible in minutes rather than hours.
        self.reactor.charge(
            2500.0, {"solvent": 0.7, "reagent_a": 0.15, "reagent_b": 0.15}, 75.0
        )
        # The crystallizer ships with a working heel too, so it has the
        # residence time to actually drop crystals from the start.
        self.cx.charge(900.0, {"solvent": 0.75, "product": 0.2, "impurity": 0.05},
                       60.0)
        for machine in (self.fuge, self.dryer, self.still):
            machine.is_on = True

    def fed_in(self) -> float:
        """Fresh material crossing the plant boundary."""
        return self.src_a.total_l + self.src_b.total_l + self.makeup.total_l

    def held(self) -> float:
        """Everything currently inside the plant, plus what has left."""
        return (
            self.reactor.volume_l
            + self.cx.volume_l
            + self.cake_tank.level_l
            + self.dry_tank.level_l
            + self.liquor_tank.level_l
            + self.solvent_tank.level_l
            + self.heavies.total_l
            + self.dryer.dried_l
            + self.reactor.boiled_off_l
        )


SOAK_S = 600.0


@pytest.fixture(scope="module")
def soaked() -> tuple[RecyclePlant, float]:
    """One commissioned plant, soaked once, read by every test below
    that only wants to look at it.

    Built once on purpose. A ring this size is a genuinely expensive
    thing to simulate -- fifty nodes solved every scan for ten thousand
    scans -- and every assertion here is about the same soak, so
    rebuilding it per test would buy nothing but minutes.
    """
    plant = RecyclePlant()
    start_inventory = plant.held()
    plant.sim.run(SOAK_S)
    return plant, start_inventory


class TestRecycleLoop:
    def test_the_loop_runs_and_solvent_comes_back(self, soaked) -> None:
        plant, _ = soaked
        assert plant.reactor.purity_frac > 0.05      # product is being made
        assert plant.cx.solids_frac > 0.05           # crystals are dropping
        assert plant.dry_tank.level_l > 0.0          # dry product is landing
        # The distillate came back round to the solvent tank.
        assert plant.still.recovered_l > 50.0
        assert plant.solvent_tank.comp.get("solvent", 0.0) > 0.7

    def test_mass_closes_around_the_ring(self, soaked) -> None:
        """Nothing is created or destroyed anywhere in the loop, even
        though material passes through the same vessels repeatedly."""
        plant, start_inventory = soaked
        assert plant.held() == pytest.approx(
            start_inventory + plant.fed_in(), rel=0.02
        )

    def test_the_solve_stays_healthy_all_the_way_round(self, soaked) -> None:
        """A ring is the hard case for a nodal solve: every node feeds
        back into itself eventually. It still has to balance, and from a
        warm start it still has to do it in a couple of iterations."""
        plant, _ = soaked
        net = plant.sim._network
        assert net.residual_lps <= net.TOLERANCE_LPS
        assert net.iterations <= 4

    def test_no_pump_in_the_ring_is_left_cavitating(self, soaked) -> None:
        """A machine whose supply has not arrived drags its suction
        toward vacuum. That is honest, but a commissioned plant running
        steadily should have none of it -- and if one does, the solve
        that reports it is the one to trust."""
        plant, _ = soaked
        starved = [p.name for p in (plant.pump_a, plant.pump_b,
                                    plant.pump_makeup, plant.pump_tx,
                                    plant.pump_recycle)
                   if p.cavitating]
        assert starved == []

    def test_recycle_carries_more_than_the_makeup(self, soaked) -> None:
        """The payoff: most of the solvent reaching the reactor has been
        round the loop before, rather than coming fresh off a header."""
        plant, _ = soaked
        assert plant.still.recovered_l > plant.makeup.total_l

    def test_recycle_carries_impurity_with_it(self, soaked) -> None:
        """The other half of the payoff, and the reason a purge exists:
        an imperfect cut sends a little heavy material back round, so
        the recycled solvent is never quite as clean as fresh."""
        plant, _ = soaked
        recycled = plant.solvent_tank.comp
        assert recycled.get("solvent", 0.0) < 1.0
        assert recycled.get("impurity", 0.0) > 0.0

    def test_breaking_the_recycle_backs_the_solvent_up(self) -> None:
        """Pull the recycle line and the ring behaves differently --
        proof it is load-bearing rather than decorative.

        Pulling a pipe is now one disconnect, not two. The draw wire it
        used to be paired with is gone, so there is no way to leave a
        pump still sucking on a tank and discharging onto the floor.
        """
        closed = RecyclePlant()
        opened = RecyclePlant()
        opened.sim.disconnect(
            opened.pump_recycle, "outlet", opened.reactor, "inlet_a"
        )
        opened.sim.disconnect(
            opened.solvent_tank, "outlet", opened.pump_recycle, "inlet"
        )
        closed.sim.run(400.0)
        opened.sim.run(400.0)
        # Without the recycle the reactor gets only its two reagents.
        assert closed.reactor.volume_l > opened.reactor.volume_l
        # And the solvent it is no longer drinking backs up in the tank.
        assert opened.solvent_tank.level_l > closed.solvent_tank.level_l

    def test_an_orphaned_pump_moves_nothing(self) -> None:
        """Pulling only the discharge leaves the recycle pump piped to
        the tank and open to nothing. With pressure solving direction a
        line that ends nowhere passes nothing, so the pump turns and the
        tank stays where it is -- the old model would have kept
        decrementing the tank through the draw wire."""
        plant = RecyclePlant()
        plant.sim.disconnect(
            plant.pump_recycle, "outlet", plant.reactor, "inlet_a"
        )
        plant.sim.run(60.0)
        before = plant.solvent_tank.level_l
        plant.sim.run(60.0)
        assert plant.pump_recycle.running
        assert plant.pump_recycle.flow_lps == pytest.approx(0.0, abs=1e-6)
        # The tank only rises, from makeup and distillate. Nothing is
        # being drawn out of it.
        assert plant.solvent_tank.level_l >= before
