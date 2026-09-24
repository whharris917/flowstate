// A spill standing on the floor: wet ground, not a coloured
// disc. Dark and glossy, so it reads by what it reflects; an irregular
// edge from noise, soft where the film thins; its size is set by the
// node's scale from the volume spilled (SpillPuddle).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform float alpha = 0.6;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	// A lobed outline: noise sampled on the unit circle, so it has no seam.
	vec2 dir = q / max(d, 1e-4);
	float wobble = 0.22 * noise(dir * 1.3 + vec2(seed, seed * 0.7)) + 0.12 * noise(dir * 3.5 + vec2(seed * 3.0, 1.0));
	float edge = 1.0 - smoothstep(0.62 - wobble, 0.98 - wobble, d);
	ALBEDO = vec3(0.012, 0.016, 0.02);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	ALPHA = clamp(edge * alpha, 0.0, 1.0);
}
