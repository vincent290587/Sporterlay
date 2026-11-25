// Wind sway shared by every surface of a model (bark and leaves alike), so a tree bends
// as one piece: the offset grows with the square of the height above `sway_from`, the
// base stays rooted, and each instance has its own phase from its position.
// `sway` is the offset in metres at `sway_height` above the root.

uniform float sway = 0.0;
uniform float sway_from = 0.0;
uniform float sway_height = 10.0;

vec3 sway_offset(vec3 v, mat4 model, float time) {
	vec3 origin = model[3].xyz;
	float above = max(v.y - sway_from, 0.0) / max(sway_height, 0.01);
	float bend = sway * above * above;
	float t = time * 1.1 + origin.x * 0.05 + origin.z * 0.07;
	return vec3(sin(t), 0.0, sin(t * 0.8 + 1.3) * 0.6) * bend;
}
