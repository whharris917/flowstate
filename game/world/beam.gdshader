shader_type spatial;
// A light's beam seen in thick air: a long cone from the lens, added
// to what is behind it, brightest along its axis and near the lamp,
// fading out down its length. density is how much the air holds (rain,
// fog) and how dark it is; clear air by day shows nothing. The cone is
// a cylinder mesh whose bottom is at the lens.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, blend_add, shadows_disabled;

uniform float density = 0.0;
uniform float beam_length = 300.0;
uniform vec3 color : source_color = vec3(1.0, 0.95, 0.82);

varying float along;

void vertex() {
	along = clamp(VERTEX.y / beam_length + 0.5, 0.0, 1.0);
}

void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	float fall = exp(-along * 3.2) * (1.0 - smoothstep(0.85, 1.0, along));
	ALBEDO = color * density * edge * fall * 0.35;
}
