"""Networks from the game that the solver once failed, replayed
(2026-09-22). Each was dumped by the GD kernel just before the failing
solve (FLOWSTATE_NET_DUMP, see tools/replay_network.py) and is rebuilt
here from the Python classes the GD kernel mirrors; the Python and GD
solvers followed the same iterations to the digit on both. Each must
now land.

  * showcase_rebuild_124_30: the showcase just after its network was
    rebuilt. The boiler's steam line (drum just firing) and Unit 400's
    line between two dry nozzles were both unsettled; one step length
    for the whole plant let the steam line swing across the drum
    pressure, and when Unit 400 found no step that helped the solve
    stopped with both unsettled (0.16 L/s). Solved block by block.
  * maine_cold_start: the Maine site's first solve, from nowhere near the
    answer. The drip line's regulator cracked open on a step that
    failed, and a block stopped at its first failure ended the solve
    82 mL/s out.

One is known to fail still, and is kept so the fix has a target:

  * showcase_xv403_dead_leg (2026-09-22): a warm solve of the showcase on
    a transient reached from a different cold seed. The short dead leg
    between Unit 400's sewer valve XV-403 (a few percent open) and its
    shut one-way drain carries a flow back through the valve; Newton's
    step on the valve's square law lands on its mirror image, and the
    halving that would cure it is never taken, because the step is
    judged on the whole Unit 400 block, whose small gains elsewhere let
    the mirror pass iteration after iteration.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from replay_network import build  # noqa: E402

DATA = Path(__file__).resolve().parent / "data"


@pytest.mark.parametrize("name", ["showcase_rebuild_124_30", "maine_cold_start"])
def test_a_network_the_solver_once_failed_now_lands(name: str) -> None:
    net = build(json.loads((DATA / (name + ".json")).read_text(encoding="utf-8")))
    net.solve()
    assert net.converged
    assert net.residual_lps < 1e-4


@pytest.mark.xfail(reason="a square-law mirror inside a block that improves elsewhere: not yet fixed",
                   strict=True)
def test_a_dead_leg_behind_a_barely_open_valve_lands() -> None:
    net = build(json.loads((DATA / "showcase_xv403_dead_leg.json").read_text(encoding="utf-8")))
    net.solve()
    assert net.converged
