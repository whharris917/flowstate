class_name CourthouseInterior
extends RefCounted
## Inside the Union County courthouse.


static func build(b: UnionCourthouse) -> void:
	var k := b.k
	var g := Transform3D()
	var oak := CourthouseKit.kc(Color(0.52, 0.34, 0.19), CourthouseKit.K_OAK)
	# The ground floor on its fill, solid.
	k.block("wall", g, Vector3(0, UnionCourthouse.F1 / 2.0, 0), Vector3(2.0 * (UnionCourthouse.MX - 0.3), UnionCourthouse.F1,
		2.0 * (UnionCourthouse.MZ - 0.3)), oak)
	for e: float in [-1.0, 1.0]:
		k.block("wall", g, Vector3(0, UnionCourthouse.F1 / 2.0, e * (UnionCourthouse.MZ + UnionCourthouse.WZ) / 2.0),
			Vector3(2.0 * (UnionCourthouse.WX - 0.3), UnionCourthouse.F1, UnionCourthouse.WZ - UnionCourthouse.MZ), oak)
