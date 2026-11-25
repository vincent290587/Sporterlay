class_name TransBats
extends RefCounted
## Bats all over the world: lone bats and small groups fluttering over the road
## everywhere, more and in bigger groups the nearer the castle, and two big flocks
## circling the great tower and the keep. One MultiMesh, flown entirely on the GPU
## (bat.gdshader): each instance sits at its orbit's centre, its custom data is
## (radius, angular speed, height above the centre, phase).

const FLOCKS_NEAR := 25.0     # m of road between groups at the castle...
const FLOCKS_FAR := 120.0     # ...and far from it
const NEAR := 150.0           # within this (m of road) of the castle it's densest
const FAR := 1800.0           # beyond this it's sparsest


static func build(parent: Node3D, route: Route, castle_s: float, castle: TransCastle, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 950
	var bats := []   # [centre, scale, custom]

	# the two big flocks over the castle
	for f: Array in [[Vector3(-27.0, 0.0, -26.0), 26, 58.0], [Vector3(-27.0, 0.0, 4.0), 14, 44.0]]:
		for _j in int(f[1]):
			var r := rng.randf_range(10.0, 38.0)
			bats.append([castle._w(f[0]), rng.randf_range(0.9, 1.5),
				Color(r, _speed(rng, r), float(f[2]) + rng.randf_range(-8.0, 12.0), rng.randf() * TAU)])

	# groups along the whole loop, either side of the road
	var s := rng.randf() * FLOCKS_FAR
	while s < route.length:
		var u := absf(s - castle_s)
		u = minf(u, route.length - u)
		var near := 1.0 - smoothstep(NEAR, FAR, u)
		var side := rng.randf_range(-18.0, 18.0)
		var centre := route.position_at(s) + route.right_at(s) * side
		var n := 1 + rng.randi() % (2 + int(near * 5.0))
		for _j in n:
			# low over the road, through the torchlight and in front of the mist (a black
			# bat against the night sky can't be seen)
			var r := rng.randf_range(4.0, 14.0)
			bats.append([centre, rng.randf_range(1.0, 1.6),
				Color(r, _speed(rng, r), rng.randf_range(3.0, 9.0) + near * 5.0, rng.randf() * TAU)])
		s += lerpf(FLOCKS_NEAR, FLOCKS_FAR, 1.0 - near) * rng.randf_range(0.6, 1.4)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh()
	mm.instance_count = bats.size()
	for k in bats.size():
		var b: Array = bats[k]
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * float(b[1])), b[0]))
		mm.set_instance_custom_data(k, b[2])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bat.gdshader")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the shader moves them off their centres: cover the whole world
	var h := TransLand.HALF + 100.0
	mi.custom_aabb = AABB(Vector3(-h, -100.0, -h), Vector3(2.0 * h, 400.0, 2.0 * h))
	parent.add_child(mi)
	print("  bats: %d" % bats.size())


## Flying at 4.5-8 m/s round the orbit, a third of them the other way.
static func _speed(rng: RandomNumberGenerator, r: float) -> float:
	return rng.randf_range(4.5, 8.0) / r * (-1.0 if rng.randf() < 0.3 else 1.0)


## A body and two scalloped wings along x (the shader beats them).
static func _mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	var col := Color.BLACK
	var n := Vector3.UP
	var i := b.add(Vector3(0.0, 0.0, 0.25), n, col)
	b.add(Vector3(0.08, 0.0, -0.2), n, col)
	b.add(Vector3(-0.08, 0.0, -0.2), n, col)
	b.tri_raw(i, i + 1, i + 2)
	for s: float in [-1.0, 1.0]:
		var root_f := b.add(Vector3(s * 0.07, 0.0, 0.12), n, col)
		var root_b := b.add(Vector3(s * 0.07, 0.0, -0.15), n, col)
		var tip := b.add(Vector3(s * 0.75, 0.05, 0.05), n, col)
		var mid := b.add(Vector3(s * 0.42, 0.0, -0.14), n, col)
		var out := b.add(Vector3(s * 0.66, 0.02, -0.12), n, col)
		b.tri_raw(root_f, tip, mid)
		b.tri_raw(root_f, mid, root_b)
		b.tri_raw(mid, tip, out)
	return b.commit()
