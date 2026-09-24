class_name LoopProfile
extends Node
## Where the main loop's time goes. Godot has no per-node profiler outside the editor, so this bisects:
## it measures the loop with everything running, then with each group
## switched off in turn — the runs, the equipment views, the HUD, the
## world's own _process — and prints what each group cost. Headless
## only, under FLOWSTATE_LOOP_PROFILE=1; it quits when done.
##
## Caveat: headless has no GPU to cache glyphs, so every Label and
## every screen's text is rasterised again each frame it changes, and
## that swamps the loop. Read this profile only for groups that
## draw no text; the windowed HUD probe's "at 25%, … not processing"
## phases are the honest measure of script cost.

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
	var screens: Array = []
	_find_screens(world, screens)
	# Headless, a screen's text is rasterised again at every redraw (no
	# GPU to cache the glyphs), which swamps the loop; the screens are
	# switched off for every phase after the first, and the rest is
	# read against "without the HMI screens".
	_phases = [
		["everything", [], []],
		["without the HMI screens", screens, []],
		["… and the runs", screens + runs, []],
		["… and the equipment views", screens + views, []],
		["… and the HUD", screens + [world.hud], []],
		["… and the plant node itself", screens + [plant], [plant]],
		["… and the world's own _process", screens + [world], [world]],
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


## The in-world screens: each hosts a Control that redraws from the
## historian on its own clock.
func _find_screens(node: Node, out: Array) -> void:
	if node is HmiScreenView or node is HmiView:
		out.append(node)
		return
	for child in node.get_children():
		_find_screens(child, out)


## Switch a phase's nodes off or on. Views take their children with
## them (mounted instruments, audio); the plant and the world keep
## their children and lose only their own callbacks.
func _set_group(phase: Array, on: bool) -> void:
	var shallow: Array = phase[2]   # these lose only their own callbacks
	for node in phase[1]:
		if node == null or not is_instance_valid(node):
			continue
		if shallow.has(node):
			(node as Node).set_process(on)
			(node as Node).set_physics_process(on)
		else:
			(node as Node).propagate_call("set_process", [on])
			(node as Node).propagate_call("set_physics_process", [on])


func _process(_delta: float) -> void:
	# The headless support exercise and the deferred routing sweeps run
	# in the plant's physics step during the first seconds and cost a
	# second a frame; the profile waits for the plant to go idle.
	var plant := world.plant
	if plant._support_exercise_phase > 0 or plant._revalidate_in > 0:
		_settle = 3
		_acc = 0.0
		_phys = 0.0
		_n = 0
		return
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
