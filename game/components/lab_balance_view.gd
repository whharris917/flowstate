class_name LabBalanceView
extends BenchView
## Renders a SimLabBalance: a top-loading balance, a round stainless
## pan, and a display of what stands on the pan less the tare. E tares.

var balance: SimLabBalance
var _display: Label3D


func _build() -> void:
	balance = record as SimLabBalance
	var body := ViewUtil.painted(Color(0.88, 0.88, 0.86))
	var dark := ViewUtil.matte(Color(0.08, 0.09, 0.10))
	ViewUtil.box(self, Vector3(0.20, BALANCE_TOP - 0.02, 0.28), Vector3(0, (BALANCE_TOP - 0.02) / 2.0, 0.0), body)
	ViewUtil.cylinder(self, 0.012, 0.012, Vector3(0, BALANCE_TOP - 0.014, 0.03), dark)
	ViewUtil.cylinder(self, BALANCE_PAN, 0.006, Vector3(0, BALANCE_TOP - 0.003, 0.03), ViewUtil.steel())
	var screen := ViewUtil.box(self, Vector3(0.12, 0.03, 0.003), Vector3(0, 0.045, -0.141), dark)
	screen.rotation.x = 0.0
	_display = Label3D.new()
	_display.font_size = 30
	_display.pixel_size = 0.0007
	_display.modulate = Color(0.85, 0.95, 1.0)
	_display.outline_size = 0
	_display.position = Vector3(0, 0.045, -0.1435)
	_display.rotation.y = PI
	add_child(_display)
	var tag := ViewUtil.label(self, balance.comp_name, Vector3(0, 0.22, 0))
	tag.font_size = 22
	ViewUtil.interact_body(self, Vector3(0.21, BALANCE_TOP, 0.29), Vector3(0, BALANCE_TOP / 2.0, 0))


func radius() -> float:
	return 0.15


func _process(_delta: float) -> void:
	if balance == null:
		return
	_display.text = "%.2f g" % balance.reading_g


func use() -> void:
	balance.tare()


func describe() -> String:
	var on := "on the pan: %s" % balance.load.comp_name if balance.load != null else "pan empty"
	return "%s — balance\n%s · reads %.2f g (tare %.2f g)\n[E] tare" % [
		balance.comp_name, on, balance.reading_g, balance.tare_g]
