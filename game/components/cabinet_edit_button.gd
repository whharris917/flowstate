class_name CabinetEditButton
extends Node3D
## The floating EDIT button inside an open cabinet: aim at it and
## click (or E) to enter the cabinet editor. Pure UI affordance.

var open_cb: Callable = Callable()


func build() -> void:
	var plate := ViewUtil.box(self, Vector3(0.34, 0.14, 0.02), Vector3.ZERO,
		ViewUtil.glow(Color(0.16, 0.45, 0.75), 1.2))
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tag := ViewUtil.label(self, "✎ EDIT", Vector3(0, 0, 0.03))
	tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	tag.font_size = 34
	var body := ViewUtil.interact_body(self, Vector3(0.4, 0.2, 0.12), Vector3.ZERO)
	body.set_meta("clickable", true)


func describe() -> String:
	return "open the cabinet editor (click or E)"


func use() -> void:
	if open_cb.is_valid():
		open_cb.call()
