// Ripples where something stands in the water (swamp trunks, boardwalk posts): a
// broken foam collar around it and rings drifting outwards. Drawn on a flat 2x2 plane
// just above the water; the inner `inner` part (the trunk) is left clear.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

#include "res://shaders/toon.gdshaderinc"

uniform float inner = 0.22;      // trunk radius, as a fraction of the plane's radius
uniform float speed = 0.2;       // rings per second, roughly
uniform vec3 foam = vec3(0.86, 0.95, 0.95);

varying float seed;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	seed = hash12(o.xz * 0.37);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float wob = (vnoise(vec2(ang * 2.0 + seed * 40.0, TIME * 0.4)) - 0.5) * 0.07;
	// the collar hugging the trunk, lapping
	float lap = inner + 0.05 + 0.03 * sin(TIME * 1.7 + seed * 30.0) + wob;
	float collar = smoothstep(inner - 0.02, inner + 0.01, r) * (1.0 - smoothstep(lap - 0.02, lap, r));
	float a = collar * 0.7;
	// rings drifting out, thinner and fainter as they go
	for (int i = 0; i < 3; i++) {
		float ph = fract(TIME * speed * (0.85 + seed * 0.3) + float(i) / 3.0 + seed);
		float rr = mix(inner + 0.04, 1.0, sqrt(ph)) + wob * (1.0 + ph);
		float w = mix(0.035, 0.015, ph);
		float band = 1.0 - smoothstep(w * 0.4, w, abs(r - rr));
		float arcs = smoothstep(0.3, 0.5, vnoise(vec2(ang * 4.0 + seed * 17.0 + float(i) * 5.0, ph * 2.0)));
		a = max(a, band * (1.0 - ph) * (1.0 - ph) * 0.5 * mix(0.2, 1.0, arcs));
	}
	a *= 1.0 - smoothstep(0.9, 1.0, r);
	ALBEDO = foam;
	ALPHA = a;
}
