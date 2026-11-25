// Grass clumps: dark roots to bright tips in the ground's own colour (instance colour),
// swaying in gusts that roll across the field. Blades sink into the ground towards
// fade_end, so the chunk's visibility cut-off never pops.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

#include "res://shaders/toon.gdshaderinc"

uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float fade_start = 130.0;
uniform float fade_end = 190.0;

varying vec3 wpos;

void vertex() {
	float k = UV.y * UV.y;
	float sway = UV2.x > 0.0 ? UV2.x : 1.0;   // per grass type (Meshes.GRASS_TYPES)
	vec2 d = normalize(wind_dir);
	float gust = sin(dot(VERTEX.xz, d) * 0.07 - TIME * 1.4) * 0.5 + 0.5;
	gust *= 0.6 + 0.4 * sin(dot(VERTEX.xz, vec2(-d.y, d.x)) * 0.02 + TIME * 0.3);
	float flutter = sin(TIME * 3.3 + VERTEX.x * 0.9 + VERTEX.z * 0.6);
	VERTEX.xz += d * (gust * 0.28 + flutter * 0.04) * k * sway;
	VERTEX.y -= gust * 0.1 * k * sway;
	VERTEX.y -= smoothstep(fade_start, fade_end, distance(VERTEX, CAMERA_POSITION_WORLD)) * UV.y * 1.7;
	NORMAL = vec3(0.0, 1.0, 0.0);
	wpos = VERTEX;
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 c = mix(base * 0.6, base * 1.2 + vec3(0.05, 0.05, 0.0), UV.y);
	c *= 1.0 + (vnoise(wpos.xz * 0.06) - 0.5) * 0.16;
	ALBEDO = srgb_to_linear(c);
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
