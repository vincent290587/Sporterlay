// Ground mist for a FogVolume: thick below `top`, thinning out over `soft` metres
// above it, broken into slow drifting wisps by 3D noise.
shader_type fog;

uniform float density = 0.08;
uniform float top = -4.0;
uniform float soft = 12.0;
uniform vec3 albedo : source_color = vec3(0.62, 0.66, 0.80);
uniform vec3 drift = vec3(0.6, 0.0, 0.25);   // m/s

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

void fog() {
	vec3 p = WORLD_POSITION - drift * TIME;
	float wisps = vnoise3(p * vec3(0.025, 0.08, 0.025)) * 0.65 + vnoise3(p * vec3(0.09, 0.2, 0.09)) * 0.35;
	// the mist's surface undulates with the wisps
	float surface = top + (wisps - 0.5) * soft * 0.8;
	float below = smoothstep(surface + soft * 0.5, surface - soft * 0.5, WORLD_POSITION.y);
	DENSITY = density * below * mix(0.35, 1.35, wisps);
	ALBEDO = albedo;
}
