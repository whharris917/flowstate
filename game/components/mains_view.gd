class_name MainsView
extends Node3D
## Renders a SimMainsFeed: a feeder pillar with a hazard band and the
## voltage class on its face. The root of every power circuit.

var mains: SimMainsFeed
var _buzz: EquipmentAudio


func setup(mains_: SimMainsFeed) -> void:
	mains = mains_
	var dark := ViewUtil.flat(Color(0.14, 0.15, 0.17))
	ViewUtil.box(self, Vector3(0.7, 1.7, 0.5), Vector3(0, 0.85, 0), dark)
	ViewUtil.box(self, Vector3(0.78, 0.14, 0.55), Vector3(0, 1.35, 0),
		ViewUtil.flat(Color(0.95, 0.78, 0.05)))
	ViewUtil.box(self, Vector3(0.5, 0.35, 0.04), Vector3(0, 0.85, 0.26),
		ViewUtil.glow(Color(0.85, 0.20, 0.12), 0.7))
	var tag := ViewUtil.label(self, "⚡ %s" % mains.spec, Vector3(0, 0.85, 0.30))
	tag.font_size = 30
	tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ViewUtil.label(self, mains.comp_name, Vector3(0, 1.95, 0))
	ViewUtil.interact_body(self, Vector3(0.8, 1.7, 0.6), Vector3(0, 0.85, 0))
	# A live feeder buzzes quietly — the low mains hum, close up only.
	_buzz = EquipmentAudio.make(self, "res://audio/motor_loop.wav",
		Vector3(0, 1.0, 0), -20.0, 0.5)
	_buzz.max_distance = 9.0


func _process(_delta: float) -> void:
	_buzz.set_running(true)


func describe() -> String:
	return "%s — mains feeder, %s\nfeeds everything wired to it" % [
		mains.comp_name, mains.spec]


func use() -> void:
	pass
