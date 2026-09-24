shader_type spatial;
// A plant floor: matte off-white tiles with grout, laid in world space on whichever face of the slab is
// being drawn, so the pad and a hall floor tile the same way without
// UVs. Each tile varies a few percent in tone and a faint dirt haze
// sits over the lot, so it reads as a floor and not a grid.

uniform float tile_m = 0.6;
uniform float grout_m = 0.012;
uniform vec3 tile_color : source_color = vec3(0.86, 0.85, 0.80);
uniform vec3 grout_color : source_color = vec3(0.58, 0.57, 0.53);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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
	vec3 n = abs(world_normal);
	vec2 p = n.y >= max(n.x, n.z) ? world_pos.xz : (n.x >= n.z ? world_pos.zy : world_pos.xy);
	vec2 cell = floor(p / tile_m);
	vec2 f = fract(p / tile_m);
	vec2 edge2 = min(f, 1.0 - f) * tile_m;
	float edge = min(edge2.x, edge2.y);
	float aa = fwidth(edge) + 0.0005;
	float grout = 1.0 - smoothstep(grout_m * 0.5 - aa, grout_m * 0.5 + aa, edge);
	float tone = 0.95 + 0.08 * hash2(cell);
	float haze = 0.97 + 0.06 * value_noise(p * 0.8);
	vec3 color = mix(tile_color * tone * haze, grout_color, grout);
	ALBEDO = color;
	ROUGHNESS = mix(0.72, 0.95, grout);
	SPECULAR = 0.3;
	// A soft bevel at each tile edge, so the joints catch the light.
	float bevel = 1.0 - smoothstep(grout_m * 0.5, grout_m * 0.5 + 0.02, edge);
	vec2 dir = (edge2.x < edge2.y) ? vec2(sign(0.5 - f.x), 0.0) : vec2(0.0, sign(0.5 - f.y));
	NORMAL_MAP = normalize(vec3(dir * bevel * 0.6, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
