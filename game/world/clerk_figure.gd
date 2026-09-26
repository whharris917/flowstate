class_name ClerkFigure
extends PlayerFigure
## The clerk's body: a studious county clerk of the 1880s on the player's
## skeleton and gait. A white shirt with black garters on the sleeves, a
## brown waistcoat with brass buttons and a watch chain, a black bow tie,
## grey trousers and black shoes; dark hair parted in the middle and
## side whiskers, round wire spectacles, a green celluloid eyeshade, a pen
## behind his ear, and the county's ledger under his left arm, which he
## opens to read. Gestures (a wave, a bow, reading) are laid over the
## walking pose.

const SHIRT := Color(0.93, 0.91, 0.85)
const WAISTCOAT := Color(0.36, 0.20, 0.12)
const TROUSERS := Color(0.24, 0.23, 0.25)
const SHOE := Color(0.05, 0.05, 0.05)
const CLERK_SKIN := Color(0.90, 0.74, 0.62)
const CLERK_HAIR := Color(0.20, 0.13, 0.08)
const BRASS := Color(0.80, 0.64, 0.30)
const SHADE := Color(0.20, 0.62, 0.36, 0.55)
const LEDGER := Color(0.42, 0.10, 0.08)

## The gesture being made: "", "wave", "bow", "read", "point"; t its time.
var gesture := ""
var gesture_t := 0.0
var _ledger: Node3D
var _ledger_open: Node3D


func _ready() -> void:
	var shirt := _material(SHIRT, 0.7)
	var vest := _material(WAISTCOAT, 0.75)
	var trousers := _material(TROUSERS, 0.85)
	var shoe := _material(SHOE, 0.35)
	var skin := _material(CLERK_SKIN, 0.55)
	var hair := _material(CLERK_HAIR, 0.8)
	var brass := _material(BRASS, 0.3)
	brass.metallic = 0.9
	var black := _material(Color(0.03, 0.03, 0.03), 0.5)
	var shade := StandardMaterial3D.new()
	shade.albedo_color = SHADE
	shade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shade.roughness = 0.2
	shade.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ledger := _material(LEDGER, 0.6)
	var pages := _material(Color(0.93, 0.89, 0.76), 0.9)

	_pelvis = _joint(self, Vector3(0, HIP_H, 0))
	_part(_pelvis, _sphere(0.16), Vector3(0, 0.04, 0), trousers, Vector3(1.05, 0.72, 0.76))
	_part(_pelvis, _cylinder(0.158, 0.158, 0.05), Vector3(0, 0.1, 0), black, Vector3(1.0, 1.0, 0.74))
	for side: float in [-1.0, 1.0]:
		var hip := _joint(_pelvis, Vector3(0.095 * side, 0, 0))
		_part(hip, _cylinder(0.074, 0.056, THIGH), Vector3(0, -THIGH / 2.0, 0), trousers)
		var knee := _joint(hip, Vector3(0, -THIGH, 0))
		_part(knee, _sphere(0.056), Vector3.ZERO, trousers)
		_part(knee, _cylinder(0.054, 0.05, SHIN), Vector3(0, -SHIN / 2.0, 0), trousers)
		var ankle := _joint(knee, Vector3(0, -SHIN, 0))
		_part(ankle, _box(Vector3(0.095, ANKLE_H, 0.26)), Vector3(0, -ANKLE_H / 2.0, -0.07), shoe)
		_hips.append(hip)
		_knees.append(knee)
		_ankles.append(ankle)

	_spine = _joint(self, Vector3(0, HIP_H + 0.06, 0))
	# The shirt, the waistcoat over it with its buttons and chain.
	_part(_spine, _capsule(0.15, 0.52), Vector3(0, 0.23, 0), shirt, Vector3(1.15, 1.0, 0.7))
	_part(_spine, _capsule(0.155, 0.44), Vector3(0, 0.19, 0.0), vest, Vector3(1.14, 1.0, 0.74))
	for k in 5:
		_part(_spine, _sphere(0.011), Vector3(0, 0.07 + k * 0.055, -0.117), brass)
	var chain := _part(_spine, _cylinder(0.004, 0.004, 0.16), Vector3(0.05, 0.12, -0.115), brass)
	chain.rotation.z = 1.2
	var yoke := _part(_spine, _capsule(0.07, 0.44), Vector3(0, 0.40, 0), shirt, Vector3(1.0, 1.0, 0.9))
	yoke.rotation.z = PI / 2.0
	_part(_spine, _cylinder(0.058, 0.062, 0.06), Vector3(0, 0.47, 0), shirt)
	# The bow tie.
	for side: float in [-1.0, 1.0]:
		var wing := _part(_spine, _box(Vector3(0.05, 0.035, 0.012)), Vector3(0.025 * side, 0.465, -0.062), black)
		wing.rotation.z = 0.25 * side
	for side: float in [-1.0, 1.0]:
		var shoulder := _joint(_spine, Vector3(0.21 * side, 0.40, 0))
		_part(shoulder, _sphere(0.06), Vector3.ZERO, shirt)
		_part(shoulder, _cylinder(0.056, 0.048, UPPER_ARM), Vector3(0, -UPPER_ARM / 2.0, 0), shirt)
		_part(shoulder, _cylinder(0.059, 0.059, 0.028), Vector3(0, -UPPER_ARM * 0.55, 0), black)
		var elbow := _joint(shoulder, Vector3(0, -UPPER_ARM, 0))
		_part(elbow, _sphere(0.047), Vector3.ZERO, shirt)
		_part(elbow, _cylinder(0.046, 0.04, FOREARM - 0.05), Vector3(0, -(FOREARM - 0.05) / 2.0, 0), shirt)
		_part(elbow, _cylinder(0.042, 0.042, 0.03), Vector3(0, -FOREARM + 0.045, 0), shirt)
		_part(elbow, _box(Vector3(0.045, 0.09, 0.08)), Vector3(0, -FOREARM - 0.03, 0), skin)
		_shoulders.append(shoulder)
		_elbows.append(elbow)

	_neck = _joint(_spine, Vector3(0, 0.46, 0))
	_head_parts.append(_part(_neck, _cylinder(0.044, 0.048, 0.1), Vector3(0, 0.04, 0), skin))
	_head = _joint(_neck, Vector3(0, 0.06, 0))
	_head_parts.append(_part(_head, _sphere(0.103), Vector3(0, 0.09, 0), skin, Vector3(0.9, 1.12, 1.0)))
	# Hair parted in the middle, whiskers down the cheeks.
	for side: float in [-1.0, 1.0]:
		var half := _part(_head, _sphere(0.108), Vector3(0.012 * side, 0.118, 0.018), hair, Vector3(0.5, 0.95, 1.0))
		half.position.x = 0.045 * side
		_head_parts.append(half)
		_head_parts.append(_part(_head, _box(Vector3(0.022, 0.07, 0.04)), Vector3(0.088 * side, 0.06, -0.035), hair))
		_head_parts.append(_part(_head, _sphere(0.025), Vector3(0.094 * side, 0.085, 0.006), skin, Vector3(0.4, 1.0, 0.7)))
	_head_parts.append(_part(_head, _box(Vector3(0.022, 0.038, 0.03)), Vector3(0, 0.075, -0.103), skin))
	# The spectacles: two wire rims, the bridge, the arms back to the ears.
	var torus := TorusMesh.new()
	torus.inner_radius = 0.022
	torus.outer_radius = 0.027
	torus.rings = 12
	torus.ring_segments = 6
	for side: float in [-1.0, 1.0]:
		var rim := _part(_head, torus, Vector3(0.037 * side, 0.105, -0.098), brass)
		rim.rotation.x = PI / 2.0
		_head_parts.append(rim)
		var arm := _part(_head, _box(Vector3(0.003, 0.003, 0.1)), Vector3(0.068 * side, 0.108, -0.05), brass)
		_head_parts.append(arm)
	_head_parts.append(_part(_head, _box(Vector3(0.022, 0.003, 0.003)), Vector3(0, 0.11, -0.1), brass))
	# The eyeshade: a band round the head and a green brim over the eyes.
	var band := _part(_head, _cylinder(0.106, 0.106, 0.025), Vector3(0, 0.155, 0.01), black, Vector3(0.92, 1.0, 1.02))
	_head_parts.append(band)
	var brim := _part(_head, _cylinder(0.105, 0.17, 0.012), Vector3(0, 0.15, -0.07), shade, Vector3(0.85, 1.0, 0.7))
	brim.rotation.x = -0.35
	_head_parts.append(brim)
	# The pen behind his right ear.
	var pen := _part(_head, _cylinder(0.005, 0.004, 0.15), Vector3(0.1, 0.12, -0.01), black)
	pen.rotation = Vector3(1.3, 0, 0.2)
	_head_parts.append(pen)
	# The ledger: under the left arm, or open in both hands.
	_ledger = _joint(_spine, Vector3(-0.19, 0.2, -0.02))
	_part(_ledger, _box(Vector3(0.035, 0.3, 0.23)), Vector3.ZERO, ledger)
	_part(_ledger, _box(Vector3(0.028, 0.285, 0.215)), Vector3(0.004, 0, 0), pages)
	_ledger_open = _joint(_spine, Vector3(0, 0.26, -0.3))
	for side: float in [-1.0, 1.0]:
		var leaf := _part(_ledger_open, _box(Vector3(0.22, 0.012, 0.3)), Vector3(0.11 * side, 0, 0), ledger)
		leaf.rotation.z = -0.12 * side
		var page := _part(_ledger_open, _box(Vector3(0.205, 0.01, 0.285)), Vector3(0.105 * side, 0.01, 0), pages)
		page.rotation.z = -0.12 * side
	_ledger_open.rotation.x = 0.55
	_ledger_open.visible = false


## The walking pose, then the gesture laid over it.
func pose(delta: float, velocity: Vector3, grounded: bool, pitch: float) -> bool:
	var struck := super(delta, velocity, grounded, pitch)
	if gesture == "":
		# At rest or walking, the left arm holds the ledger to his side.
		_shoulders[0].rotation = Vector3(0.05, 0, -0.22)
		_elbows[0].rotation.x = 0.35
		_ledger.visible = true
		_ledger_open.visible = false
		return struck
	gesture_t += delta
	var t := gesture_t
	match gesture:
		"wave":
			_shoulders[1].rotation = Vector3(-0.2, 0, 2.5)
			_elbows[1].rotation.x = 0.6 + 0.45 * sin(t * 9.0)
			_head.rotation.z = 0.08 * sin(t * 3.0)
		"bow":
			var b := sin(clampf(t / 1.4, 0.0, 1.0) * PI)
			_spine.rotation.x = -0.6 * b
			_neck.rotation.x = -0.3 * b
			_shoulders[1].rotation = Vector3(0.6 * b, 0, -0.3 * b)
			_elbows[1].rotation.x = 1.5 * b
		"read":
			_ledger.visible = false
			_ledger_open.visible = true
			for i in 2:
				var s := -1.0 if i == 0 else 1.0
				_shoulders[i].rotation = Vector3(0.9, 0, -0.25 * s)
				_elbows[i].rotation.x = 1.3
			_neck.rotation.x = -0.45
			_head.rotation.x = -0.25
			_head.rotation.y = 0.12 * sin(t * 0.8)
		"point":
			_shoulders[1].rotation = Vector3(1.45, 0, 0.1)
			_elbows[1].rotation.x = 0.05
	if gesture != "read":
		_ledger.visible = true
		_ledger_open.visible = false
		_shoulders[0].rotation = Vector3(0.05, 0, -0.22)
		_elbows[0].rotation.x = 0.35
	return struck


func set_gesture(g: String) -> void:
	gesture = g
	gesture_t = 0.0
	if g == "":
		_head.rotation.z = 0.0
		_head.rotation.y = 0.0
