// The endless world's sky: the day sky (sky.gdshader: gradient, sun, fluffy clouds)
// and the dusk sky (night_sky.gdshader: afterglow, stars, moon, thin dark clouds) in
// one, blended by `night` as the road passes from biome to biome. The directional
// light is the sun by day and the moon at dusk.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.36, 0.60, 0.90);
uniform vec3 horizon_color : source_color = vec3(0.80, 0.89, 0.96);
uniform vec3 ground_color : source_color = vec3(0.62, 0.72, 0.80);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.82);
uniform vec3 cloud_shade : source_color = vec3(0.74, 0.80, 0.90);
uniform float night = 0.0;
uniform vec3 glow_color : source_color = vec3(0.55, 0.16, 0.08);
uniform vec3 glow_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 moon_color : source_color = vec3(0.95, 0.93, 0.85);
uniform float moon_size = 0.035;

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
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.5, h));
	float s = max(dot(d, LIGHT0_DIRECTION), 0.0);
	float ang = acos(clamp(dot(d, LIGHT0_DIRECTION), -1.0, 1.0));

	// day: the sun's disc and glow, fluffy clouds
	vec3 day = col + sun_color * (smoothstep(0.9993, 0.9996, s) * 4.0 + pow(s, 28.0) * 0.3);
	// dusk: afterglow low towards glow_dir, stars overhead, the moon with a halo
	vec2 gd = normalize(glow_dir.xz + vec2(1e-5));
	float facing = max(dot(normalize(d.xz + vec2(1e-5)), gd), 0.0);
	float glow = pow(facing, 3.0) * exp(-max(h, 0.0) * 9.0);
	vec3 dusk = col + glow_color * glow * 1.1;
	if (!AT_CUBEMAP_PASS && h > 0.0 && night > 0.01) {
		vec2 sp = vec2(atan(d.x, d.z) * 180.0, asin(clamp(h, 0.0, 1.0)) * 180.0);
		vec2 cell = floor(sp);
		float r = hash12(cell);
		if (r > 0.985) {
			vec2 c = cell + vec2(hash12(cell + 7.1), hash12(cell + 3.7));
			float b = smoothstep(0.35, 0.0, length(sp - c)) * (r - 0.985) / 0.015 * (0.75 + 0.25 * sin(TIME * (1.0 + r * 3.0) + r * 40.0));
			dusk += vec3(0.85, 0.88, 1.0) * b * smoothstep(0.03, 0.35, h) * (1.0 - glow * 2.0);
		}
	}
	dusk += moon_color * 0.06 * exp(-ang / (moon_size * 6.0)) + moon_color * 0.02 * exp(-ang / (moon_size * 30.0));
	if (ang < moon_size * 1.05) {
		vec3 up = abs(LIGHT0_DIRECTION.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
		vec3 ax = normalize(cross(up, LIGHT0_DIRECTION));
		vec3 ay = cross(LIGHT0_DIRECTION, ax);
		vec2 q = vec2(dot(d, ax), dot(d, ay)) / moon_size;
		float maria = smoothstep(0.45, 0.7, fbm(q * 2.2 + 3.0));
		vec3 disc = moon_color * (1.25 - maria * 0.35) * (1.0 - 0.18 * dot(q, q));
		dusk = mix(dusk, disc, smoothstep(moon_size * 1.05, moon_size * 0.97, ang));
	}
	// clouds, white by day and dark by night
	if (!AT_CUBEMAP_PASS && h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 1.2 + vec2(TIME * 0.004, TIME * 0.002);
		float n = fbm(uv);
		float cover = smoothstep(0.5, 0.64, n) * smoothstep(0.0, 0.12, h);
		float shade = smoothstep(0.55, 0.78, fbm(uv - LIGHT0_DIRECTION.xz * 0.05));
		vec3 cloud = mix(vec3(1.0), cloud_shade, clamp(1.0 - (n - 0.5) * 4.0 + shade * 0.5, 0.0, 1.0) * 0.6);
		day = mix(day, cloud + sun_color * pow(s, 8.0) * 0.15, cover);
		float lit = exp(-ang / 0.25) * 0.6 + glow * 0.8;
		vec3 dark = vec3(0.02, 0.02, 0.035) + moon_color * lit * 0.12 + glow_color * glow * 0.25;
		dusk = mix(dusk, dark, cover * 0.85);
	}
	col = mix(day, dusk, night);
	col = mix(col, ground_color, smoothstep(0.0, -0.1, h));
	COLOR = col;
}
