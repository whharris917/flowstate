class_name ActorPresets
extends RefCounted
## The bodies an actor can start from, and the actions every actor knows
## from the start. Both are the same data an actor writes for itself:
## ActorFigure explains the frame, the shapes and the joints.
##
## Joint angles, in degrees, in the joint's own frame at rest:
##   shoulder x+ swings the arm forward and up; shoulder_r z+ raises
##   the right arm out to the side, shoulder_l z- the left
##   elbow x+ bends the forearm up in front
##   hip x+ swings the leg forward; knee x- bends the knee
##   spine x- leans forward; neck and head x- look down, y+ turn left
## An action's lift raises (or, negative, lowers) the whole body,
## metres; roll turns the whole body about the feet, degrees.


static func body(name: String) -> Dictionary:
	match name:
		"clerk":
			return _clerk()
	return _plain()


## A plain figure: grey shirt and trousers, a face, short hair.
static func _plain() -> Dictionary:
	var shirt := "#8a8f98"
	var trousers := "#3b3d45"
	var skin := "#d9b193"
	var hair := "#3a2a1c"
	var parts: Array = _skeleton_clothes(shirt, trousers, "#1a1a1a", skin)
	parts.append_array(_head(skin, hair))
	return {"scale": 1.0, "parts": parts}


static func _clerk() -> Dictionary:
	var shirt := "#eeebe0"
	var vest := "#5c3420"
	var trousers := "#3d3b40"
	var skin := "#e8c0a4"
	var hair := "#33210f"
	var brass := "#cca44c"
	var black := "#080808"
	var parts: Array = _skeleton_clothes(shirt, trousers, black, skin)
	# The waistcoat, its buttons and chain, the bow tie, the garters.
	parts.append_array([
		{"joint": "spine", "shape": "capsule", "size": [0.353, 0.44, 0.229], "at": [0, 0.19, 0], "color": vest},
		{"joint": "spine", "shape": "cylinder", "size": [0.008, 0.16, 0.008], "at": [0.05, 0.12, -0.115], "rot": [0, 0, 69], "color": brass, "finish": "metal"},
		{"joint": "spine", "shape": "box", "size": [0.05, 0.035, 0.012], "at": [-0.025, 0.465, -0.062], "rot": [0, 0, -14], "color": black},
		{"joint": "spine", "shape": "box", "size": [0.05, 0.035, 0.012], "at": [0.025, 0.465, -0.062], "rot": [0, 0, 14], "color": black},
		{"joint": "shoulder_l", "shape": "cylinder", "size": [0.118, 0.028, 0.118], "at": [0, -0.165, 0], "color": black},
		{"joint": "shoulder_r", "shape": "cylinder", "size": [0.118, 0.028, 0.118], "at": [0, -0.165, 0], "color": black},
	])
	for k in 5:
		parts.append({"joint": "spine", "shape": "sphere", "size": [0.022, 0.022, 0.022], "at": [0, 0.07 + k * 0.055, -0.117], "color": brass, "finish": "metal"})
	parts.append_array(_head(skin, hair))
	# Middle-parted hair and whiskers, over the plain head's hair.
	parts = parts.filter(func(p: Dictionary) -> bool: return str(p.get("tag", "")) != "hair")
	for s: float in [-1.0, 1.0]:
		parts.append({"joint": "head", "shape": "sphere", "size": [0.108, 0.205, 0.216], "at": [0.045 * s, 0.118, 0.018], "color": hair, "finish": "hair"})
		parts.append({"joint": "head", "shape": "box", "size": [0.022, 0.07, 0.04], "at": [0.088 * s, 0.06, -0.035], "color": hair, "finish": "hair"})
		# The spectacles.
		parts.append({"joint": "head", "shape": "torus", "size": [0.054, 0.005, 0.054], "at": [0.037 * s, 0.105, -0.098], "rot": [90, 0, 0], "color": brass, "finish": "metal"})
		parts.append({"joint": "head", "shape": "box", "size": [0.003, 0.003, 0.1], "at": [0.068 * s, 0.108, -0.05], "color": brass, "finish": "metal"})
	parts.append_array([
		{"joint": "head", "shape": "box", "size": [0.022, 0.003, 0.003], "at": [0, 0.11, -0.1], "color": brass, "finish": "metal"},
		# The green eyeshade and its band.
		{"joint": "head", "shape": "cylinder", "size": [0.2, 0.025, 0.2], "at": [0, 0.155, 0.01], "color": black},
		{"joint": "head", "shape": "cylinder", "size": [0.29, 0.012, 0.18], "at": [0, 0.15, -0.07], "rot": [-20, 0, 0], "color": "#33a05c8c", "finish": "glass"},
		# The pen behind his ear.
		{"joint": "head", "shape": "cylinder", "size": [0.008, 0.15, 0.01], "at": [0.1, 0.12, -0.01], "rot": [74, 0, 11], "color": black},
		# The ledger under his arm, and the ledger open in his hands.
		{"joint": "spine", "shape": "box", "size": [0.035, 0.3, 0.23], "at": [-0.19, 0.2, -0.02], "color": "#6b1a14", "tag": "ledger"},
		{"joint": "spine", "shape": "box", "size": [0.028, 0.285, 0.215], "at": [-0.186, 0.2, -0.02], "color": "#ede3c2", "tag": "ledger"},
	])
	for s: float in [-1.0, 1.0]:
		parts.append({"joint": "spine", "shape": "box", "size": [0.22, 0.012, 0.3], "at": [0.11 * s, 0.26, -0.3], "rot": [31, 0, -7 * s], "color": "#6b1a14", "tag": "ledger_open", "hidden": true})
		parts.append({"joint": "spine", "shape": "box", "size": [0.205, 0.01, 0.285], "at": [0.105 * s, 0.27, -0.305], "rot": [31, 0, -7 * s], "color": "#ede3c2", "tag": "ledger_open", "hidden": true})
	return {"scale": 1.0, "parts": parts,
		"rest": {"shoulder_l": [3, 0, -13], "elbow_l": [20, 0, 0]}}


## Trousers, shoes, a shirt with its sleeves, the neck and hands.
static func _skeleton_clothes(shirt: String, trousers: String, shoe: String, skin: String) -> Array:
	var p: Array = [
		{"joint": "pelvis", "shape": "sphere", "size": [0.336, 0.23, 0.243], "at": [0, 0.04, 0], "color": trousers},
		{"joint": "pelvis", "shape": "cylinder", "size": [0.316, 0.05, 0.316], "at": [0, 0.1, 0], "color": shoe},
		{"joint": "spine", "shape": "capsule", "size": [0.345, 0.52, 0.21], "at": [0, 0.23, 0], "color": shirt},
		{"joint": "spine", "shape": "capsule", "size": [0.14, 0.44, 0.126], "at": [0, 0.40, 0], "rot": [0, 0, 90], "color": shirt},
		{"joint": "spine", "shape": "cylinder", "size": [0.124, 0.06, 0.116], "at": [0, 0.47, 0], "color": shirt},
		{"joint": "neck", "shape": "cylinder", "size": [0.096, 0.1, 0.088], "at": [0, 0.04, 0], "color": skin, "finish": "skin"},
	]
	for s: String in ["l", "r"]:
		p.append_array([
			{"joint": "hip_" + s, "shape": "cylinder", "size": [0.112, 0.44, 0.148], "at": [0, -0.22, 0], "color": trousers},
			{"joint": "knee_" + s, "shape": "sphere", "size": [0.112, 0.112, 0.112], "at": [0, 0, 0], "color": trousers},
			{"joint": "knee_" + s, "shape": "cylinder", "size": [0.1, 0.42, 0.108], "at": [0, -0.21, 0], "color": trousers},
			{"joint": "ankle_" + s, "shape": "box", "size": [0.095, 0.08, 0.26], "at": [0, -0.04, -0.07], "color": shoe, "finish": "shiny"},
			{"joint": "shoulder_" + s, "shape": "sphere", "size": [0.12, 0.12, 0.12], "at": [0, 0, 0], "color": shirt},
			{"joint": "shoulder_" + s, "shape": "cylinder", "size": [0.096, 0.30, 0.112], "at": [0, -0.15, 0], "color": shirt},
			{"joint": "elbow_" + s, "shape": "sphere", "size": [0.094, 0.094, 0.094], "at": [0, 0, 0], "color": shirt},
			{"joint": "elbow_" + s, "shape": "cylinder", "size": [0.08, 0.21, 0.092], "at": [0, -0.105, 0], "color": shirt},
			{"joint": "hand_" + s, "shape": "box", "size": [0.045, 0.09, 0.08], "at": [0, 0, 0], "color": skin, "finish": "skin"},
		])
	return p


## A head with a face: eyes, brows, a nose, ears, a mouth that can smile.
static func _head(skin: String, hair: String) -> Array:
	var p: Array = [
		{"joint": "head", "shape": "sphere", "size": [0.185, 0.231, 0.206], "at": [0, 0.09, 0], "color": skin, "finish": "skin"},
		{"joint": "head", "shape": "sphere", "size": [0.2, 0.2, 0.22], "at": [0, 0.13, 0.02], "color": hair, "finish": "hair", "tag": "hair"},
		{"joint": "head", "shape": "box", "size": [0.022, 0.038, 0.03], "at": [0, 0.075, -0.103], "color": skin, "finish": "skin"},
		{"joint": "head", "shape": "box", "size": [0.04, 0.006, 0.008], "at": [0, 0.04, -0.097], "color": "#7a2e28", "tag": "mouth"},
		{"joint": "head", "shape": "sphere", "size": [0.034, 0.024, 0.01], "at": [0, 0.038, -0.096], "color": "#3a1512", "tag": "mouth_open", "hidden": true},
		{"joint": "head", "shape": "box", "size": [0.03, 0.006, 0.008], "at": [0, 0.035, -0.097], "color": "#7a2e28", "tag": "smile", "hidden": true},
		{"joint": "head", "shape": "box", "size": [0.05, 0.02, 0.006], "at": [0, 0.028, -0.094], "color": "#f4f0e6", "tag": "smile", "hidden": true},
	]
	for s: float in [-1.0, 1.0]:
		p.append_array([
			{"joint": "head", "shape": "sphere", "size": [0.022, 0.026, 0.012], "at": [0.037 * s, 0.105, -0.092], "color": "#1c1a18", "finish": "shiny", "tag": "eyes"},
			{"joint": "head", "shape": "box", "size": [0.035, 0.008, 0.01], "at": [0.037 * s, 0.138, -0.093], "rot": [0, 0, -8 * s], "color": hair},
			{"joint": "head", "shape": "sphere", "size": [0.02, 0.05, 0.035], "at": [0.094 * s, 0.085, 0.006], "color": skin, "finish": "skin"},
			{"joint": "head", "shape": "box", "size": [0.016, 0.006, 0.008], "at": [0.022 * s, 0.041, -0.095], "rot": [0, 0, 35 * s], "color": "#7a2e28", "tag": "smile", "hidden": true},
		])
	return p


## The actions every actor knows: the same format an actor uses to teach
## itself a new one.
static func actions() -> Dictionary:
	return {
		"wave": {"secs": 2.4, "keys": [
			{"t": 0.0, "pose": {"shoulder_r": [-10, 0, 150], "elbow_r": [40, 0, 0]}},
			{"t": 0.4, "pose": {"shoulder_r": [-10, 0, 150], "elbow_r": [15, 0, 0]}},
			{"t": 0.8, "pose": {"shoulder_r": [-10, 0, 150], "elbow_r": [55, 0, 0]}},
			{"t": 1.2, "pose": {"shoulder_r": [-10, 0, 150], "elbow_r": [15, 0, 0]}},
			{"t": 1.6, "pose": {"shoulder_r": [-10, 0, 150], "elbow_r": [55, 0, 0]}},
			{"t": 2.4, "pose": {"shoulder_r": [-10, 0, 150], "elbow_r": [30, 0, 0]}}]},
		"bow": {"secs": 1.8, "keys": [
			{"t": 0.0, "pose": {"spine": [0, 0, 0], "neck": [0, 0, 0], "shoulder_r": [0, 0, 0], "elbow_r": [0, 0, 0]}},
			{"t": 0.7, "pose": {"spine": [-35, 0, 0], "neck": [-18, 0, 0], "shoulder_r": [35, 0, -15], "elbow_r": [85, 0, 0]}},
			{"t": 1.1, "pose": {"spine": [-35, 0, 0], "neck": [-18, 0, 0], "shoulder_r": [35, 0, -15], "elbow_r": [85, 0, 0]}},
			{"t": 1.8, "pose": {"spine": [0, 0, 0], "neck": [0, 0, 0], "shoulder_r": [0, 0, 0], "elbow_r": [0, 0, 0]}}]},
		"nod": {"secs": 1.2, "keys": [
			{"t": 0.0, "pose": {"head": [0, 0, 0]}}, {"t": 0.3, "pose": {"head": [-22, 0, 0]}},
			{"t": 0.6, "pose": {"head": [5, 0, 0]}}, {"t": 0.9, "pose": {"head": [-18, 0, 0]}}, {"t": 1.2, "pose": {"head": [0, 0, 0]}}]},
		"shake_head": {"secs": 1.2, "keys": [
			{"t": 0.0, "pose": {"head": [0, 0, 0]}}, {"t": 0.25, "pose": {"head": [0, 30, 0]}},
			{"t": 0.55, "pose": {"head": [0, -30, 0]}}, {"t": 0.85, "pose": {"head": [0, 25, 0]}}, {"t": 1.2, "pose": {"head": [0, 0, 0]}}]},
		"shrug": {"secs": 1.4, "keys": [
			{"t": 0.0, "pose": {"shoulder_l": [0, 0, 0], "shoulder_r": [0, 0, 0], "elbow_l": [0, 0, 0], "elbow_r": [0, 0, 0], "head": [0, 0, 0]}},
			{"t": 0.5, "pose": {"shoulder_l": [15, 0, -25], "shoulder_r": [15, 0, 25], "elbow_l": [95, 0, 0], "elbow_r": [95, 0, 0], "head": [0, 0, 12]}},
			{"t": 0.9, "pose": {"shoulder_l": [15, 0, -25], "shoulder_r": [15, 0, 25], "elbow_l": [95, 0, 0], "elbow_r": [95, 0, 0], "head": [0, 0, 12]}},
			{"t": 1.4, "pose": {"shoulder_l": [0, 0, 0], "shoulder_r": [0, 0, 0], "elbow_l": [0, 0, 0], "elbow_r": [0, 0, 0], "head": [0, 0, 0]}}]},
		"point": {"secs": 2.0, "keys": [
			{"t": 0.0, "pose": {"shoulder_r": [80, 0, 5], "elbow_r": [3, 0, 0]}}, {"t": 2.0, "pose": {"shoulder_r": [80, 0, 5], "elbow_r": [3, 0, 0]}}]},
		"smile": {"secs": 3.0, "show": ["smile"], "hide": ["mouth"], "keys": [{"t": 0.0, "pose": {}}]},
		"read": {"secs": 4.0, "show": ["ledger_open"], "hide": ["ledger"], "keys": [
			{"t": 0.0, "pose": {"shoulder_l": [52, 0, 14], "shoulder_r": [52, 0, -14], "elbow_l": [75, 0, 0], "elbow_r": [75, 0, 0], "neck": [-26, 0, 0], "head": [-14, 6, 0]}},
			{"t": 2.0, "pose": {"shoulder_l": [52, 0, 14], "shoulder_r": [52, 0, -14], "elbow_l": [75, 0, 0], "elbow_r": [75, 0, 0], "neck": [-26, 0, 0], "head": [-14, -6, 0]}},
			{"t": 4.0, "pose": {"shoulder_l": [52, 0, 14], "shoulder_r": [52, 0, -14], "elbow_l": [75, 0, 0], "elbow_r": [75, 0, 0], "neck": [-26, 0, 0], "head": [-14, 6, 0]}}]},
		"jump": {"secs": 1.1, "keys": [
			{"t": 0.0, "lift": 0.0, "pose": {"hip_l": [0, 0, 0], "hip_r": [0, 0, 0], "knee_l": [0, 0, 0], "knee_r": [0, 0, 0], "shoulder_l": [0, 0, 0], "shoulder_r": [0, 0, 0]}},
			{"t": 0.25, "lift": -0.15, "pose": {"hip_l": [35, 0, 0], "hip_r": [35, 0, 0], "knee_l": [-60, 0, 0], "knee_r": [-60, 0, 0], "shoulder_l": [-30, 0, 0], "shoulder_r": [-30, 0, 0]}},
			{"t": 0.55, "lift": 0.55, "pose": {"hip_l": [10, 0, 0], "hip_r": [10, 0, 0], "knee_l": [-20, 0, 0], "knee_r": [-20, 0, 0], "shoulder_l": [150, 0, -10], "shoulder_r": [150, 0, 10]}},
			{"t": 0.85, "lift": -0.1, "pose": {"hip_l": [30, 0, 0], "hip_r": [30, 0, 0], "knee_l": [-50, 0, 0], "knee_r": [-50, 0, 0], "shoulder_l": [20, 0, 0], "shoulder_r": [20, 0, 0]}},
			{"t": 1.1, "lift": 0.0, "pose": {"hip_l": [0, 0, 0], "hip_r": [0, 0, 0], "knee_l": [0, 0, 0], "knee_r": [0, 0, 0], "shoulder_l": [0, 0, 0], "shoulder_r": [0, 0, 0]}}]},
		"sit": {"secs": 0.8, "hold": true, "keys": [
			{"t": 0.0, "lift": 0.0, "pose": {"hip_l": [0, 0, 0], "hip_r": [0, 0, 0], "knee_l": [0, 0, 0], "knee_r": [0, 0, 0]}},
			{"t": 0.8, "lift": -0.46, "pose": {"hip_l": [88, 0, 3], "hip_r": [88, 0, -3], "knee_l": [-88, 0, 0], "knee_r": [-88, 0, 0], "ankle_l": [0, 0, 0], "ankle_r": [0, 0, 0], "shoulder_l": [25, 0, -5], "shoulder_r": [25, 0, 5], "elbow_l": [45, 0, 0], "elbow_r": [45, 0, 0], "spine": [3, 0, 0]}}]},
		"think": {"secs": 3.0, "keys": [
			{"t": 0.0, "pose": {"shoulder_r": [40, 0, -10], "elbow_r": [140, 0, 0], "head": [-8, 0, 6]}},
			{"t": 3.0, "pose": {"shoulder_r": [40, 0, -10], "elbow_r": [140, 0, 0], "head": [-8, 0, 6]}}]},
	}
