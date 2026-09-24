// Shared ground functions for a landscape: value noise, a
// triplanar sample of it, and the granite of the Maine coast with the
// bands the sea leaves on it. Included by terrain.gdshader (the
// heightfield), rock.gdshader (the boulders) and sea.gdshader (the
// noise only). World-space throughout, so nothing swims.
//
// Colours are written as an artist reads them (sRGB) and put through
// lin(): a literal in a shader is linear, a `source_color` uniform is
// converted, and mixing the two unconverted reads five times too bright.
// This world's exposure turns even an sRGB 0.47 grey into snow, so the
// rock sits about 0.40.

vec3 lin(vec3 srgb) {
	return pow(srgb, vec3(2.2));
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Value noise on the three world planes, blended by the normal, so a
// vertical face carries the same grain as a flat one.
float tri_noise(vec3 wp, vec3 wn, float scale) {
	vec3 w = abs(wn);
	w = w / max(w.x + w.y + w.z, 1e-4);
	return value_noise(wp.yz * scale) * w.x
		+ value_noise(wp.xz * scale + 11.0) * w.y
		+ value_noise(wp.xy * scale + 23.0) * w.z;
}

// Coastal granite: pink-grey feldspar and grey quartz in broad veins,
// a fine dark speckle of mica and hornblende, and the odd pale
// feldspar glint. Grain at hand scale, speckle at fingernail scale.
vec3 granite(vec3 wp, vec3 wn) {
	float veins = tri_noise(wp, wn, 0.9);
	float grain = tri_noise(wp, wn, 7.0);
	float speck = tri_noise(wp, wn, 31.0);
	vec3 pink = lin(vec3(0.44, 0.37, 0.33));
	vec3 grey = lin(vec3(0.38, 0.37, 0.36));
	vec3 dark = lin(vec3(0.17, 0.16, 0.15));
	vec3 c = mix(pink, grey, smoothstep(0.35, 0.65, veins));
	c *= 1.0 - 0.4 * smoothstep(0.55, 0.80, grain);
	c = mix(c, dark, smoothstep(0.72, 0.85, speck) * 0.6);
	c = mix(c, lin(vec3(0.58, 0.53, 0.48)), smoothstep(0.80, 0.92, tri_noise(wp, wn, 23.0)) * 0.3);
	return c;
}

// Lichen: black rock tripe in patches on any face above the spray,
// orange Xanthoria only in the spray zone above the barnacles.
// `above` is height above mean sea level.
vec3 lichen(vec3 c, vec3 wp, vec3 wn, float above) {
	float patch = tri_noise(wp, wn, 0.6);
	float fine = tri_noise(wp, wn, 3.7);
	float black = smoothstep(0.55, 0.75, patch * 0.7 + fine * 0.3) * smoothstep(2.6, 4.2, above);
	c = mix(c, lin(vec3(0.08, 0.08, 0.07)), black * 0.8);
	float orange = smoothstep(0.80, 0.92, fine) * smoothstep(2.2, 3.5, above) * (1.0 - smoothstep(6.0, 9.0, above));
	c = mix(c, lin(vec3(0.80, 0.48, 0.10)), orange * 0.7);
	return c;
}

// The bands the tide leaves on rock, lowest first: the seabed's kelp,
// rockweed to the neap high water, a barnacle band above it, and
// everything below today's water plus a splash margin is wet and
// dark. `rough` is the roughness the caller will write out.
vec3 shore_bands(vec3 c, vec3 wp, vec3 wn, float sea_y, float tide_y, inout float rough) {
	float above = wp.y - sea_y;
	float n = tri_noise(wp, wn, 1.3);
	float weed = (1.0 - smoothstep(1.2, 2.1, above)) * smoothstep(-3.5, -1.5, above);
	c = mix(c, lin(vec3(0.11, 0.12, 0.04)), weed * (0.55 + 0.45 * smoothstep(0.3, 0.6, n)));
	float barn = smoothstep(1.7, 2.1, above) * (1.0 - smoothstep(2.5, 3.1, above));
	c = mix(c, lin(vec3(0.55, 0.53, 0.48)), barn * 0.35 * smoothstep(0.25, 0.7, n));
	float bed = 1.0 - smoothstep(-2.5, -0.8, above);
	c = mix(c, lin(vec3(0.07, 0.07, 0.04)), bed * 0.8);
	float wet = 1.0 - smoothstep(tide_y + 0.15, tide_y + 0.9, wp.y);
	c *= 1.0 - 0.38 * wet;
	rough = mix(rough, 0.35, wet);
	return c;
}
