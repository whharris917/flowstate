shader_type spatial;
// Boulders and erratics (2026-09-12): the same granite as the ledge,
// tinted per instance, wearing the tide's bands where the sea reaches
// them. Flat-shaded facets from the mesh give the form; no relief map.
#include "res://world/granite.gdshaderinc"

uniform float sea_y = -7.0;
uniform float tide_y = -7.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 tint;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	tint = COLOR.rgb;
}

void fragment() {
	vec3 wn = normalize(world_normal);
	float above = world_pos.y - sea_y;
	vec3 c = lichen(granite(world_pos, wn), world_pos, wn, above) * tint;
	float rough = 0.78;
	c = shore_bands(c, world_pos, wn, sea_y, tide_y, rough);
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
