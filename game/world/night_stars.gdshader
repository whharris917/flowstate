shader_type spatial;
// The stars of the catalogue, a square each (NightSky). The vertex is the
// star's direction in the celestial frame; to_world turns it into the
// sky at the hour. Each square is set out far off along that direction
// and spread across a fixed number of pixels round it, so a star is a
// point however large the screen: a soft dot about a pixel wide at the
// eye's limit, a little wider for the bright ones, as the eye's own
// glare widens them, never a disc.
//
// Brightness follows the magnitude against the faintest the eye reaches
// here (limit, lowered by twilight through visibility and by the moon's
// light): each magnitude two and a half times. Through more air toward
// the horizon a star dims (a quarter magnitude an air mass) and reddens,
// and it scintillates, more the lower it stands. Colour shows in the
// bright stars only, as it does to the eye at night.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform mat3 to_world = mat3(1.0);
uniform float visibility = 0.0;
uniform float limit = 6.3;
uniform float moon = 0.0;

varying vec3 v_col;
varying float v_peak;
varying vec2 v_at;

void vertex() {
	vec3 w = normalize(to_world * VERTEX);
	float elev = w.y;
	float airmass = 1.0 / max(elev + 0.03, 0.03);
	float mag = UV2.x + 0.25 * (airmass - 1.0);
	// The faintest star seen now: none in daylight, the brightest first.
	float lim = mix(-2.0, limit - 1.6 * moon, visibility);
	float light = pow(10.0, -0.4 * (mag - lim));
	float seed = UV2.y;
	float amp = 0.05 + 0.45 * pow(1.0 - clamp(elev, 0.0, 1.0), 4.0);
	float tw = 1.0 + amp * (0.6 * sin(TIME * (6.0 + 8.0 * seed) + seed * 41.0)
		+ 0.4 * sin(TIME * (15.0 + 7.0 * seed) + seed * 97.0));
	light *= max(tw, 0.0);
	v_peak = clamp(0.04 * pow(light, 0.72), 0.0, 1.8) * smoothstep(-0.005, 0.02, elev);
	float r = 0.75 + 0.5 * log(max(light, 1.0)) / log(10.0);
	float colour = clamp(0.15 + 0.2 * log(max(light, 1.0)) / log(10.0), 0.0, 0.75);
	v_col = mix(vec3(1.0), COLOR.rgb, colour) * exp(-vec3(0.0, 0.05, 0.14) * (airmass - 1.0));
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(CAMERA_POSITION_WORLD + w * 3500.0, 1.0));
	// The square reaches three widths out, where the dot has gone.
	clip.xy += UV * r * 3.0 * 2.0 / VIEWPORT_SIZE * clip.w;
	v_at = UV * 3.0;
	if (v_peak < 0.0015) {
		clip = vec4(2.0, 2.0, 2.0, 1.0);
	}
	POSITION = clip;
}

void fragment() {
	float d2 = dot(v_at, v_at);
	ALBEDO = v_col * v_peak * exp(-d2);
}
