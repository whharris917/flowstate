class_name VialTableView
extends VialPartView
## Renders a SimVialTable: the outfeed turntable, a stainless disc on a
## pedestal with a rim, the latest vials standing on it in rings as they
## arrived (the record keeps the last sixty). Each arrival is a clink of
## glass. Its hover is the batch record.

const RADIUS := 0.42

var table: SimVialTable
var _vials: VialDraw
var _disc: Node3D
var _last_count := 0


func _build() -> void:
	table = record as SimVialTable
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.24, 0.25, 0.27))
	ViewUtil.cylinder(self, 0.06, DECK - 0.02, Vector3(0, (DECK - 0.02) / 2.0, 0), steel)
	ViewUtil.cylinder(self, 0.22, 0.014, Vector3(0, 0.007, 0), dark)
	_disc = Node3D.new()
	add_child(_disc)
	ViewUtil.cylinder(_disc, RADIUS, 0.012, Vector3(0, DECK - 0.006, 0), steel)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.004
	torus.outer_radius = RADIUS + 0.006
	torus.rings = 40
	torus.ring_segments = 6
	rim.mesh = torus
	rim.material_override = steel
	rim.position = Vector3(0, DECK + 0.03, 0)
	add_child(rim)
	# The infeed guide from the line's height onto the disc.
	ViewUtil.box(self, Vector3(0.12, 0.004, 0.09), Vector3(-RADIUS - 0.02, DECK - 0.002, 0), steel)
	_vials = VialDraw.new()
	_vials.set_meta("no_merge", true)
	_disc.add_child(_vials)
	var tag := ViewUtil.label(self, table.comp_name, Vector3(0, DECK + 0.3, 0))
	tag.font_size = 24
	ViewUtil.interact_cylinder(self, RADIUS, 0.15, Vector3(0, DECK + 0.03, 0))
	_last_count = table.count
	_disc.rotation.y = -float(table.count) * 0.21   # turned as far as its vials have come


func item_points() -> Dictionary:
	return {"infeed": Vector3(-RADIUS - 0.05, DECK, 0)}


func _process(_delta: float) -> void:
	if table == null:
		return
	if table.count != _last_count:
		_last_count = table.count
		_disc.rotation.y = -float(table.count) * 0.21
		EquipmentAudio.play_once(self, "res://audio/clink.wav", Vector3(-RADIUS, DECK, 0), -12.0,
			0.9 + 0.2 * float(table.count % 5) / 4.0)
	# The latest vials in rings from the rim inward. Vial k was set down
	# at the infeed (-x) when the disc had turned k steps, so in the
	# disc's own space it stands at PI - k steps: it turns with the disc.
	var items: Array = []
	var n := table.recent.size()
	for i in n:
		var vial := table.recent[n - 1 - i]
		var k := table.count - i
		@warning_ignore("integer_division")
		var ring := i / 20
		var angle := PI - float(k) * 0.21
		var rr := RADIUS - 0.04 - float(ring) * 0.045
		items.append([vial, Vector3(rr * cos(angle), DECK, rr * sin(angle))])
	_vials.draw(items)


func describe() -> String:
	if table.count == 0:
		return "%s — outfeed table: no vials yet" % table.comp_name
	return "%s — outfeed table: %d vials, %d capped\nfill %.2f mL mean (%.2f to %.2f) · %.1f mL in all · %.1f %% product" % [
		table.comp_name, table.count, table.capped_count, table.mean_ml, table.min_ml, table.max_ml,
		table.out_l * 1000.0, 100.0 * table.product_l / maxf(table.out_l, 1e-12)]
