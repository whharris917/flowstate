shader_type spatial;
// Streets, sidewalks and the harbour's gravel. A ribbon's UV is metres
// across from its centre line and metres along it; the vertex colour's
// alpha says what it is (0 asphalt, 0.5 concrete walk, 1 gravel) and
// red whether a painted centre line runs down it.
//
// Rain wets it: it darkens and slicks over, water stands in the low
// patches of the asphalt and gravel, and while it falls rings spread in
// the wet near the viewer. The puddles hold mirror-smooth, so the
// street lamps and the lit windows lie in them.
#include "res://world/granite.gdshaderinc"

uniform float wet = 0.0;
uniform float rain = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Rain rings: in each cell a drop lands once a cycle at its own place
// and time and its ring spreads and fades. Returns the ring's slope
// (world x, z).
vec2 ripples(vec2 p, float t) {
	vec2 g = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 q = p / 0.22 + float(k) * 0.5;
		vec2 cell = floor(q);
		vec2 c = cell + 0.2 + 0.6 * vec2(h21(cell + 1.7), h21(cell + 3.1));
		float phase = fract(t * 1.1 + h21(cell + 5.3));
		vec2 to = q - c;
		float d = length(to);
		float r = phase * 0.4;
		float ring = exp(-pow((d - r) / 0.06, 2.0)) * (1.0 - phase) * (1.0 - phase) * sin((d - r) * 30.0);
		g += (d > 1e-4 ? to / d : vec2(0.0)) * ring;
	}
	return g;
}

void fragment() {
	float kind = COLOR.a;
	vec2 p = world_pos.xz;
	float across = UV.x;
	float along = UV.y;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(10.0, 40.0, dist);

	vec3 col;
	float rough;
	float pond = 0.0;
	if (kind < 0.25) {
		// Asphalt: fine aggregate, darker patches, the wheel tracks
		// worn paler, a white centre line in dashes.
		col = lin(vec3(0.22, 0.215, 0.21)) * (0.85 + 0.25 * value_noise(p * 7.0)) * (0.9 + 0.15 * value_noise(p * 0.4));
		col *= 1.0 - 0.25 * smoothstep(0.62, 0.72, value_noise(p * 0.15 + 30.0));
		float track = exp(-pow((abs(across) - 1.6) / 0.5, 2.0));
		col *= 1.0 + 0.12 * track;
		if (COLOR.r > 0.5) {
			float line = (1.0 - smoothstep(0.05, 0.07, abs(across))) * step(fract(along / 6.0), 0.55);
			col = mix(col, lin(vec3(0.78, 0.77, 0.72)) * (0.7 + 0.3 * value_noise(p * 5.0)), line * 0.85);
		}
		rough = 0.88;
		pond = smoothstep(0.64, 0.74, value_noise(p * 0.22) * 0.75 + value_noise(p * 0.9) * 0.25 + 0.1 * track);
	} else if (kind < 0.75) {
		// Concrete walk: slabs a metre and a half long, a joint between.
		float f = fract(along / 1.5);
		float joint = 1.0 - smoothstep(0.0, 0.012, f) * smoothstep(1.0, 0.988, f);
		col = lin(vec3(0.56, 0.55, 0.52)) * (0.85 + 0.2 * value_noise(p * 3.0)) * (0.92 + 0.1 * h21(vec2(floor(along / 1.5), 1.0)));
		col = mix(col, col * 0.55, joint);
		rough = 0.85;
		pond = smoothstep(0.78, 0.85, value_noise(p * 0.5)) * 0.5;
	} else {
		col = lin(vec3(0.40, 0.37, 0.33)) * (0.75 + 0.4 * value_noise(p * 11.0)) * (0.9 + 0.15 * value_noise(p * 0.5));
		rough = 0.95;
		pond = smoothstep(0.6, 0.72, value_noise(p * 0.3 + 11.0));
	}

	// The wet: a darker, slicker street, standing water in the low patches.
	float standing = pond * smoothstep(0.35, 0.9, wet);
	col *= 1.0 - 0.45 * wet;
	col = mix(col, col * 0.35, standing);
	rough = mix(rough, 0.32, wet);
	rough = mix(rough, 0.03, standing);
	vec3 n = vec3(0.0, 1.0, 0.0);
	if (rain > 0.0 && near > 0.0) {
		vec2 g = ripples(p, TIME * 0.6) * rain * 0.6 * near * (0.25 + 0.75 * standing) * wet;
		n = normalize(vec3(-g.x * 0.2, 1.0, -g.y * 0.2));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = mix(0.35, 0.6, wet);
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
