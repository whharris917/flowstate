shader_type spatial;
// World-space grass. Procedural value noise at
// four scales — metre-wide patches that dry to straw, forty-centimetre
// clumps, blade-scale grain near the camera, and a faint relief from
// that grain — drawn in world space so the mesh can follow the player
// without the pattern swimming. No grid: the build ghost snaps anyway.

// Uniformly green: the "dry" tone is only a lighter, warmer green, and
// it mixes in lightly.
// Dark and quiet: a mown field under trees, not a sports pitch.
uniform vec3 base_color : source_color = vec3(0.15, 0.26, 0.09);
uniform vec3 dry_color : source_color = vec3(0.23, 0.32, 0.11);
uniform vec3 dark_color : source_color = vec3(0.09, 0.17, 0.06);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec2 p = world_pos.xz;
	float near = clamp(1.0 - dist / 25.0, 0.0, 1.0);
	// Patches: broad drifts of drier grass over the green.
	float patches = value_noise(p * 0.07) * 0.6 + value_noise(p * 0.23 + 7.0) * 0.4;
	// Clumps: the lumpiness of a mown field.
	float clumps = value_noise(p * 2.2 + 3.0);
	// Blades: fine grain that only matters close up.
	float blades = value_noise(p * 38.0) * near;
	vec3 color = mix(base_color, dry_color, smoothstep(0.45, 0.90, patches) * 0.55);
	color = mix(color, dark_color, (1.0 - clumps) * 0.30);
	color *= 0.92 + 0.22 * (blades - 0.5 * near);
	ALBEDO = color;
	ROUGHNESS = 0.96;
	SPECULAR = 0.08;
	// Relief from the clumps and the blades, fading with distance so the
	// far field stays calm.
	float e = 0.04;
	float h0 = value_noise(p * 2.2 + 3.0) * 0.6 + value_noise(p * 38.0) * 0.4;
	float hx = value_noise((p + vec2(e, 0.0)) * 2.2 + 3.0) * 0.6 + value_noise((p + vec2(e, 0.0)) * 38.0) * 0.4;
	float hz = value_noise((p + vec2(0.0, e)) * 2.2 + 3.0) * 0.6 + value_noise((p + vec2(0.0, e)) * 38.0) * 0.4;
	NORMAL_MAP = normalize(vec3(-(hx - h0) * 3.0 * near, -(hz - h0) * 3.0 * near, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.5;
}
