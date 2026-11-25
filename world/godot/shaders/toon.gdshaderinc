// Shared toon lighting: the sun gives a soft-edged lit band (cut by shadows), a narrow
// brighter band facing it, and a thin rim. Ambient light fills the shadow side.
// Point lights (torches) light softly, in a few broad bands of their falloff.

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

vec3 srgb_to_linear(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	if (!LIGHT_IS_DIRECTIONAL) {
		float a = ATTENUATION;
		float banded = mix(a, floor(a * 4.0 + 0.6) / 4.0, 0.22);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * smoothstep(-0.15, 0.35, ndl) * banded;
	} else {
		float lit = smoothstep(0.0, 0.08, ndl) * smoothstep(0.3, 0.7, ATTENUATION);
		float high = smoothstep(0.55, 0.63, ndl) * lit;
		float rim = smoothstep(0.66, 0.76, 1.0 - max(dot(NORMAL, VIEW), 0.0)) * lit;
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * (lit * 0.85 + high * 0.15 + rim * 0.2);
	}
}
