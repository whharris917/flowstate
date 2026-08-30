shader_type spatial;
// World-space ground grid: 1 m minor lines, 8 m major lines, each
// fading with distance so the infinite plane reads as ground rather
// than moiré. Drawn in world space so the mesh can follow the player
// without the pattern swimming.

uniform vec3 base_color : source_color = vec3(0.44, 0.47, 0.44);
uniform vec3 minor_color : source_color = vec3(0.39, 0.42, 0.39);
uniform vec3 major_color : source_color = vec3(0.31, 0.35, 0.32);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 pos, float spacing) {
	vec2 g = abs(fract(pos / spacing - 0.5) - 0.5) * spacing / fwidth(pos);
	return 1.0 - min(min(g.x, g.y), 1.0);
}

void fragment() {
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float fade_minor = clamp(1.0 - dist / 45.0, 0.0, 1.0);
	float fade_major = clamp(1.0 - dist / 160.0, 0.0, 1.0);
	vec3 color = base_color;
	color = mix(color, minor_color, grid_line(world_pos.xz, 1.0) * fade_minor);
	color = mix(color, major_color, grid_line(world_pos.xz, 8.0) * fade_major);
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
