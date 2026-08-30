class_name SimInputPort
extends SimPort

var wire_count: int = 0


func reset() -> void:
	value = 0.0


func accumulate(incoming: float) -> void:
	if SimTypes.is_summing(kind):
		value += incoming
	elif SimTypes.is_oring(kind):
		value = maxf(value, incoming)
	else:
		value = incoming
