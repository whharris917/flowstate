# flowstate

A first-person factory-building simulation game set aboard a massive starship. The player builds a pharmaceutical plant from raw materials and bare bulkheads, one sensor, relay, and wire at a time, guided by an AI that can only perceive what the player instruments.

**Read `docs/GDD.md` before doing any design or implementation work.** It is the single source of truth for vision, story, world, systems, progression, and build order.

## Roles
- The human is the **creative director**. They set vision, review builds, and report what they saw. They do not write code and should not be asked to.
- Claude is the **entire development team**: architecture, code, scenes, tools, tests, docs. Make decisions, explain them briefly, and ask only when a choice is genuinely creative rather than technical.
- The director cannot see Claude's screen. Claude CAN see rendered output when needed: run a probe scene windowed (a real window briefly appears) that screenshots the viewport to `user://*.png` and read the PNG (`%APPDATA%\Godot\app_userdata\flowstate\`) — see `game/world/hud_probe.gd`. Use this to verify visual/UI work instead of guessing. Claude must also run Godot headlessly (see Environment) before every delivery: `--import` to catch parse errors, then a `--quit-after 600` smoke run to catch runtime errors and read the kernel self-check. Deliver things the director can open and press play, then ask for a build report ("what did you see, what felt wrong").

## Environment (Windows)
- Python lives in `.venv` (created from `~\anaconda3\python.exe`, 3.11). Always run Python via the venv: `.venv\Scripts\python.exe` or after `.venv\Scripts\Activate.ps1`. Never rely on a bare `python` or `py` on PATH — they do not exist on this machine.
- Shell is PowerShell. Use PowerShell syntax in commands.
- Godot 4.7.2 is installed via winget (2026-08-29). Exe: `C:\Users\wilha\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe` (also on PATH as `godot` in fresh shells). The director opens `game/project.godot`; Claude authors `.gd`, `.tscn`, `.tres`, and `.gdshader` files as text and validates them headlessly: `& $exe --headless --path <repo>\game --import`, then `--quit-after 600` smoke runs of BOTH worlds — the default scene (sandbox) and `res://world/hall.tscn` (pass the scene path as an argument). GDScript gotchas that the editor catches but text-authoring misses: untyped for-loop variables break `:=` inference; RefCounted back-references (component<->port style) leak — check exit output for "resources still in use".

## Layout
```
flowstate/
  CLAUDE.md
  docs/            GDD.md and design notes
  sim/             Engine-independent Python simulation kernel (design validation, reference implementation)
  tests/           pytest for sim/
  tools/           Python scripts (generators, data conversion, checks)
  game/            Godot 4 project
    project.godot
    sim/           GDScript port of the kernel; NO node inheritance, pure classes
    world/         Scenes: districts, ship structure
    components/    Placeable equipment scenes (tank, pump, relay, sensor...)
    ui/            Panel view, HMI, logic editor
    player/        First-person controller, interaction
    data/          Component definitions, inventory, tier tables
```

## Architecture rules
- **The sim is data plus a tick.** Simulation logic lives in plain classes with declared inputs/outputs and `tick(dt)`. Nodes only render and take input. No game logic in `_process`.
- Two layers: **process** (fluid, pressure, level, temperature, composition) and **signal** (24 V discrete, 4–20 mA analog, later fieldbus). Components bridge them.
- Fixed-rate deterministic tick. No frame-rate dependence.
- Every visual object in the world is backed by a sim record. No decorative equipment.
- **The historian is first-class.** Every sim variable is a tag, sampled every tick into a time-series record. All displays — trend pages, HMIs, gauges — read from the historian or live sim state. Displayed data is never faked, smoothed, or hand-tuned; it must be an accurate reflection of simulated process conditions, as if read from a plant historian (PI / DeltaV Process History View).
- **Every feature ships visual, as a GUI.** A delivery is not done until the director can *see* the process behave: during the Python phase, a live browser GUI (stdlib http server + HTML/JS) with operator graphics and trends of the real historized data; in-game HMI trends later. Include how to launch it.
- Save/load serializes the sim graph. Keep it working from the first playable.
- Placeholder art only (boxes, capsules, flat color) until systems are proven.
- Prototype new mechanics in `sim/` (Python) first when it is cheaper to validate there; port to GDScript once the design is settled.

## Conventions
- GDScript: static typing everywhere (`var level: float = 0.0`), snake_case, one class per file, `class_name` on sim classes.
- Python: 3.11, type hints, pytest, no heavy dependencies.
- Commit small, descriptive, and often. Never commit `.venv/` or `game/.godot/`.
- When delivering a build, end with: what changed, how to test it in Godot, and what to look for.

## Current phase
See "Build order" in `docs/GDD.md`. Step 1 (Python kernel + live GUI demo) is done. Step 2 (Godot engine foundations) is in progress: first playable exists — FPS controller, look-and-interact, the step-1 plant in 3D on the GDScript kernel port, in-world HMI trend, save/load (F5/F9). Grid placement and player-made connections are done; still to come in step 2: panel UI. Engine choice was re-confirmed with the director on 2026-08-29 (Unity considered, Godot chosen).

Two worlds share one bootstrap (`world/world_base.gd`): `world/sandbox.tscn` is the default scene — an infinite outdoor plane for sandboxing and development (director's call, 2026-08-30) — and `world/hall.tscn` is the parked manufacturing hall + aseptic annex, kept working and bootable (open it in the editor and Play Current Scene). The annex/air cascade only builds in the hall (`Plant.build_suite`); saves are per-world (`save_sandbox.json` / `save_hall.json`).
