// Bats circling the castle towers, flown entirely on the GPU: each instance sits at
// its orbit's centre, and INSTANCE_CUSTOM = (radius, angular speed, height, phase).
// The mesh is a body with two wings along x; the wings beat by lifting with |x|.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 color : source_color = vec3(0.015, 0.012, 0.018);

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
	float beat = sin(TIME * (13.0 + fract(ph * 7.3) * 5.0) + ph * 11.0);
	v.y += beat * abs(v.x) * 0.75;
	VERTEX = pos + side * v.x + up * v.y + fwd * v.z;
}

void fragment() {
	ALBEDO = color;
}
