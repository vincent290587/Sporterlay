// The ground: vertex colour (sRGB) with painterly variation, like toon_vcol, plus the
// forest canopy (CUSTOM0: crown colour, cover) blended in with distance, with a
// clumpy crown pattern. Far forests read as forests where no tree is drawn any more.
shader_type spatial;

#include "res://shaders/toon.gdshaderinc"

uniform float paint = 0.08;
uniform float canopy_near = 500.0;   // m: canopy starts showing in the ground colour
uniform float canopy_far = 1600.0;   // m: fully

varying vec3 wpos;
varying vec4 canopy;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	canopy = CUSTOM0;
}

void fragment() {
	float n = vnoise(wpos.xz * 0.06) * 0.6 + vnoise(wpos.xz * 0.45) * 0.4;
	vec3 c = COLOR.rgb * (1.0 + (n - 0.5) * paint * 2.0);
	float d = distance(wpos, CAMERA_POSITION_WORLD);
	float cover = canopy.a * smoothstep(canopy_near, canopy_far, d);
	if (cover > 0.001) {
		// crowns: bright clumps with dark gaps, about tree-sized
		float crowns = vnoise(wpos.xz * 0.16) * 0.65 + vnoise(wpos.xz * 0.5) * 0.35;
		vec3 tree = canopy.rgb * mix(0.62, 1.12, smoothstep(0.3, 0.7, crowns));
		c = mix(c, tree, clamp(cover * 1.25, 0.0, 1.0) * smoothstep(0.15, 0.4, crowns + canopy.a * 0.3));
	}
	ALBEDO = srgb_to_linear(c);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
