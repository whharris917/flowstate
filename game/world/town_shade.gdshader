shader_type spatial;
render_mode cull_disabled;
// Lamp shades, ceiling bowls, a radio's dial, a porch lantern's glass:
// everything in a house that glows when its lamp is on, in one mesh.
// Vertex colour r is the darkness at which that lamp comes on (the same
// as its light's), g how brightly it glows. By day an unlit shade is
// parchment or milk glass.

uniform float night = 0.0;

void fragment() {
	float on = smoothstep(COLOR.r, COLOR.r + 0.03, night);
	ALBEDO = vec3(0.95, 0.88, 0.72);
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	EMISSION = vec3(1.0, 0.66, 0.36) * on * COLOR.g * 3.0;
	BACKLIGHT = vec3(0.9, 0.7, 0.5) * 0.4;
}
