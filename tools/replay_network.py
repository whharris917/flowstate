"""Replay a hydraulic solve from the game in the Python reference kernel.

The game kernel dumps a network exactly as it stands before a solve --
every node's pressure and whether it is fixed, every branch with its
kind and live parameters -- when a smoke run is given the time of the
scan:

    FLOWSTATE_NET_DUMP=124.30 godot --headless --path game res://world/sandbox.tscn --quit-after 600

which writes %APPDATA%/Godot/app_userdata/flowstate/net_dump_124.30.json.
This rebuilds that network from the Python classes the GD kernel mirrors
and solves it once, printing each iteration: the imbalance, the worst
node and its pressure, and whether the solve landed.

    PYTHONPATH=<repo> .venv/Scripts/python.exe tools/replay_network.py <dump.json> [--quiet]

The point (2026-09-22): a solver failure inside a running plant can be
watched only through prints; replayed here it can be studied, changed
and re-run in seconds, and a fix proven on the very network that failed.
"""
from __future__ import annotations

import json
import sys

from sim.hydraulics import (
    CheckResistance, ControlResistance, FixedFlow, Network, NozzleResistance,
    PumpCurve, RegulatorResistance, Resistance, _norm,
)


def build(dump: dict) -> Network:
    """The network in a dump, ready to solve."""
    net = Network()
    for pressure, fixed in zip(dump["pressures"], dump["fixed"]):
        net.add_node(float(pressure), bool(fixed))
    for entry in dump["branches"]:
        a, b, name, kind = int(entry["a"]), int(entry["b"]), entry["name"], entry["kind"]
        if kind == "resistance":
            branch = Resistance(a, b, entry["k"], name)
        elif kind == "check":
            branch = CheckResistance(a, b, entry["k"], name)
        elif kind == "control":
            branch = ControlResistance(a, b, entry["cv_lps"], name, one_way=entry["one_way"])
            branch.opening = entry["opening"]
        elif kind == "nozzle":
            branch = NozzleResistance(a, b, entry["cv_lps"], name)
            branch.submergence = entry["submergence"]
        elif kind == "regulator":
            branch = RegulatorResistance(a, b, entry["cv_lps"], entry["set_pa"], entry["band_pa"], name)
        elif kind == "pump":
            branch = PumpCurve(a, b, entry["head_pa"], entry["max_lps"], name, entry["exponent"])
            branch.running = entry["running"]
            branch.datum_pa = entry["datum_pa"]
        elif kind == "fixed_flow":
            branch = FixedFlow(a, b, entry["lps"], name)
        else:
            raise ValueError("cannot rebuild a branch of kind %r (%s)" % (kind, name))
        net.add_branch(branch)
    net._solved_once = bool(dump["solved_once"])
    return net


def describe(net: Network, node: int) -> str:
    """The branches meeting at a node with their flows, as the GD
    kernel's describe_node prints them."""
    parts = []
    for branch in net.branches:
        q = branch.flow_at(net.pressures[branch.node_a], net.pressures[branch.node_b])
        if branch.node_a == node:
            parts.append("%s ->%.3f" % (branch.name, q))
        elif branch.node_b == node:
            parts.append("%s <-%.3f" % (branch.name, q))
    return "node %d at %.0f Pa: %s" % (node, net.pressures[node], ", ".join(parts))


def main() -> None:
    path = sys.argv[1]
    quiet = "--quiet" in sys.argv
    with open(path, encoding="utf-8") as handle:
        net = build(json.load(handle))

    def trace(event: str, **fields) -> None:
        if event != "iteration" or quiet:
            return
        residual = fields["residual"]
        free = fields["free"]
        worst = max(range(len(residual)), key=lambda i: abs(residual[i]))
        print("it%-3d norm %.6f  worst %s" % (fields["iteration"], _norm(residual),
                                             describe(net, free[worst])))

    net.trace = trace
    net.solve()
    print("%s after %d iterations, residual %.6f L/s" % (
        "converged" if net.converged else "NOT CONVERGED", net.iterations, net.residual_lps))


if __name__ == "__main__":
    main()
