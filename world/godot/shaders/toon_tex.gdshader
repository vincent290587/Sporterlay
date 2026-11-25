// Imported models (Stylized Nature MegaKit) in our toon style: their colour texture
// times the instance tint, our toon lighting, optional alpha cut-out (leaves, petals,
// grass), sway, and the per-instance LOD dissolve. Normals are reworked on import
// (MegaKit): leaves point away from the crown's centre, small plants mostly up.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon.gdshaderinc"
#include "res://shaders/lod_fade.gdshaderinc"
#include "res://shaders/sway.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float cutout = 0.0;      // 1: alpha-tested
uniform float paint = 0.06;

varying vec3 wpos;

void vertex() {
	lod_d = lod_distance(MODEL_MATRIX, CAMERA_POSITION_WORLD);
	if (!lod_keep_vertex(lod_d)) {
		VERTEX = vec3(0.0);
	}
	VERTEX += sway_offset(VERTEX, MODEL_MATRIX, TIME);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	lod_dither(FRAGCOORD.xy);
	vec4 tex = texture(albedo_tex, UV);
	if (cutout > 0.5) {
		ALPHA = tex.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
	float n = vnoise(wpos.xz * 0.06) * 0.6 + vnoise(wpos.xz * 0.45) * 0.4;
	ALBEDO = tex.rgb * srgb_to_linear(COLOR.rgb) * (1.0 + (n - 0.5) * paint * 2.0);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
