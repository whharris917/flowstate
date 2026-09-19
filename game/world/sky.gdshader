shader_type sky;
// The sky (director, 2026-09-18: "the sunrise and sunset lighting looks
// rather unnatural"). Godot's physical sky goes black as the sun nears
// the horizon, so dawn and dusk were a lit ground under a dark dome.
// This is an analytic sky with the twilight built in: the dome stays
// bright while the sun is low or just under, warm along the horizon
// toward the sun and cool away from it, and only then fades to night.
//
// The sun's true direction comes in as a uniform (below the horizon
// too), since the scene's directional light turns into the moon at
// night; the moon's direction comes in beside it.

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);    // toward the sun, unit
uniform vec3 moon_dir = vec3(0.0, 0.5, -0.87);
uniform float energy = 1.0;                    // the dome's brightness before tone mapping
uniform float haze : hint_range(0.0, 1.0) = 0.35;   // coastal air: more haze, softer glow, whiter horizon

// The colours of the day, in linear light (source_color converts).
uniform vec4 zenith_day : source_color = vec4(0.19, 0.36, 0.72, 1.0);
uniform vec4 horizon_day : source_color = vec4(0.62, 0.72, 0.84, 1.0);
uniform vec4 sun_glow_day : source_color = vec4(1.0, 0.96, 0.88, 1.0);
// Twilight: the band along the horizon toward the sun, the dome
// opposite it, and the sky overhead.
uniform vec4 twilight_warm : source_color = vec4(1.0, 0.52, 0.22, 1.0);
uniform vec4 twilight_band : source_color = vec4(0.96, 0.76, 0.58, 1.0);
uniform vec4 twilight_far : source_color = vec4(0.36, 0.40, 0.58, 1.0);
uniform vec4 twilight_zenith : source_color = vec4(0.12, 0.18, 0.40, 1.0);
// Night.
uniform vec4 night_zenith : source_color = vec4(0.020, 0.028, 0.065, 1.0);
uniform vec4 night_horizon : source_color = vec4(0.07, 0.09, 0.15, 1.0);
uniform vec4 moon_color : source_color = vec4(0.85, 0.90, 1.0, 1.0);
uniform vec4 ground_color : source_color = vec4(0.10, 0.13, 0.15, 1.0);

const float SUN_RADIUS = 0.0047;   // about half a degree, in cos terms below

float sat(float x) {
	return clamp(x, 0.0, 1.0);
}

void sky() {
	vec3 eye = normalize(EYEDIR);
	vec3 sun = normalize(sun_dir);
	float s = sun.y;                      // sun elevation, -1..1
	float v = eye.y;                      // view elevation
	float above = sat(v);
	// How much of the day is in the sky: full with the sun 12 degrees up,
	// gone with it 9 degrees under (the end of civil twilight and a bit).
	float day = smoothstep(-0.16, 0.26, s);
	// The twilight itself: strongest with the sun on the horizon, spread
	// wider below it than above, since the glow outlasts the disc.
	float dusk = exp(-pow(s / (s < 0.0 ? 0.13 : 0.16), 2.0));
	// Where the sun stands along the horizon: 1 looking straight at it.
	// Clamped: looking exactly away from the sun the dot rounds a hair
	// under -1, and pow() of a negative base is NaN, which the glow
	// bloomed into a trail of white blobs down the sky opposite the sun
	// and the tone mapper painted black at the centre (2026-09-18).
	vec2 sun_flat = normalize(sun.xz + vec2(1e-5, 0.0));
	vec2 eye_flat = normalize(eye.xz + vec2(1e-5, 0.0));
	float toward = sat(dot(sun_flat, eye_flat) * 0.5 + 0.5);

	// ---- the day dome: a pale horizon rising to a blue zenith, whiter
	// with haze, and the sun's own glow.
	float horizon_w = pow(1.0 - above, 2.2 - 1.2 * haze);
	vec3 day_sky = mix(zenith_day.rgb, horizon_day.rgb, horizon_w);
	day_sky = mix(day_sky, horizon_day.rgb, haze * 0.25);
	float cos_sun = dot(eye, sun);
	float glow = pow(sat(cos_sun), 8.0) * 0.28 * (0.6 + haze) + pow(sat(cos_sun), 64.0) * 0.5;
	day_sky += sun_glow_day.rgb * glow;

	// ---- twilight: a warm band low toward the sun, a cool wash away
	// from it, and a deep blue overhead, all sitting on the day dome as
	// it dims.
	float band = pow(1.0 - above, 3.0 + 3.0 * (1.0 - haze)) * pow(toward, 1.5);
	float band_far = pow(1.0 - above, 2.5);
	vec3 dusk_sky = mix(twilight_zenith.rgb, twilight_far.rgb, band_far);
	dusk_sky = mix(dusk_sky, twilight_band.rgb, band * 0.85);
	dusk_sky += twilight_warm.rgb * pow(band, 1.8) * (0.9 + haze) * pow(sat(cos_sun + 0.3), 2.0);

	// ---- night: a dark dome, paler at the horizon, with the moon.
	vec3 night_sky = mix(night_zenith.rgb, night_horizon.rgb, pow(1.0 - above, 2.0));
	vec3 moon = normalize(moon_dir);
	float cos_moon = dot(eye, moon);
	float moon_up = sat(moon.y * 4.0);
	night_sky += moon_color.rgb * (pow(sat(cos_moon), 200.0) * 0.6 + pow(sat(cos_moon), 12.0) * 0.06) * moon_up;

	// ---- put together: day over twilight over night. The twilight is
	// worth its full weight only while the day is fading.
	vec3 col = mix(night_sky, dusk_sky, sat(dusk * 1.4));
	col = mix(col, day_sky, day);
	// A last warmth of the whole dome at sunrise and sunset.
	col *= mix(vec3(1.0), vec3(1.08, 0.94, 0.86), dusk * (1.0 - day) * 0.6 + dusk * day * 0.3);

	// ---- the sun's disc, only while it is up, softened by haze. Its
	// edge is a few times its own radius wide and its peak modest: a
	// pin-sharp disc many times over white flickered through the glow
	// as it crossed pixels (2026-09-18).
	float disc = smoothstep(cos(SUN_RADIUS * 5.0), cos(SUN_RADIUS * 1.5), cos_sun);
	float sun_up = smoothstep(-0.02, 0.03, s);
	vec3 disc_color = mix(twilight_warm.rgb, sun_glow_day.rgb, smoothstep(0.0, 0.3, s));
	col += disc_color * disc * sun_up * mix(6.0, 3.0, haze) * mix(0.4, 1.0, smoothstep(0.0, 0.25, s));

	// ---- under the horizon: the ground's colour, lit as the dome is.
	float under = smoothstep(0.0, -0.06, v);
	vec3 ground = ground_color.rgb * mix(0.08, 1.0, day) * mix(vec3(1.0), twilight_band.rgb, dusk * 0.5);
	col = mix(col, ground, under);

	COLOR = col * energy;
}
