# flowstate

A first-person factory-building game set aboard a starship. The player builds a pharmaceutical plant from raw materials, one sensor, relay and wire at a time, advised by an AI that sees only what the player sees and controls nothing.

- `docs/GDD.md` is the source of truth for vision, story, world, systems and progression. Read it before design or implementation work. It sets no build order; sequencing is a working decision made here.
- `docs/history.md` is the full session-by-session record: why each rule exists, measurements, findings. Look there for background. New history goes there, not here.
- This file holds rules and current state only. Keep it under 5,000 words, in the plain register below.

## Communicating with the director

The director is the creative director: fluent in process control, does not code, reviews builds by playing them.

- Every message is an executive summary: a few sentences, answer first. What changed, whether it works, what to look at, what needs their call.
- Report what they can do and see in the game. Leave out test counts, timings, iteration counts, file lists and how a bug was found. Give a number only when it changes a decision.
- State each fact once, in plain words. Describe behaviour rather than using a term of art ("running total", not "totalizer"); in-game text too.
- Avoid: dramatic framing; contrast for effect ("not X, just Y"); giving objects agency ("load-bearing"); verdicts; asides about yourself; openers ("Certainly", "You're right"); hedges ("It's worth noting"); narrating an action before taking it; softening adverbs (simply, just, actually, genuinely, quietly); recaps of work they watched; closing summaries; habitual next-step menus.
- A defect in what the sim computes (lost mass, a wrong resistance, stale derived state) leads the message and is fixed or escalated with a recommendation. Never mention one in passing or offer it as an option.
- During a walkdown, acknowledge each observation in a line and wait. Fixes start when they say so.
- Player-facing prose (library pages, campaign briefs) is drafted by hand for their review, never generated from code.
- Commit messages use the same register. A delivery ends with: what changed, how to test it in Godot, what to look for.

Full versions: memory files `concise-technical-diction` and `executive-summary-messages`.

## Roles

- Director: sets vision, reviews builds, reports what they saw. Never asked to write code.
- Claude: the whole development team. Decide technical questions and explain briefly; ask only when a choice is creative.
- Claude can see rendered output: a windowed probe scene saves screenshots to `user://*.png` (`%APPDATA%\Godot\app_userdata\flowstate\`) and Claude reads them (`game/world/hud_probe.gd` is the pattern). Use this for visual work instead of guessing.

## Environment (Windows)

- Python: `.venv\Scripts\python.exe` only (3.11). There is no bare `python` or `py`.
- Shell: PowerShell 5.1. Commit messages go in single-quoted here-strings with no embedded double quotes. Never edit text with `Get-Content | Set-Content` or `-replace` (they corrupt UTF-8 and add BOMs); use Edit or a scratch Python script. In the Bash tool a quoted heredoc breaks on any apostrophe in its body; use Write or a scratch `.py` in the scratchpad.
- `open(path, "w")` empties the file before it checks its other arguments. Commit work in progress before any bulk edit, and keep patch scripts until their work is committed.
- Before writing a new script, grep for its `class_name` and filename: Write overwrites silently.
- Godot 4.7.2: `C:\Users\wilha\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe` (`godot` on PATH in fresh shells). Claude writes `.gd`, `.tscn`, `.tres` and `.gdshader` as text; the director opens `game/project.godot`.
- Reference scenes for what "realistic" means, outside the repo and not game code: `C:\Users\wilha\projects\godot-demos` (official demos), `C:\Users\wilha\projects\grass-demo` (`godot --path <dir> res://scenes/main.tscn`), `C:\Users\wilha\projects\jungle-demo\JungleDemoV2.0_Windows.exe` (the director launches it).

### Checks

- **Per change** (director's rule): `& $exe --headless --path <repo>\game --import`, then one headless smoke, `--quit-after 600` with the scene named (the default scene is the title menu, which quits at once headless). Worlds: `res://world/sandbox.tscn` (the showcase), `hall.tscn`, `campaign.tscn` (the milestone ladder check), `blank.tscn` (kernel self-checks), `maine.tscn` (landscape check and the exercises). The director launches the game to check fixes; do not add automated tests beyond what a change needs.
- If `--import` reports only `Could not resolve class "X"`, run `--check-only -s res://path/to/changed.gd` on each changed script to find the real error.
- Each smoke prints the kernel self-checks, `hydraulic solves that did not converge since t=0` (keep at none), `lines priced by their length and size: all`, the four routing counts (overlaps, crossings, unsupported, through solids) and a startup time. Watch the exit output for "resources still in use".
- **Windowed probes** take minutes. Run them once per batch of related edits, before a delivery that needs a screenshot, and at the end of a session. `showcase_probe.tscn` (about 4 min; `FLOWSTATE_SOAK_MIN=2` shortens its soak): screenshots, the soak's material balance, walks up every stair. `hud_probe.tscn`: graphics presets with frame rates, frame pacing, noon/dusk/night shots; read these before touching lighting. `maine_probe.tscn`: the Maine vantages. `library_probe.tscn`: pages missing prose, an editorial to-do list rather than a failure. `FLOWSTATE_PROBE_SCENE=<scene>` points a probe at another world.
- Every probe sets `MouseMode.probe = true` first in `_ready`. All mouse capture goes through `MouseMode.capture()` (`player/mouse_mode.gd`); never write `Input.MOUSE_MODE_CAPTURED` directly.
- A temporary probe to look at one thing several times is fine; delete it before committing.
- Full pytest takes about 4 minutes; `test_hydraulics` and `test_flow_network` are fast.
- Diagnostics: `FLOWSTATE_NET_DUMP=<t>` writes the network at time t to `user://net_dump_<t>.json`, and `tools/replay_network.py <dump>` replays it in the Python kernel with a trace. `tests/data/*.json` are networks that once failed; `tests/test_replayed_networks.py` requires them to converge. `FLOWSTATE_ROUTE_DEBUG=1` prints lane costs and laid paths. `FLOWSTATE_SYNC_SCAN=1` runs the scan on the main thread. `tools/drip_rig.py` and `tools/gravity_drain_rig.py` compare kernels across trees via `PYTHONPATH`.

### GDScript and shader gotchas

- Untyped for-loop variables break `:=` inference.
- A ternary of two array literals is an untyped Array: declare typed, then assign.
- `var x := <Variant comparison>` cannot infer bool: annotate it.
- RefCounted back-references (component to port) leak.
- A Packed*Array taken out of an Array or Dictionary is a copy; `dict[k].append(x)` changes nothing. Write it back or hold a plain Array.
- A method call costs about a dozen float operations; hot loops ask each object for several answers per call.
- `%g` is not a format specifier; use `%f`.
- A colour literal in a shader is linear; a `source_color` uniform is converted. Literals go through `lin()` in `granite.gdshaderinc`.
- Clamp the base of every `pow()` in a shader: a negative base gives NaN, which the glow turns into flickering blobs.
- `SurfaceTool.append_from` of a non-indexed source after an indexed one draws nothing of it. `MeshMerge._indexed` indexes every source first.

## Layout

```
flowstate/
  CLAUDE.md
  docs/            GDD.md, history.md, platform_exposition.html, routing_explained.html
  sim/             Python reference kernel (design validation)
  tests/           pytest for sim/
  tools/           Python scripts (audio generator, replay, rigs)
  game/            Godot 4 project
    project.godot
    sim/           GDScript kernel; pure classes, no node inheritance
    world/         Worlds, landscapes, probes
    components/    Equipment views
    ui/            Panels, HMIs, editors
    player/        First-person controller, interaction
    data/          Component definitions, milestones
```

`docs/platform_exposition.html` and `docs/routing_explained.html` are the long-form reference for the platform and for routing.

## Architecture rules

- **The sim is data plus a tick.** Logic lives in plain classes with declared inputs and outputs and `tick(dt)`. Nodes only render and take input; no game logic in `_process`. The sim never touches a node (no signals or callables out of `sim/`). Fixed-rate, deterministic tick.
- **Layers.** Process (material streams) and signal (24 V discrete, 4–20 mA analog). Components bridge them. Port kind `ITEM` carries countable things (vials) between filling-line parts, moved once a scan after the signals.
- **Rich streams, simple insides** (director's call). A stream carries rate, temperature, species fractions and suspended solids, conserved through merges, splits and vessels. Inside a unit: a few algebraic and first-order relations. No discretized transport, VLE or film coefficients. Six species on a 1 L = 1 kg basis.
- **Pressure drives flow; nothing asserts a rate** (director's call). Every material port is a node of a hydraulic network, every line a branch. Headers and vessels fix pressures, pumps add head on a curve, valves follow the valve equation, and the flow is whatever satisfies all of it. One material port kind. A tee is a placeable fitting (`tee_split`, `tee_mix`) whose nozzles share one node. `PROCESS_LEVEL` and `PROCESS_PRESSURE` are instrument taps only.
- **No draw wires.** A port that exists so the arithmetic closes is the smell.
- **One line per nozzle, one cable per terminal.** `Plant.connect_equipment` refuses a second visible wire on a port; split with a tee. Instrument taps and hidden wires are exempt. A feeder has numbered ways (`Plant.free_way`).
- **Elevation.** Node pressures are piezometric (P + ρgz). Every record with an `elevation_m` property re-derives it from where it stands at placement, on a move and on a load through `Plant._apply_elevation`; `NOZZLE_ELEVATION_TYPES` gives an inline type's nozzle height. Any value derived from a record's position or host (elevation, a transmitter's range) is re-derived by one rule on move, resize and load, never kept from placement and never by a list of types. A boundary node's pressure is refreshed in `update_hydraulics`, not only at build.
- **Every gauge shows static pressure**, converted at its own height. A new instrument reading a liquid node subtracts ρgz at its elevation.
- **Tank nozzles** are boundary nodes where they stand, at `P_headspace + ρg(z + max(depth, h))`, each with a `NozzleResistance` branch: submerged it carries flow either way; above the liquid it vents and passes nothing out, so a tank keeps a heel below its outlet. The height is set in one place, `TankView._place_nozzle`. Reactor and crystallizer keep fixed roof and floor nodes.
- **Sizes match automatically** (director's call; never a CONFIGURE row for this). A nozzle fitting takes its line's bore (`Plant._sync_nozzle_bores`, DN50 with none), and a tank nozzle's Cv scales with that bore's area. Inline fittings (`PlantFactory.INLINE_FLUSH`) take the largest material line on them (`_sync_bores`); tees and valves keep the `dn` they were bought at, changed only in CONFIGURE. Different sizes meet through a reducer.
- **A line's resistance follows its length and size**: `Plant._sync_line_resistance` prices the drawn path with `pipe_k` (Darcy-Weisbach, f 0.02, plus 0.3 velocity heads per right angle) on every lay, cut, move, resize and load. Nothing sets a line's resistance by hand; a line that must pass more is a bigger line. `LINE_SIZES` runs DN1 to DN150. A fixed fitting resistance is a hidden line size.
- **Sizing basis.** `cv_lps` is flow at full open across a 1 bar drop. Pump curve `H = H0(1 − (Q/Qmax)²)`, runout capped at 1.35× rated; cavitation is a suction-pressure taper.
- **The equipment library is hand-authored** in `game/sim/sim_library_data.gd` under the director's review. Never generated; `tools/generate_library.py` must not come back in any form. Port names, kinds and directions are read off the live record (`sim_library.gd`). The Python `EquipmentSpec` documents the Python kernel only.
- **Every visual object is backed by a sim record.** The one exception is Unit 500, the geometry gallery (`world/gallery.gd`); do not add another. Scenery (trees, landscapes, sky, heighliner) is art with no records.
- **The historian is first-class.** Every sim variable is a tag, sampled once a second of sim time. Displays read the historian or live state. Displayed data is never faked, smoothed or tuned.
- **Every feature ships visual**: the director must be able to watch the process behave in game.
- **Save/load serializes the sim graph** and must always work. `Plant.snapshot()`/`restore()` also back undo.
- **Prototype in Python** (`sim/`) when that is cheaper, then port. Both kernels give the same answers; solver changes land in both.

## Hydraulic solver rules

Each of these cost real time; the stories are in `docs/history.md`. They hold in both kernels.

- Damp Newton steps: halve until the block's residual improves by Armijo's margin (`_improves`) and no node swings to the other side of its balance without at least halving (`accepts` / `_accepts`). Either alone lets a square law's mirror image through: a dead leg behind a throttled valve flips for ever.
- `_square_law_flow` and `_square_law_slope` regularise consistently.
- "Does it conduct?" (`is_conducting`) and "what is its slope?" (`conductance`) are separate. A shut check or dry nozzle reports the open side's slope while flow pushes toward its crack, and nothing while flow is pulled away (`_pulled_away`); connectivity treats it as a wall. A `FixedFlow` has zero slope and is not a wall.
- An internal node with one branch carries no flow: join it to a nozzle node or make it a fixed boundary.
- An imposed flow (`FixedFlow`) and a pump curve taper to nothing over the 20 kPa above hard vacuum, with the taper's derivative in the Jacobian.
- Record flows before settling islands. An unreachable node keeps its row with a small tie (`ISLAND_TIE`).
- Plateaus are crossed by stepping to a wall's crack (`crack_target`, `_plateau_step`, two landings: passing and at rest; the vacuum floor for a pull). A plateau step may be forced once per solve.
- When no halving helps, try lengthening (`LENGTHENINGS`). A failed step lands at its shortest attempt, never back at the start.
- Convergence is judged per node, relative to what it passes. Every solve reports `converged`; misses are counted from t = 0, printed by every smoke, and raise HYDRAULICS NOT CONVERGED.
- A branch whose flow depends on its ends differently (the regulator) reports a slope per end (`two_sided`).
- Solve block by block (`_blocks`, `_block_step`); a block stops after two failed steps in a row. A converged solve takes one polish step.
- A rebuild carries each nozzle's pressure into the new network by port path (`net.warm`); saves carry them too. A cold solve gets `COLD_ITERATIONS`. The seed is the plant-wide mean of fixed pressures.
- GD solver: banded solve after reverse Cuthill-McKee ordering, no pivoting; `SimBranch.evaluate(pa, pb)` answers flow, slope and connectivity in one call.

## Building and editing

- Left click selects movable equipment; clicking it again deselects. A double click opens the device menu (I/O and CONFIGURE tabs); every change to equipment goes through it. A right-hold carries; the wheel with the right button held turns it 15° a notch. A right click only cancels or deselects and never opens a menu. Editing stays in first person; handles are dragged by aiming.
- CONFIGURE rows come from `PlantFactory.CONFIG`, keyed identically to `_params_for`, or an edit is lost on reload.
- Click any port fitting to start a line; it finishes on a port of the other kind. E ends a line open (an open cap that vents to the air at its height and spills). A right-hold on a vessel nozzle moves it. A line meets a fitting at its outer face (`Plant.marker_face`).
- Lines are edited per leg. A click selects a straight and shows a gold cube at every corner of the line. The cubes stand on the player's own route (`Plant.wire_own_path`) and match waypoints exactly; no proximity rules. A click on the selected line plants a corner; drag a cube to move it; Ctrl-drag duplicates; a right press deletes a corner and re-routes the gap; a middle click locks a corner; Ctrl+wheel raises a cube or a level straight 0.25 m. A right-hold pulled across a line cuts it and caps both ends.
- Inline placement: an inline type aimed at or within 0.75 m of a line cuts itself in (`Plant.place_inline`). An inline element whose lines run straight through it slides along the line with a right-hold. A pump above the floor gets a pedestal.
- Undo and redo: Ctrl+Z, Ctrl+Y (or Ctrl+Shift+Z), at the plant (`Plant.checkpoint`; a gesture is one step; 50 deep).
- Build palette: Tab opens the page rail and cards; B enters or leaves build mode; number keys pick from a nine-slot hotbar the player assigns (saved in `user://settings.json`). A page holds at most 9 entries; adding a page means changing `_catalog()`, `_is_equipment_page()`, `page_names` and the page count in `build_controller.gd` together.
- An interact body's `view` meta names the node the player acts on.
- Put a control station where the operator stands, facing the walkway.
- User-facing terms: inlet and outlet (never suction, battery limit, in_flow); pump modes Manual On / Off / Auto.

## Routing

- **Loose cables** (`Plant._cable_route`, `CableDrape`): a 24 V or signal cable drops from each terminal in a curve and lies on the floor along the router's route round solids, straight between corners with rounded bends. No lanes, bridges, supports, crossing or overlap rule; pipes do not route round cables; the player walks over them. The one rule it keeps is RunClearance's. A cable whose ends stand on different floors keeps the router's route off the floor. Its waypoints are its floor corners. A sleeved cable's waypoints are its two tails' corners, found by the router when it is threaded and then baked; split between the tails where both come out shortest (`Plant._tail_split`). A sleeve is edited like a line: every point of it is a cube (`Plant._sleeve_of_view`; the `wire_*` queries answer for it).
- **A line routes once.** When laid it is routed (corners, lanes, bridges), then baked (`Plant._bake`, `visual["fixed"]`): its waypoints become its drawn corners and it is never routed again. A later line routes round earlier ones (the order rule); existing lines are not recalculated.
- **Direct line.** Horizontally any bearing, the shortest path; elevation changes are vertical risers; drop first, run low. No turn sharper than 45° between straights; the square leg goes in before the search.
- `world/run_clearance.gd` (`RunClearance`) is the only answer to "may a run pass here?". Nothing else probes for solids.
- An impossible route is refused with its reason (`Plant.connect_equipment_checked`), never threaded through. Code-laid lines are laid regardless and counted in the report.
- **Support rule:** no span over 3 m unsupported (`SupportCheck`). Pipe stands are added automatically where a floor is within 6 m below; a riser over 3 m needs a column. Keep showcase pipe waypoints near y 0.35 and tall-tank fill nozzles low.
- The director audits for any crossing. Quote the four counts when routing changes.
- Routing is improved through simple configurations on the Maine site (`world/routing_exercises.gd`), one at a time, each examined by the director; never by fixing the showcase. The showcase's remaining through-solids are layout debt awaiting the director's call.
- **Stairs.** A flight is 4.4 m long, rises 3.03 m and ends in a 0.6 m landing; the player is a 0.35 m capsule with no step-up. (1) A deck a flight serves sits on beams at 2.7 or 5.7 m (deck top 3.025 or 6.025), never 3.0. (2) The flight's top edge is 0.1 m inside the deck edge. (3) No beam crosses the flight elsewhere. (4) The foot needs 0.4 m of floor behind it, so a flight on a platform needs 4.8 m of platform. (5) Keep the 4.4 m strip in front of a flight from grade clear. (6) The deck above a flight is open over its whole run: give each flight a bay the next level leaves open (the gallery tower is the example). The showcase probe walks every flight with real input.

## Art, sound and performance

- **Realism is the art direction.** Colour chooses the finish (`ViewUtil.flat`): light low-saturation grey is brushed stainless, dark grey painted steel, colour enamel, alpha glass; `ViewUtil.matte()` for concrete and painted walls. Choose colours by what a part is made of. Keep the screen calm: realism is finish and light, not more objects. Judge in probe screenshots, never by guessing.
- **Merged meshes.** `MeshMerge.merge_view` bakes whatever a view builds and forgets. A part the view will move, hide, retint or replace must be held in a member variable (or an array held by one); anything else is baked.
- Floating labels (`ViewUtil.label`) show only on hover; `ViewUtil.plate` is engraved text that stays.
- **Sensory layer** (the director's favourite feature; maintain it on everything new). Every sound and effect comes from a real sim state edge, never a timer: `EquipmentAudio.make()` loops, `play_once()` on edges, `VaporPlume`, the spill jet, overflow and puddles. Audio is generated by `tools/generate_audio.py`; regenerate, never hand-edit WAVs, and give each new sound its own RNG so existing files stay identical.
- **Performance target:** the showcase at 60 fps on Low on the director's laptop (Ryzen 7 5700U, integrated Vega 8, 1600×900). Medium is the default preset. No FSR 2 on an integrated GPU. The scan runs on a thread (`Plant._start_scans`) and is joined before anything reads or writes the sim. Measure with the windowed HUD probe, best of two runs, never the headless loop profile.
- Anything placed in a world must sit inside the 3.8 km star dome.

## Conventions

- GDScript: static typing, snake_case, one class per file, `class_name` on sim classes.
- Python: 3.11, type hints, pytest, no heavy dependencies.
- Comments describe the code as it is now: what it does and, where not obvious, why, as a present-tense rule. No dates, attributions, prior behaviour or how a bug was found; that goes in the commit message and `docs/history.md`.
- Pressure-kernel tests never name a flow rate. Check balances against meters (`Source.total_l`, `Drain.total_l`) with the `tests/conftest.py` helpers (`wire_power`, `wire_supply`, `open_drain`; `feed` and `supplied_stream` for a unit on the bench). Commands are wired (`Duty`, `Contact`), never poked. A PLC needs a feeder and a power supply.
- Ladder lessons: a sequence step's exit switch is single-point; a TON's done bit updates at the end of the scan.
- Commit small and often. Never commit `.venv/`, `game/.godot/` or `docs/design_guidelines.docx` (the director's file). Ask before pushing.
- **New equipment type checklist:** (1) Python class in `sim/` with pytest; (2) its `EquipmentSpec` with a meaning for every port and an honest assumptions list; (3) GD mirror in `game/sim/` with `state_dict`/`apply_state` and `build_hydraulics`/`update_hydraulics`/`supplied_stream`/`tap_ports`; (4) view in `game/components/` with describe()/use(), sim-edge audio, members held for anything it will change; (5) `plant_factory.gd`: catalog entry, FOOTPRINTS, Y_OFFSETS, CONFIG rows, PORT_ANCHORS, make_record and make_view arms; (6) `plant.gd`: place() arm, `_params_for`, `elevation_m` if its pressures depend on height; (7) `asset_preview.gd` arm; (8) a library page draft for the director; (9) a demonstration (Maine exercise or showcase, as the director wants) and a rung's `unlocks` in `data/milestones.gd`, or the campaign can never build it; (10) pytest, `--import`, a smoke, the probes, and read the screenshots.

## Where things stand

**Worlds** (title screen `world/menu.tscn`; each saves to its own file):
- **Showcase** (`world/sandbox.tscn`, built by `showcase.gd`): the home loop, pipe rack, Unit 100 level loop, MCC room, **Unit 300** (the full synthesis train with a closed solvent recycle), **Unit 400** (a PLC-sequenced transfer tower with HMI-400 and a local station), Unit 500 gallery, inside the hall.
- **Maine coast** (`world/maine.tscn`): the blank map's rules on a landscape (`landscape.gd`, `maine_coast.gd`) with a river and the heighliner as scenery. It hosts the exercises: routing, the drip demo (small-bore devices on tubing, on the home pad), line pressure gauges, and the vial filling line built from parts (`world/fill_line_demo.gd`, 40 vials a minute).
- **Blank map**, **campaign** (a Satisfactory-style milestone ladder, `data/milestones.gd`; journal on J), and **the hall** (parked, kept bootable).

**What exists:** both kernels on pressure with species streams; the control tier (PLC with ladder editor, PID, valves, relays, cabinets built module by module, junction boxes and multicores, stations); the process train (boiler, exchanger, reactor, crystallizer, centrifuge, dryer, still, vacuum lock, vial filler); small-bore family; filling-line parts; alarms; trend screens; the material balance screen; save/load; undo; graphics presets.

**Showcase routing counts:** 0 crossings, 0 overlaps, 0 unsupported, 19 through solids (layout debt). Maine: all 0.

**Run sizes** (`Plant.run_radius`, by the port's kind and voltage class): process lines by bore, 480 V feeders 50 mm, 24 V and signal cables 8 mm. A signal or power terminal is a cable gland sized to its cable (`PlantFactory._marker_bore`); RunClearance gives a cable a 5 mm margin, a pipe 30 mm.

**Cable plan** (director, 2026-09-24), in order: (1) loose cables, done; (2) sleeves, done: `run_sleeve` on the routing page, laid on the floor by clicks; T on a loose cable threads it into the sleeve whose ends are nearest its terminals (within 8 m), T again takes it out (`Plant.toggle_sleeve`, `_cable_carriers`, saved as the wire's `sleeve`); the sleeve grows with its cables; a sleeve can be clear (E on it: tinted glass, the cables seen inside); the filling room's field cables run in SL-601, clear; the Unit 400 multicore is still its own thing; (3) trays, begun: T threads a cable into a tray as into a sleeve (`Plant._trayed_route`): in at the tray point nearest its source, on the tray floor in a slot of its own, out nearest its destination; trays 400 and 150 mm, cables side by side then in layers; the filling room's 24 V leads run in CT-601. Conduit (`run_conduit`) takes cables end to end like a sleeve, the cable held to its bends (`_tight_corners`); the drip demo's two cables run in CD-201. Trays and conduit refuse a cable past 40 % fill (`_carrier_capacity`); the Maine smoke prints each carrier's fill. Still to do: a sleeve into a tray or conduit, and cables between floors (a showcase layout question for the director).

**First things next session:**
1. **Filling line, open for the director:** the look at bench scale beside full-size conduits and four free-standing 24 V supplies, the four crossings at the cabinet, nine library page drafts, the campaign rung.
2. **Standing review items:** the drip demo with tube-sized nozzles; the small-bore views (first drafts; coil and cable anchors sit where a DN50 body would put them); the two documents in `docs/` and their list of five spec-prose drifts; the walk report on the merged showcase and hover-only labels; the showcase's startup time.

**Known gaps:**
- Mass does not close across the steam generator: its drum is a fixed-pressure boundary that makes up whatever is drawn. Closing it needs a real drum inventory and changes the boiler's dynamics; the director's call.
- Orifice and rotameter carry no elevation (nothing of theirs depends on it). A pressure gauge on a liquid line exists only as the line gauge.
- Readouts other than valves, tees and caps print `%.2f L/s` and read 0.00 on a micro line.
- Deferred by the director: a geometry-constraint tool, DWSIM as an offline reference (never in the game), acute-angle rules beyond 45°.
