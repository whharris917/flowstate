# Modelling a real building

How a real building is brought into the game. Written from the Mark Twain house (HABS CT-359), and general for any building.

## Why a generator

The first Twain models were built from pieces placed and sized by hand: a wall here, a roof face there, a gable's triangle, a dormer's cheeks. Each piece was right on its own, and nothing related one piece to another, so the faults were in the relations: a gable sunk behind an eave, a slot between two roofs, a wall rising through a room, a window cut by a roof, brick showing inside. Checks on pictures and sampled grids found some of them, after the fact and not all; a fix to one piece broke its neighbour. The faults came from the representation, not from individual mistakes.

So the building is now generated. The data holds only architectural decisions (where the rooms are, how high each floor is, the pitch and overhang of each roof, the width and head of each opening). Everything else is computed from them: walls from the rooms' outlines, roof planes from plates and pitches, eaves, ridges, hips and valleys as the planes' intersections, openings cut from the walls they stand in. Parameters that cannot make a building are refused while generating. What is generated is then validated as a solid, with no drawing or photograph involved. A building that fails validation is broken, not a draft: it is not written out for the game.

Fitting to drawings and photographs comes after, and only moves the parameters: it chooses a building within the space of valid ones.

## The pieces

- **The building file**, `game/data/buildings/<name>.json`, in feet. Grid lines (`grid.x`, `grid.z`) name the lines walls stand on; any coordinate may be a grid name, so one measurement moves every wall on it. Levels with their floors. Groups (the main block, a wing): which owns the wall between them. Spaces on levels: rooms, halls, stairs, porches, balconies, decks, attics, with a polygon (`rect`, points, `arc_at` for a round or a bay), a floor and a top. Openings at a point on a wall with a width, sill and head, and a kind (window, french, door, interior door, shutters, open). Roofs. Chimneys from hearth to top. A style: materials, brick bands, slate courses. A `note` on anything whose number is not the obvious reading of a drawing says which sheet it came from and why.
- **The kernel**, `tools/building/solid.py` and `surface.py`: every part is a set of convex cells, each the intersection of half-spaces, each plane carrying the role of the face it makes (a wall's inner face, a roof's slope, a fascia). Subtraction, exact overlap by volume, and the union's surface with every edge matched.
- **The generator**, `tools/building/arch.py` (`Model.generate`), in this order:
  1. *Roofs.* Each roof has a footprint and, per edge, a kind (eave, gable, abut), a plate height, a pitch and an overhang. Its surface is the lowest of its edge planes. Hips, ridges and valleys follow from the planes. A pyramid or cone gives an apex and peak; `eave` sets every eave at one height and derives each edge's plate. A shed rises from one edge; a flat roof has pitch 0; a deck is a level cut with its own covering; holes leave a well open. A dormer is defined by its host roof, side, centre, width and setback, and its footprint is derived.
  2. *Composition.* Where roofs meet, the higher wins inside the other's footprint. An eave is cut where another roof stands above it. A gable rising from the same wall line cuts the eave across its span. Nothing is trimmed by hand.
  3. *Walls.* Per level and group, from the outline of its rooms, mitred at corners, standing on the floor of the room they close and rising to what is over them: the slab, the next level's wall or the roof's underside.
  4. *Partitions*, inside the level's rooms only.
  5. *Cheeks.* The wall under one roof's edge where it stands over another roof is derived from the two roofs.
  6. *Chimneys.*
  7. *Openings.* Each is found on the wall containing its middle and must fit that wall's face with a ring of wall round it. Frames, glass and leaves follow. Casings, hoods and sills take only the room their face leaves, clear of roofs and of other openings.
  8. *Porches.* Posts on open edges, rising to the roof that covers them. Railings run between posts and walls. Then skirts, and steps at entries.
  9. *Brackets*, kept only where they bear on wall and soffit.

  Whatever cannot be honoured raises `GenError` with the reason, such as a window into a roof, a pitch too steep for its span, or a plate above its peak.
- **The validator**, `tools/building/validate.py`, checks the solids alone:
  - *closed*: every part is a closed solid.
  - *overlap*: no two parts share volume; designed joints are already cut by the generator.
  - *fitted*: every face that must rest on something does: wall tops, frames, casings, posts, brackets.
  - *sealed*: with openings shut, no inside face can be reached from outside. Where it can, the smallest leak is named.
  - *finish*: no inside finish stands in the weather.
  - *roof edges*: each is classified as eave, rake, ridge, hip, valley, deck edge, abutment, well, seam or cricket. Anything else is a step or slot and a finding.
  - *openings*: each lies in its wall, clear of the roof and its neighbours.
  - *chimneys*: each clears the roof it passes through by 2 ft.
  - *headroom*: every room has headroom.
  - *carried*: every roof stands on walls, posts or roof.
  - *generation*: whatever the generator could not honour.
- **`tools/building/build.py <name>`** generates, validates, and writes `game/data/buildings/<name>.bld` only when clean (`--force` writes it marked broken, for looking). `BuildingMesh` (`game/world/building/building_mesh.gd`) draws the `.bld` in the game with its collision.
- **Fitting tools**, which read the drawings and never decide validity:
  - `register.py` places each plan sheet in the frame.
  - `measure.py` reads walls off a plan.
  - `overlay.py` lays the data and the generated roof over every sheet and lists lines with no ink under them.
  - `roofplan.py` draws the classified roof edges over the roof plan.
  - `chimneys.py` finds chimney tops.
  - `camera.py` solves a photograph's camera and lays the render over it.
  - The world's probe photographs the built house from any viewpoint.
- **The test house**, `tools/building/examples/cottage.json`, with `tests/test_building_generator.py`. It must stay clean, and each kind of fault must stay found.

## The steps

1. **Sources.** Gather every sheet and photograph, and register the plans.
2. **Spaces**, level by level, on named grid lines, until `measure.py` and `overlay.py` agree with the plans.
3. **Openings**, from the plans (position, width) and elevations (sill, head).
4. **Roofs**, as architectural parameters read from the roof plan, sections and elevations: footprint, plates, pitches, overhangs, gables. Never as faces.
5. **Chimneys.**
6. **Generate and validate** after every change to the data or the generator. Fix a finding in the data when a number is wrong. Fix it in the generator when it is a kind of fault, so the next building cannot have it. Add the kind to the test house when it is new.
7. **Fit.** Compare the clean house with the drawings and photographs (`overlay.py`, `roofplan.py`, `camera.py`, probe views), adjust parameters, and validate again.
8. **Then interiors**: finishes, stairs, furniture.

Where sources disagree, the plan decides position, the elevation height, a section what is inside the roof, and a photograph between drawings. The note on the number records which was taken.
