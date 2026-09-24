class_name SimPowerDistribution
extends SimComponent
## A fused 24 V distribution strip: one supply in, a numbered fused way
## per load out. A terminal takes one cable, so a supply that serves N
## loads does it through N ways of one of these. Mirrors
## sim/components.py PowerDistribution.

var ways: int
var dc_in: SimInputPort
var way_ports: Array[SimOutputPort] = []


func _init(name_: String, ways_: int = 8) -> void:
	super(name_)
	assert(ways_ >= 1, "ways must be at least 1")
	ways = ways_
	dc_in = add_input("in", SimTypes.PortKind.POWER, "24VDC")
	for i in ways_:
		way_ports.append(add_output("way%d" % (i + 1), SimTypes.PortKind.POWER, "24VDC"))


func tick(_dt: float) -> void:
	var live := 1.0 if dc_in.value > 0.5 else 0.0
	for port in way_ports:
		port.value = live
