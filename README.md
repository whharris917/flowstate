# flowstate

First-person factory-building sim aboard a starship. Design bible: `docs/GDD.md`. Working agreement: `CLAUDE.md`.

## Python kernel (build-order step 1)

```powershell
# launch the live operator GUI (opens in your browser)
.venv\Scripts\python.exe tools\demo_gui.py

# run the tests
.venv\Scripts\python.exe -m pytest tests -q
```

The GUI shows the supply-tank loop — tank, float switch, relay, pump — with an
operator graphic and live trends of historized data. Try setting low trip = high
trip and watch the relay cycle counter. Full history is downloadable as CSV from
the page footer.

The Godot project lives in `game/` (open `game/project.godot`); it is a
placeholder until build-order step 2.
