shader_type spatial;
// The night sky: drawn on a dome that follows the player, additive
// over the sky, fading in as the sun's twilight fades out. The stars
// are fixed in a celestial frame that turns about the pole with the
// clock (sky_rotation, world to celestial, set by the world), so they
// rise in the east and wheel round Polaris.
//
// Three layers hashed on a cube-mapped grid, so they are as dense at
// the zenith as at the horizon: a rare bright few, the naked-eye
// field, and a fine faint dust of stars that only a dark sky shows.
// Each star has its own magnitude and a colour from its temperature,
// blue-white to orange. A star is a soft dot sized to the pixel, so
// it neither shimmers nor vanishes at any render scale, and it
// scintillates, more near the horizon where its light crosses more
// air; the same air dims and reddens it there.
//
// The Milky Way is a band on the galactic equator, brightest toward
// the galactic centre, clumped by noise and split by a dark rift,
// with the faint layer crowded into it. Fog never touches any of it.
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, blend_add;

uniform float visibility = 0.0;
uniform mat3 sky_rotation = mat3(1.0);

// The celestial frame: y the pole, x toward right ascension zero, -z
// toward ninety degrees, so (cos dec cos ra, sin dec, -cos dec sin ra).
// The galactic north pole and centre in it, from their right ascension
// and declination (192.86, +27.13 and 266.40, -28.94).
const vec3 GAL_POLE = vec3(-0.8676, 0.4560, 0.1981);
const vec3 GAL_CENTRE = vec3(-0.0549, -0.4840, 0.8733);

varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// The colour of a star from a uniform draw: most are white to yellow,
// a few blue-white, a few orange.
vec3 star_tint(float t) {
	if (t < 0.10) return vec3(0.62, 0.74, 1.0);
	if (t < 0.40) return vec3(0.84, 0.90, 1.0);
	if (t < 0.72) return vec3(1.0, 0.97, 0.92);
	if (t < 0.92) return vec3(1.0, 0.86, 0.66);
	return vec3(1.0, 0.70, 0.46);
}

// One layer: the grid's cells per cube face, the share of cells that
// hold a star, the light of the brightest, and how steeply the
// magnitudes fall off (higher: more faint ones).
vec3 layer(vec2 uv, float face, float cells, float share, float peak, float steep,
		float seed, float airmass, float elevation) {
	vec2 g = (uv * 0.5 + 0.5) * cells + face * 1000.0 + seed;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float h = hash2(cell);
	if (h < 1.0 - share) {
		return vec3(0.0);
	}
	vec2 c = vec2(0.3 + 0.4 * hash2(cell + 1.3), 0.3 + 0.4 * hash2(cell + 2.7));
	float mag = pow(hash2(cell + 4.1), steep);
	// The dot is about a pixel across whatever the cell's size on
	// screen; brighter stars spread a little wider, as the eye sees them.
	vec2 px = fwidth(g);
	float r = max(max(px.x, px.y), 1e-4) * (0.55 + 0.6 * mag);
	float d = length(f - c);
	float dot_ = exp(-(d * d) / (r * r));
	// Scintillation: two incommensurate flickers per star, stronger low.
	float ph = hash2(cell + 7.7) * 6.2832;
	float rate = 5.0 + 9.0 * hash2(cell + 8.8);
	float tw = 1.0 + (0.12 + 0.55 * pow(1.0 - elevation, 3.0))
		* (0.6 * sin(TIME * rate + ph) + 0.4 * sin(TIME * rate * 2.37 + ph * 1.7));
	vec3 tint = star_tint(hash2(cell + 9.0));
	return tint * dot_ * mag * peak * max(tw, 0.0);
}

void fragment() {
	vec3 w = normalize(dir);
	float elevation = clamp(w.y, 0.0, 1.0);
	if (w.y < -0.02) {
		discard;
	}
	// Air mass: one straight up, about forty at the horizon.
	float airmass = 1.0 / max(w.y + 0.025, 0.025);
	vec3 extinction = exp(-vec3(0.12, 0.20, 0.34) * (airmass - 1.0));

	vec3 d = normalize(sky_rotation * w);
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

	// The Milky Way: galactic latitude and the direction to the centre.
	float b = dot(d, GAL_POLE);
	float toward = dot(d, GAL_CENTRE) * 0.5 + 0.5;
	float band = exp(-pow(b / (0.10 + 0.08 * toward), 2.0));
	float clumps = fbm3(d * 6.0);
	float rift = exp(-pow((b - 0.015) / 0.035, 2.0)) * smoothstep(0.35, 0.7, fbm3(d * 11.0 + 5.0))
		* smoothstep(0.35, 0.85, toward);
	float milky = band * (0.35 + 0.65 * toward * toward) * smoothstep(0.30, 0.75, clumps) * (1.0 - 0.8 * rift);
	vec3 glow = vec3(0.78, 0.78, 0.74) * milky * 0.045;

	vec3 col = vec3(0.0);
	col += layer(uv, face, 38.0, 0.05, 6.0, 4.0, 0.0, airmass, elevation);
	col += layer(uv, face, 110.0, 0.14, 1.6, 2.5, 311.0, airmass, elevation);
	col += layer(uv, face, 240.0, 0.10 + 0.45 * milky, 0.55, 1.5, 733.0, airmass, elevation);
	col += glow;

	float above = smoothstep(-0.02, 0.06, w.y);
	ALBEDO = col * extinction * visibility * above;
}
