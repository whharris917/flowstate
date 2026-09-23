class_name FillNeedleView
extends VialPartView
## Renders a SimFillNeedle: a stand beside the track on the +z side, an
## arm out over the centreline, and the needle pointing straight down
## with its tip a finger's width above the tallest vial. Its inlet takes
## the dosing line at the top of the stand. What leaves the tip is drawn
## by a SpillJet pointing down, off the record's own flow, and lands on
## the liquid in the vial under it, on the belt, or on the floor. The
## origin is the tip's point on the track's centreline.

const TIP_Y := 1.00        # the tip above the floor: over a 73 mm vial on the deck
const ARM_Y := 1.16
const STAND_Z := 0.26

var needle: SimFillNeedle
var _jet: SpillJet


func _build() -> void:
	needle = record as SimFillNeedle
	var steel := ViewUtil.flat(Color(0.62, 0.66, 0.70))
	var dark := ViewUtil.flat(Color(0.24, 0.25, 0.27))
	ViewUtil.cylinder(self, 0.012, ARM_Y, Vector3(0, ARM_Y / 2.0, STAND_Z), steel)
	ViewUtil.cylinder(self, 0.06, 0.012, Vector3(0, 0.006, STAND_Z), dark)
	# The arm, and a clamp block holding the needle over the line.
	ViewUtil.box(self, Vector3(0.02, 0.02, STAND_Z + 0.02), Vector3(0, ARM_Y, STAND_Z / 2.0), steel)
	ViewUtil.box(self, Vector3(0.03, 0.035, 0.03), Vector3(0, ARM_Y, 0), steel)
	# The needle: a fine stainless tube from the block to the tip.
	ViewUtil.cylinder(self, 0.0025, ARM_Y - TIP_Y, Vector3(0, (ARM_Y + TIP_Y) / 2.0, 0), steel)
	# The dosing line's fitting at the top of the stand.
	ViewUtil.box(self, Vector3(0.03, 0.03, 0.03), Vector3(0, ARM_Y + 0.02, STAND_Z), dark)
	_jet = SpillJet.make(self)
	var tag := ViewUtil.label(self, needle.comp_name, Vector3(0, ARM_Y + 0.15, STAND_Z / 2.0))
	tag.font_size = 22
	ViewUtil.interact_body(self, Vector3(0.06, 0.1, STAND_Z + 0.06), Vector3(0, ARM_Y, STAND_Z / 2.0))


func _process(delta: float) -> void:
	if needle == null:
		return
	var q := needle.flow_lps
	var tip := to_global(Vector3(0, TIP_Y, 0))
	var landing := global_position.y
	var into := false
	if needle.catch_vial != null:
		var vial := needle.catch_vial
		landing = global_position.y + DECK + BELT / 2.0 \
			+ vial.height_m * 0.9 * clampf(vial.volume_l / vial.brim_l, 0.0, 1.0)
		into = true
	elif needle.host != "":
		landing = global_position.y + DECK
	elif needle.catch != null and needle.catch.open_top:
		landing = needle.catch.elevation_m + needle.catch.depth_m
		into = true
	# A filling needle's bore: two millimetres.
	_jet.set_state(q, tip, Vector3.DOWN, 0.002, landing, into, delta)


func describe() -> String:
	var q := needle.flow_lps
	var where := "into vial %s" % needle.catch_vial.serial if needle.catch_vial != null \
		else ("onto the belt of %s" % needle.host if needle.host != "" else "onto the floor")
	if q <= 0.0:
		where = "dry"
	return "%s — fill needle%s\n%s %s · %.2f mL delivered · %.2f mL spilled" % [
		needle.comp_name, " over %s" % needle.host if needle.host != "" else "",
		SimTypes.flow_text(q), where, needle.delivered_l * 1000.0, needle.spilled_l * 1000.0]
