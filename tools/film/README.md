# Film tools

How "The Four Faces" was made, kept so the next film can be made the same way.

1. **Rehearse and record.** With MONROE COURTHOUSE running: `POST /takes/start {"title"}`, let the actors play (agents driving `/actors/<name>/do`), `POST /takes/stop`. The take lands in `user://takes/<title>.json` (`the_four_faces_rehearsal.json` here).
2. **Edit.** `edit_take.py` cuts the rehearsal into the film by whole beats, never changing a word, bridged with title cards and new marks (`the_four_faces_cut.json`).
3. **Voice.** `voices.py <take.json>` records every line in its actor's voice with the Windows speech engine into `user://voices/`; the stage plays them as the actors speak and holds the scene's clock while they do.
4. **Film.** `godot --path game --write-movie <out.avi> --fixed-fps 30 res://world/take_render.tscn` with `FLOWSTATE_TAKE=<title>`.
5. **Music and encode.** `VOICES_IN_GAME=1 python soundtrack.py <render.log> <out.avi> <film.mp4>` adds the music box under the titles and encodes.

The scripts need ffmpeg, taken from the `imageio-ffmpeg` Python package (`pip install --target pylib imageio-ffmpeg` beside them), and hold absolute paths from the session that made them; adjust before reuse.
