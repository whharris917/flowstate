shader_type spatial;
// Clouds: two decks over the world, drawn on a dome that follows the
// player. Each pixel's view ray is carried up to a flat deck at the
// deck's height and the cloud there is read from noise, so the decks
// have true perspective: large overhead, crowding into the horizon.
// A high deck of cloud at 1600 m, from a few fair-weather puffs to a
// solid overcast; a low deck of ragged scud at 420 m, dark and fast,
// that comes in with a storm. The wind carries each (drift, in metres,
// advanced by the world).
//
// Lit simply: the sky's light from above, the sun's through the thin
// parts and on the edges toward it, the thick parts darker; a storm
// darkens the bases. At night the town's lamps light the bases of the
// low deck over it, and a lightning stroke lights both decks around
// it. Far cloud fades into the horizon's colour.
//
// The dome is drawn after everything opaque with no depth test, and
// reads the depth buffer instead: a pixel keeps a deck only where the
// scene behind it is further than the deck, so the heighliner hangs
// between the decks and a lighthouse stands in front of both.
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, fog_disabled, blend_mix, shadows_disabled;
#include "res://world/granite.gdshaderinc"

uniform float cover : hint_range(0.0, 1.0) = 0.25;
uniform float scud : hint_range(0.0, 1.0) = 0.0;
uniform float storm : hint_range(0.0, 1.0) = 0.0;
uniform vec2 drift_high = vec2(0.0);
uniform vec2 drift_low = vec2(0.0);
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_light = vec3(1.0);        // linear, with its strength in it
uniform vec3 sky_light = vec3(0.5);        // linear, the light from the dome
uniform vec3 horizon_color = vec3(0.6);    // linear, what far cloud fades into
uniform vec3 town_glow = vec3(0.0);        // linear, the streets' light on the low bases
uniform vec2 town_xz = vec2(15.0, 10.0);
uniform float flash = 0.0;
uniform vec3 flash_dir = vec3(0.0, 0.2, -1.0);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

const float HIGH = 1600.0;
const float LOW = 420.0;

varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < octaves; k++) {
		v += a * value_noise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return v / (1.0 - pow(0.5, float(octaves)));
}

void fragment() {
	vec3 d = normalize(dir);
	if (d.y < 0.004) {
		discard;
	}
	// How far the opaque scene is along this pixel: the sky reads as the
	// far plane.
	float depth_raw = texture(depth_tex, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float scene = length(view.xyz / view.w);
	bool open_sky = scene > 3700.0;
	vec3 cam = CAMERA_POSITION_WORLD;
	float t_low = (LOW - cam.y) / d.y;
	float t_high = (HIGH - cam.y) / d.y;
	if (!open_sky && scene < t_low) {
		discard;
	}
	vec3 sun = normalize(sun_dir);
	float toward_sun = clamp(dot(d, sun), 0.0, 1.0);
	float toward_flash = clamp(dot(d, normalize(flash_dir)), 0.0, 1.0);
	vec3 flash_light = vec3(0.75, 0.80, 1.0) * flash * (0.15 + 2.2 * pow(toward_flash, 10.0));

	// ---- the high deck.
	float a_high = 0.0;
	vec3 c_high = vec3(0.0);
	if (open_sky || scene > t_high) {
		vec2 p = (cam.xz + d.xz * t_high + drift_high) * 0.00055;
		float n = fbm(p, 5);
		float edge = 1.0 - cover;
		a_high = smoothstep(edge - 0.06, edge + 0.22, n) * smoothstep(0.004, 0.05, d.y);
		float thick = smoothstep(edge, edge + 0.45, n);
		// Light through it: the sun's on the thin parts and round the
		// edges toward it, the sky's everywhere, less on the thick.
		float lit = mix(1.0, 0.35, thick);
		float silver = pow(toward_sun, 6.0) * (1.0 - thick) * 1.2;
		c_high = sky_light * (0.75 - 0.35 * thick) + sun_light * (0.45 * lit + silver);
		c_high *= 1.0 - 0.6 * storm;
		c_high += flash_light * (0.6 + 0.4 * thick);
		c_high = mix(c_high, horizon_color, 1.0 - exp(-t_high / 14000.0));
	}

	// ---- the low deck: ragged, stretched down the wind, dark.
	float a_low = 0.0;
	vec3 c_low = vec3(0.0);
	if (scud > 0.0) {
		vec2 q = cam.xz + d.xz * t_low + drift_low;
		vec2 along = normalize(wind_dir);
		vec2 local = vec2(dot(q, along), dot(q, vec2(-along.y, along.x)));
		float n = fbm(local * vec2(0.0018, 0.0042), 4);
		float edge = 1.0 - 0.75 * scud;
		a_low = smoothstep(edge - 0.05, edge + 0.25, n) * smoothstep(0.004, 0.04, d.y) * min(scud * 1.6, 1.0);
		float thick = smoothstep(edge, edge + 0.4, n);
		c_low = sky_light * (0.42 - 0.2 * thick) + sun_light * 0.12 * (1.0 - thick);
		c_low *= 1.0 - 0.45 * storm;
		float from_town = length(q - drift_low - town_xz);
		c_low += town_glow * exp(-from_town / 650.0) * (0.6 + 0.4 * thick);
		c_low += flash_light * (0.8 + 0.4 * thick);
		c_low = mix(c_low, horizon_color * 0.8, 1.0 - exp(-t_low / 7000.0));
	}

	float alpha = a_low + a_high * (1.0 - a_low);
	if (alpha < 0.003) {
		discard;
	}
	ALBEDO = (c_low * a_low + c_high * a_high * (1.0 - a_low)) / alpha;
	ALPHA = alpha;
}
