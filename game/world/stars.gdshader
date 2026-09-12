shader_type spatial;
// A star field (director, 2026-09-12): drawn on a dome that follows the
// player, additive over the sky, fading in as the sun's twilight fades
// out. Stars are hashed on a cube-mapped grid so they are as dense at
// the zenith as at the horizon; each has its own magnitude and a
// faint warm-or-cool tint. Fog never touches it.
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, blend_add;

uniform float visibility = 0.0;

varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 a = abs(d);
	vec2 uv;
	float face;
	if (a.y >= a.x && a.y >= a.z) {
		uv = d.xz / a.y;
		face = step(0.0, d.y);
	} else if (a.x >= a.z) {
		uv = d.yz / a.x;
		face = 2.0 + step(0.0, d.x);
	} else {
		uv = d.xy / a.z;
		face = 4.0 + step(0.0, d.z);
	}
	// About half a degree per cell; a star is a soft dot a few pixels
	// wide at 1080p, its size and light following its magnitude.
	vec2 g = (uv * 0.5 + 0.5) * 150.0 + face * 1000.0;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float bright = 0.0;
	if (hash2(cell) > 0.955) {
		vec2 c = vec2(0.25 + 0.5 * hash2(cell + 1.3), 0.25 + 0.5 * hash2(cell + 2.7));
		float dist = length(f - c);
		float mag = 0.3 + 0.7 * pow(hash2(cell + 4.1), 2.0);
		bright = smoothstep(0.10 + 0.12 * mag, 0.0, dist) * (0.6 + 1.4 * mag);
	}
	float above = smoothstep(0.0, 0.10, d.y);
	vec3 tint = mix(vec3(0.80, 0.88, 1.0), vec3(1.0, 0.95, 0.82), hash2(cell + 9.0));
	ALBEDO = tint * bright * visibility * above;
}
