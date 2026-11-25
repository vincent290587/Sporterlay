// Boardwalk deck: planks across the road drawn from UV (x = metres across the deck,
// y = metres along the road). Each plank gets its own tone and weathering, wood grain
// runs along it, joints are staggered, nails sit over the stringers, and the gaps are
// dark. Detail fades out with distance (fwidth) so it doesn't shimmer.
shader_type spatial;

#include "res://shaders/toon.gdshaderinc"

uniform float plank = 0.26;      // plank width along the road (m)
uniform float gap = 0.022;       // gap between planks (m)
uniform float half_width = 2.6;
uniform vec3 warm = vec3(0.60, 0.42, 0.26);
uniform vec3 grey = vec3(0.55, 0.50, 0.44);
uniform vec3 dark = vec3(0.36, 0.25, 0.16);
uniform vec3 moss = vec3(0.32, 0.38, 0.20);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = UV.x;
	float along = UV.y;
	float row = floor(along / plank);
	float f = fract(along / plank);
	// staggered joints: most planks are two boards, split somewhere off centre
	float split = (hash12(vec2(row, 3.1)) - 0.5) * half_width * 1.2;
	float board = row * 2.0 + step(split, across);
	float r1 = hash12(vec2(board, 1.7));
	float r2 = hash12(vec2(board, 8.3));
	float r3 = hash12(vec2(board, 5.9));

	vec3 c = mix(warm, grey, smoothstep(0.35, 0.95, r1));
	c = mix(c, dark, smoothstep(0.75, 1.0, r2) * 0.55);
	c *= 0.86 + 0.26 * r3;

	// grain: streaks along the board (across the road), with a slow wobble
	float aa = fwidth(along) / plank;            // how much of a plank one pixel covers
	float detail = 1.0 - smoothstep(0.15, 0.6, aa);
	float wob = vnoise(vec2(across * 0.7 + board * 13.0, f * 2.0)) * 3.0;
	float grain = vnoise(vec2(across * 1.2 + board * 7.0, f * 22.0 + wob));
	grain = grain * 0.7 + vnoise(vec2(across * 6.0 + board * 3.0, f * 60.0)) * 0.3;
	c *= 1.0 + (grain - 0.5) * 0.34 * detail;

	// an occasional knot
	float kx = (hash12(vec2(board, 2.2)) - 0.5) * half_width * 1.6;
	float knot = 1.0 - smoothstep(0.03, 0.07, length(vec2((across - kx) * 0.6, (f - 0.5) * plank)));
	c = mix(c, dark * 0.8, knot * step(0.82, r2) * detail);

	// worn track down the middle, damp and mossy towards the edges
	float edge = smoothstep(half_width - 0.9, half_width, abs(across));
	c = mix(c, moss, edge * (0.35 + 0.3 * vnoise(wpos.xz * 0.8)));
	c *= 1.0 + 0.06 * (1.0 - smoothstep(0.0, 1.2, abs(across)));

	// nails over the stringers
	float nail = 0.0;
	for (int k = -1; k <= 1; k++) {
		float sx = float(k) * (half_width - 0.35);
		vec2 d = vec2(across - sx, (f - 0.5) * plank);
		d.y = abs(d.y) - plank * 0.24;
		nail = max(nail, 1.0 - smoothstep(0.008, 0.016, length(d)));
	}
	c = mix(c, vec3(0.18, 0.17, 0.16), nail * detail);

	// board ends and gaps: dark, softened by the plank's rounded edges
	float g = gap / plank;
	float soft = max(fwidth(f), 0.002);
	float in_gap = 1.0 - smoothstep(g * 0.5 - soft, g * 0.5 + soft, min(f, 1.0 - f));
	float bevel = 1.0 - smoothstep(g * 0.5, g * 0.5 + 0.08, min(f, 1.0 - f));
	float joint = 1.0 - smoothstep(0.004, 0.004 + fwidth(across) * 1.5, abs(across - split));
	c *= 1.0 - bevel * 0.18 * detail;
	vec3 gapcol = vec3(0.07, 0.06, 0.05);
	float hole = max(in_gap, joint * 0.8) * mix(0.35, 1.0, detail);
	c = mix(c, gapcol, hole);

	float n = vnoise(wpos.xz * 0.06) * 0.6 + vnoise(wpos.xz * 0.45) * 0.4;
	c *= 1.0 + (n - 0.5) * 0.1;
	ALBEDO = srgb_to_linear(c);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
