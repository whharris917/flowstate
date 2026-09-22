"""The Maine drip demo (RoutingExercises._drip_demo) in the Python
kernel, for bisecting solver behaviour against an older tree.

    PYTHONPATH=<repo> .venv/Scripts/python.exe tools/drip_rig.py [seconds]
    git archive <rev> sim tests | tar -x -C <dir>; PYTHONPATH=<dir> ... tools/drip_rig.py

Prints iterations, residual and the drip, rotameter and metering-pump
flows every 2.5 s, then every unbalanced node and every branch. Found
the shortest-step rule of 2026-09-22 (restoring a failed step exactly
left the regulator shut for good)."""
import sys

from sim.components import Cap, MainsFeed, PowerSupply, Source, Tank
from sim.core import Simulation
from sim.small_bore import (BallValve, MeteringPump, NeedleValve, Orifice, Regulator,
                            Rotameter, SolenoidValve)

TUBE_K = 5000.0 * (50.0 / 6.0) ** 5


def tube(sim, a, ap, b, bp):
    w = sim.connect(a, ap, b, bp)
    w.k_pa_per_lps2 = TUBE_K
    return w


sim = Simulation(dt=0.05)
hdr = sim.add(Source("supply_2", pressure_kpa=400.0))
pr = sim.add(Regulator("pr_2", set_kpa=150.0, cv_lps=0.5))
bv = sim.add(BallValve("bv_2", cv_lps=0.5))
nv = sim.add(NeedleValve("nv_2", cv_lps=0.0005, turns=10.0))
fi = sim.add(Rotameter("fi_2", range_lps=0.001))
ro = sim.add(Orifice("ro_2", cv_lps=0.0005))
cap = sim.add(Cap("cap_1", elevation_m=0.9))
cap.open = True
t2 = sim.add(Tank("t_2", capacity_l=1.0, height_m=0.6, diameter_m=0.4, open_top=True))
t2.charge(20.0, {"water": 1.0})
mp = sim.add(MeteringPump("mp_2", rated_lps=0.01, max_head_m=50.0))
sv = sim.add(SolenoidValve("sv_2", cv_lps=0.3))
t3 = sim.add(Tank("t_3", capacity_l=1.0, height_m=0.6, diameter_m=0.4))
mains = sim.add(MainsFeed("mains_2", ways=2))
psu = sim.add(PowerSupply("psu_2"))
sim.connect(mains, "way1", psu, "ac_in")
sim.connect(psu, "dc_out", mp, "power")
tube(sim, hdr, "outlet", pr, "inlet")
tube(sim, pr, "outlet", bv, "inlet")
tube(sim, bv, "outlet", nv, "inlet")
tube(sim, nv, "outlet", fi, "inlet")
tube(sim, fi, "outlet", ro, "inlet")
tube(sim, ro, "outlet", cap, "a")
tube(sim, t2, "outlet", mp, "inlet")
tube(sim, mp, "outlet", sv, "inlet")
tube(sim, sv, "outlet", t3, "inlet")
bv.open = True
nv.turns_open = 2.0
mp.hand_on = True
if hasattr(t2, "set_nozzle"):
    t2.set_nozzle("outlet", height_m=0.06, dn=6)
    t2.set_nozzle("inlet", height_m=0.55, dn=6)
    t3.set_nozzle("outlet", height_m=0.06)
    t3.set_nozzle("inlet", height_m=0.55, dn=6)
for step in range(int(float(sys.argv[1]) / 0.05) if len(sys.argv) > 1 else 200):
    sim.run(0.05)
    net = sim._network
    if step < 3 or step % 50 == 49:
        print("t=%5.2f iters %2d residual %.3e  cap spill %.4f mL/s  fi %.4f mL/s  mp %.4f mL/s running=%s" % (
            sim.time, net.iterations, net.residual_lps, cap.spill_lps() * 1000.0 if hasattr(cap, "spill_lps") else -1,
            fi.flow_lps * 1000.0, mp.flow_lps * 1000.0, mp.running))
net = sim._network
free = [i for i, f in enumerate(net.fixed) if not f]
index_of = {n: s for s, n in enumerate(free)}
res = net._residuals(index_of, len(free))
for s, n in enumerate(free):
    if abs(res[s]) > 1e-6:
        print("  node %d residual %.4e p=%.1f" % (n, res[s], net.pressures[n]))
for b in net.branches:
    print("  %-28s a=%2d b=%2d q=%+.4e pa=%10.1f pb=%10.1f" % (b.name, b.node_a, b.node_b, b.flow_lps, net.pressures[b.node_a], net.pressures[b.node_b]))
