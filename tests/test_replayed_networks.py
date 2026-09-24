"""Networks from the game that the solver once failed, replayed.
Each was dumped by the GD kernel just before the failing
solve (FLOWSTATE_NET_DUMP, see tools/replay_network.py) and is rebuilt
here from the Python classes the GD kernel mirrors; the Python and GD
solvers follow the same iterations to the digit on both. Each must
land.

  * showcase_rebuild_124_30: the showcase just after its network was
    rebuilt, with the boiler's steam line (drum just firing) and Unit
    400's line between two dry nozzles both unsettled. One step length
    for the whole plant lets the steam line swing across the drum
    pressure, and when Unit 400 finds no step that helps the solve
    stops with both unsettled. Solved block by block.
  * maine_cold_start: the Maine site's first solve, from nowhere near the
    answer. The drip line's regulator cracks open on a step that fails,
    so a block that stops at its first failure ends the solve 82 mL/s
    out.

  * showcase_xv403_dead_leg: a warm solve of the showcase on a
    transient reached from a different cold seed. The short dead leg
    between Unit 400's sewer valve XV-403 (a few percent open) and its
    shut one-way drain carries a flow back through the valve; Newton's
    step on the valve's square law lands near its mirror image, which
    the block's norm alone would accept. A step that swings a node to
    the other side of its balance without halving it is refused.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from replay_network import build  # noqa: E402

DATA = Path(__file__).resolve().parent / "data"


@pytest.mark.parametrize("name", ["showcase_rebuild_124_30", "maine_cold_start",
                                  "showcase_xv403_dead_leg"])
def test_a_network_the_solver_once_failed_now_lands(name: str) -> None:
    net = build(json.loads((DATA / (name + ".json")).read_text(encoding="utf-8")))
    net.solve()
    assert net.converged
    assert net.residual_lps < 1e-4
