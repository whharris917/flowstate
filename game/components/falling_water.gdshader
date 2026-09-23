// Falling water (2026-09-22): a stream from an open pipe end, or the
// sheet running down a tank that overflows. Streaks move along the mesh
// (UV.y, 0 at the start, 1 at the end) at the liquid's real speed, so the
// motion is the flow's own and never a decoration; the vertex colour's
// alpha carries where a jet thins and breaks up into spray.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.74, 0.86, 0.94, 1.0);
uniform float alpha = 0.7;
uniform float speed = 1.0;        // m/s along the length
uniform float length_m = 1.0;     // the mesh's length, for UV.y in metres
uniform float streak_m = 0.08;    // how long a streak is
uniform float around = 6.0;       // streaks around the circumference
uniform float rivulets = 0.0;     // >0: water running down a wall in this many rivulets
uniform float coverage = 1.0;     // with rivulets, how much of the wall is wet (0..1)

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
	float s = UV.y * length_m;
	// Wrap the circumference so the seam does not show.
	float n = noise(vec2(UV.x * around, (s - TIME * speed) / streak_m));
	float n2 = noise(vec2(UV.x * around * 2.3 + 7.0, (s - TIME * speed * 1.1) / (streak_m * 0.4)));
	float streak = 0.6 * n + 0.4 * n2;
	ALBEDO = tint.rgb * (0.82 + 0.3 * streak);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.65;
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = pow(clamp(1.0 - facing, 0.0, 1.0), 2.0);
	float a = clamp(alpha * (0.55 + 0.45 * streak) + 0.3 * fresnel, 0.0, 1.0) * COLOR.a;
	if (rivulets > 0.0) {
		// Rivulets wander a little as they run down; more of them join
		// into a sheet as the flow grows.
		float x = UV.x * rivulets + 0.6 * noise(vec2(UV.x * rivulets * 0.5, s * 0.8));
		float lane = noise(vec2(x, 0.37)) * 0.7 + 0.3 * noise(vec2(x * 3.1, s * 0.3));
		float wet = smoothstep(1.0 - coverage, 1.0 - coverage + 0.05, lane);
		a *= wet;
	}
	ALPHA = a;
}
