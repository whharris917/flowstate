shader_type spatial;
// Lamp glass and bulbs: every street lamp's globe, every bare bulb
// under a shade and the theatre's marquee bulbs, in one mesh. Each
// lamp's photocell trips a few seconds after or before its
// neighbours: vertex colour r is its delay as a share of eight
// seconds; the world passes the last switching edge (switched_on,
// seconds since). A filament comes up over half a second. g marks a
// marquee bulb, b its place in the chase. By day an unlit globe is
// milky glass.

uniform bool switched_on = false;
uniform float since = 1000.0;

void fragment() {
	float delay = COLOR.r * 8.0;
	float ramp = clamp((since - delay) / 0.5, 0.0, 1.0);
	float on = switched_on ? ramp : 1.0 - ramp;
	vec3 warm = vec3(1.0, 0.70, 0.40);
	float energy = 5.0;
	if (COLOR.g > 0.5) {
		// The marquee chases: three bulbs in four lit, stepping round.
		float bulb = round(COLOR.b * 64.0);
		on *= mod(bulb + floor(TIME * 6.0), 4.0) < 3.0 ? 1.0 : 0.12;
		warm = vec3(1.0, 0.82, 0.55);
		energy = 7.0;
	}
	ALBEDO = vec3(0.82, 0.80, 0.76);
	ROUGHNESS = 0.3;
	SPECULAR = 0.5;
	EMISSION = warm * energy * on;
}
