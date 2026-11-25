// Late dusk: a deep blue-violet sky, the last dull red band low where the sun went
// down (`glow_dir`), stars coming out overhead, a big pale moon (the directional
// light) with a halo, and thin dark clouds drifting across it.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.012, 0.016, 0.045);
uniform vec3 horizon_color : source_color = vec3(0.07, 0.07, 0.13);
uniform vec3 ground_color : source_color = vec3(0.03, 0.03, 0.05);
uniform vec3 glow_color : source_color = vec3(0.55, 0.16, 0.08);
uniform vec3 glow_high : source_color = vec3(0.30, 0.12, 0.22);
uniform vec3 glow_dir = vec3(1.0, 0.0, 0.0);
uniform vec3 moon_color : source_color = vec3(0.95, 0.93, 0.85);
uniform vec3 cloud_color : source_color = vec3(0.02, 0.02, 0.035);
uniform float moon_size = 0.035;      // angular radius (rad)
uniform float star_amount = 1.0;

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
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.45, h));

	// afterglow: strongest low on the horizon towards glow_dir, fading up and round
	vec2 gd = normalize(glow_dir.xz);
	float facing = max(dot(normalize(d.xz + vec2(1e-5)), gd), 0.0);
	float glow = pow(facing, 3.0) * exp(-max(h, 0.0) * 9.0);
	col += glow_color * glow * 1.1 + glow_high * pow(facing, 2.0) * exp(-max(h, 0.0) * 3.5) * 0.35;

	// stars: one per cell of a direction grid, more overhead, none in the afterglow
	if (!AT_CUBEMAP_PASS && h > 0.0) {
		vec2 sp = vec2(atan(d.x, d.z) * 180.0, asin(clamp(h, 0.0, 1.0)) * 180.0);
		vec2 cell = floor(sp);
		float r = hash12(cell);
		if (r > 0.985) {
			vec2 c = cell + vec2(hash12(cell + 7.1), hash12(cell + 3.7));
			float dist = length(sp - c);
			float twinkle = 0.75 + 0.25 * sin(TIME * (1.0 + r * 3.0) + r * 40.0);
			float b = smoothstep(0.35, 0.0, dist) * (r - 0.985) / 0.015 * twinkle;
			col += vec3(0.85, 0.88, 1.0) * b * star_amount * smoothstep(0.03, 0.35, h) * (1.0 - glow * 2.0);
		}
	}

	// the moon: a disc with darker maria, and a soft halo
	vec3 m = LIGHT0_DIRECTION;
	float ang = acos(clamp(dot(d, m), -1.0, 1.0));
	col += moon_color * 0.06 * exp(-ang / (moon_size * 6.0)) + moon_color * 0.02 * exp(-ang / (moon_size * 30.0));
	if (ang < moon_size * 1.05) {
		vec3 up = abs(m.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
		vec3 ax = normalize(cross(up, m));
		vec3 ay = cross(m, ax);
		vec2 q = vec2(dot(d, ax), dot(d, ay)) / moon_size;
		float maria = smoothstep(0.45, 0.7, fbm(q * 2.2 + 3.0));
		vec3 disc = moon_color * (1.25 - maria * 0.35) * (1.0 - 0.18 * dot(q, q));
		col = mix(col, disc, smoothstep(moon_size * 1.05, moon_size * 0.97, ang));
	}

	// thin dark clouds drifting over it all
	if (!AT_CUBEMAP_PASS && h > 0.0) {
		vec2 uv = d.xz / (h + 0.15) * 0.9 + vec2(TIME * 0.006, TIME * 0.002);
		float n = fbm(uv);
		float cover = smoothstep(0.52, 0.72, n) * smoothstep(0.0, 0.15, h) * 0.85;
		float lit = exp(-ang / 0.25) * 0.6 + glow * 0.8;   // silver edges by the moon, red by the glow
		vec3 cloud = cloud_color + moon_color * lit * 0.12 * (1.0 - smoothstep(0.55, 0.8, n)) + glow_color * glow * 0.25;
		col = mix(col, cloud, cover);
	}
	col = mix(col, ground_color, smoothstep(0.0, -0.08, h));
	COLOR = col;
}
