// Swamp water (Giant Wetland): still, tea-coloured water you can see a little way into.
// - small waves from two drifting noise layers bend the normal: toon-banded sun
//   highlights and a glitter streak towards the sun
// - the sky reflected by view angle (horizon colour at grazing angles, the zenith's
//   colour looking down), darker under the trees' shadows
// - refraction: the ground and roots below show through, bent by the waves, fading
//   into murk with depth
// - duckweed drifting in sheltered patches, foam at the shore
// Patterns fade out with distance (fwidth) so they don't shimmer.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/toon.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 sun_dir = vec3(0.3, 0.4, 0.8);     // towards the sun (world)
uniform vec3 shallow = vec3(0.26, 0.32, 0.20);  // tea-green, sRGB
uniform vec3 murk = vec3(0.05, 0.12, 0.12);
uniform vec3 sky_top = vec3(0.20, 0.42, 0.55);
uniform vec3 sky_horizon = vec3(0.72, 0.86, 0.82);
uniform vec3 weed = vec3(0.42, 0.58, 0.16);
uniform float clarity = 2.6;    // m of water before the bottom is mostly gone

varying vec3 wpos;

float h2(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.3 + 7.1) * 0.4;
}

// height of the small waves at p (m), two layers drifting different ways
float waves(vec2 p, float t) {
	return h2(p * 0.22 + vec2(t * 0.05, t * 0.03)) * 0.65
		+ h2(p * 0.8 - vec2(t * 0.03, -t * 0.07)) * 0.35;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(80.0, 260.0, dist);

	// wave normal (world), flattened with distance
	float e = 0.15;
	vec2 p = wpos.xz;
	float h0 = waves(p, t);
	vec3 n = normalize(vec3((h0 - waves(p + vec2(e, 0.0), t)) * 0.3,
		e, (h0 - waves(p + vec2(0.0, e), t)) * 0.3));
	n = normalize(mix(vec3(0.0, 1.0, 0.0), n, mix(0.25, 1.0, near)));
	vec3 view = normalize(CAMERA_POSITION_WORLD - wpos);

	// depth below the surface along the view ray, and the bottom bent by the waves
	vec2 bend = n.xz * 0.035 * near;
	float d0 = texture(depth_tex, SCREEN_UV + bend).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4((SCREEN_UV + bend) * 2.0 - 1.0, d0, 1.0);
	v.xyz /= v.w;
	if (VERTEX.z - v.z < 0.0) {   // bent onto something in front of the water: don't
		bend = vec2(0.0);
		d0 = texture(depth_tex, SCREEN_UV).r;
		v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d0, 1.0);
		v.xyz /= v.w;
	}
	float thick = max(VERTEX.z - v.z, 0.0);
	vec3 below = texture(screen_tex, SCREEN_UV + bend).rgb;
	float seen = exp(-thick / clarity);
	vec3 c = srgb_to_linear(mix(murk, shallow, 0.35 + 0.65 * seen));

	// the sky by reflection
	vec3 r = reflect(-view, n);
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 5.0);
	vec3 sky = srgb_to_linear(mix(sky_horizon, sky_top, smoothstep(0.0, 0.5, r.y)));
	float refl = clamp(fres * 0.85, 0.0, 0.85);
	c = mix(c, sky, refl);
	// what shows through is already lit, so it goes in as emission, not albedo
	float through = seen * 0.8 * (1.0 - refl);
	c *= 1.0 - through;
	vec3 lit_below = below * vec3(0.78, 0.82, 0.58) * through;

	// sun: a glitter streak and toon bands where waves face it
	vec3 hv = normalize(normalize(sun_dir) + view);
	float spec = pow(max(dot(n, hv), 0.0), 220.0);
	float sparkle = smoothstep(0.45, 0.75, vnoise(p * 3.5 + vec2(t * 0.9, -t * 0.6)));
	float glitter = smoothstep(0.3, 0.45, spec) * mix(1.0, sparkle, near) * (0.6 + 0.4 * near);
	float tilt = smoothstep(0.990, 0.996, dot(n, normalize(sun_dir * vec3(1.0, 0.25, 1.0) + vec3(0.0, 1.0, 0.0))));
	vec3 sun = srgb_to_linear(vec3(1.0, 0.96, 0.85)) * (glitter * 1.2 + tilt * 0.08 * near);

	// shore foam, lapping
	float foam = 1.0 - smoothstep(0.04, 0.18, thick + sin(t * 1.5 + p.x * 0.3 + p.y * 0.2) * 0.03);
	c = mix(c, vec3(0.9), foam * 0.7);
	lit_below *= 1.0 - foam * 0.7;

	// duckweed in sheltered patches (shallows, between islands), drifting slowly
	float shallow_side = 1.0 - smoothstep(0.5, 4.0, thick);
	float patch = vnoise(p * 0.035 + vec2(t * 0.002, 0.0)) * 0.7 + vnoise(p * 0.11) * 0.3;
	float specks = vnoise(p * 3.0 + vec2(t * 0.02, t * 0.013));
	float cover = smoothstep(0.68, 0.76, patch + shallow_side * 0.12);
	float dw = cover * mix(1.0, smoothstep(0.3, 0.55, specks), near * 0.8);
	vec3 weed_c = srgb_to_linear(weed * (0.85 + 0.3 * vnoise(p * 0.7)));

	// duckweed only: surface plants stay out of the reflection
	float plant = dw * 0.9;
	ALBEDO = mix(c, weed_c, plant);
	EMISSION = (lit_below + sun) * (1.0 - plant);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
