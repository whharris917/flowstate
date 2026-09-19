class_name RoutingExercises
## Routing exercises on the Maine site (director, 2026-09-19: the
## showcase's auto-routed pipes are "a spaghettified mess"; rather than
## work on the showcase, simple configurations go on the Maine factory
## one at a time, the director examines each auto-routed line and
## says what is wrong). Every exercise is a few pieces of equipment
## and a line laid with no waypoints, so what is seen is the router's
## own answer. They accumulate here in the order they were asked for.


static func build(plant: Plant) -> void:
	_one_source_one_tank(plant)


## Exercise 1: a single supply header leading to a single tank, on the
## pad, eight metres apart. The header's outlet faces the tank; the
## tank stands as placed, so its inlet nozzle faces where a fresh
## tank's does (south-west), not the header.
static func _one_source_one_tank(plant: Plant) -> void:
	plant.place("source", "supply_1", {}, Vector3(-4.0, 0.0, -2.0), 0.0, false)
	plant.place("tank", "t_1", {"height_m": 2.4, "diameter_m": 1.1},
		Vector3(4.0, 0.0, -2.0), 0.0, false)
	var err := plant.connect_equipment("supply_1", "outlet", "t_1", "inlet")
	if err != "":
		push_error("routing exercise 1: " + err)
