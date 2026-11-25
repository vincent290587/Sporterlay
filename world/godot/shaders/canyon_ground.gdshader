// Canyon country surfaces: the vertex colour (sRGB) with detail painted in world
// space, fading out with distance so it never shimmers:
// - rock (steep faces): fine strata lines by height, each band a little lighter or
//   darker, and vertical cracks;
// - sand (flats): wind ripples and pebbles;
// - masonry (> 0, buildings): courses of blocks with joints, uneven stones, and
//   weathering; plaster (> 0): smooth with blotches and bricks showing through.
shader_type spatial;

#include "res://shaders/toon.gdshaderinc"

uniform float masonry = 0.0;
uniform float course = 0.55;      // masonry course height (m)
uniform float plaster = 0.0;
uniform float detail_far = 220.0; // detail is gone by this distance

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float lines(float v, float width) {
	float f = fract(v);
	return 1.0 - smoothstep(0.0, width, min(f, 1.0 - f));
}

void fragment() {
	vec3 c = COLOR.rgb;
	// steep rock is drawn faceted (the face's own normal), so cliffs read as cut
	// rock rather than soft slopes; flats and buildings keep their smooth normals
	vec3 face = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	if (dot(face, NORMAL) < 0.0) {
		face = -face;
	}
	// vertex alpha: how much rock and sand detail to paint (the endless world blends
	// it in with the canyon biome; everything else has alpha 1)
	float amount = COLOR.a;
	float cliff = (masonry > 0.0 || plaster > 0.0) ? 0.0 : (1.0 - smoothstep(0.2, 0.45, wnorm.y)) * 0.65 * amount;
	NORMAL = normalize(mix(NORMAL, face, cliff));
	float dist = -VERTEX.z;
	float near = 1.0 - smoothstep(detail_far * 0.4, detail_far, dist);
	float steep = 1.0 - smoothstep(0.5, 0.85, wnorm.y);
	float paint = vnoise(wpos.xz * 0.06) * 0.6 + vnoise(wpos.xz * 0.45) * 0.4;
	c *= 1.0 + (paint - 0.5) * 0.14;

	if (masonry > 0.0) {
		// blocks: horizontal courses, joints staggered every other course
		float row = floor(wpos.y / course);
		float along = abs(wnorm.x) > abs(wnorm.z) ? wpos.z : wpos.x;
		float len = course * (2.2 + hash12(vec2(row, 3.0)) * 0.8);
		float u = along / len + row * 0.5;
		float block = hash12(vec2(floor(u), row));
		float joint = max(lines(wpos.y / course, 0.06), lines(u, 0.05 / (len / course)) * (1.0 - step(0.9, abs(wnorm.y))));
		c *= 0.9 + block * 0.18;
		c = mix(c, c * 0.55, joint * near * masonry);
		// weathering: dark streaks down from the joints, chipped pale edges
		float streak = vnoise(vec2(along * 1.3, wpos.y * 0.15));
		c *= 1.0 - smoothstep(0.6, 0.85, streak) * 0.15 * masonry;
	} else if (plaster > 0.0) {
		float blotch = vnoise(wpos.xz * 0.7 + wpos.y * 0.5) * 0.6 + vnoise(vec2(wpos.x + wpos.z, wpos.y) * 2.0) * 0.4;
		c *= 0.93 + blotch * 0.14;
		// mud bricks showing where the plaster fell off
		float bare = smoothstep(0.68, 0.72, vnoise(vec2(wpos.x + wpos.z, wpos.y) * 0.45));
		float brow = floor(wpos.y / 0.18);
		float bu = (wpos.x + wpos.z) / 0.38 + brow * 0.5;
		float bj = max(lines(wpos.y / 0.18, 0.1), lines(bu, 0.08));
		c = mix(c, c * (0.82 - bj * 0.25), bare * near * plaster);
	} else {
		// strata: bands ~1-3 m thick following the height, gently warped
		float y = wpos.y + (vnoise(wpos.xz * 0.015) - 0.5) * 8.0;
		float b = floor(y * 0.6);
		float shade = 0.84 + hash12(vec2(b, 7.0)) * 0.3;
		float fine = lines(y * 2.3, 0.08) * 0.5 + lines(y * 0.6, 0.04);
		vec2 h = abs(wnorm.x) > abs(wnorm.z) ? wpos.zy : wpos.xy;
		// joints: thin, nearly straight vertical cracks, only some of them
		float cn = vnoise(vec2(h.x * 0.35 + vnoise(vec2(h.y * 0.02, h.x * 0.1)) * 0.8, h.y * 0.008));
		float crack = (1.0 - smoothstep(0.0, 0.012, abs(cn - 0.5))) * step(0.45, vnoise(vec2(h.x * 0.05, 3.0)));
		float rock_detail = mix(1.0, mix(1.0, shade, steep), amount) * (1.0 - fine * 0.12 * steep * near * amount) * (1.0 - crack * 0.3 * steep * near * amount);
		c *= rock_detail;
		// sand: ripples across the wind, and pebbles
		float flat_ = 1.0 - steep;
		float rip = sin(dot(wpos.xz, vec2(0.83, 0.55)) * 2.6 + vnoise(wpos.xz * 0.08) * 7.0);
		c *= 1.0 + rip * 0.045 * flat_ * near * amount;
		vec2 cell = floor(wpos.xz * 2.2);
		float r = hash12(cell);
		float peb = step(0.96, r) * (1.0 - smoothstep(0.08, 0.18, length(fract(wpos.xz * 2.2) - 0.5)));
		c = mix(c, c * (r > 0.98 ? 1.15 : 0.82), peb * flat_ * near * amount);
	}
	ALBEDO = srgb_to_linear(c);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
