shader_type spatial;
// Behind the stars (NightSky): the Milky Way and the glow of the upper
// air, on a dome that follows the viewer, additive over the sky.
//
// The Milky Way is a picture in galactic coordinates (milky_way.png,
// the square root of its light): each direction is turned into the
// celestial frame at the hour (to_celestial) and from there into
// galactic longitude and latitude. Its light is faint, a little over the
// night sky's own at its brightest, and it is the first thing twilight,
// moonlight and cloud take away. Toward the horizon the air dims and
// reddens it, and the airglow, a faint band a few degrees up where the
// eye looks through the most of the glowing layer, takes over.
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, blend_add;

uniform sampler2D milky_way : filter_linear, repeat_enable;   // the square root of the light, not a colour
uniform mat3 to_celestial = mat3(1.0);
uniform float visibility = 0.0;
uniform float moon = 0.0;
uniform float strength = 0.022;

// The galactic north pole and centre in the celestial frame (J2000).
const vec3 GAL_POLE = vec3(-0.8677, 0.4560, 0.1981);
const vec3 GAL_CENTRE = vec3(-0.0549, -0.4838, 0.8734);

varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 w = normalize(dir);
	if (w.y < -0.02) {
		discard;
	}
	float airmass = 1.0 / max(w.y + 0.03, 0.03);
	vec3 extinction = exp(-vec3(0.20, 0.26, 0.38) * (airmass - 1.0));
	vec3 d = normalize(to_celestial * w);
	vec3 across = cross(GAL_POLE, GAL_CENTRE);
	float l = atan(dot(d, across), dot(d, GAL_CENTRE));
	float b = asin(clamp(dot(d, GAL_POLE), -1.0, 1.0));
	float bd = degrees(b);
	vec2 uv = vec2(0.5 - degrees(l) / 360.0, (40.0 - bd) / 80.0);
	vec3 tex = texture(milky_way, uv).rgb;
	vec3 milky = tex * tex * (1.0 - smoothstep(34.0, 40.0, abs(bd)));
	// Only a dark sky shows it: it waits for full dark and the moon's
	// light washes it out.
	float dark = pow(visibility, 2.5) * (1.0 - 0.85 * moon);
	vec3 col = milky * strength * dark * extinction;
	// Airglow: strongest some ten degrees up, faintly green.
	float glow = exp(-pow((w.y - 0.15) / 0.18, 2.0));
	col += vec3(0.55, 0.65, 0.5) * 0.0012 * glow * pow(visibility, 2.0);
	float above = smoothstep(-0.02, 0.05, w.y);
	ALBEDO = col * above;
}
