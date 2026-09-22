"""Unit 400's T-401 draining by gravity through a stroking valve into
T-402's dry top nozzle, in the Python kernel: the standing example of a
plateau a stroking valve opens onto (half a second of unconverged scans,
identical on the committed kernel of 2026-09-22, the balance still closing).

    PYTHONPATH=<repo> .venv/Scripts/python.exe tools/gravity_drain_rig.py

Counts the unconverged scans and prints the first six."""
from sim.components import Tank
from sim.core import Simulation
from sim.small_bore import BallValve
sim = Simulation(dt=0.05)
top = sim.add(Tank("t_401", capacity_l=1.0, height_m=1.2, diameter_m=1.0, elevation_m=6.0, nozzle_cv_lps=200.0))
mid = sim.add(Tank("t_402", capacity_l=1.0, height_m=1.2, diameter_m=1.0, elevation_m=3.0, nozzle_cv_lps=200.0))
top.charge(450.0, {"water": 1.0})
mid.charge(150.0, {"water": 1.0})
xv = sim.add(BallValve("xv_401", cv_lps=60.0, stroke_s=2.0))
w1 = sim.connect(top, "outlet", xv, "inlet"); w1.k_pa_per_lps2 = 50.0
w2 = sim.connect(xv, "outlet", mid, "inlet"); w2.k_pa_per_lps2 = 50.0
sim.run(1.0)
xv.open = True
bad = 0
for i in range(200):
    sim.run(0.05)
    net = sim._network
    if net.residual_lps > 1e-3:
        bad += 1
        if bad <= 6:
            print("t=%.2f iters %d residual %.3f  xv %.3f L/s" % (sim.time, net.iterations, net.residual_lps, xv.flow_lps))
print("unconverged scans: %d; top %.0f L mid %.0f L" % (bad, top.level_l, mid.level_l))
