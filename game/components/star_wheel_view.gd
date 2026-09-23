class_name StarWheelView
extends VialPartView
## Renders a SimStarWheel: a star plate with a pocket per vial on a hub,
## turning over a stainless dead plate at the line's height, with an
## outer guide round the side the vials travel, and the indexer under
## it. The infeed station (0) stands at -x, the pockets travel through
## +z -- the side a line's controls stand, so a capper at a station
## between faces them -- and the outfeed stands where its station puts
## it (+x for the usual half turn). The rotor turns with the record's own offset and
## progress, and a servo whirs on each index.

var wheel: SimStarWheel
var _rotor: Node3D
var _vials: VialDraw
var _was_moving := false


## A station's point, in the wheel's own space, at a fractional station.
static func station_point(radius: float, pockets: int, f: float) -> Vector3:
	var angle := PI - f * TAU / float(pockets)
	return Vector3(radius * cos(angle), DECK, radius * sin(angle))


func _build() -> void:
	wheel = record as SimStarWheel
	var r := wheel.pitch_radius_m
	var row := vial_row()
	var d: float = row[0]
	var h: float = row[1]
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.24, 0.25, 0.27))
	var white := ViewUtil.flat(Color(0.86, 0.86, 0.84))
	# The dead plate the vials slide on, and the stand under it.
	ViewUtil.cylinder(self, r + d, 0.012, Vector3(0, DECK - 0.006, 0), steel)
	ViewUtil.cylinder(self, 0.05, DECK - 0.012, Vector3(0, (DECK - 0.012) / 2.0, 0), steel)
	ViewUtil.cylinder(self, 0.16, 0.012, Vector3(0, 0.006, 0), dark)
	ViewUtil.box(self, Vector3(0.14, 0.16, 0.14), Vector3(0, DECK - 0.12, 0), ViewUtil.flat(Color(0.20, 0.34, 0.55)))
	ViewUtil.box(self, Vector3(0.28, 0.12, 0.02), Vector3(0, 0.55, 0.15), dark)
	# The outer guide: an arc of posts round the travelling side (+z).
	var posts := 9
	for i in posts:
		var f := float(wheel.out_station) * float(i) / float(posts - 1)
		var p := station_point(r + d / 2.0 + 0.006, wheel.pockets, f)
		ViewUtil.box(self, Vector3(0.006, h * 0.7, 0.006), Vector3(p.x, DECK + h * 0.35, p.z), steel)
	# The rotor: a hub and a star plate of teeth between the pockets, in
	# food-grade white plastic, at two thirds of the vial's height.
	_rotor = Node3D.new()
	add_child(_rotor)
	var plate_y := DECK + h * 0.45
	ViewUtil.cylinder(_rotor, r - d * 0.55, 0.012, Vector3(0, plate_y, 0), white)
	ViewUtil.cylinder(_rotor, 0.035, plate_y - DECK + 0.04, Vector3(0, (plate_y + DECK) / 2.0 + 0.01, 0), steel)
	for p in wheel.pockets:
		var mid := station_point(r, wheel.pockets, float(p) + 0.5)
		var tooth := ViewUtil.box(_rotor, Vector3(d * 1.1, 0.012, TAU * r / wheel.pockets - d * 1.05),
			Vector3(mid.x, plate_y, mid.z), white)
		tooth.rotation.y = -atan2(mid.z, mid.x)
	_vials = VialDraw.new()
	_vials.set_meta("no_merge", true)
	add_child(_vials)
	var tag := ViewUtil.label(self, wheel.comp_name, Vector3(0, DECK + 0.3, 0))
	tag.font_size = 24
	ViewUtil.interact_cylinder(self, r + d, 0.12, Vector3(0, DECK + 0.03, 0))


func item_points() -> Dictionary:
	return {"infeed": station_point(wheel.pitch_radius_m, wheel.pockets, 0.0),
		"outfeed": station_point(wheel.pitch_radius_m, wheel.pockets, float(wheel.out_station))}


func _process(delta: float) -> void:
	if wheel == null:
		return
	_rotor.rotation.y = (float(wheel.offset) + wheel.progress) * TAU / float(wheel.pockets)
	if wheel.moving and not _was_moving:
		EquipmentAudio.play_once(self, "res://audio/servo.wav", Vector3(0, DECK - 0.1, 0), -14.0, 1.4)
	_was_moving = wheel.moving
	var items: Array = []
	for pair: Array in smoothed(wheel.vials(), delta):
		items.append([pair[0], station_point(wheel.pitch_radius_m, wheel.pockets, float(pair[1])) \
			+ Vector3(0, BELT / 2.0, 0)])
	_vials.draw(items)


func describe() -> String:
	var state := "INDEXING" if wheel.moving else "at rest"
	if wheel.power.value <= 0.5:
		state += " · NO 24 V"
	var how := " · E indexes it (nothing wired to index)" if wheel.is_hand_operated else ""
	return "%s — star wheel, %d pockets, outfeed at station %d\n%s · %d vials in it · %d indexes%s" % [
		wheel.comp_name, wheel.pockets, wheel.out_station, state, wheel.vials_on, wheel.indexes, how]


func use() -> void:
	if wheel.is_hand_operated:
		wheel.hand_index()
