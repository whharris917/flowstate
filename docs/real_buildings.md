# Modelling a real building

How a real building is brought into the game from its survey drawings and photographs. Written from the Mark Twain house (HABS CT-359), where most of the time went on errors this method prevents. Follow it in order; each step's checks pass before the next begins.

## The rule behind the method

A house is not a picture to be matched. It is a set of spaces (rooms, stairs, porches, balconies, decks, attics, the basement) joined by openings and closed by walls, floors and roofs. Almost every visible error comes from authoring those parts separately so they disagree: a window drawn where no wall is cut, a railing round no floor, a door that opens onto a roof, a room that pokes through the roof over it. So the spaces are authored first, and walls, openings, railings and roof holes are derived from them or checked against them. Matching the elevations comes after the building makes sense, never instead of it.

## 1. Gather and register the sources

- Get every sheet: each floor plan, the roof plan, all elevations, sections, details. Get photographs from known viewpoints (survey photographs, a good modern view).
- Register every sheet to one frame, in the drawings' own feet, using the drawings' own references: the outline walls on the plans, the level marks beside the elevations (0'-0", floor heights, ridge). Record each sheet's offset and datum in one table in the code and in the comparison tools.
- Check the registration before modelling: a plan's outer walls fall on the first plan's; an elevation's level marks fall on the floor heights. The Twain house lost a whole pass to a first-floor line read 1.3 ft off its sheet's own mark.

## 2. Author the spaces, level by level

From the plans, for every level including the basement and the attic: each space as a polygon with its name, its floor height, its ceiling (or "up to the roof"), and its kind: room, stair, porch (covered, open to the air at the sides), balcony or deck (open above or under its own roof), attic, void. Nothing else in the building is authored before this list exists and is complete for every level that has an opening.

## 3. Author the openings as connections

Each window and door is a connection between two spaces on one wall: its position and width from the plan, its sill and head from the elevation. An outside window joins a room (or attic) to the air; an outside door joins a room to a porch, balcony, deck or the ground; an inside door joins two rooms. An opening whose two sides are not both known spaces is not authored until they are. Stacked openings (a door and the fan light over it) are allowed and cut together.

## 4. Derive the rest

- Walls: every edge between spaces of different kinds, or between rooms, is a wall; an outside wall runs up until a roof meets it, and wherever it carries on past the roof (a gable, a dormer, a deck's well) it stands to the roof above that.
- Railings: every open edge of a balcony, deck or porch floor that is not against a wall or a stair.
- Roof holes: wherever a space rises through a roof (a tower, a dormer, a deck's well), the roof is cut round it. A hole wholly inside a roof face is cut by splitting the face, never left as an outline filled again.
- Eaves and fascias only where a roof actually starts at a wall's top.
- Chimneys: a flue from each hearth on the plans to the top on the elevations; its position must agree on the plan and on both elevations that see it.
- Things built from a derived height (a wall up to the roof) are built after what they follow.

## 5. Check that it is a building

The Twain audit (`world/twain_audit.tscn`, the `arch` group) checks what was built, not what the code meant. The rules, which hold for any building:

- orphan: every opening is carried by exactly one wall.
- blind: rays through every opening pass: no solid wall behind a sash.
- faces: every opening has open air in front of it, not a wall or roof.
- nowhere: behind every window and door is a space (a window high in a gable may light the attic over a room).
- straddle: no window or door stands across the partition between two rooms.
- landing: every door has a floor at its sill on both sides.
- rail: every railing stands on a floor.

With the room checks already there (leak, roof, poke, reach, clash, float, fight), a building passes when every rule is clean or each exception is named with its reason. A failure is fixed in the spaces or openings, the source data, never by nudging geometry until the check goes quiet.

## 6. Match the drawings and photographs

Only now: the straight-on pictures against each elevation (`tools/twain_overlay.py`, `tools/twain_diff.py` with `--skyline`, and a drawing-over-model crop for any region), and views from the photographs' viewpoints. Where two sheets disagree, the plan decides position, the elevation height, and a photograph decides between drawings. Every correction goes back into the space and opening lists, and the building checks run again after each batch.

## 7. Then the interiors

Finishes and furniture go in after the shell and the spaces pass. The same checks cover them.

## For the next building

Start with steps 1 to 3 as data files (sheet table, space list per level, opening list), and a builder that derives walls, railings and roof holes from them (step 4). The Twain house was built the other way round, outside first, and is being brought to the same checks after the fact; the next one should not be.
