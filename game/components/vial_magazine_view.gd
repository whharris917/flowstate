class_name VialMagazineView
extends VialPartView
## Renders a SimVialMagazine: a stainless tray of empty vials tilted
## toward the line, standing on a frame, with its escapement at the lip
## where each vial leaves for the track (+x). The tray is drawn full: the
## model's magazine never runs out. A tick of the escapement as each one
## goes.

var magazine: SimVialMagazine
var _stock: VialDraw
var _last_supplied := 0


func _build() -> void:
	magazine = record as SimVialMagazine
	vial_ml = magazine.vial_ml
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.24, 0.25, 0.27))
	var row := vial_row()
	var d: float = row[0]
	# The frame, the tilted tray and its lip down to the line's height.
	for x: float in [-0.25, 0.2]:
		for z: float in [-0.16, 0.16]:
			ViewUtil.box(self, Vector3(0.03, DECK, 0.03), Vector3(x, DECK / 2.0, z), steel)
	var tray := Node3D.new()
	add_child(tray)
	tray.position = Vector3(-0.02, DECK + 0.05, 0)
	tray.rotation.z = -0.12
	ViewUtil.box(tray, Vector3(0.5, 0.008, 0.36), Vector3.ZERO, steel)
	for z: float in [-0.18, 0.18]:
		ViewUtil.box(tray, Vector3(0.5, 0.05, 0.006), Vector3(0, 0.025, z), steel)
	ViewUtil.box(tray, Vector3(0.006, 0.05, 0.36), Vector3(-0.25, 0.025, 0), steel)
	# The escapement at the lip: a star of fingers on a spring.
	ViewUtil.box(self, Vector3(0.1, 0.03, 0.06), Vector3(0.3, DECK + 0.01, 0), steel)
	ViewUtil.box(self, Vector3(0.05, 0.05, 0.05), Vector3(0.3, DECK - 0.03, 0.06), dark)
	# The stock: rows of empty vials standing in the tray.
	_stock = VialDraw.new()
	_stock.set_meta("no_merge", true)
	tray.add_child(_stock)
	var stock: Array = []
	var pitch := d + 0.003
	var cols := int(0.46 / pitch)
	var rows := int(0.32 / pitch)
	for i in cols:
		for j in rows:
			var v := SimVial.new("", magazine.vial_ml)
			stock.append([v, Vector3(-0.22 + (i + 0.5) * pitch, 0.004, -0.16 + (j + 0.5) * pitch)])
	_stock.draw(stock)
	var tag := ViewUtil.label(self, magazine.comp_name, Vector3(0, DECK + 0.3, 0))
	tag.font_size = 24
	ViewUtil.plate(self, "%d mL" % magazine.vial_ml, Vector3(0.0, DECK - 0.1, 0.19))
	ViewUtil.interact_body(self, Vector3(0.6, 0.2, 0.4), Vector3(0, DECK + 0.05, 0))
	_last_supplied = magazine.supplied


func item_points() -> Dictionary:
	return {"outfeed": Vector3(0.35, DECK, 0)}


func _process(_delta: float) -> void:
	if magazine == null:
		return
	if magazine.supplied != _last_supplied:
		_last_supplied = magazine.supplied
		EquipmentAudio.play_once(self, "res://audio/relay_click.wav", Vector3(0.3, DECK, 0), -18.0, 1.8)


func describe() -> String:
	return "%s — vial magazine, %d mL vials, up to %.0f a minute\n%s · %d let onto the line · E %s" % [
		magazine.comp_name, magazine.vial_ml, magazine.rate_per_min,
		"FEEDING" if magazine.is_on else "STOPPED", magazine.supplied,
		"stops it" if magazine.is_on else "starts it"]


func use() -> void:
	magazine.is_on = not magazine.is_on
	EquipmentAudio.play_once(self, "res://audio/clunk.wav", Vector3(0.3, DECK, 0), -14.0, 1.5)
