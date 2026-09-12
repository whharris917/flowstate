"""A tee is one node with separated nozzles: a splitter shares its
inlet by resistance, a mixer blends what arrives, and both conserve.
"""

import pytest

from sim.components import Drain, Source, Tank, Tee
from sim.core import Simulation
from sim.stream import Stream


def test_a_splitter_conserves_and_splits_by_resistance() -> None:
    sim = Simulation(dt=0.05)
    header = sim.add(Source("hdr", pressure_kpa=300.0))
    tee = sim.add(Tee("tee", mode="split"))
    fat = sim.add(Drain("fat", rate_lps=6.0))
    thin = sim.add(Drain("thin", rate_lps=2.0))
    sim.connect(header, "outlet", tee, "in")
    sim.connect(tee, "a", fat, "inlet")
    sim.connect(tee, "b", thin, "inlet")
    sim.run(20.0)
    assert header.total_l == pytest.approx(fat.total_l + thin.total_l, rel=1e-6)
    # The runs' own resistances share the drop with the drains, so the
    # split is short of the 3:1 the drains alone would give.
    assert fat.total_l > thin.total_l * 1.5
    # One node: every nozzle of the tee reads the same pressure.
    nodes = {port.node for port in tee.material_ports().values()}
    assert len(nodes) == 1
    # The capped nozzle carries nothing.
    assert tee.outputs["c"].flow_lps == pytest.approx(0.0)


def test_a_mixer_blends_what_arrives() -> None:
    sim = Simulation(dt=0.05)
    water = sim.add(Source("water", pressure_kpa=300.0, species="water"))
    solvent = sim.add(Source("solv", pressure_kpa=300.0, species="solvent"))
    tee = sim.add(Tee("tee", mode="mix"))
    tank = sim.add(Tank("t", capacity_l=9000.0, level_l=0.0, height_m=4.0))
    sim.connect(water, "outlet", tee, "a")
    sim.connect(solvent, "outlet", tee, "b")
    sim.connect(tee, "out", tank, "inlet")
    sim.run(30.0)
    assert tank.level_l == pytest.approx(water.total_l + solvent.total_l, rel=1e-4)
    assert 0.3 < tank.contents.frac("water") < 0.7
    assert tank.contents.frac("water") + tank.contents.frac("solvent") == pytest.approx(1.0)


def test_mode_is_checked() -> None:
    with pytest.raises(ValueError):
        Tee("bad", mode="cross")
