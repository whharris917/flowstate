class_name MainsView
extends Node3D
## Renders a SimMainsFeed: a feeder pillar with a hazard band and the
## voltage class on its face. The root of every power circuit.

var mains: SimMainsFeed
var _buzz: EquipmentAudio


func setup(mains_: SimMainsFeed) -> void:
	mains = mains_
	var dark := ViewUtil.flat(Color(0.14, 0.15, 0.17))
	var steel := ViewUtil.flat(Color(0.55, 0.57, 0.60))
	# Switchgear: a plinth, the enclosure, a door with hinges, handle and
	# louvres, the breaker window, the warning band and label, and two
	# conduit stubs through the top plate. The feed lands on a busbar
	# box on the right-hand side.
	ViewUtil.box(self, Vector3(0.76, 0.08, 0.56), Vector3(0, 0.04, 0), ViewUtil.flat(Color(0.22, 0.23, 0.25)))
	ViewUtil.box(self, Vector3(0.7, 1.7, 0.5), Vector3(0, 0.85, 0), dark)
	ViewUtil.box(self, Vector3(0.62, 1.5, 0.012), Vector3(0, 0.88, 0.254), ViewUtil.flat(Color(0.19, 0.20, 0.22)))
	for hy: float in [0.35, 0.88, 1.41]:
		ViewUtil.box(self, Vector3(0.025, 0.08, 0.03), Vector3(-0.335, hy, 0.24), steel)
	ViewUtil.box(self, Vector3(0.03, 0.16, 0.035), Vector3(0.25, 0.85, 0.275), steel)
	for i in 5:
		ViewUtil.box(self, Vector3(0.28, 0.012, 0.02), Vector3(-0.1, 0.28 + i * 0.045, 0.262), steel)
	ViewUtil.box(self, Vector3(0.78, 0.14, 0.55), Vector3(0, 1.35, 0),
		ViewUtil.flat(Color(0.95, 0.78, 0.05)))
	ViewUtil.box(self, Vector3(0.16, 0.06, 0.006), Vector3(0.15, 1.15, 0.262), ViewUtil.flat(Color(0.95, 0.85, 0.10)))
	ViewUtil.box(self, Vector3(0.14, 0.04, 0.007), Vector3(0.15, 1.15, 0.262), ViewUtil.flat(Color(0.05, 0.05, 0.05)))
	ViewUtil.box(self, Vector3(0.5, 0.35, 0.04), Vector3(0, 0.85, 0.26),
		ViewUtil.glow(Color(0.85, 0.20, 0.12), 0.7))
	ViewUtil.box(self, Vector3(0.7, 0.03, 0.5), Vector3(0, 1.715, 0), steel)
	for sx: float in [-0.2, 0.2]:
		ViewUtil.cylinder(self, 0.03, 0.26, Vector3(sx, 1.85, 0), ViewUtil.flat(Color(0.72, 0.72, 0.75)))
	ViewUtil.box(self, Vector3(0.06, 0.18, 0.18), Vector3(0.36, 1.05, 0), steel)
	ViewUtil.box(self, Vector3(0.14, 0.04, 0.006), Vector3(-0.15, 1.55, 0.262), ViewUtil.flat(Color(0.93, 0.93, 0.90)))
	var tag := ViewUtil.plate(self, "⚡ %s" % mains.spec, Vector3(0, 0.85, 0.30))
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
