// Lit windows and other things that give off their own light: the vertex colour
// (sRGB) pushed past 1 so the glow picks it up, with a slow candle flicker per window.
// Dark windows (near-black vertex colour) stay dark.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float strength = 2.6;
uniform float flicker = 0.18;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float seed = dot(floor(wpos * 0.7), vec3(12.9898, 78.233, 37.719));
	float f = 1.0 - flicker * (0.5 + 0.5 * sin(TIME * (2.3 + fract(seed) * 2.0) + fract(seed * 1.7) * 30.0))
		* (0.5 + 0.5 * sin(TIME * 7.1 + seed));
	ALBEDO = c * strength * f;
}
