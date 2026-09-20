class_name DripStream
extends Node3D
## What comes out of an open pipe end, drawn and heard off the real
## rate (director, 2026-09-20: "letting the tank fill drop by drop,
## where the drops are audible"). Fed every frame with the flow the
## kernel solved and the height it falls: below STREAM_LPS the flow is
## drops — falling particles at the rate the volume makes, a drop being
## about a twentieth of a millilitre, and a drip sound for each one
## where it lands — and above it a continuous stream, a falling column
## sized by the flow with a pour that swells with it. Every drop is an
## event off the rate, never a decoration timer: a millilitre a second
## is twenty drops a second and a trickle of a tenth is two.

const DROP_ML := 0.05        # one drop
const STREAM_LPS := 0.003    # sixty drops a second: a stream, not drips
const POOL := 6              # drip players in flight at once
const FALL_SPEED := 1.5      # m/s, the column's speed for its width

var _drops: GPUParticles3D
var _proc: ParticleProcessMaterial
var _stream: MeshInstance3D
var _stream_mesh: CylinderMesh
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_next := 0
var _debt := 0.0
var _pour: EquipmentAudio = null
var _fall := 1.0
var _lps := 0.0
var _drop_index := 0


static func make(parent: Node3D, at: Vector3) -> DripStream:
	var drip := DripStream.new()
	drip.position = at
	parent.add_child(drip)
	drip._build()
	return drip


func _build() -> void:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.62, 0.80, 0.92, 0.75)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.metallic = 0.2
	water.roughness = 0.05
	water.metallic_specular = 0.8
	# Drops: small spheres falling under gravity from the lip.
	_drops = GPUParticles3D.new()
	_drops.emitting = false
	_drops.local_coords = false
	_drops.explosiveness = 0.0
	_drops.randomness = 0.05
	_drops.amount = 4
	_drops.lifetime = 0.5
	_proc = ParticleProcessMaterial.new()
	_proc.direction = Vector3(0, -1, 0)
	_proc.spread = 3.0
	_proc.initial_velocity_min = 0.15
	_proc.initial_velocity_max = 0.25
	_proc.gravity = Vector3(0, -9.81, 0)
	_proc.scale_min = 1.0
	_proc.scale_max = 1.0
	_drops.process_material = _proc
	var drop := SphereMesh.new()
	drop.radius = 0.007
	drop.height = 0.017
	drop.radial_segments = 8
	drop.rings = 4
	drop.material = water
	_drops.draw_pass_1 = drop
	add_child(_drops)
	# The stream: a column from the lip to the landing, sized by the flow.
	_stream = MeshInstance3D.new()
	_stream_mesh = CylinderMesh.new()
	_stream_mesh.top_radius = 0.004
	_stream_mesh.bottom_radius = 0.004
	_stream_mesh.height = 1.0
	_stream_mesh.radial_segments = 10
	_stream_mesh.rings = 1
	_stream.mesh = _stream_mesh
	_stream.material_override = water
	_stream.visible = false
	add_child(_stream)
	if DisplayServer.get_name() != "headless":
		for i in POOL:
			var player := AudioStreamPlayer3D.new()
			player.stream = load("res://audio/drip_%d.wav" % (i % 3 + 1)) as AudioStreamWAV
			player.bus = "Room"
			player.unit_size = 3.0
			player.max_distance = 22.0
			player.volume_db = -10.0
			add_child(player)
			_pool.append(player)
		_pour = EquipmentAudio.make(self, "res://audio/pour_loop.wav", Vector3.ZERO, -14.0)


## The state this frame: the flow leaving the end (L/s) and how far it
## falls to what it lands on.
func set_state(lps: float, fall_m: float, delta: float) -> void:
	_lps = maxf(lps, 0.0)
	_fall = maxf(fall_m, 0.05)
	var landing := Vector3(0, -_fall, 0)
	if _lps <= 1e-7:
		_drops.emitting = false
		_stream.visible = false
		if _pour != null:
			_pour.set_running(false)
		_debt = 0.0
		return
	var stream := _lps >= STREAM_LPS
	if stream:
		_drops.emitting = false
		# The column: its width from the flow at a falling speed, drawn
		# no thinner than can be seen and twice its true width, since a
		# millimetre thread is invisible at a stride.
		var r := clampf(2.0 * sqrt(_lps * 1e-3 / (PI * FALL_SPEED)), 0.004, 0.06)
		if absf(_stream_mesh.top_radius - r) > r * 0.1 or absf(_stream_mesh.height - _fall) > 0.02:
			_stream_mesh.top_radius = r
			_stream_mesh.bottom_radius = r * 0.85
			_stream_mesh.height = _fall
		_stream.position = Vector3(0, -_fall / 2.0, 0)
		_stream.visible = true
		if _pour != null:
			_pour.position = landing
			# -22 dB at the threshold, up to -4 dB at a litre a second.
			_pour.volume_db = clampf(-22.0 + 7.0 * log(_lps / STREAM_LPS) / log(2.0), -22.0, -4.0)
			_pour.set_running(true)
		_debt = 0.0
		return
	# Drops: the rate the volume makes, each one a particle and a sound.
	_stream.visible = false
	if _pour != null:
		_pour.set_running(false)
	var drops_per_s := _lps * 1000.0 / DROP_ML
	var flight := sqrt(2.0 * _fall / 9.81) + 0.05
	var amount := maxi(int(ceil(drops_per_s * flight)) + 1, 2)
	if _drops.amount != amount or absf(_drops.lifetime - flight) > 0.01:
		_drops.amount = amount
		_drops.lifetime = flight
	_drops.emitting = true
	_debt += drops_per_s * delta
	var played := 0
	while _debt >= 1.0 and played < 3:
		_debt -= 1.0
		played += 1
		_drop_index += 1
		if _pool.is_empty():
			continue
		var player := _pool[_pool_next]
		_pool_next = (_pool_next + 1) % _pool.size()
		player.position = landing
		# The pitch wanders a little from drop to drop, as drops do.
		player.pitch_scale = 0.9 + 0.25 * float((_drop_index * 7) % 5) / 4.0
		player.play()
	if _debt > 3.0:
		_debt = 3.0   # a hitch is not repaid with a burst
