shader_type spatial;
// A river (2026-09-18): a ribbon of water along a stream's centreline,
// its UV in metres across and along, so the ripples run down it. Tea
// water, as a Maine river is: clear and brown over the stones, dark
// in the pools. The surface is the sea shader's idea with the swell
// taken out — a fine ripple drifting downstream, a riffle pattern
// across the current, both fading with distance — and the same
// depth read from the depth buffer for the shallows and for the foam
// against the boulders standing in it.
render_mode cull_disabled;
#include "res://world/granite.gdshaderinc"

uniform vec3 deep_color : source_color = vec3(0.034, 0.030, 0.012);
uniform vec3 shallow_color : source_color = vec3(0.18, 0.14, 0.05);
uniform float flow = 1.3;      // metres a second downstream
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;

varying vec3 world_pos;
varying vec2 along;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	along = UV;
}

vec3 river_normal(vec2 q, float t, float fade) {
	// q: across, along (metres). The current runs toward smaller along.
	vec2 g = vec2(0.0);
	float e = 0.08;
	vec2 p1 = q * 1.4 + vec2(0.0, t * flow * 1.4);
	float a0 = value_noise(p1);
	g += vec2(value_noise(p1 + vec2(e, 0.0)) - a0, value_noise(p1 + vec2(0.0, e)) - a0) / e * 0.08;
	vec2 p2 = q * 0.45 + vec2(t * 0.1, t * flow * 0.45);
	float b0 = value_noise(p2);
	g += vec2(value_noise(p2 + vec2(e, 0.0)) - b0, value_noise(p2 + vec2(0.0, e)) - b0) / e * 0.12;
	// Riffles: low bars across the current, drifting down with it.
	float rif = sin(q.y * 2.6 + t * flow * 2.6 + 1.5 * value_noise(q * 0.3)) * 0.05;
	g.y += rif;
	g *= fade;
	return normalize(vec3(-g.x, 1.0, -g.y));
}

void fragment() {
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float fade = clamp(1.0 - dist / 160.0, 0.0, 1.0);
	vec3 wn = river_normal(along, TIME, 0.3 + 0.7 * fade);
	// The ribbon's normal in world space is up; its ripple gradient is in
	// ribbon space, near enough to world space for a surface that is flat.
	float depth_raw = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float dz = max(-view.z - (-VERTEX.z), 0.0);
	vec3 ray = normalize(world_pos - CAMERA_POSITION_WORLD);
	float vertical = dz * max(abs(ray.y), 0.05);

	float foam_n = value_noise(along * vec2(1.1, 0.9) + vec2(0.0, TIME * flow * 1.6)) * 0.6
		+ value_noise(along * 3.3 + vec2(TIME * 0.2, TIME * flow * 2.5)) * 0.4;
	// Foam where the water is a hand deep against a stone, torn by the current.
	float foam = (1.0 - smoothstep(0.04, 0.40, vertical))
		* smoothstep(0.45, 0.75, foam_n + 0.25 * (1.0 - smoothstep(0.0, 0.15, vertical))) * 0.8;
	vec3 color = mix(shallow_color, deep_color, 1.0 - exp(-vertical * 0.9));
	color = mix(color, lin(vec3(0.80, 0.82, 0.80)), foam);
	ALBEDO = color;
	ALPHA = clamp((1.0 - exp(-vertical * 2.6)) + foam, 0.0, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = mix(0.06, 0.3, 1.0 - fade) + 0.35 * foam;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
