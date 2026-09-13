class_name LoopProfile
extends Node
## Where the main loop's time goes (2026-09-13: the showcase's loop
## cost 21 ms a frame headless, a 45 fps ceiling before rendering).
## Godot has no per-node profiler outside the editor, so this bisects:
## it measures the loop with everything running, then with each group
## switched off in turn — the runs, the equipment views, the HUD, the
## world's own _process — and prints what each group cost. Headless
## only, under FLOWSTATE_LOOP_PROFILE=1; it quits when done.

const FRAMES := 20

var world: WorldBase
var _phases: Array = []
var _phase := -1
var _settle := 0
var _acc := 0.0
var _phys := 0.0
var _n := 0
var _results: Array[String] = []


static func run(on: WorldBase) -> void:
	var profile := LoopProfile.new()
	profile.world = on
	on.add_child(profile)


func _ready() -> void:
	var plant := world.plant
	var runs: Array = []
	for child in plant.get_children():
		if child is PipeView:
			runs.append(child)
	var views: Array = plant.views.values()
	_phases = [
		["everything", [], []],
		["without the runs", runs, []],
		["without the equipment views", views, []],
		["without the HUD", [world.hud], []],
		["without the plant node itself", [plant], ["plant"]],
		["without the world's own _process", [world], ["world"]],
	]
	_next()


func _next() -> void:
	if _phase >= 0:
		_set_group(_phases[_phase], true)
	_phase += 1
	if _phase >= _phases.size():
		print("[flowstate] loop profile (headless, %d frames each):" % FRAMES)
		for line in _results:
			print("    " + line)
		get_tree().quit()
		return
	_set_group(_phases[_phase], false)
	_settle = 3
	_acc = 0.0
	_phys = 0.0
	_n = 0


## Switch a phase's nodes off or on. Views take their children with
## them (mounted instruments, audio); the plant and the world keep
## their children and lose only their own callbacks.
func _set_group(phase: Array, on: bool) -> void:
	var flags: Array = phase[2]
	for node in phase[1]:
		if node == null or not is_instance_valid(node):
			continue
		if flags.is_empty():
			(node as Node).propagate_call("set_process", [on])
			(node as Node).propagate_call("set_physics_process", [on])
		else:
			(node as Node).set_process(on)
			(node as Node).set_physics_process(on)


func _process(_delta: float) -> void:
	if _settle > 0:
		_settle -= 1
		return
	_acc += Performance.get_monitor(Performance.TIME_PROCESS)
	_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_n += 1
	if _n >= FRAMES:
		_results.append("%-36s loop %5.1f ms · physics %5.1f ms" % [str(_phases[_phase][0]),
			_acc / _n * 1000.0, _phys / _n * 1000.0])
		_next()
