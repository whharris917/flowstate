class_name SimPort
## One typed terminal on a component.

var owner_component: SimComponent
var port_name: String
var kind: SimTypes.PortKind
var value: float = 0.0


func _init(owner: SimComponent, name_: String, kind_: SimTypes.PortKind) -> void:
	owner_component = owner
	port_name = name_
	kind = kind_


func path() -> String:
	return owner_component.comp_name + "." + port_name
