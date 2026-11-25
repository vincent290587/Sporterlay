// Torch and candle flames: crossed quads (UV y from the base up) drawn as a wavering
// teardrop, white-hot at the root to red at the edges, added onto the scene bright
// enough for the glow. Each flame flickers on its own clock (seeded by its position).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float strength = 2.5;

varying float seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	seed = hash(o.xz * 0.37);
	float t = TIME * (1.4 + seed);
	float tip = UV.y * UV.y;
	VERTEX.x += sin(t * 3.1 + seed * 20.0) * 0.07 * tip;
	VERTEX.z += cos(t * 2.3 + seed * 11.0) * 0.07 * tip;
	VERTEX.y *= 0.85 + 0.2 * sin(t * 5.3 + seed * 31.0) * sin(t * 1.7);
}

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float y = UV.y;
	float n = vnoise(vec2(UV.x * 3.0, y * 5.0 - TIME * 4.0 - seed * 10.0));
	float w = pow(max(1.0 - y, 0.0), 0.75) * smoothstep(0.0, 0.2, y);
	float m = smoothstep(w, w * 0.35, x + (n - 0.5) * 0.45 * y);
	vec3 col = mix(vec3(0.9, 0.18, 0.03), vec3(1.0, 0.62, 0.22), m);
	col = mix(col, vec3(1.0, 0.92, 0.75), smoothstep(0.55, 1.0, m) * (1.0 - y));
	ALBEDO = col * strength;
	ALPHA = m;
}
