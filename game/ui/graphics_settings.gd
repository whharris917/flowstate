class_name GraphicsSettings
extends RefCounted
## The graphics options (director, 2026-09-12: switch between them in
## play "to understand what the right balance is between speed and
## prettiness"). A dictionary of values, four presets over it, and
## apply(), which pushes the values into the viewport, the rendering
## server, the sun, the environment and the foliage. The world saves
## them with its other settings; the options panel edits them in
## place; F7 cycles the presets in play. Every value is one thing the
## GPU pays for, named in the panel by what it does to the picture.

const PRESET_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra"]

# What each preset sets. High is the game as it was tuned on
# 2026-09-11; Low is what an integrated GPU can hold; Ultra adds the
# global illumination and fog the old "high lighting" toggle held.
const PRESETS: Dictionary = {
	"Low": {"scale": 0.59, "upscaler": "fsr2", "aa": "off", "shadow_size": 2048,
		"shadow_filter": "hard", "shadow_distance": 60, "ssao": false, "ssr": false,
		"glow": false, "sdfgi": false, "volumetric_fog": false, "tree_shadows": false},
	"Medium": {"scale": 0.77, "upscaler": "fsr2", "aa": "off", "shadow_size": 4096,
		"shadow_filter": "soft_low", "shadow_distance": 120, "ssao": true, "ssr": false,
		"glow": true, "sdfgi": false, "volumetric_fog": false, "tree_shadows": true},
	"High": {"scale": 1.0, "upscaler": "bilinear", "aa": "msaa4", "shadow_size": 8192,
		"shadow_filter": "soft_medium", "shadow_distance": 200, "ssao": true, "ssr": true,
		"glow": true, "sdfgi": false, "volumetric_fog": false, "tree_shadows": true},
	"Ultra": {"scale": 1.0, "upscaler": "bilinear", "aa": "msaa4", "shadow_size": 8192,
		"shadow_filter": "soft_ultra", "shadow_distance": 200, "ssao": true, "ssr": true,
		"glow": true, "sdfgi": true, "volumetric_fog": true, "tree_shadows": true},
}

# Knobs outside the presets: they change how the picture is measured
# and shown, not how it looks, so they never make a preset "Custom".
const EXTRAS: Dictionary = {"vsync": true, "fps_overlay": true}

# The choice lists, as [value, label] pairs, in the order the panel shows them.
const CHOICES: Dictionary = {
	"upscaler": [["bilinear", "Bilinear"], ["fsr1", "FSR 1"], ["fsr2", "FSR 2"]],
	"aa": [["off", "Off"], ["fxaa", "FXAA"], ["msaa2", "MSAA 2x"], ["msaa4", "MSAA 4x"], ["taa", "TAA"]],
	"shadow_size": [[2048, "2048"], [4096, "4096"], [8192, "8192"]],
	"shadow_filter": [["hard", "Hard"], ["soft_low", "Soft low"], ["soft_medium", "Soft medium"],
		["soft_high", "Soft high"], ["soft_ultra", "Soft ultra"]],
	"shadow_distance": [[60, "60 m"], [120, "120 m"], [200, "200 m"]],
}
const LABELS: Dictionary = {
	"upscaler": "Upscaler", "aa": "Anti-aliasing", "shadow_size": "Shadow map",
	"shadow_filter": "Shadow filter", "shadow_distance": "Shadow distance",
}
# The switches, as [key, label] pairs.
const BOOLS: Array = [
	["ssao", "Ambient occlusion"], ["ssr", "Screen-space reflections"],
	["glow", "Glow"], ["sdfgi", "Global illumination (SDFGI)"],
	["volumetric_fog", "Volumetric fog"], ["tree_shadows", "Tree shadows"],
	["vsync", "VSync"], ["fps_overlay", "Frame-rate overlay"],
]

var values: Dictionary = {}


func _init() -> void:
	set_preset("High")
	for key: String in EXTRAS:
		values[key] = EXTRAS[key]


func set_preset(preset: String) -> void:
	var table: Dictionary = PRESETS[preset]
	for key: String in table:
		values[key] = table[key]


## The preset the values match, or "Custom".
func preset_name() -> String:
	for preset: String in PRESET_NAMES:
		var table: Dictionary = PRESETS[preset]
		var same := true
		for key: String in table:
			if not _same(values.get(key), table[key]):
				same = false
				break
		if same:
			return preset
	return "Custom"


## F7: the next preset up, wrapping; Custom goes to Low.
func next_preset() -> String:
	var idx := PRESET_NAMES.find(preset_name())
	var next := PRESET_NAMES[(idx + 1) % PRESET_NAMES.size()]
	set_preset(next)
	return next


func to_dict() -> Dictionary:
	return values.duplicate()


## JSON hands back floats for every number and nothing for a key a
## newer build added, so each value is coerced to its own kind.
func from_dict(saved: Dictionary) -> void:
	for key: String in values:
		if not saved.has(key):
			continue
		var current: Variant = values[key]
		var incoming: Variant = saved[key]
		if current is bool:
			values[key] = bool(incoming)
		elif current is int:
			values[key] = int(incoming)
		elif current is float:
			values[key] = float(incoming)
		else:
			values[key] = str(incoming)


## One line for the toast and the overlay: the preset, then what it costs.
func summary() -> String:
	var parts: PackedStringArray = [preset_name(),
		"%d%% %s" % [roundi(float(values["scale"]) * 100.0), label_for("upscaler")],
		label_for("aa"), "shadows %s %s to %d m" % [label_for("shadow_size"),
		label_for("shadow_filter").to_lower(), int(values["shadow_distance"])]]
	var on: PackedStringArray = []
	if bool(values["ssao"]):
		on.append("AO")
	if bool(values["ssr"]):
		on.append("SSR")
	if bool(values["glow"]):
		on.append("glow")
	if bool(values["sdfgi"]):
		on.append("GI")
	if bool(values["volumetric_fog"]):
		on.append("fog")
	if not on.is_empty():
		parts.append(" ".join(on))
	if not bool(values["tree_shadows"]):
		parts.append("no tree shadows")
	return " · ".join(parts)


func label_for(key: String) -> String:
	for pair: Array in CHOICES[key]:
		if _same(pair[0], values[key]):
			return str(pair[1])
	return str(values[key])


func choice_index(key: String) -> int:
	var choices: Array = CHOICES[key]
	for i in choices.size():
		if _same(choices[i][0], values[key]):
			return i
	return 0


static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b


## Push the values into the engine. Everything here is what the GPU
## pays for: the render resolution and how it is upscaled, the
## anti-aliasing, the shadow map and its filter and reach, the
## screen-space passes, global illumination and fog, whether the woods
## cast shadows, and how the frame is presented and measured.
func apply(world: WorldBase) -> void:
	var vp := world.get_viewport()
	var fsr2 := str(values["upscaler"]) == "fsr2"
	if vp != null:
		match str(values["upscaler"]):
			"fsr1":
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			"fsr2":
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			_:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = clampf(float(values["scale"]), 0.25, 1.0)
		# FSR 2 anti-aliases as it upscales; MSAA and TAA under it are
		# paid for and thrown away.
		var aa := str(values["aa"])
		vp.msaa_3d = Viewport.MSAA_DISABLED
		if not fsr2 and aa == "msaa2":
			vp.msaa_3d = Viewport.MSAA_2X
		elif not fsr2 and aa == "msaa4":
			vp.msaa_3d = Viewport.MSAA_4X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" \
			else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = aa == "taa" and not fsr2
	RenderingServer.directional_shadow_atlas_set_size(int(values["shadow_size"]), true)
	var quality := _filter_quality()
	RenderingServer.directional_soft_shadow_filter_set_quality(quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(quality)
	if world.sun != null:
		world.sun.directional_shadow_max_distance = float(values["shadow_distance"])
	var env := world.sky_env
	if env == null:
		for node in world.find_children("*", "WorldEnvironment", true, false):
			env = (node as WorldEnvironment).environment
			break
	if env != null:
		env.ssao_enabled = bool(values["ssao"])
		env.ssr_enabled = bool(values["ssr"])
		env.glow_enabled = bool(values["glow"])
		env.sdfgi_enabled = bool(values["sdfgi"])
		env.sdfgi_use_occlusion = true
		env.sdfgi_bounce_feedback = 0.5
		if world.sky_mat != null:  # outdoors; the hall keeps its own fog either way
			env.volumetric_fog_enabled = bool(values["volumetric_fog"])
	var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(values["tree_shadows"]) \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node in world.get_tree().get_nodes_in_group("foliage_shadows"):
		(node as GeometryInstance3D).cast_shadow = cast
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(values["vsync"])
			else DisplayServer.VSYNC_DISABLED)
	if world.hud != null:
		world.hud.set_fps_overlay(bool(values["fps_overlay"]), summary())


func _filter_quality() -> RenderingServer.ShadowQuality:
	match str(values["shadow_filter"]):
		"hard":
			return RenderingServer.SHADOW_QUALITY_HARD
		"soft_low":
			return RenderingServer.SHADOW_QUALITY_SOFT_LOW
		"soft_medium":
			return RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
		"soft_high":
			return RenderingServer.SHADOW_QUALITY_SOFT_HIGH
		_:
			return RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
