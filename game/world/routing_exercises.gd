class_name RoutingExercises
## Routing exercises on the Maine site (director, 2026-09-19: the
## showcase's auto-routed pipes are "a spaghettified mess"; rather than
## work on the showcase, simple configurations go on the Maine factory
## one at a time, the director examines each auto-routed line and
## says what is wrong). Every exercise is a few pieces of equipment
## and a line laid with no waypoints, so what is seen is the router's
## own answer. They accumulate here in the order they were asked for.


static func build(plant: Plant) -> void:
	_one_source_one_pump(plant)


## Exercise 1: a single supply header leading to a single pump, on the
## pad, eight metres apart on one axis: the header's outlet faces the
## pump's inlet exactly in plan. The heights differ, a header at 1.55 m
## and a pump inlet at 0.42 m, so the line must drop once. (A tank was
## the first version; its inlet nozzle could not be aligned this way.)
static func _one_source_one_pump(plant: Plant) -> void:
	plant.place("source", "supply_1", {}, Vector3(-4.0, 0.0, -2.0), 0.0, false)
	plant.place("pump", "p_1", {"rated_lps": 3.0}, Vector3(4.0, 0.0, -2.0), 0.0, false)
	var err := plant.connect_equipment("supply_1", "outlet", "p_1", "inlet")
	if err != "":
		push_error("routing exercise 1: " + err)
