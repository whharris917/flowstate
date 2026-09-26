shader_type spatial;
// The town's windows, every pane in one mesh. Each window is a quad
// with UV 0..1 (v up) and a vertex colour that says how it lives:
//   r  the darkness at which someone switches its light on (1: never)
//   g  the curtains' hue
//   b  the window: 0 a six-over-six sash, 0.5 a storefront's plate
//      glass, 1 a church's tall window
//   a  how warm its bulb burns
// Unlit, the glass is dark and takes the sky; lit, the room behind it
// glows through, brighter low where the lamp stands, the curtains at
// the sides and a blind part way down catching the light. Sashes carry
// their muntins and meeting rail in white trim.
#include "res://world/granite.gdshaderinc"

uniform float night = 0.0;        // 0 full daylight, 1 dark
uniform float wet = 0.0;

void fragment() {
	vec2 uv = UV;
	float style = COLOR.b;
	float thr = COLOR.r;
	float on = thr > 0.99 ? 0.0 : smoothstep(thr, thr + 0.03, night);
	float seed = COLOR.g;

	// The bars.
	float bar = 0.0;
	float w = 0.02;
	if (style < 0.25) {
		float frame = 1.0 - step(0.045, uv.x) * step(uv.x, 0.955) * step(0.03, uv.y) * step(uv.y, 0.97);
		float rail = 1.0 - step(0.022, abs(uv.y - 0.5));
		float sy = fract(uv.y * 2.0);
		float mullion = (1.0 - step(w, abs(uv.x - 0.3333))) + (1.0 - step(w, abs(uv.x - 0.6667)));
		float transom = 1.0 - step(w * 1.6, abs(sy - 0.5));
		bar = clamp(frame + rail + mullion + transom, 0.0, 1.0);
	} else if (style < 0.75) {
		float frame = 1.0 - step(0.02, uv.x) * step(uv.x, 0.98) * step(0.02, uv.y) * step(uv.y, 0.98);
		float transom = 1.0 - step(0.012, abs(uv.y - 0.8));
		bar = clamp(frame + transom, 0.0, 1.0);
	} else {
		float frame = 1.0 - step(0.06, uv.x) * step(uv.x, 0.94) * step(0.03, uv.y) * step(uv.y, 0.97);
		float lead = (1.0 - step(0.012, abs(fract(uv.x * 2.0) - 0.5))) + (1.0 - step(0.008, abs(fract(uv.y * 6.0) - 0.5)));
		bar = clamp(frame + lead * 0.8, 0.0, 1.0);
	}

	// The room behind: a warm glow, brighter toward the sill, curtains
	// at the sides, a blind drawn part way down.
	vec3 bulb = mix(vec3(1.0, 0.46, 0.16), vec3(1.0, 0.60, 0.28), COLOR.a);
	float glow = 0.55 + 0.45 * (1.0 - uv.y);
	float blind_at = 1.0 - 0.15 - 0.5 * fract(seed * 7.13);
	vec3 curtain = mix(vec3(0.9, 0.55, 0.35), vec3(0.75, 0.8, 0.55), fract(seed * 3.7));
	float side = 1.0 - smoothstep(0.16, 0.22, min(uv.x, 1.0 - uv.x));
	vec3 room = bulb * glow;
	if (style < 0.25) {
		room = mix(room, bulb * curtain * 1.3, side * 0.85);
		room = mix(room, bulb * vec3(1.0, 0.85, 0.6) * 1.2, step(blind_at, uv.y));
	} else if (style < 0.75) {
		// A shop: brighter, the shelves' shadows in bands under the transom.
		room = bulb * (0.8 + 0.25 * step(0.8, uv.y)) * (0.88 + 0.12 * step(0.5, fract(uv.y * 5.0)));
	} else {
		room = bulb * vec3(1.0, 0.8, 0.5) * (0.8 + 0.4 * value_noise(uv * vec2(6.0, 20.0)));
	}

	vec3 glass = lin(vec3(0.07, 0.08, 0.09));
	vec3 trim = lin(vec3(0.86, 0.85, 0.80));
	// By day the curtains and a drawn blind show in a sash window's glass.
	if (style < 0.25) {
		glass = mix(glass, lin(curtain) * 0.45, side * 0.85);
		glass = mix(glass, lin(vec3(0.82, 0.76, 0.6)) * 0.45, step(blind_at, uv.y) * 0.9);
	}
	ALBEDO = mix(glass, trim, bar);
	ROUGHNESS = mix(0.04, mix(0.5, 0.25, wet), bar);
	SPECULAR = mix(0.75, 0.4, bar);
	METALLIC = 0.0;
	EMISSION = room * on * (1.0 - bar) * 0.75;
}
