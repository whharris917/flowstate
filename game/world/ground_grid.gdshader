shader_type spatial;
// World-space ground: poured concrete with faint 1 m minor and 8 m
// major lines (the pad's own grid, not a construction overlay), each
// fading with distance so the infinite plane reads as ground rather
// than moiré. Drawn in world space so the mesh can follow the player
// without the pattern swimming. The concrete is procedural value
// noise at three scales — mottling, aggregate and a hairline sheen —
// so no texture asset is needed (director, 2026-09-11: as realistic
// as possible).

uniform vec3 base_color : source_color = vec3(0.50, 0.50, 0.48);
uniform vec3 minor_color : source_color = vec3(0.45, 0.45, 0.43);
uniform vec3 major_color : source_color = vec3(0.38, 0.39, 0.38);

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

float grid_line(vec2 pos, float spacing) {
	vec2 g = abs(fract(pos / spacing - 0.5) - 0.5) * spacing / fwidth(pos);
	return 1.0 - min(min(g.x, g.y), 1.0);
}

void fragment() {
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec2 p = world_pos.xz;
	// Concrete: broad mottling, fine aggregate, and a sparse speckle.
	float mottle = value_noise(p * 0.35) * 0.6 + value_noise(p * 1.3) * 0.4;
	float grain = value_noise(p * 14.0);
	float speckle = step(0.965, hash2(floor(p * 40.0)));
	float shade = 0.70 + 0.40 * mottle + 0.12 * (grain - 0.5) - 0.14 * speckle;
	vec3 color = base_color * shade;
	float fade_minor = clamp(1.0 - dist / 40.0, 0.0, 1.0);
	float fade_major = clamp(1.0 - dist / 160.0, 0.0, 1.0);
	color = mix(color, minor_color * shade, grid_line(p, 1.0) * fade_minor * 0.7);
	color = mix(color, major_color * shade, grid_line(p, 8.0) * fade_major);
	ALBEDO = color;
	ROUGHNESS = 0.90 - 0.08 * grain;
	SPECULAR = 0.15;
}
