class_name SimMainsFeed
extends SimComponent
## The plant's electrical feeder: numbered always-energized POWER ways
## at its voltage class, one per load (a terminal takes one cable, so
## a feeder that serves N loads has N ways). Load accounting and breakers arrive with the power-monitoring
## tier; for now this is the honest root of every power circuit —
## nothing runs without a cable back to a feed. Mirrors
## sim/components.py MainsFeed.

var spec: String
var ways: int
var way_ports: Array[SimOutputPort] = []


func _init(name_: String, spec_ := "480VAC", ways_: int = 8) -> void:
	super(name_)
	assert(ways_ >= 1, "ways must be at least 1")
	spec = spec_
	ways = ways_
	for i in ways_:
		var port := add_output("way%d" % (i + 1), SimTypes.PortKind.POWER, spec_)
		port.value = 1.0
		way_ports.append(port)


func tick(_dt: float) -> void:
	for port in way_ports:
		port.value = 1.0
