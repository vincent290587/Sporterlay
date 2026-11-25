class_name FlowerGrass
extends RefCounted
## Flowering grass in drifts: one instancer and material per colour variant (the grass
## shader paints the heads with the material's head_color). A slow noise picks the
## variant, so each drift is mostly one colour.

var variants := []                  # [Instancer, mesh, material]
var drift := FastNoiseLite.new()


## `list`: [[head style ("plume", "haze", "star"), Color], ...]; `base` is the grass
## material to copy (its fade distances are registered with Lod per copy).
func _init(rng: RandomNumberGenerator, list: Array, base: ShaderMaterial, chunk: float, lean := Vector3.ZERO) -> void:
	drift.seed = 4242
	drift.frequency = 0.012
	for v: Array in list:
		var m: ShaderMaterial = base.duplicate()
		m.set_shader_parameter("head_color", v[1])
		Lod.add_param("grass", m, "fade_start", 130.0)
		Lod.add_param("grass", m, "fade_end", 190.0)
		variants.append([Instancer.new(chunk), Meshes.grass(rng, Meshes.GRASS_FLOWERING, lean, v[0]), m])


func put(rng: RandomNumberGenerator, pos: Vector3, yaw: float, col: Color) -> void:
	var n := drift.get_noise_2d(pos.x, pos.z) * 0.5 + 0.5 + rng.randf_range(-0.12, 0.12)
	var v: Array = variants[clampi(int(n * variants.size()), 0, variants.size() - 1)]
	(v[0] as Instancer).put(pos, yaw, rng.randf_range(0.8, 1.2), rng.randf_range(0.75, 1.1), col)


func build(parent: Node3D, far: float) -> int:
	var n := 0
	for v: Array in variants:
		n += (v[0] as Instancer).build(parent, v[1], v[2], far, false, 0.0, "grass")
	return n
