# Working Title — Game Design Document
**Version 0.2 — 1 September 2026**
**Creative Director:** you · **Development:** Claude

---

## 1. Vision

A first-person factory-building simulation set aboard a massive starship, where the factory does not exist yet. The player builds a pharmaceutical plant from raw materials and bare bulkheads, one sensor, relay, and wire at a time, advised by an AI that knows the chemistry, sees only what the player sees, and controls nothing.

**One sentence:** *Nobody designed this factory. They packed the periodic table into a ship, added an AI, and sent one person to figure it out on the way.*

**Pillars**
1. **Detail is the game.** You don't place "a machine." You place a tank, a level switch, a relay, a pump, and the wire between them — and it works or it doesn't for reasons you can trace.
2. **Manual first, then automate.** Every automated system was once a chore the player did by hand. Automation is earned by suffering the manual version.
3. **Awe.** The scale of the ship, the hold, and the plant should make the player feel small, and then feel responsible.
4. **One integrated system.** Life support, power, thermal, and the medicine plant share resources. The ship is one machine with a person inside it.

**Tone:** lonely, sacred, industrial. Silence, hum, reverb. Competence as heroism. The illness the medicine treats is deliberately abstract; the drama is the plant.

**Reference points:** Satisfactory (build loop, scale), Project Hail Mary (solo mission, ship-as-world — differentiated by being a *builder's* story, not a mystery), Shenzhen I/O and Stormworks (logic editors as play), Moon and Silent Running (tone).

---

## 2. Story

### 2.1 Premise
A medicine is needed by a population far away that cannot make it. There was no time to manufacture it and ship it. There was only time to build a ship, fill it with every raw material, reagent, instrument, and spare part a synthesis might need, install an AI with the route and the theory, and send one person.

The process was never run beyond lab scale. The route is paper. The plant is unbuilt. The hold is full.

### 2.2 The player
Not the ideal candidate — the available one. Competent with their hands, some industrial background, no experience with *this*. Knows what a wrench feels like; does not know bioprocessing. The AI knows theory the player lacks; the player knows the world the AI cannot touch.

### 2.3 The AI
The player's advisor, not an operator. It carries the route, the theory, and the ship's documents. It sees only what the player sees and controls nothing: no instrumentation of its own, no actuators, no hand on any valve, and that never changes. The factory is the player's.

The AI is a mentor, a voice in the silence, and fallible. It reasons from incomplete data and an unvalidated route. It is sometimes confidently wrong. The player learns to distrust a guess and demand a measurement.

### 2.4 Arc
- **Act I — Hands.** Survive. Keep your own air. Learn the isolator. Restore the tram. Enter the hold.
- **Act II — Eyes.** Instrument the ship. Build the first plant. Discover that scale-up breaks everything.
- **Act III — Agency.** Automate the plant end to end. The ship runs on the player's logic. The player goes outside because they want to.
- **Arrival.** No countdown. The ship arrives when it arrives; the ending is how many doses are on board. A well-run ship arrives full. A struggling one arrives with something. There is no "lose."

### 2.5 The medicine
A **biologic** (a protein product from a cell line) as the main line, with a **small-molecule side plant** making buffers, solvents, cleaning agents, and a stabilizer or adjuvant. The cell bank is frozen somewhere in the hold. Its freezer is the first thing the player fails to instrument, once, early, and never again.

Why both: bioprocessing gives biology, fragility, and contamination drama; chemical synthesis gives classic pressure/flow/temperature control and big equipment. Two factory personalities, one plant.

---

## 3. World

### 3.1 The ship
Massive. Minutes to cross, not seconds. A **spine** — a central corridor and tram tunnel running bow to stern — with **districts** branching off. The player learns the ship like a city: by the line and the stops.

| District | Character | Role |
|---|---|---|
| Habitat | Small, warm, human-scale | Home, sleep, food, story documents |
| Life Support | Utilitarian, humming, cramped | The first plant: O₂, CO₂, water, thermal |
| Reactor & Power | Hot, loud, restricted | The budget everything else draws from |
| The Hold | Cathedral of raw material | Inventory, awe, the ship's memory |
| Process Decks | Bare structure, unfinished | The player's canvas: upstream, downstream |
| Fill-Finish | Clean, white, quiet | Isolators; the last step; Act I tutorial and Act III climax |
| Hangar | Cavernous, foil-wrapped modules | Prefab equipment waiting for power |
| Exterior | Silent, vast, red-glowing radiators | Heat rejection, tankage, sensor booms, thrusters |

Navigation is diegetic: deck numbers, frame numbers on bulkheads, pipe color codes, cable trays you can follow to find where a wire goes.

### 3.2 Designed emptiness
A rushed ship has unfinished volume: bare structure, mounted equipment never connected, prefab modules still in shipping foil. Empty space is marked as deliberate — it is exploration reward, story, and future build area. Accidentally empty space is forbidden.

### 3.3 The hold (vignette)
Earned, not given. The player spends Act I in cramped spaces, then passes a large door with a long cycle and pressure equalization, and it opens onto something the camera cannot fit.

- Human-scale ruler at the threshold: railing, hand cart, hard-hat rack.
- Far wall not initially visible: haze, distance lighting.
- Enormous reverb, low structural hum, something moving far away.
- Order at scale: rows of drums, IBC totes, super sacks, gas cylinder racks, cable coils.
- No cutscene. The walk is the scene.
- A dead glass-walled control station overlooks the hold, screens dark — the player sees where the brain used to be at the moment they feel the scale.

Every container is a real inventory record: material, lot, quantity, hazard class, expiry, manufacturer. Labels tell story. Getting material *out* is first a manual chore (pallet jack, hand-pump transfer) and later cranes, conveyors, AGVs, and warehouse logic.

### 3.4 The isolator (vignette)
Glove-port aseptic manipulation in first person. The gloves constrain reach; the sightline is through a panel; every action has a procedure. Sterile technique is enforced by consequence, not tooltip: wrong transfer order through the rapid transfer port, reaching over open product, gloves on the chamber floor, skipping decon — and something contaminates. The player finds out later, when a culture crashes or a batch fails. The system does not tell you it was wrong; you have to build the instrumentation that will.

Act I: the player does one or two barely tolerable chores by hand (periodic sampling, manually holding a pressure differential), then unlocks the first transmitter and relay and automates the isolator's own pressure. The first thing automated is the thing that was annoying. Act III: the player returns to the isolator only to install, calibrate, and troubleshoot — same room, different relationship.

### 3.5 The exterior
Rare, deliberate, unforgettable. The whole ship seen from outside, radiators glowing, running lights receding, silence but breath and suit fans. Functionally: radiator panels, external tankage, sensor and antenna booms, thruster quads, reactor heat rejection. Each EVA has a purpose, a checklist, and a consumable clock. The suit is a life-support plant on your body — O₂, CO₂, thermal, power, gauges on the wrist — and rhymes with everything the player has automated inside.

Designed early, built late.

---

## 4. Core systems

### 4.1 Simulation kernel
Engine-independent, deterministic, tick-based (fixed rate, ~20–60 Hz). A graph of components, each a small state machine with declared inputs and outputs and a `tick(dt)`.

Two interacting layers:
- **Process layer** — fluid, pressure, level, temperature, composition flowing between equipment.
- **Signal layer** — 24 V discrete, 4–20 mA analog, later fieldbus.

A level switch reads process and drives signal. A pump reads signal and drives process. Contamination is a process-layer property that propagates and is invisible until measured or until a batch fails.

Every visual object in the world is backed by a sim record. No decorative equipment.

### 4.2 Building and wiring
- Look-at-and-interact raycast model: highlight, press to use. Every switch, valve, panel door.
- Grid-snapped placement with ghost preview and validity coloring.
- Wiring abstracted to keep hundreds of conductors playable: terminal-to-terminal connections in a **panel view**; cable trays as a bulk capacity resource in the 3D world. Physical routing is implied, not hand-drawn, except where it teaches something.
- Panels are real enclosures the player opens, with terminal strips, DIN rail, and labeled wires.

### 4.3 The logic editor
Ladder logic, because it maps directly onto the relay tier the player has already built by hand. An IEC 61131-flavored subset: contacts, coils, TON/TOF timers, counters, compare, move. Function block diagram and structured text as later unlocks. Fun first; not a vendor emulator.

### 4.4 Diagnostics
Real control systems fail quietly. The game must not. Tools arrive alongside components: indicator lamps, a multimeter, pressure gauges, HMI trends, alarm lists, loop check procedures. "Why is my process doing that" is a core verb, not an afterthought.

### 4.5 Survival
Not hunger bars. The low background of a body that needs air, water, food, and sleep, and a ship that is trying to be lived in. Early on the player keeps themselves alive by hand — cracking an O₂ bottle when the cabin gauge drops, swapping a scrubber cartridge, bleeding a heat exchanger. The first thing ever automated is your own air.

Threats are environmental, not hostile:
- **Pressure** — slow leaks, hatches you shouldn't open, finite suit tanks
- **Thermal** — cold dead sections, hot loops
- **Chemical** — the hold contains things that don't like each other
- **Radiation** — a solar event forces shelter; the unattended plant survives on its own logic or doesn't
- **Power** — the reactor has a budget; the player decides what stays on

The plant competes with life support for heat rejection, power, and water. The ship must be built as one system.

### 4.6 Exploration
Reward is *what* you find: unlogged crates of transmitters, a laminated P&ID on a bench, engineer's notes contradicting the AI, a prefab module that becomes a bioreactor suite once powered. Gates are engineering: restore a bus to light a section, fix a leak to pressurize it, route heat to warm it. The tram is dead at start; restoring it is an early milestone and paces the unlock of districts.

---

## 5. Progression

The ladder is the history of industrial control. Each tier removes the previous tier's pain.

| Tier | Player does | Pain that motivates next tier |
|---|---|---|
| 0 Manual | Valves, switches, bottles, gauges by hand | Can't be everywhere; can't sleep |
| 1 Hardwired relay | Float switches, contactors, latching, interlocks | Pump chatter; relay panels sprawl |
| 2 Timers & sequencers | Timed steps, drum sequencers | Rigid; can't handle exceptions |
| 3 Micro-PLC / ladder | Replace the relay cabinet with logic | On/off control oscillates |
| 4 Analog & PID | Transmitters, control valves, loops | Can't see it all at once |
| 5 HMI & alarms | Screens, trends, alarm management | Islands of control |
| 6 Networked / SCADA | Fieldbus, plant overview, redundancy | — the plant runs unattended |

Plant flow maps onto progression front to back:
- **Life Support** (Tiers 0–2): the first plant; survival loop
- **Upstream** (Tiers 1–4): media prep, seed train, bioreactors, harvest — biology, foaming, oxygen transfer, heat, contamination
- **Downstream** (Tiers 3–5): chromatography, filtration, buffers — classic instrumentation, channelled columns
- **Fill-Finish** (Tiers 0 and 5–6): the isolator, first by hand, finally automated

Scale-up problems are discoveries, not arbitrary challenges: the route was never run past a lab.

---

## 6. Awe — design rules

1. Earn every reveal with a cramped approach and a slow door.
2. Put a human-scale ruler at every threshold.
3. Don't show the far wall at first.
4. Sound is half the scale.
5. Repetition and order, never clutter.
6. Never cut away. Let the player walk.
7. Put a dead brain in view at the moment of scale.

---

## 7. Technical direction

- **Engine:** Godot 4, GDScript (Python-like; static typing used throughout). Scenes are text and authored directly by the dev team.
- **Kernel:** first prototyped in plain Python for design validation and unit tests, then ported to GDScript as engine-independent classes. Nodes render and take input; the sim is data plus a tick.
- **Instancing** for the hold and cable trays; visual object and inventory record are one thing.
- **Save/load** serializes the sim graph from the first playable build.
- **Placeholder art** (boxes, capsules, flat color) until systems are proven.
- **Version control** from day one.
- **Workflow:** dev team delivers files; creative director drops them into the project, presses play, and reports back like a producer reviewing a build.

---

## 8. Open questions for the creative director

- **Name.** For the ship, the AI, the medicine, and the game.
- **The AI's voice.** Warm, clinical, wry? Does it have a personality flaw that matters?
- **Destination.** Who is waiting, and do they ever speak to the ship?
- **The player's body.** Sleep and food as gentle rhythms or real constraints?
- **Failure texture.** How bad is a lost batch? A lost cell bank? Does the ship carry a second bank?
- **What stays manual forever.** Which tasks should the endgame still require a human hand for?
