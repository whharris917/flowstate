class_name SimInputPort
extends SimPort

var wire_count: int = 0


func reset() -> void:
	# Material ports keep their stream: the node composition is
	# resolved by the hydraulic pass, not delivered by a wire.
	if not SimTypes.is_material(kind):
		value = 0.0


func accumulate_value(incoming: float) -> void:
	if SimTypes.is_oring(kind):
		value = maxf(value, incoming)
	else:
		value = incoming
