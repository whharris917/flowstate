class_name EquipmentAudio
extends AudioStreamPlayer3D
## Positional loop for running machinery: a view creates one with
## make(), then calls set_running(state) from _process — the loop
## starts and stops with the real sim state, never on a timer.
## Silent in headless runs (no audio driver; avoids teardown noise).

static func make(parent: Node3D, stream_path: String, at: Vector3,
		volume_db_: float = -8.0, pitch: float = 1.0) -> EquipmentAudio:
	var node := EquipmentAudio.new()
	var stream := load(stream_path) as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	node.stream = stream
	node.position = at
	node.volume_db = volume_db_
	node.pitch_scale = pitch
	node.bus = "Room"
	node.unit_size = 4.0
	node.max_distance = 28.0
	parent.add_child(node)
	return node


func set_running(running: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if running and not playing:
		play()
	elif not running and playing:
		stop()
