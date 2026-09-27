class_name ActorFigure
extends PlayerFigure
## An actor's body: the player's skeleton and walking gait, dressed from
## data the actor may rewrite as it likes. A body is a list of parts,
## each a simple solid hung on a joint of the skeleton, sized, placed,
## turned, coloured and finished; parts with a tag can be shown and
## hidden by an action (a mouth that smiles, a book that opens). An
## action is a set of keyframed joint angles, a lift and a roll of the
## whole body, played over the walk and faded in and out, so a new
## ability (a jump, a shrug, a handstand) is data too.
##
## Joints: root (the whole figure, at the feet), pelvis, spine, neck,
## head, hip_l, hip_r, knee_l, knee_r, ankle_l, ankle_r, shoulder_l,
## shoulder_r, elbow_l, elbow_r, hand_l, hand_r. A part's "at" and
## "rot" are in its joint's frame: x to the actor's right, y up, -z
## forward; angles in degrees. Joint angles in an action are the same
## frame's; at 0 every joint hangs straight (arms down, legs straight).

const JOINTS := ["root", "pelvis", "spine", "neck", "head", "hip_l", "hip_r", "knee_l", "knee_r", "ankle_l",
	"ankle_r", "shoulder_l", "shoulder_r", "elbow_l", "elbow_r", "hand_l", "hand_r"]
const SHAPES := ["box", "sphere", "capsule", "cylinder", "cone", "torus"]
const FINISHES := ["cloth", "skin", "hair", "shiny", "metal", "glass", "glow", "matte"]
const MAX_PARTS := 180
const MAX_SIZE := 2.5

var joints: Dictionary = {}               # name -> Node3D
var _parts: Array[Node3D] = []
var _tags: Dictionary = {}                # tag -> Array[Node3D]
var _materials: Dictionary = {}
var _hidden_by_default: Dictionary = {}   # tag -> true when the body hides it at rest
var _hands: Array[Node3D] = []
## The body's own stance at rest (joint: [x, y, z] degrees): how it holds
## its arms when not busy.
var rest: Dictionary = {}
## Life in the face: the eyes blink every few seconds; the mouth works
## while the actor speaks; the head turns toward what it attends to.
## Eyes are the parts tagged "eyes", or, untagged, the small dark
## spheres on the face; the mouth is the parts tagged "mouth", opened by
## showing "mouth_open" where there is one, by stretching "mouth" where not.
var talking := false
var head_turn := 0.0          # radians, left positive, laid over the pose
var _eyes: Array[Node3D] = []
var _blink_in := 2.5
var _blink_left := 0.0
var _talk_t := 0.0

## The action playing: its definition, its time, its fade.
var action: Dictionary = {}
var action_t := 0.0
var _fade := 0.0
var _ending := false
var _base_y := 0.0


func _ready() -> void:
	_pelvis = _joint(self, Vector3(0, HIP_H, 0))
	for side: float in [-1.0, 1.0]:
		var hip := _joint(_pelvis, Vector3(0.095 * side, 0, 0))
		var knee := _joint(hip, Vector3(0, -THIGH, 0))
		var ankle := _joint(knee, Vector3(0, -SHIN, 0))
		_hips.append(hip)
		_knees.append(knee)
		_ankles.append(ankle)
	_spine = _joint(self, Vector3(0, HIP_H + 0.06, 0))
	for side: float in [-1.0, 1.0]:
		var shoulder := _joint(_spine, Vector3(0.21 * side, 0.40, 0))
		var elbow := _joint(shoulder, Vector3(0, -UPPER_ARM, 0))
		_hands.append(_joint(elbow, Vector3(0, -FOREARM - 0.03, 0)))
		_shoulders.append(shoulder)
		_elbows.append(elbow)
	_neck = _joint(_spine, Vector3(0, 0.46, 0))
	_head = _joint(_neck, Vector3(0, 0.06, 0))
	joints = {"root": self, "pelvis": _pelvis, "spine": _spine, "neck": _neck, "head": _head,
		"hip_l": _hips[0], "hip_r": _hips[1], "knee_l": _knees[0], "knee_r": _knees[1],
		"ankle_l": _ankles[0], "ankle_r": _ankles[1], "shoulder_l": _shoulders[0], "shoulder_r": _shoulders[1],
		"elbow_l": _elbows[0], "elbow_r": _elbows[1], "hand_l": _hands[0], "hand_r": _hands[1]}


## Check a body before it is worn: the problems, empty when it is fine.
static func check_body(spec: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var parts: Variant = spec.get("parts", [])
	if not parts is Array:
		return ["parts must be a list"]
	if (parts as Array).size() > MAX_PARTS:
		problems.append("at most %d parts" % MAX_PARTS)
	var k := 0
	for p: Variant in parts:
		k += 1
		if not p is Dictionary:
			problems.append("part %d is not an object" % k)
			continue
		var d: Dictionary = p
		if not str(d.get("joint", "")) in JOINTS:
			problems.append("part %d: no joint called '%s'" % [k, d.get("joint", "")])
		if not str(d.get("shape", "")) in SHAPES:
			problems.append("part %d: shape must be one of %s" % [k, ", ".join(SHAPES)])
		if d.has("finish") and not str(d["finish"]) in FINISHES:
			problems.append("part %d: finish must be one of %s" % [k, ", ".join(FINISHES)])
		for key: String in ["size", "at", "rot"]:
			if d.has(key) and not (d[key] is Array and (d[key] as Array).size() == 3):
				problems.append("part %d: %s must be three numbers" % [k, key])
	return problems


## Wear a body: every part rebuilt from the spec.
func wear(spec: Dictionary) -> void:
	for n in _parts:
		n.queue_free()
	_parts.clear()
	_tags.clear()
	_hidden_by_default.clear()
	rest = spec.get("rest", {}) if spec.get("rest", {}) is Dictionary else {}
	_eyes.clear()
	var s := clampf(float(spec.get("scale", 1.0)), 0.5, 1.6)
	scale = Vector3(s, s, s)
	for p: Dictionary in spec.get("parts", []):
		var joint: Node3D = joints.get(str(p.get("joint", "spine")), _spine)
		var mesh := _mesh(str(p.get("shape", "box")), _vec(p.get("size", [0.1, 0.1, 0.1]), 0.005, MAX_SIZE))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _finish(Color.from_string(str(p.get("color", "#888888")), Color(0.5, 0.5, 0.5)),
			str(p.get("finish", "cloth")))
		var rot := _vec(p.get("rot", [0, 0, 0]), -720.0, 720.0)
		mi.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))),
			_vec(p.get("at", [0, 0, 0]), -3.0, 3.0))
		joint.add_child(mi)
		_parts.append(mi)
		var tag := str(p.get("tag", ""))
		if tag == "eyes" or (tag == "" and _looks_like_eye(p)):
			_eyes.append(mi)
		if tag != "":
			if not _tags.has(tag):
				_tags[tag] = []
			(_tags[tag] as Array).append(mi)
			if bool(p.get("hidden", false)):
				mi.visible = false
				_hidden_by_default[tag] = true


## An untagged part that is plainly an eye: a small dark sphere on the
## front of the head, off the middle.
func _looks_like_eye(p: Dictionary) -> bool:
	if str(p.get("joint", "")) != "head" or str(p.get("shape", "")) != "sphere":
		return false
	var s := _vec(p.get("size", [1, 1, 1]), 0.0, 9.0)
	var at := _vec(p.get("at", [0, 0, 0]), -9.0, 9.0)
	var c := Color.from_string(str(p.get("color", "#888888")), Color.GRAY)
	return maxf(s.x, maxf(s.y, s.z)) < 0.045 and at.z < -0.07 and absf(at.x) > 0.015 and absf(at.x) < 0.07 and c.get_luminance() < 0.3


func _vec(v: Variant, lo: float, hi: float) -> Vector3:
	if v is Array and (v as Array).size() == 3:
		var a: Array = v
		return Vector3(clampf(float(a[0]), lo, hi), clampf(float(a[1]), lo, hi), clampf(float(a[2]), lo, hi))
	return Vector3.ZERO


## A primitive of the given outer size (metres, x y z).
func _mesh(shape: String, s: Vector3) -> Mesh:
	match shape:
		"box":
			var b := BoxMesh.new()
			b.size = s
			return b
		"sphere":
			var m := SphereMesh.new()
			m.radius = 0.5
			m.height = 1.0
			m.radial_segments = 16
			m.rings = 8
			return _baked(m, s)
		"capsule":
			# A capsule as wide as x, as tall as y, as deep as z.
			var c := CapsuleMesh.new()
			c.radius = 0.5
			c.height = maxf(s.y / maxf(s.x, 0.001), 1.0)
			c.radial_segments = 12
			c.rings = 4
			return _baked(c, Vector3(s.x, s.x, s.z))
		"cylinder", "cone":
			var cy := CylinderMesh.new()
			cy.bottom_radius = s.x / 2.0
			cy.top_radius = 0.0 if shape == "cone" else s.z / 2.0
			cy.height = s.y
			cy.radial_segments = 14
			return cy
		"torus":
			var t := TorusMesh.new()
			t.outer_radius = s.x / 2.0
			t.inner_radius = maxf(s.x / 2.0 - s.y, 0.001)
			t.rings = 16
			t.ring_segments = 8
			return t
	return BoxMesh.new()


## A primitive stretched by s, baked into the mesh so the part's own
## transform stays free.
func _baked(m: PrimitiveMesh, s: Vector3) -> Mesh:
	var arrays := m.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in v.size():
		v[i] = v[i] * s
		n[i] = (n[i] / s).normalized()
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


func _finish(c: Color, finish: String) -> Material:
	var key := "%s/%s" % [c.to_html(), finish]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	match finish:
		"skin":
			m.roughness = 0.55
		"hair":
			m.roughness = 0.8
		"shiny":
			m.roughness = 0.2
			m.clearcoat_enabled = true
		"metal":
			m.metallic = 0.9
			m.roughness = 0.3
		"glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = minf(c.a, 0.5)
			m.roughness = 0.05
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"glow":
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 2.0
		"matte":
			m.roughness = 1.0
		_:
			m.roughness = 0.85
	_materials[key] = m
	return m


## ---- actions ------------------------------------------------------------

## Check an action before it is learnt: the problems, empty when fine.
static func check_action(a: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var keys: Variant = a.get("keys", [])
	if not keys is Array or (keys as Array).is_empty():
		return ["an action needs keys: a list of {t, pose, lift, roll}"]
	if (keys as Array).size() > 64:
		problems.append("at most 64 keys")
	for k: Variant in keys:
		if not k is Dictionary:
			problems.append("each key is an object")
			continue
		var pose: Variant = (k as Dictionary).get("pose", {})
		if not pose is Dictionary:
			problems.append("a key's pose is an object of joint: [x, y, z] degrees")
			continue
		for j: String in (pose as Dictionary):
			if not j in JOINTS or j == "root":
				problems.append("no joint called '%s' to pose (use lift and roll for the whole body)" % j)
	var secs := float(a.get("secs", 1.0))
	if secs <= 0.0 or secs > 30.0:
		problems.append("secs between 0 and 30")
	return problems


## Start an action (its definition as checked); it runs its secs, then
## fades out unless it holds.
func play(a: Dictionary) -> void:
	action = a
	action_t = 0.0
	_ending = false
	for tag: String in a.get("show", []):
		_show(tag, true)
	for tag: String in a.get("hide", []):
		_show(tag, false)


## Let go of the action: it fades back into the walk.
func release() -> void:
	if not action.is_empty():
		_ending = true


func _show(tag: String, on: bool) -> void:
	for n: Node3D in _tags.get(tag, []):
		n.visible = on


func _restore_tags() -> void:
	for tag: String in _tags:
		_show(tag, not _hidden_by_default.has(tag))


func busy() -> bool:
	return not action.is_empty()


func pose(delta: float, velocity: Vector3, grounded: bool, pitch: float) -> bool:
	var struck := super(delta, velocity, grounded, pitch)
	_face(delta)
	for j: String in rest:
		var rn: Node3D = joints.get(j)
		if rn != null and rn != self:
			rn.rotation = _deg(rest[j])
	if action.is_empty():
		_fade = 0.0
		position = Vector3.ZERO
		rotation = Vector3.ZERO
		_head.rotation.y += head_turn
		return struck
	action_t += delta
	var secs := float(action.get("secs", 1.0))
	var loop := bool(action.get("loop", false))
	var hold := bool(action.get("hold", false))
	var t := fmod(action_t, secs) if loop else minf(action_t, secs)
	if not loop and not hold and action_t >= secs:
		_ending = true
	_fade = move_toward(_fade, 0.0 if _ending else 1.0, delta / 0.2)
	if _ending and _fade <= 0.0:
		action = {}
		_restore_tags()
		position = Vector3.ZERO
		rotation = Vector3.ZERO
		return struck
	# The two keys either side of t, and how far between.
	var keys: Array = action.get("keys", [])
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[0]
	for k: Dictionary in keys:
		if float(k.get("t", 0.0)) <= t:
			a = k
			b = k
		else:
			b = k
			break
	var ta := float(a.get("t", 0.0))
	var tb := float(b.get("t", 0.0))
	var f := 0.0 if tb <= ta else clampf((t - ta) / (tb - ta), 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	var pa: Dictionary = a.get("pose", {})
	var pb: Dictionary = b.get("pose", {})
	var names := {}
	for j: String in pa:
		names[j] = true
	for j: String in pb:
		names[j] = true
	for j: String in names:
		var node: Node3D = joints.get(j)
		if node == null or node == self:
			continue
		var ra := _deg(pa.get(j, pb.get(j, [0, 0, 0])))
		var rb := _deg(pb.get(j, pa.get(j, [0, 0, 0])))
		node.rotation = node.rotation.lerp(ra.lerp(rb, f), _fade)
	var lift := lerpf(float(a.get("lift", 0.0)), float(b.get("lift", 0.0)), f)
	var roll := _deg(a.get("roll", [0, 0, 0])).lerp(_deg(b.get("roll", [0, 0, 0])), f)
	position = Vector3(0, lift * _fade, 0)
	rotation = roll * _fade
	_head.rotation.y += head_turn * (1.0 - _fade)
	return struck


## Blinks, the working mouth; the head's turn is laid on after the pose.
func _face(delta: float) -> void:
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_left = 0.13
		_blink_in = randf_range(2.2, 5.5)
	_blink_left -= delta
	var shut := _blink_left > 0.0
	for e in _eyes:
		e.scale.y = 0.12 if shut else 1.0
	var open := false
	if talking:
		_talk_t += delta
		# Syllables: open and shut about six times a second, unevenly.
		open = fmod(_talk_t * 6.3 + 0.35 * sin(_talk_t * 2.1), 1.0) < 0.55
	else:
		_talk_t = 0.0
	if _tags.has("mouth_open"):
		_show("mouth_open", open)
		if not action.get("hide", []).has("mouth") and not action.get("show", []).has("smile"):
			_show("mouth", not open)
	elif _tags.has("mouth"):
		for m: Node3D in _tags["mouth"]:
			m.scale.y = 4.0 if open else 1.0


func _deg(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() == 3:
		var a: Array = v
		return Vector3(deg_to_rad(float(a[0])), deg_to_rad(float(a[1])), deg_to_rad(float(a[2])))
	return Vector3.ZERO
