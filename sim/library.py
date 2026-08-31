"""The equipment library: what each unit operation is, what goes in and
out of it, and the equations that relate them.

This is the reference the player can open in-game. It exists because a
plant you cannot reason about is a plant you can only poke at, and the
whole game is about reasoning.

The honesty rule that governs the historian governs this too: a library
page is never allowed to describe a machine that does not exist.

  * The **port table is not authored**. It is read off a real
    constructed component at render time -- names, directions, and
    kinds come from the same ``add_input``/``add_output`` calls the
    simulation uses. A page cannot list a nozzle the equipment does not
    have, or miss one it does.
  * The **equations are authored, and are the only copy**. They live on
    the class beside the ``tick`` that implements them, not in a
    separate document that can quietly fall out of date.
  * What is authored per port is only its *meaning* -- the sentence a
    port table cannot infer. ``test_library.py`` fails if any real port
    lacks one, or if a meaning names a port that no longer exists.
"""
from __future__ import annotations

import inspect
from typing import Iterable

from sim.core import Component, PortKind

# How each port kind reads to a person rather than to the kernel.
KIND_LABELS: dict[PortKind, str] = {
    PortKind.SIGNAL_DISCRETE: "24 V discrete",
    PortKind.SIGNAL_ANALOG: "4-20 mA analog",
    PortKind.PROCESS_STREAM: "material (delivered)",
    PortKind.PROCESS_SUPPLY: "material (offered)",
    PortKind.PROCESS_FLOW: "draw demand, L/s",
    PortKind.PROCESS_LEVEL: "level tap, L",
    PortKind.PROCESS_PRESSURE: "pressure tap, Pa",
    PortKind.POWER: "electrical supply",
}


class Equation:
    """One governing relation, as it is written and as it is meant."""

    def __init__(self, formula: str, meaning: str) -> None:
        self.formula = formula
        self.meaning = meaning

    def as_dict(self) -> dict:
        return {"formula": self.formula, "meaning": self.meaning}


class Param:
    """A construction parameter: what the player sizes when they place
    the equipment."""

    def __init__(self, name: str, units: str, meaning: str) -> None:
        self.name = name
        self.units = units
        self.meaning = meaning

    def as_dict(self, info: dict | None = None) -> dict:
        info = info or {"default": None, "required": False}
        return {
            "name": self.name,
            "units": self.units,
            "meaning": self.meaning,
            "default": info.get("default"),
            "required": info.get("required", False),
        }


class EquipmentSpec:
    """A library page. Attach one to a component class as ``SPEC``."""

    def __init__(
        self,
        key: str,
        title: str,
        tier: str,
        summary: str,
        ports: dict[str, str],
        equations: Iterable[Equation] = (),
        params: Iterable[Param] = (),
        assumptions: Iterable[str] = (),
    ) -> None:
        self.key = key
        self.title = title
        self.tier = tier            # process | separation | control | utility
        self.summary = summary
        self.ports = dict(ports)    # port name -> what it means
        self.equations = list(equations)
        self.params = list(params)
        self.assumptions = list(assumptions)


def spec_of(cls: type) -> EquipmentSpec | None:
    """The spec declared on a component class, if it has one. Read from
    the class itself rather than inherited, so a subclass without its
    own page does not silently borrow its parent's."""
    return cls.__dict__.get("SPEC")


def constructor_params(cls: type) -> dict[str, dict]:
    """Every construction parameter, straight off the signature, with
    its real default -- so the library shows the actual sizing rather
    than a transcription of it. A parameter with no default is one the
    player must choose, and is flagged as required."""
    found: dict[str, dict] = {}
    for name, param in inspect.signature(cls.__init__).parameters.items():
        if name in ("self", "name"):
            continue
        if param.kind in (param.VAR_POSITIONAL, param.VAR_KEYWORD):
            continue
        required = param.default is inspect.Parameter.empty
        found[name] = {
            "default": None if required else param.default,
            "required": required,
        }
    return found


def port_table(component: Component) -> list[dict]:
    """The real I/O of a real component, in a form a page can render.

    Nothing here is authored: it is the ports the component actually
    built for itself.
    """
    rows: list[dict] = []
    for direction, ports in (("in", component.inputs), ("out", component.outputs)):
        for port in ports.values():
            rows.append(
                {
                    "name": port.name,
                    "direction": direction,
                    "kind": port.kind.value,
                    "kind_label": KIND_LABELS.get(port.kind, port.kind.value),
                    "spec": port.spec,
                }
            )
    return rows


def describe(component: Component) -> dict:
    """A full library page for one piece of equipment: the authored
    prose and equations, merged with the machine's actual I/O."""
    spec = spec_of(type(component))
    if spec is None:
        return {
            "key": type(component).__name__.lower(),
            "title": type(component).__name__,
            "tier": "undocumented",
            "summary": "",
            "ports": port_table(component),
            "equations": [],
            "params": [],
            "assumptions": [],
            "observables": sorted(component.observables),
        }
    params = constructor_params(type(component))
    ports = port_table(component)
    for row in ports:
        row["meaning"] = spec.ports.get(row["name"], "")
    return {
        "key": spec.key,
        "title": spec.title,
        "tier": spec.tier,
        "summary": spec.summary,
        "ports": ports,
        "equations": [eq.as_dict() for eq in spec.equations],
        "params": [p.as_dict(params.get(p.name)) for p in spec.params],
        "assumptions": list(spec.assumptions),
        "observables": sorted(component.observables),
    }


def catalog(components: Iterable[Component]) -> list[dict]:
    """Library pages for a set of sample components, one per type,
    sorted by tier then title."""
    seen: set[type] = set()
    pages: list[dict] = []
    for component in components:
        if type(component) in seen:
            continue
        seen.add(type(component))
        pages.append(describe(component))
    order = {"process": 0, "separation": 1, "utility": 2, "control": 3}
    pages.sort(key=lambda p: (order.get(p["tier"], 9), p["title"]))
    return pages


def sample_components() -> list[Component]:
    """One of everything, built with its default sizing.

    The library is generated from real instances, so building this list
    is also a standing check that every documented machine can still be
    constructed.
    """
    from sim import components as comp
    from sim import control as ctrl
    from sim import process as proc
    from sim import separation as sep

    return [
        ctrl.PID("controller"),
        ctrl.PLC("plc"),
        comp.Tank("tank", capacity_l=4000.0),
        comp.Pump("pump", rated_lps=4.0),
        comp.ControlValve("valve"),
        comp.Source("header"),
        comp.Drain("drain"),
        comp.Gauge("gauge", "level_kpa"),
        comp.FloatSwitch("switch", low_l=40.0, high_l=80.0),
        comp.Relay("relay"),
        comp.MainsFeed("mains"),
        comp.PowerSupply("psu"),
        comp.Terminal("terminal"),
        comp.Column("column"),
        proc.SteamGen("boiler"),
        proc.HeatExchanger("exchanger"),
        proc.Reactor("reactor"),
        proc.Centrifuge("centrifuge"),
        proc.VacuumLock("lock"),
        proc.VialFiller("filler"),
        sep.Crystallizer("crystallizer"),
        sep.Dryer("dryer"),
        sep.Still("still"),
    ]
