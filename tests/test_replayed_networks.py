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
