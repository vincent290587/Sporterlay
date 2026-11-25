// Ground, road, trees, rocks: vertex colour (sRGB, times the instance colour) with a
// faint painterly variation in world space.
shader_type spatial;

#include "res://shaders/toon.gdshaderinc"

uniform float paint = 0.08;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = vnoise(wpos.xz * 0.06) * 0.6 + vnoise(wpos.xz * 0.45) * 0.4;
	vec3 c = COLOR.rgb * (1.0 + (n - 0.5) * paint * 2.0);
	ALBEDO = srgb_to_linear(c);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
