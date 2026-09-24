class_name PlayerFigure
extends Node3D
## The player's body: a person in ship coveralls and work boots, built
## from primitives hung on a skeleton of joints and posed every frame
## from how the player moves. The legs turn toward the direction of
## travel, the chest and head toward the direction of view. On the
## ground the feet stay on the floor: the pelvis sits at the height of
## the longer leg, which gives the stride its rise and fall. In the air
## the legs tuck while rising and reach for the floor while falling; a
## landing bends the knees in proportion to the fall.

const HIP_H := 0.94          # hip joint above the soles, standing straight
const THIGH := 0.44
const SHIN := 0.42
const ANKLE_H := 0.08
const UPPER_ARM := 0.30
const FOREARM := 0.26
const STRIDE := 2.6          # metres travelled per gait cycle (two steps)
const FULL_SPEED := 4.0      # speed at which the gait reaches full swing
const HIP_TURN := 1.0        # the most the legs turn from the view, rad

const COVERALL := Color(0.34, 0.40, 0.46)
const BOOT := Color(0.07, 0.07, 0.07)
const GLOVE := Color(0.13, 0.13, 0.14)
const SKIN := Color(0.70, 0.52, 0.41)
const HAIR := Color(0.11, 0.08, 0.06)

var _pelvis: Node3D
var _spine: Node3D
var _neck: Node3D
var _head: Node3D
var _hips: Array[Node3D] = []       # left, right
var _knees: Array[Node3D] = []
var _ankles: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _head_parts: Array[MeshInstance3D] = []

var _travel: float = 0.0    # gait cycles walked, signed, never wrapped
var _gait: float = 0.0      # 0 standing .. 1 full stride
var _air: float = 0.0       # 0 on the ground .. 1 airborne
var _rise: float = 0.0      # 1 rising .. 0 falling, while airborne
var _land: float = 0.0      # landing crouch, decays
var _hip_yaw: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	var cloth := ViewUtil.matte(COVERALL)
	cloth.roughness = 0.88
	var boot := _material(BOOT, 0.8)
	var glove := _material(GLOVE, 0.7)
	var skin := _material(SKIN, 0.55)
	var hair := _material(HAIR, 0.85)

	_pelvis = _joint(self, Vector3(0, HIP_H, 0))
	_part(_pelvis, _sphere(0.16), Vector3(0, 0.04, 0), cloth, Vector3(1.05, 0.72, 0.76))
	_part(_pelvis, _cylinder(0.158, 0.158, 0.05), Vector3(0, 0.1, 0), boot,
		Vector3(1.0, 1.0, 0.74))
	for side: float in [-1.0, 1.0]:
		var hip := _joint(_pelvis, Vector3(0.095 * side, 0, 0))
		_part(hip, _cylinder(0.078, 0.058, THIGH), Vector3(0, -THIGH / 2.0, 0), cloth)
		var knee := _joint(hip, Vector3(0, -THIGH, 0))
		_part(knee, _sphere(0.058), Vector3.ZERO, cloth)
		_part(knee, _cylinder(0.056, 0.046, SHIN), Vector3(0, -SHIN / 2.0, 0), cloth)
		_part(knee, _cylinder(0.062, 0.058, 0.2), Vector3(0, -SHIN + 0.1, 0), boot)
		var ankle := _joint(knee, Vector3(0, -SHIN, 0))
		_part(ankle, _box(Vector3(0.105, ANKLE_H, 0.27)), Vector3(0, -ANKLE_H / 2.0, -0.075), boot)
		_hips.append(hip)
		_knees.append(knee)
		_ankles.append(ankle)

	_spine = _joint(self, Vector3(0, HIP_H + 0.06, 0))
	_part(_spine, _capsule(0.16, 0.52), Vector3(0, 0.23, 0), cloth, Vector3(1.18, 1.0, 0.72))
	var yoke := _part(_spine, _capsule(0.075, 0.46), Vector3(0, 0.40, 0), cloth,
		Vector3(1.0, 1.0, 0.9))
	yoke.rotation.z = PI / 2.0
	_part(_spine, _cylinder(0.062, 0.066, 0.05), Vector3(0, 0.47, 0), cloth)
	for side: float in [-1.0, 1.0]:
		var shoulder := _joint(_spine, Vector3(0.22 * side, 0.40, 0))
		_part(shoulder, _sphere(0.062), Vector3.ZERO, cloth)
		_part(shoulder, _cylinder(0.058, 0.048, UPPER_ARM), Vector3(0, -UPPER_ARM / 2.0, 0), cloth)
		var elbow := _joint(shoulder, Vector3(0, -UPPER_ARM, 0))
		_part(elbow, _sphere(0.048), Vector3.ZERO, cloth)
		_part(elbow, _cylinder(0.047, 0.04, FOREARM - 0.06), Vector3(0, -(FOREARM - 0.06) / 2.0, 0), cloth)
		_part(elbow, _cylinder(0.046, 0.042, 0.07), Vector3(0, -FOREARM + 0.035, 0), glove)
		_part(elbow, _box(Vector3(0.05, 0.1, 0.085)), Vector3(0, -FOREARM - 0.045, 0), glove)
		_shoulders.append(shoulder)
		_elbows.append(elbow)

	_neck = _joint(_spine, Vector3(0, 0.46, 0))
	_head_parts.append(_part(_neck, _cylinder(0.046, 0.05, 0.1), Vector3(0, 0.04, 0), skin))
	_head = _joint(_neck, Vector3(0, 0.06, 0))
	_head_parts.append(_part(_head, _sphere(0.105), Vector3(0, 0.09, 0), skin,
		Vector3(0.9, 1.12, 1.0)))
	_head_parts.append(_part(_head, _sphere(0.112), Vector3(0, 0.107, 0.02), hair,
		Vector3(0.93, 1.06, 1.0)))
	_head_parts.append(_part(_head, _box(Vector3(0.024, 0.04, 0.03)), Vector3(0, 0.075, -0.106), skin))
	for side: float in [-1.0, 1.0]:
		_head_parts.append(_part(_head, _sphere(0.026), Vector3(0.096 * side, 0.085, 0.006), skin,
			Vector3(0.4, 1.0, 0.7)))


## Pose the body for this frame. `velocity` is in the player's own
## frame (forward is -Z), `pitch` the camera's. Returns true on the
## frame a foot strikes the floor.
func pose(delta: float, velocity: Vector3, grounded: bool, pitch: float) -> bool:
	_clock += delta
	var forward := -velocity.z
	var side := velocity.x
	var speed := Vector2(forward, side).length()

	# Which way the legs face, and whether they walk forward or back.
	var direction := 1.0
	var yaw_target := 0.0
	if speed > 0.3:
		if forward < -0.2 * speed:
			direction = -1.0
			yaw_target = atan2(side, -forward)
		else:
			yaw_target = atan2(-side, forward)
		yaw_target = clampf(yaw_target, -HIP_TURN, HIP_TURN)
	_hip_yaw = lerpf(_hip_yaw, yaw_target, 1.0 - exp(-8.0 * delta))

	var struck := false
	if grounded:
		var before := floorf(2.0 * _travel - 0.5)
		_travel += direction * speed * delta / STRIDE
		struck = floorf(2.0 * _travel - 0.5) != before and _gait > 0.3
	_gait = lerpf(_gait, clampf(speed / FULL_SPEED, 0.0, 1.0), 1.0 - exp(-10.0 * delta))
	_air = lerpf(_air, 0.0 if grounded else 1.0, 1.0 - exp(-14.0 * delta))
	_rise = lerpf(_rise, 1.0 if velocity.y > 0.0 else 0.0, 1.0 - exp(-6.0 * delta))
	_land = lerpf(_land, 0.0, 1.0 - exp(-7.0 * delta))

	var reach: Array[float] = [0.0, 0.0]
	var swings: Array[float] = [0.0, 0.0]
	for i in 2:
		var a := TAU * (_travel + 0.5 * i)
		var swing := sin(a)
		var carry := cos(a)          # positive while the leg swings forward
		var thigh := 0.55 * swing * _gait
		var knee := _gait * (0.15 + 1.1 * pow(maxf(carry, 0.0), 2.0) + 0.25 * maxf(-carry, 0.0))
		var tuck := 1.0 if i == 0 else 0.8
		thigh = lerpf(thigh, lerpf(0.3, 0.75, _rise) * tuck, _air) + 0.55 * _land
		knee = lerpf(knee, lerpf(0.45, 1.35, _rise) * tuck, _air) + 1.1 * _land
		_hips[i].rotation = Vector3(thigh, 0, 0)
		_knees[i].rotation.x = -knee
		_ankles[i].rotation.x = -(thigh - knee) * 0.85
		reach[i] = THIGH * cos(thigh) + SHIN * cos(thigh - knee) + ANKLE_H
		swings[i] = swing

	var height := lerpf(maxf(reach[0], reach[1]), HIP_H, _air)
	_pelvis.position.y = height
	_pelvis.rotation.y = _hip_yaw
	_spine.position.y = height + 0.06
	var lean := 0.09 * _gait + 0.3 * _land + 0.05 * _air
	var twist := -0.12 * swings[0] * _gait * (1.0 - _air)
	_spine.rotation = Vector3(-lean, 0.3 * _hip_yaw + twist, 0)

	var breath := 0.025 * sin(_clock * 1.7)
	for i in 2:
		var side_sign := -1.0 if i == 0 else 1.0
		var arm := -0.6 * swings[i] * _gait + breath * (1.0 - _gait)
		arm = lerpf(arm, 0.1 + 0.25 * _rise, _air) + 0.3 * _land
		var spread := 0.1 + 0.3 * _air
		_shoulders[i].rotation = Vector3(arm, 0, spread * side_sign)
		_elbows[i].rotation.x = lerpf(0.2 + 0.95 * _gait, 0.5, _air)

	var look := clampf(pitch, -1.0, 0.9)
	_neck.rotation.x = 0.35 * look + lean
	_head.rotation.x = 0.65 * look
	return struck


## Keep the head out of a camera that has come in close behind the
## eyes; it still casts its shadow.
func show_head(visible_: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if visible_ \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for part in _head_parts:
		part.cast_shadow = mode


## A crouch on landing, deeper for a harder fall.
func land(fall_speed: float) -> void:
	_land = clampf(fall_speed / 12.0, 0.08, 0.45)


func _joint(parent: Node3D, at: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.position = at
	parent.add_child(joint)
	return joint


func _part(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material,
		stretch: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.scale = stretch
	part.material_override = mat
	parent.add_child(part)
	return part


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


func _cylinder(top: float, bottom: float, length: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = length
	mesh.radial_segments = 14
	mesh.rings = 1
	return mesh


func _capsule(radius: float, length: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.rings = 4
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh
