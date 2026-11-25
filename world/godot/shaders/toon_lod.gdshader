// Like toon_vcol, for tiered props (tree bark, far trees): with the per-instance LOD
// dissolve. Kept separate so the ground's shader has no discard in it.
shader_type spatial;

#include "res://shaders/toon.gdshaderinc"
#include "res://shaders/lod_fade.gdshaderinc"

uniform float paint = 0.08;

varying vec3 wpos;

void vertex() {
	lod_d = lod_distance(MODEL_MATRIX, CAMERA_POSITION_WORLD);
	if (!lod_keep_vertex(lod_d)) {
		VERTEX = vec3(0.0);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	lod_dither(FRAGCOORD.xy);
	float n = vnoise(wpos.xz * 0.06) * 0.6 + vnoise(wpos.xz * 0.45) * 0.4;
	vec3 c = COLOR.rgb * (1.0 + (n - 0.5) * paint * 2.0);
	ALBEDO = srgb_to_linear(c);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
