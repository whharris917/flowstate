"""Generate the in-game equipment library from the Python specs.

The kernel exists twice: once in Python as the reference implementation
and once in GDScript as the thing the game runs. The library text must
not exist twice as well, or the two copies will drift and the game will
start explaining a machine that is not the machine.

So Python owns the prose and the equations, and this script writes them
out as a GDScript constant. Run it after editing any ``SPEC``:

    .venv\\Scripts\\python.exe tools\\generate_library.py

What is deliberately NOT generated is the port table. The in-game
library reads that off a real constructed GDScript component at render
time (see ``sim_library.gd``), so a page always shows the I/O the game
actually has, even if the two kernels have drifted. Port *meanings* come
from here; port names, kinds and directions come from the live record.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from sim.library import (  # noqa: E402
    catalog, describe, sample_components, spec_of,
)

OUT = ROOT / "game" / "sim" / "sim_library_data.gd"

# One Python spec can serve several placeable types: a gauge is one
# model with six configurations.
TYPE_IDS: dict[str, list[str]] = {
    "tank": ["tank"],
    "pump": ["pump"],
    "reactor": ["reactor"],
    "heat_exchanger": ["hx"],
    "steam_gen": ["steamgen"],
    "vial_filler": ["vialfill"],
    "crystallizer": ["crystallizer"],
    "centrifuge": ["centrifuge"],
    "dryer": ["dryer"],
    "still": ["still"],
    "column": ["column"],
    "source": ["source"],
    "drain": ["drain"],
    "vacuum_lock": ["vaclock"],
    "control_valve": ["valve"],
    "float_switch": ["float_switch"],
    "relay": ["relay"],
    "mains_feed": ["mains"],
    "power_supply": ["psu"],
    "terminal": ["terminal"],
    "pid": ["controller"],
    "plc": ["plc"],
    "gauge": [
        "gauge_level", "gauge_flow", "gauge_dp",
        "gauge_press", "gauge_temp", "gauge_conc",
    ],
}


def gd_string(text: str) -> str:
    """A GDScript double-quoted literal."""
    escaped = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", " ")
    )
    return f'"{escaped}"'


def emit_page(page: dict, type_ids: list[str],
              meanings: dict[str, str] | None = None) -> list[str]:
    lines: list[str] = []
    for type_id in type_ids:
        lines.append(f"\t{gd_string(type_id)}: {{")
        lines.append(f"\t\t\"title\": {gd_string(page['title'])},")
        lines.append(f"\t\t\"tier\": {gd_string(page['tier'])},")
        lines.append(f"\t\t\"summary\": {gd_string(page['summary'])},")
        lines.append("\t\t\"ports\": {")
        # Every authored meaning, not just the ports the sample instance
        # happened to build: one spec can cover several configurations,
        # and a dp gauge has taps a level gauge does not.
        for port_name, meaning in sorted((meanings or {}).items()):
            lines.append(f"\t\t\t{gd_string(port_name)}: {gd_string(meaning)},")
        lines.append("\t\t},")
        lines.append("\t\t\"equations\": [")
        for eq in page["equations"]:
            lines.append(
                "\t\t\t[%s, %s]," % (gd_string(eq["formula"]), gd_string(eq["meaning"]))
            )
        lines.append("\t\t],")
        lines.append("\t\t\"params\": [")
        for param in page["params"]:
            default = param["default"]
            shown = "required" if param["required"] else repr(default)
            if isinstance(default, float):
                shown = f"{default:g}"
            elif isinstance(default, str):
                shown = default
            elif default is None and not param["required"]:
                shown = "-"
            elif not param["required"]:
                shown = str(default)
            lines.append(
                "\t\t\t[%s, %s, %s, %s],"
                % (
                    gd_string(param["name"]),
                    gd_string(param["units"]),
                    gd_string(str(shown)),
                    gd_string(param["meaning"]),
                )
            )
        lines.append("\t\t],")
        lines.append("\t\t\"assumptions\": [")
        for note in page["assumptions"]:
            lines.append(f"\t\t\t{gd_string(note)},")
        lines.append("\t\t],")
        lines.append("\t},")
    return lines


# Placeable items that are enclosures rather than simulated records.
# They have no ports of their own -- what goes inside them does.
EXTRA_PAGES: dict[str, dict] = {
    "cabinet": {
        "title": "Control Cabinet",
        "tier": "control",
        "summary": (
            "An empty enclosure with bare DIN rails. It simulates "
            "nothing on its own: open the door, press EDIT, and fit it "
            "out with a supply, a processor, I/O cards, relays and "
            "terminal strips. Those modules are the real records, and "
            "the internal wiring between them is landed for you as "
            "hidden kernel wires. Field runs terminate on the flank "
            "markers; a channel with no card behind it is dead, and so "
            "is the whole rack without 24 V."
        ),
        "ports": {},
        "equations": [],
        "params": [],
        "assumptions": [
            "The enclosure itself has no thermal, ingress or space "
            "limit: any module fits anywhere on the rail.",
        ],
    },
}


def main() -> None:
    samples = sample_components()
    pages = catalog(samples)
    by_key = {page["key"]: page for page in pages}
    meanings_by_key: dict[str, dict[str, str]] = {}
    for component in samples:
        spec = spec_of(type(component))
        if spec is not None:
            meanings_by_key[spec.key] = dict(spec.ports)
    unmapped = sorted(set(by_key) - set(TYPE_IDS) - set(EXTRA_PAGES))
    if unmapped:
        raise SystemExit(
            "these specs have no in-game type id, add them to TYPE_IDS: "
            + ", ".join(unmapped)
        )

    lines = [
        "class_name SimLibraryData",
        "## GENERATED FILE — do not edit by hand.",
        "##",
        "## Written by tools/generate_library.py from the EquipmentSpec",
        "## declarations in sim/*.py, which are the single source of truth",
        "## for equipment prose and equations. Edit a SPEC and re-run the",
        "## generator; editing this file just means your change is lost the",
        "## next time somebody does.",
        "##",
        "## Port NAMES, KINDS and DIRECTIONS are deliberately absent: the",
        "## library reads those off a live component so a page can never",
        "## describe I/O the game does not actually have.",
        "",
        "const PAGES := {",
    ]
    for key, type_ids in TYPE_IDS.items():
        page = by_key.get(key)
        if page is None:
            continue
        lines.extend(emit_page(page, type_ids, meanings_by_key.get(key)))
    for type_id, page in EXTRA_PAGES.items():
        lines.extend(emit_page(page, [type_id], page["ports"]))
    lines.append("}")
    lines.append("")

    OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)} — {len(pages)} specs, "
          f"{sum(len(v) for v in TYPE_IDS.values())} placeable types")


if __name__ == "__main__":
    main()
