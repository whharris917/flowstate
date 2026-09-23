class_name LoadCellView
extends VialPartView
## Renders a SimLoadCell: a round weighing pan let into the belt where a
## held vial stands, and beside the track on a post the indicator, whose
## display is the record's own net reading and whose setpoint lamp is its
## contact. The origin is the pan's centre on the track.

var cell: SimLoadCell
var _display: Label3D
var _lamp: StandardMaterial3D
var _refresh := 0.0


func _build() -> void:
	cell = record as SimLoadCell
	var d: float = vial_row()[0]
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.14, 0.15, 0.16))
	# The pan, flush with the belt, and the cell under it.
	ViewUtil.cylinder(self, d * 0.7, 0.004, Vector3(0, DECK + 0.001, 0), ViewUtil.flat(Color(0.80, 0.82, 0.84)))
	ViewUtil.box(self, Vector3(0.05, 0.03, 0.03), Vector3(0, DECK - 0.07, 0), steel)
	# Its cable from the cell to the indicator, under the belt.
	ViewUtil.box(self, Vector3(0.012, 0.012, 0.42), Vector3(0.05, DECK - 0.08, 0.21), steel)
	# The indicator on its post.
	ViewUtil.box(self, Vector3(0.03, 1.05, 0.03), Vector3(0.10, 0.525, 0.42), steel)
	ViewUtil.cylinder(self, 0.05, 0.01, Vector3(0.10, 0.005, 0.42), dark)
	ViewUtil.box(self, Vector3(0.14, 0.09, 0.05), Vector3(0.10, 1.1, 0.42), dark)
	_display = ViewUtil.plate(self, "", Vector3(0.10, 1.11, 0.392))
	_display.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_display.rotation_degrees = Vector3(0, 180, 0)
	_display.font_size = 30
	_display.modulate = Color(0.35, 1.0, 0.45)
	_lamp = ViewUtil.glow(Color(0.1, 0.9, 0.3), 1.2)
	ViewUtil.cylinder(self, 0.005, 0.004, Vector3(0.15, 1.08, 0.394), _lamp).rotation_degrees = Vector3(90, 0, 0)
	var tag := ViewUtil.label(self, cell.comp_name, Vector3(0.10, 1.3, 0.42))
	tag.font_size = 22
	ViewUtil.interact_body(self, Vector3(0.16, 0.12, 0.08), Vector3(0.10, 1.1, 0.42))


func _process(delta: float) -> void:
	if cell == null:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.2
		_display.text = "%6.2f g" % cell.net_g
	var at := cell.at_target.value > 0.5
	_lamp.emission_energy_multiplier = 1.2 if at else 0.0
	_lamp.albedo_color = Color(0.1, 0.9, 0.3) if at else Color(0.2, 0.24, 0.2)


func describe() -> String:
	var where := " on %s" % cell.host if cell.host != "" else " · not under a track"
	return "%s — load cell%s, target %.1f g of %.0f g\nnet %.2f g%s" % [cell.comp_name, where,
		cell.target_g, cell.range_g, cell.net_g, " · AT TARGET" if cell.at_target.value > 0.5 else ""]
