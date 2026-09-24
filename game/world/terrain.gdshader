shader_type spatial;
// A landscape's ground: one heightfield wearing the field
// shader's grass where it is flat and clear of the sea, granite ledge
// where it is steep or within the sea's reach, cobble where the site
// says a beach is (vertex colour red), and the tide's bands on the
// rock. Graded ground (vertex colour green) is plain field whatever
// its height: a site is mown. Outcrops (vertex colour blue) are rock.
// World-space throughout, as the field shader is, so nothing swims.
// Shared rock functions live in granite.gdshaderinc. Past FAR metres
// the grain, the lichen and the relief are under a pixel, so the far
// ground takes a cheap path: the same colours by slope and height
// from one noise.
#include "res://world/granite.gdshaderinc"

const float FAR = 110.0;

uniform float sea_y = -7.0;
uniform float tide_y = -7.0;
uniform vec3 grass_color : source_color = vec3(0.15, 0.26, 0.09);
uniform vec3 grass_dry : source_color = vec3(0.23, 0.32, 0.11);
uniform vec3 grass_dark : source_color = vec3(0.09, 0.17, 0.06);
uniform vec3 heath_color : source_color = vec3(0.22, 0.20, 0.09);

varying vec3 world_pos;
varying vec3 world_normal;
varying float beach;
varying float graded;
varying float outcrop;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	beach = COLOR.r;
	graded = COLOR.g;
	outcrop = COLOR.b;
}

void fragment() {
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec2 p = world_pos.xz;
	vec3 wn = normalize(world_normal);
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float above = world_pos.y - sea_y;
	// Only the graded flat itself is mown; its blend to the wild
	// ground keeps the rock and the heath.
	float wild = 1.0 - smoothstep(0.5, 0.9, graded);

	if (dist > FAR) {
		float patches = value_noise(p * 0.07);
		vec3 veg = mix(grass_color, grass_dry, smoothstep(0.45, 0.90, patches) * 0.55);
		float rockness = max(max(smoothstep(0.20, 0.40, slope), 1.0 - smoothstep(3.0, 6.0, above)) * wild, outcrop);
		vec3 rock = lin(vec3(0.40, 0.36, 0.33));
		float weed = (1.0 - smoothstep(1.2, 2.1, above)) * smoothstep(-3.5, -1.5, above);
		rock = mix(rock, lin(vec3(0.11, 0.12, 0.04)), weed * 0.7);
		rock = mix(rock, lin(vec3(0.07, 0.07, 0.04)), (1.0 - smoothstep(-2.5, -0.8, above)) * 0.8);
		ALBEDO = mix(veg, rock, rockness);
		ROUGHNESS = mix(0.96, 0.78, rockness);
		SPECULAR = mix(0.08, 0.25, rockness);
	} else {
		float near = clamp(1.0 - dist / 25.0, 0.0, 1.0);

		// The field: the grass shader's patches, clumps and blades, with
		// drifts of heath (bayberry, juniper, blueberry) toward the shore.
		float patches = value_noise(p * 0.07) * 0.6 + value_noise(p * 0.23 + 7.0) * 0.4;
		float clumps = value_noise(p * 2.2 + 3.0);
		float blades = value_noise(p * 38.0) * near;
		vec3 veg = mix(grass_color, grass_dry, smoothstep(0.45, 0.90, patches) * 0.55);
		veg = mix(veg, grass_dark, (1.0 - clumps) * 0.30);
		veg *= 0.92 + 0.22 * (blades - 0.5 * near);
		float heath = smoothstep(0.55, 0.85, value_noise(p * 0.03 + 41.0)) * (1.0 - smoothstep(9.0, 16.0, above)) * wild;
		veg = mix(veg, heath_color * (0.85 + 0.3 * clumps), heath * 0.45);

		// Rock: every steep face, and the band the sea works — bare ledge
		// to a few metres over high water, its upper edge ragged.
		float rockness = smoothstep(0.20, 0.40, slope);
		float shore = 1.0 - smoothstep(3.0, 6.0, above + 1.5 * value_noise(p * 0.06));
		rockness = max(max(rockness, shore) * wild, outcrop);
		vec3 rock = lichen(granite(world_pos, wn), world_pos, wn, above);
		float rough = 0.78;
		rock = shore_bands(rock, world_pos, wn, sea_y, tide_y, rough);
		// A beach: cobble and gravel in the low band where the site says
		// so, instead of ledge.
		float cobble = beach * (1.0 - smoothstep(2.5, 4.0, above)) * smoothstep(-3.0, -1.0, above);
		vec3 pebbles = mix(lin(vec3(0.30, 0.28, 0.26)), lin(vec3(0.42, 0.40, 0.36)), smoothstep(0.4, 0.8, value_noise(p * 9.0)));
		pebbles = mix(pebbles, lin(vec3(0.36, 0.29, 0.23)), smoothstep(0.6, 0.9, value_noise(p * 3.3 + 5.0)) * 0.5);
		pebbles *= 1.0 - 0.38 * (1.0 - smoothstep(tide_y + 0.15, tide_y + 0.9, world_pos.y));
		rock = mix(rock, pebbles, cobble);
		rockness = max(rockness, cobble);

		vec3 color = mix(veg, rock, rockness);
		ALBEDO = color;
		ROUGHNESS = mix(0.96, mix(rough, 0.85, cobble), rockness);
		SPECULAR = mix(0.08, 0.25, rockness);

		// Relief: the clumps and blades of the field near the camera, the
		// grain of the rock a little further, both fading with distance so
		// the far ground stays calm.
		float e = 0.04;
		float h0 = value_noise(p * 2.2 + 3.0) * 0.6 + value_noise(p * 38.0) * 0.4;
		float hx = value_noise((p + vec2(e, 0.0)) * 2.2 + 3.0) * 0.6 + value_noise((p + vec2(e, 0.0)) * 38.0) * 0.4;
		float hz = value_noise((p + vec2(0.0, e)) * 2.2 + 3.0) * 0.6 + value_noise((p + vec2(0.0, e)) * 38.0) * 0.4;
		float er = 0.06;
		float r0 = value_noise(p * 3.1 + 5.0);
		float rx = value_noise((p + vec2(er, 0.0)) * 3.1 + 5.0);
		float rz = value_noise((p + vec2(0.0, er)) * 3.1 + 5.0);
		float mid = clamp(1.0 - dist / 60.0, 0.0, 1.0);
		vec2 bump = mix(vec2(hx - h0, hz - h0) * 3.0 * near, vec2(rx - r0, rz - r0) * 4.0 * mid, rockness);
		NORMAL_MAP = normalize(vec3(-bump.x, -bump.y, 1.0)) * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 0.5;
	}
}
