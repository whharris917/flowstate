class_name SimInputPort
extends SimPort

var wire_count: int = 0


func reset() -> void:
	value = 0.0
	if SimTypes.is_stream(kind):
		# Streams are immutable, so every dead port can share one
		# instance instead of allocating a fresh one every scan.
		stream = SimStream.empty()


func accumulate_value(incoming: float) -> void:
	if SimTypes.is_summing(kind):
		value += incoming
	elif SimTypes.is_oring(kind):
		value = maxf(value, incoming)
	else:
		value = incoming


## Two lines landing on one nozzle blend: flows add, temperature and
## composition are flow-weighted. Offered material does not mix (see
## SimTypes.is_mixing), so it simply replaces.
func accumulate_stream(incoming: SimStream) -> void:
	if SimTypes.is_mixing(kind):
		stream = SimStream.mix(stream, incoming)
	else:
		stream = incoming
