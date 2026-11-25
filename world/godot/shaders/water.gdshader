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
	// a thin foam line right at the shore, lapping a little
	float foam = 1.0 - smoothstep(0.04, 0.16, thick + sin(TIME * 1.5 + wpos.x * 0.3 + wpos.z * 0.2) * 0.03);
	// small glints that come and go
	float g = vnoise(wpos.xz * 1.6 + vec2(TIME * 0.35, TIME * 0.21)) * vnoise(wpos.xz * 0.9 - vec2(TIME * 0.17, TIME * 0.29));
	float glint = smoothstep(0.66, 0.72, g) * (1.0 - smoothstep(60.0, 160.0, -VERTEX.z));   // only up close
	// the sky's blue at grazing angles, not a milky white
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	c = mix(c, vec3(0.32, 0.55, 0.80), fres * 0.45);
	// slow ripple streaks drifting across, in toon bands
	float r = vnoise(vec2(wpos.x * 0.18 + TIME * 0.12, wpos.z * 0.9 - TIME * 0.05));
	float streak = smoothstep(0.62, 0.66, r) * (1.0 - smoothstep(0.7, 0.75, r));
	c = mix(c, c * 1.18 + 0.04, streak * 0.6);
	c = mix(c, vec3(1.0), max(foam * 0.75, glint * 0.5));
	ALBEDO = c;
	ALPHA = clamp(mix(0.7, 0.97, t) + foam, 0.0, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
