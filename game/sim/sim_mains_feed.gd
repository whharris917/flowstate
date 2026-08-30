class_name SimMainsFeed
extends SimComponent
## The plant's electrical feeder: one always-energized POWER output at
## its voltage class. Load accounting and breakers arrive with the
## power-monitoring tier; for now this is the honest root of every
## power circuit — nothing runs without a cable back to a feed.
## Mirrors sim/components.py MainsFeed.

var spec: String

var power: SimOutputPort


func _init(name_: String, spec_ := "480VAC") -> void:
	super(name_)
	spec = spec_
	power = add_output("power", SimTypes.PortKind.POWER, spec_)
	power.value = 1.0


func tick(_dt: float) -> void:
	power.value = 1.0
