// Per-instance level-of-detail dissolve, for instanced props split into distance tiers.
// lod_fade = (fade in from, fade in to, fade out from, fade out to), in metres from the
// camera to the instance's origin; set per tier material by the LOD manager (Lod).
// Instances outside their tier collapse to a point in vertex(), so they cost no pixels;
// inside the fade bands a screen-space dither shows a growing share of the incoming
// tier's pixels and the complementary share of the outgoing one's.

uniform vec4 lod_fade = vec4(-2.0, -1.0, 1e9, 2e9);

varying float lod_d;

float lod_distance(mat4 model, vec3 camera) {
	return distance(model[3].xyz, camera);
}

// call at the start of vertex(); returns false when the instance isn't drawn
bool lod_keep_vertex(float d) {
	return d >= lod_fade.x && d <= lod_fade.w;
}

// call in fragment(); discards this tier's share of the pixel
void lod_dither(vec2 frag) {
	float noise = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
	float fade_in = lod_fade.y > lod_fade.x ? smoothstep(lod_fade.x, lod_fade.y, lod_d) : 1.0;
	float fade_out = lod_fade.w > lod_fade.z ? smoothstep(lod_fade.z, lod_fade.w, lod_d) : 0.0;
	if (1.0 - noise > fade_in || noise >= 1.0 - fade_out) {
		discard;
	}
}
