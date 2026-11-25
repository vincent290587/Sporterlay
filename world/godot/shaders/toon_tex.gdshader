// Imported models (Stylized Nature MegaKit) in our toon style: their colour texture
// times the instance tint, our toon lighting, optional alpha cut-out (leaves, petals,
// grass), sway, and the per-instance LOD dissolve. Normals are reworked on import
// (MegaKit): leaves point away from the crown's centre, small plants mostly up.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon.gdshaderinc"
#include "res://shaders/lod_fade.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float cutout = 0.0;      // 1: alpha-tested
uniform float sway = 0.0;        // m per m above sway_from
uniform float sway_from = 0.0;
uniform float paint = 0.06;

varying vec3 wpos;

void vertex() {
	lod_d = lod_distance(MODEL_MATRIX, CAMERA_POSITION_WORLD);
	if (!lod_keep_vertex(lod_d)) {
		VERTEX = vec3(0.0);
	}
	vec3 origin = MODEL_MATRIX[3].xyz;
	float above = max(VERTEX.y - sway_from, 0.0);
	float t = TIME * 1.1 + origin.x * 0.05 + origin.z * 0.07;
	VERTEX.x += sin(t) * sway * above;
	VERTEX.z += sin(t * 0.8 + 1.3) * sway * 0.6 * above;
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
