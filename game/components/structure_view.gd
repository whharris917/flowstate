class_name StructureView
extends StaticBody3D
## A placed structural element: real collision on layer 1, so runs can
## be routed along it, waypoints land on it, and the support rule
## counts it. Not sim-backed — structure carries load, not process.

var type_id: String
var struct_name: String


func describe() -> String:
	return "%s — structure (X removes)" % struct_name
