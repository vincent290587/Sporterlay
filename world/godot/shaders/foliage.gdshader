// Tree crowns. Normals point away from the crown's centre (set by TreeGen), so the toon
// light shades a crown as one soft volume. COLOR.a picks the cut-out:
//   0    solid (cluster cores, conifer core)
//   0.5  needle frond: a tapering strip with a jagged edge
//   0.75 needle tuft: a spiky burst (pine)
//   1    leaf clump: a scalloped disc
// The tree sways as one piece with its bark (sway.gdshaderinc). Tiers dissolve into each
// other per tree (lod_fade.gdshaderinc).
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon.gdshaderinc"
#include "res://shaders/lod_fade.gdshaderinc"
#include "res://shaders/sway.gdshaderinc"

varying vec3 wpos;

void vertex() {
	lod_d = lod_distance(MODEL_MATRIX, CAMERA_POSITION_WORLD);
	if (!lod_keep_vertex(lod_d)) {
		VERTEX = vec3(0.0);
	}
	VERTEX += sway_offset(VERTEX, MODEL_MATRIX, TIME);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float clump(vec2 uv) {
	vec2 p = uv * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	float edge = 0.78 + 0.12 * sin(a * 7.0) + 0.06 * sin(a * 13.0 + 1.7);
	return step(length(p), edge);
}

// a spiky burst of needles (pine tufts)
float tuft(vec2 uv) {
	vec2 p = uv * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	float spikes = pow(abs(sin(a * 11.0)), 0.8);
	float edge = 0.68 + 0.24 * spikes + 0.05 * sin(a * 23.0);
	return step(length(p), edge);
}

float needles(vec2 uv) {
	float across = abs(uv.x - 0.5) * 2.0;
	float shape = smoothstep(0.0, 0.12, uv.y) * (1.0 - uv.y * 0.55);
	float teeth = 1.0 - 0.35 * abs(fract(uv.y * 9.0) - 0.5) * 2.0;
	return step(across, shape * teeth);
}

void fragment() {
	lod_dither(FRAGCOORD.xy);
	float kind = COLOR.a;
	float mask = 1.0;
	if (kind > 0.875) {
		mask = clump(UV);
	} else if (kind > 0.6) {
		mask = tuft(UV);
	} else if (kind > 0.25) {
		mask = needles(UV);
	}
	ALPHA = mask;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	float n = vnoise(wpos.xz * 0.9 + wpos.y * 0.7);
	ALBEDO = srgb_to_linear(COLOR.rgb * (0.92 + 0.16 * n));
	// back faces keep the crown normal (Godot would flip it)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
