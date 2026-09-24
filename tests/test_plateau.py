"""Solves that stop short at a plateau. A solve that does not land
records flows that do not balance, and inside a machine that passes
material through that is material made or lost. Each case here is one
such pattern, and each must converge every scan."""
from __future__ import annotations

import pytest

from conftest import open_drain, wire_power
from sim.components import Drain, MainsFeed, Pump, Source, Tank, Tee
from sim.core import Simulation
from sim.process import HeatExchanger, SteamGen, VacuumLock, VialFiller
from sim.small_bore import BallValve


def _run_counting(sim: Simulation, seconds: float) -> None:
    for _ in range(round(seconds / sim.dt)):
        sim.run(sim.dt)


class TestPlateau:
    def test_a_valve_opening_onto_a_dry_roof_nozzle(self) -> None:
        # Unit 400's XV-401: T-401 drains by gravity through a stroking
        # valve into T-402's dry roof nozzle, 10 kPa above the line.
        # Newton's local slope alone climbs that gap in steps of a few
        # hundred pascals for twenty scans with the valve's flow
        # unbalanced; the plateau step goes straight to the crack.
        sim = Simulation(dt=0.05)
        top = sim.add(Tank("t_401", capacity_l=1.0, height_m=1.2, diameter_m=1.0,
                           elevation_m=6.0, nozzle_cv_lps=200.0))
        mid = sim.add(Tank("t_402", capacity_l=1.0, height_m=1.2, diameter_m=1.0,
                           elevation_m=3.0, nozzle_cv_lps=200.0))
        top.charge(450.0, {"water": 1.0})
        mid.charge(150.0, {"water": 1.0})
        xv = sim.add(BallValve("xv", cv_lps=60.0, stroke_s=2.0))
        sim.connect(top, "outlet", xv, "inlet").k_pa_per_lps2 = 50.0
        sim.connect(xv, "outlet", mid, "inlet").k_pa_per_lps2 = 50.0
        sim.run(1.0)
        xv.open = True
        _run_counting(sim, 10.0)
        assert sim.unconverged_scans == 0
        assert mid.level_l > 150.0 + 100.0
        assert top.level_l + mid.level_l == pytest.approx(600.0, abs=1e-6)

    def test_a_filler_cannot_draw_from_a_dry_outlet(self) -> None:
        # The silo's outlet stands above its liquid; an imposed draw
        # taken anyway is an imbalance the solve can never close, and
        # vials filled from nowhere. An imposed draw starves as its
        # suction nears a hard vacuum.
        sim = Simulation(dt=0.05)
        silo = sim.add(Tank("pt", capacity_l=1.0, height_m=7.0, diameter_m=3.2))
        silo.charge(1500.0, {"product": 1.0})          # 0.19 m deep
        silo.set_nozzle("outlet", height_m=0.7)        # above the liquid
        filler = sim.add(VialFiller("vf"))
        sim.connect(silo, "outlet", filler, "inlet")
        wire_power(sim, filler)
        filler.is_on = True
        _run_counting(sim, 20.0)
        assert filler.filled_l == pytest.approx(0.0, abs=1e-6)
        assert silo.level_l == pytest.approx(1500.0, abs=1e-6)
        assert sim.unconverged_scans <= 2    # the first scans off a cold start

    def test_a_pump_on_a_vessel_gone_dry_moves_nothing_and_converges(self) -> None:
        # The dryer's feed pump on the empty cake hopper: the suction is
        # pulled against a dry nozzle that can give nothing, and falls to
        # where the pump runs out of prime.
        sim = Simulation(dt=0.05)
        hopper = sim.add(Tank("ht", capacity_l=1.0, height_m=2.0, diameter_m=1.0))
        pump = sim.add(Pump("p", rated_lps=2.0, mode="hand", head_m=20.0))
        sim.connect(hopper, "outlet", pump, "inlet")
        out = open_drain(sim, pump)
        wire_power(sim, pump)
        _run_counting(sim, 10.0)
        assert out.total_l == pytest.approx(0.0, abs=1e-6)
        assert sim.unconverged_scans <= 2

    def test_a_cold_boiler_line_at_the_sewer_pressure_comes_to_rest(self) -> None:
        # The showcase's boiler start: a cold drum at exactly the sewer's
        # pressure feeds an exchanger's shell whose condensate and a
        # vacuum lock's drain meet in a tee to a one-way drain. The answer
        # is every node at zero with nothing flowing; the landing at the
        # drain's crack with the arriving trickle passing is always a
        # trickle short, and the solve creeps by a quarter an iteration.
        # The landing at rest is tried too.
        sim = Simulation(dt=0.05)
        bfw = sim.add(Source("bfw", "water"))
        sg = sim.add(SteamGen("sg", rated_kgps=0.5))
        hx = sim.add(HeatExchanger("hx", max_duty_kw=1200.0))
        proc = sim.add(Source("proc", "water"))
        out = sim.add(Drain("out", rate_lps=3.0))
        vl = sim.add(VacuumLock("vl"))
        tee = sim.add(Tee("tee", "mix"))
        du = sim.add(Drain("du", rate_lps=1.5))
        mains = sim.add(MainsFeed("m", ways=4))
        sim.connect(mains, "way1", sg, "power")
        sim.connect(mains, "way2", vl, "power")
        sim.connect(bfw, "outlet", sg, "inlet")
        sim.connect(sg, "steam", hx, "steam_in")
        sim.connect(proc, "outlet", hx, "cold_in")
        sim.connect(hx, "cold_out", out, "inlet")
        sim.connect(hx, "condensate", tee, "a")
        sim.connect(vl, "drain_flow", tee, "b")
        sim.connect(tee, "out", du, "inlet")
        sg.is_on = True
        vl.is_on = True
        _run_counting(sim, 10.0)
        assert sim.unconverged_scans == 0
