// Tree crowns. Normals point away from the crown's centre (set by TreeGen), so the toon
// light shades a crown as one soft volume. COLOR.a picks the cut-out:
//   0    solid (cluster cores, conifer core)
//   0.5  needle frond: a tapering strip with a jagged edge
//   1    leaf clump: a scalloped disc
// Crowns sway a little in the wind, more towards the top.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon.gdshaderinc"

uniform float sway = 0.06;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float above = max(VERTEX.y - 2.5, 0.0);
	float t = TIME * 1.1 + origin.x * 0.05 + origin.z * 0.07;
	VERTEX.x += sin(t) * sway * above;
	VERTEX.z += sin(t * 0.8 + 1.3) * sway * 0.6 * above;
}

float clump(vec2 uv) {
	vec2 p = uv * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	float edge = 0.78 + 0.12 * sin(a * 7.0) + 0.06 * sin(a * 13.0 + 1.7);
	return step(length(p), edge);
}

float needles(vec2 uv) {
	float across = abs(uv.x - 0.5) * 2.0;
	float shape = smoothstep(0.0, 0.12, uv.y) * (1.0 - uv.y * 0.55);
	float teeth = 1.0 - 0.35 * abs(fract(uv.y * 9.0) - 0.5) * 2.0;
	return step(across, shape * teeth);
}

void fragment() {
	float kind = COLOR.a;
	float mask = 1.0;
	if (kind > 0.75) {
		mask = clump(UV);
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
