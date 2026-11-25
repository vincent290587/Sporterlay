class_name CanyonBirds
extends RefCounted
## Vultures circling high on the evening air: groups over the canyon and the ruins,
## over the oasis, and a few out over the desert. One MultiMesh flown on the GPU by
## bat.gdshader (orbit from per-instance custom data), with slow shallow wingbeats.


static func build(parent: Node3D, route: Route, ruins_s: float, oasis_s: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 970
	var birds := []   # [centre, custom]
	var spots := [[ruins_s, 7], [ruins_s - 450.0, 4], [ruins_s + 450.0, 4], [oasis_s, 5]]
	var s := rng.randf() * 1200.0
	while s < route.length:
		spots.append([s, 2 + rng.randi() % 3])
		s += rng.randf_range(900.0, 1500.0)
	for spot: Array in spots:
		var at := route.position_at(spot[0]) + route.right_at(spot[0]) * rng.randf_range(-60.0, 60.0)
		for _j in int(spot[1]):
			var r := rng.randf_range(25.0, 75.0)
			var speed := rng.randf_range(6.0, 9.0) / r * (-1.0 if rng.randf() < 0.4 else 1.0)
			birds.append([at, Color(r, speed, rng.randf_range(45.0, 110.0), rng.randf() * TAU)])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh()
	mm.instance_count = birds.size()
	for k in birds.size():
		mm.set_instance_transform(k, Transform3D(Basis(), birds[k][0]))
		mm.set_instance_custom_data(k, birds[k][1])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bat.gdshader")
	mat.set_shader_parameter("color", Color(0.20, 0.14, 0.11))
	mat.set_shader_parameter("beat_rate", 2.2)
	mat.set_shader_parameter("beat_amp", 0.12)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var h := CanyonLand.HALF + 200.0
	mi.custom_aabb = AABB(Vector3(-h, -100.0, -h), Vector3(2.0 * h, 400.0, 2.0 * h))
	parent.add_child(mi)
	print("  vultures: %d" % birds.size())


## Broad wings with fingered tips, 2.6 m across, a wedge tail and a small head.
static func _mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	var col := Color.WHITE
	var n := Vector3.UP
	var i := b.add(Vector3(0.0, 0.0, 0.55), n, col)        # head
	b.add(Vector3(0.12, 0.0, 0.2), n, col)
	b.add(Vector3(-0.12, 0.0, 0.2), n, col)
	b.tri_raw(i, i + 1, i + 2)
	i = b.add(Vector3(0.14, 0.0, 0.25), n, col)            # body and tail
	b.add(Vector3(-0.14, 0.0, 0.25), n, col)
	b.add(Vector3(-0.22, 0.0, -0.75), n, col)
	b.add(Vector3(0.22, 0.0, -0.75), n, col)
	b.tri_raw(i, i + 1, i + 2)
	b.tri_raw(i, i + 2, i + 3)
	for s: float in [-1.0, 1.0]:
		var rf := b.add(Vector3(s * 0.12, 0.0, 0.22), n, col)
		var rb := b.add(Vector3(s * 0.12, 0.0, -0.25), n, col)
		var mf := b.add(Vector3(s * 0.85, 0.04, 0.2), n, col)
		var mb := b.add(Vector3(s * 0.85, 0.04, -0.3), n, col)
		b.tri_raw(rf, mf, mb)
		b.tri_raw(rf, mb, rb)
		# five primaries fanned at the tip
		for k in 5:
			var t := float(k) / 4.0
			var root := Vector3(s * 0.85, 0.04, lerpf(0.18, -0.28, t))
			var tip := Vector3(s * (1.3 - absf(t - 0.4) * 0.25), 0.08, lerpf(0.22, -0.2, t))
			var a := b.add(root + Vector3(0.0, 0.0, 0.05), n, col)
			b.add(root - Vector3(0.0, 0.0, 0.05), n, col)
			b.add(tip, n, col)
			b.tri_raw(a, a + 1, a + 2)
	return b.commit()
