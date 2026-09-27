shader_type spatial;
// The Clemens house's painted and papered rooms (Hartford, 1881: the
// decorations of Tiffany's Associated Artists). The vertex colour is the
// ground colour as an artist reads it; its alpha picks the pattern laid
// over it, in tenths:
//   0 plain distemper       1 the hall: a lattice of small diamonds
//   2 the drawing room: sprigs in rows, a diaper between
//   3 the library: a trellis with a flower at each crossing
//   4 the dining room: embossed paper like tooled leather, gilt
//   5 the hall ceiling: stars in a lattice of ribs
//   6 a bedroom paper: a small repeat of leaves
// The motif colour is worked out from the ground: silver on the red and
// the salmon, gold on the blue and the leather. Drawn in world space from
// the surface's own direction, so nothing needs UVs.
#include "res://world/granite.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float diamond(vec2 p) {
	return abs(p.x) + abs(p.y);
}

void fragment() {
	int kind = int(round(COLOR.a * 10.0));
	vec3 base = lin(COLOR.rgb);
	vec3 wn = normalize(world_normal);
	bool flat_face = abs(wn.y) > 0.95;
	vec3 across = normalize(flat_face ? vec3(1.0, 0.0, 0.0) : cross(vec3(0.0, 1.0, 0.0), wn));
	vec2 uv = flat_face ? world_pos.xz : vec2(dot(world_pos, across), world_pos.y);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(12.0, 40.0, dist);
	vec3 silver = lin(vec3(0.78, 0.78, 0.74));
	vec3 gold = lin(vec3(0.80, 0.62, 0.28));
	vec3 col = base;
	float rough = 0.85;
	float spec = 0.3;
	float metal = 0.0;
	// How fine a motif may be before it only shimmers: fade it out
	// where a repeat falls under a few pixels.
	float fine = 1.0 - smoothstep(0.08, 0.25, max(fwidth(uv.x), fwidth(uv.y)) / 0.1);

	if (kind == 1) {
		// Small diamonds in a lattice, each with a dot of silver.
		vec2 p = uv / vec2(0.075, 0.075);
		vec2 f = fract(p) - 0.5;
		vec2 g = fract(p + 0.5) - 0.5;
		float lattice = smoothstep(0.06, 0.02, abs(diamond(f) - 0.42));
		float dot_ = smoothstep(0.14, 0.08, diamond(g));
		col = mix(col, silver, (0.55 * lattice + 0.8 * dot_) * fine * detail);
		col = mix(col, col * 0.55, 0.35 * smoothstep(0.2, 0.1, diamond(f)) * fine);
		metal = 0.25 * (lattice + dot_) * fine;
		rough = 0.55;
	} else if (kind == 2) {
		// Rows of sprigs, dropped half a repeat each row, a fine diaper
		// between them.
		vec2 p = uv / vec2(0.11, 0.14);
		float row = floor(p.y);
		p.x += 0.5 * mod(row, 2.0);
		vec2 f = fract(p) - 0.5;
		float sprig = smoothstep(0.2, 0.12, length(f * vec2(1.0, 0.55))) - smoothstep(0.1, 0.04, length(f));
		float diaper = smoothstep(0.03, 0.0, abs(fract((uv.x + uv.y) / 0.035) - 0.5) - 0.46);
		col = mix(col, silver, (0.75 * sprig + 0.12 * diaper) * fine * detail);
		metal = 0.3 * sprig * fine;
		rough = 0.6;
	} else if (kind == 3) {
		// A trellis on the diagonal, a small flower at each crossing.
		vec2 p = uv / 0.09;
		vec2 d = vec2(p.x + p.y, p.x - p.y) * 0.5;
		float bars = smoothstep(0.05, 0.02, min(abs(fract(d.x) - 0.5), abs(fract(d.y) - 0.5)));
		vec2 f = fract(p) - 0.5;
		float flower = smoothstep(0.2, 0.12, length(f)) * (0.6 + 0.4 * cos(atan(f.y, f.x) * 5.0));
		col = mix(col, gold, (0.35 * bars + 0.7 * flower) * fine * detail);
		metal = 0.35 * flower * fine;
		rough = 0.6;
	} else if (kind == 4) {
		// Tooled leather: hexagonal cells, their rims raised and gilt,
		// the fields darker toward the middle.
		vec2 p = uv / vec2(0.12, 0.104);
		vec2 r = vec2(1.0, 1.732);
		vec2 h = r * 0.5;
		vec2 a = mod(p, r) - h;
		vec2 b = mod(p - h, r) - h;
		vec2 gv = dot(a, a) < dot(b, b) ? a : b;
		float edge = max(abs(gv.x), dot(abs(gv), normalize(vec2(1.0, 1.732))));
		float rim = smoothstep(0.38, 0.47, edge);
		col = mix(col * (0.75 + 0.35 * edge), gold, rim * 0.75 * detail);
		metal = 0.5 * rim;
		rough = mix(0.7, 0.35, rim);
		spec = 0.5;
	} else if (kind == 5) {
		// Stars in a lattice: ribs on the diagonals and square, each
		// cell's star a darker red.
		vec2 p = uv / 0.6;
		vec2 f = fract(p) - 0.5;
		float square = min(abs(f.x), abs(f.y));
		float diag = min(abs(f.x + f.y), abs(f.x - f.y)) * 0.7071;
		float star = smoothstep(0.22, 0.2, diamond(f) * 0.8 + 0.25 * min(abs(f.x), abs(f.y)));
		col = mix(col, col * 0.45, star * 0.6);
		col = mix(col, silver * 0.8, smoothstep(0.02, 0.008, abs(diamond(f) - 0.32)) * 0.6 * detail);
		col = mix(col, lin(vec3(0.20, 0.10, 0.05)), smoothstep(0.03, 0.015, min(square, diag)) * 0.8);
		rough = 0.7;
	} else if (kind == 6) {
		// A small repeat of leaves, dropped a half each row.
		vec2 p = uv / vec2(0.08, 0.1);
		p.x += 0.5 * mod(floor(p.y), 2.0);
		vec2 f = fract(p) - 0.5;
		float leaf = smoothstep(0.18, 0.1, length((f - vec2(0.12, 0.0)) * vec2(1.0, 2.2)))
			+ smoothstep(0.18, 0.1, length((f + vec2(0.12, 0.0)) * vec2(1.0, 2.2)));
		col = mix(col, col * vec3(0.55, 0.75, 0.55), clamp(leaf, 0.0, 1.0) * 0.6 * fine * detail);
		rough = 0.85;
	} else {
		col *= 0.96 + 0.05 * value_noise(uv * 3.0);
		rough = 0.9;
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
}
