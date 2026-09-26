shader_type spatial;
// Trees made of cards: bark on the trunk and limbs, leaf clusters and
// needle boughs as textured cards cut out by their alpha. One shader
// for both, so the whole tree sways together: the wind bends it more
// the higher up, in slow swings with a faster flutter over them, each
// tree on its own phase. The leaf colour comes per tree (instance
// custom data), so one mesh serves a green maple and a scarlet one;
// the bark keeps its own colour. Light through a leaf shows on its
// shaded side.
render_mode cull_disabled;

uniform sampler2D leaves : source_color, filter_linear_mipmap, repeat_disable;
uniform bool bark = false;
uniform float wind = 0.2;                     // 0 still to 1 a gale
uniform vec2 wind_dir = vec2(-0.7071, -0.7071);
uniform float wet = 0.0;
uniform float tex_size = 256.0;

varying vec3 tint;
varying vec3 local;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

void vertex() {
	// The tints are picked as screen colours; the light works in linear.
	tint = pow(INSTANCE_CUSTOM.rgb, vec3(2.2));
	local = VERTEX;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.21 + origin.z * 0.17;
	float h = max(VERTEX.y, 0.0);
	float bend = h * h * 0.0022;
	float swing = sin(TIME * (0.9 + 0.5 * wind) + phase) + 0.45 * sin(TIME * 2.3 + phase * 1.7);
	float flutter = sin(TIME * 7.0 + VERTEX.x * 3.0 + VERTEX.z * 2.0 + phase) * 0.35 * (bark ? 0.0 : 1.0);
	vec3 push = vec3(wind_dir.x, 0.0, wind_dir.y) * (bend * wind * (0.8 + 0.6 * swing) + flutter * wind * 0.04 * h / 12.0);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * push;
}

void fragment() {
	if (bark) {
		// Bark: furrows running up the stem, lichen in patches.
		float furrow = noise3(vec3(local.x * 14.0, local.y * 1.2, local.z * 14.0));
		float patch = smoothstep(0.62, 0.8, noise3(local * 2.3 + 7.0));
		vec3 bark_col = pow(COLOR.rgb, vec3(2.2)) * (0.6 + 0.6 * furrow);
		ALBEDO = mix(bark_col, vec3(0.22, 0.26, 0.16), patch * 0.5);
		ROUGHNESS = mix(0.95, 0.55, wet);
		SPECULAR = 0.2;
	} else {
		// A card's two faces share one normal, bent out from the crown's
		// heart, so the crown is lit as a mass and no card goes dark for
		// facing inward.
		if (!FRONT_FACING) {
			NORMAL = -NORMAL;
		}
		vec4 t = texture(leaves, UV);
		// Far off, where the texture's smaller copies have thinned the
		// leaves, the cut-out holds more so the crown stays full.
		vec2 px = UV * tex_size;
		float mip = max(0.0, log2(max(length(dFdx(px)), length(dFdy(px)))));
		ALPHA = clamp(t.a * (1.0 + 0.45 * mip), 0.0, 1.0);
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		ALBEDO = t.rgb * tint * COLOR.rgb;
		// Leaves are matte, wet or dry: a card seen edge-on would otherwise
		// mirror the sky and turn the crown grey.
		ROUGHNESS = mix(0.9, 0.6, wet);
		SPECULAR = mix(0.02, 0.1, wet);
		BACKLIGHT = ALBEDO * 0.25;
	}
}
