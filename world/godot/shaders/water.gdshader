// Lakes: clear turquoise in the shallows, deep blue further out, a foam line at the
// shore and drifting glints.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://shaders/toon.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform vec3 shallow : source_color = vec3(0.36, 0.78, 0.74);
uniform vec3 deep : source_color = vec3(0.08, 0.34, 0.52);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	v.xyz /= v.w;
	float thick = VERTEX.z - v.z;
	float t = smoothstep(0.0, 3.0, thick);
	vec3 c = mix(shallow, deep, t);
	float foam = 1.0 - smoothstep(0.15, 0.6, thick + sin(TIME * 1.5 + wpos.x * 0.3 + wpos.z * 0.2) * 0.12);
	float glint = smoothstep(0.86, 0.9, vnoise(wpos.xz * 0.4 + vec2(TIME * 0.2, TIME * 0.13)));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	c = mix(c, vec3(0.55, 0.75, 0.90), fres * 0.35);
	c = mix(c, vec3(1.0), max(foam * 0.85, glint * 0.5));
	ALBEDO = c;
	ALPHA = clamp(mix(0.7, 0.97, t) + foam, 0.0, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
