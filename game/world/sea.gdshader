shader_type spatial;
// The sea: one flat plane that follows the player at the
// tide's height. Waves are in the normal only — four directional
// trains at deep-water speed, the longest a swell from the open sea,
// plus a wind chop of hashed noise — fading with distance so the far
// water does not sparkle into aliasing. Depth is read from the depth
// buffer: the water goes clear and green over the shallows, foams
// where it is a hand deep against the rock, and is dark and opaque
// out past the ledges. Reflections come from the sky and the
// environment's screen-space pass.
render_mode cull_disabled;
#include "res://world/granite.gdshaderinc"

uniform vec3 deep_color : source_color = vec3(0.010, 0.040, 0.055);
uniform vec3 shallow_color : source_color = vec3(0.06, 0.18, 0.18);
uniform float swell = 1.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// The slope of one wave train at p: direction, wavelength, amplitude.
vec2 wave_grad(vec2 dir, float len, float amp, vec2 p, float t) {
	float k = 6.2831853 / len;
	float w = sqrt(9.81 * k);
	float ph = dot(dir, p) * k - t * w;
	return dir * (k * amp * cos(ph));
}

vec3 wave_normal(vec2 p, float t, float fade) {
	vec2 g = vec2(0.0);
	g += wave_grad(normalize(vec2(-0.70, -0.70)), 24.0, 0.32 * swell, p, t);
	g += wave_grad(normalize(vec2(-1.00, -0.25)), 9.5, 0.14 * swell, p, t);
	g += wave_grad(normalize(vec2(-0.30, -1.00)), 4.6, 0.07, p, t);
	g += wave_grad(normalize(vec2(-0.85, 0.50)), 2.3, 0.035, p, t);
	// The wind's chop: a noise gradient drifting downwind.
	float e = 0.08;
	vec2 q = p * 1.6 + vec2(t * 0.35, t * 0.2);
	float r0 = value_noise(q);
	float rx = value_noise(q + vec2(e, 0.0));
	float rz = value_noise(q + vec2(0.0, e));
	g += vec2(rx - r0, rz - r0) / e * 0.045 * fade;
	return normalize(vec3(-g.x, 1.0, -g.y));
}

void fragment() {
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float fade = clamp(1.0 - dist / 250.0, 0.0, 1.0);
	vec3 wn = wave_normal(world_pos.xz, TIME, fade);
	wn = normalize(mix(vec3(0.0, 1.0, 0.0), wn, 0.25 + 0.75 * fade));

	// How much water is under this pixel: the opaque scene's depth
	// along the view ray, less the surface's, made vertical.
	float depth_raw = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float along = max(-view.z - (-VERTEX.z), 0.0);
	vec3 ray = normalize(world_pos - CAMERA_POSITION_WORLD);
	float vertical = along * max(abs(ray.y), 0.05);

	float foam_n = value_noise(world_pos.xz * 0.7 + vec2(TIME * 0.25, -TIME * 0.15)) * 0.6
		+ value_noise(world_pos.xz * 2.9 - vec2(TIME * 0.4, TIME * 0.1)) * 0.4;
	// Foam: a fringe where the water is a hand deep, broken up by the
	// wash, never a sheet.
	float foam = (1.0 - smoothstep(0.05, 0.45, vertical))
		* smoothstep(0.50, 0.80, foam_n + 0.20 * (1.0 - smoothstep(0.0, 0.2, vertical))) * 0.7;
	vec3 color = mix(shallow_color, deep_color, 1.0 - exp(-vertical * 0.45));
	color = mix(color, lin(vec3(0.75, 0.78, 0.78)), foam);
	ALBEDO = color;
	ALPHA = clamp((1.0 - exp(-vertical * 2.2)) + foam, 0.0, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = mix(0.05, 0.35, 1.0 - fade) + 0.3 * foam;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
