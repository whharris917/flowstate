shader_type spatial;
// The harbour town's building fabric: one shader for every wall, roof,
// deck and trim board, so the whole town is a few draws. The vertex
// colour carries the paint or stone colour (as an artist reads it) and,
// in alpha, what the surface is made of:
//   0 paint or trim      1 clapboard        2 brick
//   3 cedar shingle      4 granite ashlar   5 roof shingle
//   6 plank decking      7 rough timber     8 tar paper, cloth
// The courses, bricks, shingles and boards are drawn in world space
// from the surface's own direction, so nothing needs UVs and nothing
// swims. Rain wets it all: darker, glossier, most on what faces up.
#include "res://world/granite.gdshaderinc"

uniform float wet = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	int kind = int(round(COLOR.a * 10.0));
	vec3 base = lin(COLOR.rgb);
	vec3 wn = normalize(world_normal);
	// Across the face: the horizontal direction in the surface.
	vec3 across = normalize(abs(wn.y) > 0.95 ? vec3(1.0, 0.0, 0.0) : cross(vec3(0.0, 1.0, 0.0), wn));
	float u = dot(world_pos, across);
	float v = world_pos.y;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(30.0, 90.0, dist);

	vec3 col = base;
	float rough = 0.7;
	float spec = 0.4;

	if (kind == 1) {
		// Clapboard: laps 11.5 cm, each board's lower edge standing
		// proud and throwing a thin shadow line on the one below.
		float f = fract(v / 0.115);
		float shade = mix(0.72, 1.0, smoothstep(0.0, 0.12, f));
		col *= mix(1.0, shade, detail);
		col *= 0.96 + 0.08 * h21(vec2(floor(v / 0.115), floor(u / 4.3)));
		rough = 0.55;
	} else if (kind == 2) {
		// Brick in running bond, 20 by 7.6 cm with a pale mortar joint.
		float row = floor(v / 0.0762);
		float bu = u / 0.2032 + 0.5 * mod(row, 2.0);
		vec2 cell = vec2(floor(bu), row);
		vec2 f = vec2(fract(bu), fract(v / 0.0762));
		float mortar = 1.0 - (smoothstep(0.0, 0.05, f.x) * smoothstep(1.0, 0.95, f.x)
			* smoothstep(0.0, 0.13, f.y) * smoothstep(1.0, 0.87, f.y));
		vec3 brick = base * (0.82 + 0.3 * h21(cell)) * (0.92 + 0.12 * value_noise(world_pos.xz * 3.0 + v * 2.0));
		col = mix(brick, lin(vec3(0.62, 0.60, 0.56)), mortar * detail);
		rough = 0.9;
		spec = 0.25;
	} else if (kind == 3) {
		// Cedar shingle: courses of 18 cm, shingles of random width,
		// weathered silver-grey unevenly.
		float row = floor(v / 0.18);
		float w = 0.14 + 0.1 * h21(vec2(row, 3.0));
		float su = u / w + h21(vec2(row, 7.0));
		float f = fract(su);
		float seam = smoothstep(0.0, 0.04, f) * smoothstep(1.0, 0.96, f);
		float lap = smoothstep(0.0, 0.1, fract(v / 0.18));
		col *= (0.8 + 0.3 * h21(vec2(floor(su), row))) * mix(1.0, mix(0.7, 1.0, seam * lap), detail);
		rough = 0.85;
		spec = 0.3;
	} else if (kind == 4) {
		// Granite ashlar: blocks 60 by 35 cm, speckled.
		float row = floor(v / 0.35);
		float bu = u / 0.6 + 0.37 * mod(row, 3.0);
		vec2 f = vec2(fract(bu), fract(v / 0.35));
		float joint = 1.0 - smoothstep(0.0, 0.02, f.x) * smoothstep(1.0, 0.98, f.x) * smoothstep(0.0, 0.04, f.y) * smoothstep(1.0, 0.96, f.y);
		col *= (0.88 + 0.2 * h21(vec2(floor(bu), row))) * (0.85 + 0.3 * value_noise(world_pos.xz * 9.0 + v * 9.0));
		col = mix(col, col * 0.6, joint * detail);
		rough = 0.8;
		spec = 0.3;
	} else if (kind == 5) {
		// Roof shingle: courses by height, three-tab slots, each tab a
		// shade of its own.
		float row = floor(v / 0.085);
		float tu = u / 0.33 + 0.5 * mod(row, 2.0);
		float f = fract(tu);
		float slot = smoothstep(0.0, 0.03, f) * smoothstep(1.0, 0.97, f);
		float lap = smoothstep(0.0, 0.15, fract(v / 0.085));
		col *= (0.8 + 0.35 * h21(vec2(floor(tu), row))) * mix(1.0, mix(0.55, 1.0, slot * lap), detail);
		col *= 0.9 + 0.2 * value_noise(world_pos.xz * 0.8);
		rough = 0.9;
		spec = 0.3;
	} else if (kind == 6) {
		// Plank decking: 20 cm boards across the run, weathered grey.
		float pv = world_pos.z / 0.2;
		float f = fract(pv);
		float gap = smoothstep(0.0, 0.05, f) * smoothstep(1.0, 0.95, f);
		col *= (0.8 + 0.3 * h21(vec2(floor(pv), floor(world_pos.x / 3.7)))) * mix(1.0, mix(0.35, 1.0, gap), detail);
		col *= 0.88 + 0.24 * value_noise(vec2(world_pos.x * 0.6, world_pos.z * 6.0));
		rough = 0.88;
		spec = 0.3;
	} else if (kind == 7) {
		// Rough timber: pilings and posts, the grain running up them.
		col *= 0.8 + 0.3 * value_noise(vec2(u * 12.0, v * 0.8));
		rough = 0.9;
		spec = 0.2;
	} else if (kind == 8) {
		col *= 0.9 + 0.15 * value_noise(world_pos.xz * 2.0 + v);
		rough = 0.95;
		spec = 0.15;
	} else {
		// Paint and trim: smooth, a slight sheen.
		rough = 0.5;
	}

	// Rain: everything darkens a little and slicks over; what faces up
	// holds a film of water.
	float up = smoothstep(0.3, 0.9, wn.y);
	float soak = wet * (0.55 + 0.45 * up);
	col *= 1.0 - 0.25 * soak;
	rough = mix(rough, mix(0.35, 0.12, up), soak);
	spec = mix(spec, 0.5, soak);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = 0.0;
}
