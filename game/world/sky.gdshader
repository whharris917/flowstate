shader_type sky;
// The sky. Godot's physical sky goes black as the sun nears the
// horizon, leaving dawn and dusk a lit ground under a dark dome.
// This is an analytic sky with the twilight built in: the dome stays
// bright while the sun is low or just under, warm along the horizon
// toward the sun and cool away from it, and only then fades to night.
//
// The sun's true direction comes in as a uniform (below the horizon
// too), since the scene's directional light turns into the moon at
// night; the moon's direction comes in beside it.

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);    // toward the sun, unit
uniform vec3 moon_dir = vec3(0.0, 0.5, 0.87);
// The moon's face: north on it as seen (moon_up), the sun's direction
// that lights it (moon_sun), the share of it lit (moon_lit).
uniform vec3 moon_up = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_sun = vec3(0.0, -1.0, 0.0);
uniform float moon_lit = 0.0;
// A town's lamps lighting the air low over it, warm (0 none, 1 a small
// town at night).
uniform float town_glow = 0.0;
uniform float energy = 1.0;                    // the dome's brightness before tone mapping
uniform float haze : hint_range(0.0, 1.0) = 0.35;   // coastal air: more haze, softer glow, whiter horizon
// Weather: a cloud deck that greys and dims the dome and hides the sun
// and the moon, and the light of a lightning stroke (its direction and
// strength) lighting the deck from under it.
uniform float overcast : hint_range(0.0, 1.0) = 0.0;
uniform float flash = 0.0;
uniform vec3 flash_dir = vec3(0.0, 0.2, -1.0);

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
uniform vec4 night_zenith : source_color = vec4(0.026, 0.030, 0.042, 1.0);
uniform vec4 night_horizon : source_color = vec4(0.075, 0.080, 0.092, 1.0);
uniform vec4 moon_color : source_color = vec4(0.85, 0.90, 1.0, 1.0);
uniform vec4 ground_color : source_color = vec4(0.10, 0.13, 0.15, 1.0);

const float SUN_RADIUS = 0.0047;   // about half a degree, in cos terms below
// The moon is a quarter of a degree across its radius; drawn 2.2 times
// that, since the camera sees some ninety degrees top to bottom while a
// screen fills about forty of the eye's, which shrinks everything on it:
// so enlarged, it looks the size the moon looks.
const float MOON_RADIUS = 0.01;

// The seas on the moon's near side: latitude and longitude (degrees,
// east to the viewer's right as seen from the north), radius, darkness.
const int SEAS = 13;
const vec4 SEA[13] = vec4[](
	vec4(20.0, -55.0, 26.0, 0.42),   // Oceanus Procellarum
	vec4(33.0, -16.0, 15.0, 0.45),   // Imbrium
	vec4(28.0, 17.5, 9.5, 0.45),     // Serenitatis
	vec4(8.5, 31.0, 10.5, 0.45),     // Tranquillitatis
	vec4(17.0, 59.0, 6.5, 0.5),      // Crisium
	vec4(-7.8, 51.3, 9.0, 0.4),      // Fecunditatis
	vec4(-15.2, 35.0, 5.0, 0.4),     // Nectaris
	vec4(-21.3, -16.6, 9.5, 0.35),   // Nubium
	vec4(-24.4, -38.6, 5.0, 0.4),    // Humorum
	vec4(56.0, 1.4, 8.0, 0.3),       // Frigoris, west
	vec4(56.0, 25.0, 7.0, 0.3),      // Frigoris, east
	vec4(13.3, 3.6, 4.0, 0.4),       // Vaporum
	vec4(-20.0, -50.0, 6.0, 0.25)    // Cognitum and the south of Procellarum
);

// The moon's face at a point of its disc (p, -1..1 across, north up,
// the viewer's right x): its albedo and its light from the sun, with
// the ashen light of the earth on the dark part of a crescent.
vec3 moon_face(vec2 p, vec3 view, vec3 right, vec3 up, vec3 lit_from, float lit_share) {
	float z = sqrt(max(1.0 - dot(p, p), 0.0));
	vec3 n = normalize(right * p.x + up * p.y - view * z);
	vec3 s = vec3(p.x, p.y, z);
	float albedo = 1.0;
	for (int k = 0; k < SEAS; k++) {
		vec4 sea = SEA[k];
		float la = radians(sea.x);
		float lo = radians(sea.y);
		vec3 c = vec3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo));
		float a = acos(clamp(dot(s, c), -1.0, 1.0));
		albedo -= sea.w * smoothstep(radians(sea.z) * 1.15, radians(sea.z) * 0.7, a);
	}
	// Tycho, bright, low in the south.
	vec3 tycho = vec3(cos(radians(-43.3)) * sin(radians(-11.4)), sin(radians(-43.3)), cos(radians(-43.3)) * cos(radians(-11.4)));
	albedo += 0.25 * smoothstep(0.06, 0.0, acos(clamp(dot(s, tycho), -1.0, 1.0)));
	albedo = clamp(albedo, 0.35, 1.2);
	float sunlit = pow(clamp(dot(n, lit_from), 0.0, 1.0), 0.7) * smoothstep(-0.02, 0.05, dot(n, lit_from));
	float earthshine = 0.06 * (1.0 - lit_share);
	return vec3(1.0, 0.98, 0.94) * albedo * (sunlit * 2.6 + earthshine);
}

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
	// blooms into a trail of white blobs down the sky opposite the sun
	// and the tone mapper paints black at the centre.
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

	// ---- night: a dark dome, paler at the horizon; the moon's light
	// scattered blue through it, most near the moon; a town's lamps
	// warming the air low down.
	vec3 night_sky = mix(night_zenith.rgb, night_horizon.rgb, pow(1.0 - above, 2.0));
	vec3 moon = normalize(moon_dir);
	float cos_moon = dot(eye, moon);
	float moon_high = sat(moon.y * 6.0 + 0.1);
	float moon_light = pow(moon_lit, 1.5) * moon_high;
	night_sky += moon_color.rgb * vec3(0.30, 0.42, 0.75) * 0.02 * moon_light * (0.6 + 0.4 * pow(1.0 - above, 1.5));
	night_sky += moon_color.rgb * (pow(sat(cos_moon), 900.0) * 0.12 + pow(sat(cos_moon), 60.0) * 0.012 * (0.5 + haze)) * moon_light;
	night_sky += vec3(0.060, 0.040, 0.022) * town_glow * pow(1.0 - above, 5.0);

	// ---- put together: day over twilight over night. The twilight is
	// worth its full weight only while the day is fading.
	vec3 col = mix(night_sky, dusk_sky, sat(dusk * 1.4));
	col = mix(col, day_sky, day);
	// A last warmth of the whole dome at sunrise and sunset.
	col *= mix(vec3(1.0), vec3(1.08, 0.94, 0.86), dusk * (1.0 - day) * 0.6 + dusk * day * 0.3);

	// ---- the sun's disc, only while it is up, softened by haze. Its
	// edge is a few times its own radius wide and its peak modest: a
	// pin-sharp disc many times over white flickers through the glow
	// as it crosses pixels.
	float disc = smoothstep(cos(SUN_RADIUS * 5.0), cos(SUN_RADIUS * 1.5), cos_sun);
	float sun_up = smoothstep(-0.02, 0.03, s);
	vec3 disc_color = mix(twilight_warm.rgb, sun_glow_day.rgb, smoothstep(0.0, 0.3, s));
	col += disc_color * disc * sun_up * mix(6.0, 3.0, haze) * mix(0.4, 1.0, smoothstep(0.0, 0.25, s)) * (1.0 - overcast);

	// ---- the moon's disc, over the sky and under any cloud.
	{
		vec3 view = moon;
		vec3 up = normalize(moon_up - view * dot(moon_up, view));
		vec3 right = normalize(cross(view, up));
		vec3 rel = eye - view * dot(eye, view);
		vec2 p = vec2(dot(rel, right), dot(rel, up)) / MOON_RADIUS;
		float r = length(p);
		if (r < 1.2 && cos_moon > 0.0) {
			float edge = smoothstep(1.0, 0.93, r);
			vec3 face = moon_face(p / max(r, 1.0), view, right, up, normalize(moon_sun), moon_lit);
			float over_land = smoothstep(-0.005, 0.01, moon.y);
			col = mix(col, max(col, face), edge * over_land);
		}
	}

	// ---- a cloud deck: the dome's light spread flat under it, greyer
	// and dimmer the thicker it is, a little brighter toward the horizon
	// where the deck is seen edge on; then a stroke's light under it.
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	vec3 deck = mix(vec3(luma), col, 0.3) * mix(0.9, 0.38, overcast) * (0.85 + 0.3 * (1.0 - above));
	col = mix(col, deck, overcast);
	float toward_flash = sat(dot(eye, normalize(flash_dir)));
	col += vec3(0.55, 0.60, 0.78) * flash * (0.25 + 1.5 * pow(toward_flash, 6.0));

	// ---- under the horizon: the ground's colour, lit as the dome is.
	float under = smoothstep(0.0, -0.06, v);
	vec3 ground = ground_color.rgb * mix(0.08, 1.0, day) * mix(vec3(1.0), twilight_band.rgb, dusk * 0.5);
	col = mix(col, ground, under);

	COLOR = col * energy;
}
