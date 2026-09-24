shader_type spatial;
// The heighliner's hull: dark and matte, lit by the sun like anything
// else, but outside the environment's fog — at a kilometre the aerial
// perspective would turn it a pale ghost of the sky,
// and a thing that size should stay a dark presence. It takes a
// little of the horizon's colour itself instead, set from the clock.
render_mode fog_disabled, cull_back;

uniform vec3 hull : source_color = vec3(0.085, 0.088, 0.095);
uniform vec3 haze_color : source_color = vec3(0.62, 0.72, 0.84);
uniform float haze : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	ALBEDO = hull * (1.0 - haze);
	EMISSION = haze_color * haze * 0.8;
	ROUGHNESS = 0.86;
	METALLIC = 0.0;
	SPECULAR = 0.2;
}
