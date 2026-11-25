// Painterly sky: a soft blue gradient, a warm sun and fluffy shaded clouds.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.36, 0.60, 0.90);
uniform vec3 horizon_color : source_color = vec3(0.80, 0.89, 0.96);
uniform vec3 ground_color : source_color = vec3(0.62, 0.72, 0.80);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.82);
uniform vec3 cloud_shade : source_color = vec3(0.74, 0.80, 0.90);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.1, h));
	float s = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += sun_color * (smoothstep(0.9993, 0.9996, s) * 4.0 + pow(s, 28.0) * 0.3);
	if (!AT_CUBEMAP_PASS && h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 1.2 + vec2(TIME * 0.004, TIME * 0.002);
		float n = fbm(uv);
		float cover = smoothstep(0.5, 0.64, n) * smoothstep(0.0, 0.12, h);
		float shade = smoothstep(0.55, 0.78, fbm(uv - LIGHT0_DIRECTION.xz * 0.05));
		vec3 cloud = mix(vec3(1.0), cloud_shade, clamp(1.0 - (n - 0.5) * 4.0 + shade * 0.5, 0.0, 1.0) * 0.6);
		col = mix(col, cloud + sun_color * pow(s, 8.0) * 0.15, cover);
	}
	COLOR = col;
}
