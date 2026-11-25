// Bats circling the castle towers, flown entirely on the GPU: each instance sits at
// its orbit's centre, and INSTANCE_CUSTOM = (radius, angular speed, height, phase).
// The mesh is a body with two wings along x; the wings beat by lifting with |x|.
// Also the canyon's vultures: slow, shallow beats that are mostly gliding.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/toon.gdshaderinc"

// dark leathery brown: black against the sky, caught by the torches and the moon
uniform vec3 color : source_color = vec3(0.10, 0.07, 0.065);
uniform float beat_rate = 13.0;   // wingbeats (rad/s)
uniform float beat_amp = 0.75;    // how far the wings lift, per metre out

void vertex() {
	float r = INSTANCE_CUSTOM.x;
	float w = INSTANCE_CUSTOM.y;
	float ph = INSTANCE_CUSTOM.w;
	float a = TIME * w + ph;
	// a wobbly orbit: the radius breathes and the height dips and climbs
	float rr = r * (1.0 + 0.18 * sin(a * 1.7 + ph * 3.0));
	vec3 pos = vec3(cos(a) * rr, INSTANCE_CUSTOM.z + 4.0 * sin(a * 2.3 + ph), sin(a) * rr);
	vec3 fwd = normalize(vec3(-sin(a), 0.15 * cos(a * 2.3 + ph), cos(a))) * sign(w);
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec3 up = cross(fwd, side);
	vec3 v = VERTEX;
	float beat = sin(TIME * (beat_rate + fract(ph * 7.3) * beat_rate * 0.4) + ph * 11.0);
	v.y += beat * abs(v.x) * beat_amp;
	VERTEX = pos + side * v.x + up * v.y + fwd * v.z;
	NORMAL = up;
}

void fragment() {
	ALBEDO = srgb_to_linear(color);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
