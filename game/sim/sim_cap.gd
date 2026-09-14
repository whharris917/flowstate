class_name SimCap
extends SimComponent
## A pipe cap: a two-nozzle fitting that is one hydraulic node, a
## blind end while only one nozzle carries a line and a plain
## coupling once both do. A cut leaves one on each side of the cut
## (director, 2026-09-13: cutting is putting a closed cap on a pipe
## until it is connected again). A node with one branch carries no
## flow, so a capped line stands at pressure and moves nothing.
## Mirrors sim/components.py Cap.


func _init(name_: String) -> void:
	super(name_)
	add_input("a", SimTypes.PortKind.PROCESS_MATERIAL)
	add_output("b", SimTypes.PortKind.PROCESS_MATERIAL)


func shared_node_ports() -> Array:
	return [material_ports().keys()]


func tick(_dt: float) -> void:
	pass
