// A slat-top chain belt: stainless slats at the standard
// 38.1 mm pitch, the dark gaps between them moving at the belt's real
// travel, which the view integrates from the record's speed while it
// runs -- so the belt moves exactly when and as fast as the kernel says.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform float length_m = 2.0;   // UV.x 0..1 along the belt
uniform float travel_m = 0.0;   // how far the belt has moved
uniform float pitch_m = 0.0381;
uniform vec4 steel : source_color = vec4(0.70, 0.73, 0.76, 1.0);

void fragment() {
	float s = UV.x * length_m - travel_m;
	float f = fract(s / pitch_m);
	float gap = smoothstep(0.0, 0.05, f) * (1.0 - smoothstep(0.93, 0.98, f));
	ALBEDO = steel.rgb * mix(0.25, 1.0, gap);
	METALLIC = 0.75;
	ROUGHNESS = mix(0.6, 0.32, gap);
}
