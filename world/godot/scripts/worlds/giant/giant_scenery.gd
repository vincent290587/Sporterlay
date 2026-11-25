class_name GiantScenery
extends RefCounted
## Puts the giant flooded world together: islands and a mountain skirt, a
## water plane, a wooden boardwalk, giant procedural trees (10x normal),
## and reeds along the shores.

const TOON := preload("res://shaders/toon_vcol.gdshader")
const GRASS := preload("res://shaders/grass.gdshader")
const WATER := preload("res://shaders/water.gdshader")

const TREE_NEAR := 650.0         # full TreeGen models out to here
const TREE_MID := 1800.0         # lighter TreeGen models out to here
const TREE_FAR := 3600.0         # far crowns out to here, blobs beyond
const TREE_VISIBLE := 6200.0
const TREE_CHUNK := 200.0
const REEDS_CHUNK := 32.0
const REEDS_VISIBLE := 350.0

const WOOD := Color(0.52, 0.38, 0.25)
const RUST := Color(0.64, 0.40, 0.24)

static func build(parent: Node3D, land: GiantLand, route: Route, seed: int) -> void:
	for c in [["trees", 1.0], ["reeds", 0.65], ["props", 0.5]]:
		Lod.category(c[0], c[1])
	var toon := ShaderMaterial.new()
	toon.shader = TOON
	_mesh(parent, land.build_mesh(), toon, true)
	_water(parent)
	var bridge := PackedByteArray()
	bridge.resize(route.count())
	bridge.fill(1)
	_mesh(parent, Roads.ribbon(route, bridge), toon, true)
	_railings(parent, route, toon)

	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = GRASS
	Lod.add_param("reeds", grass_mat, "fade_start", 120.0)
	Lod.add_param("reeds", grass_mat, "fade_end", 190.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	_giant_trees(parent, land, route, rng, toon)
	_reeds(parent, land, route, rng, grass_mat)
	_piers(parent, land, route, rng, toon)


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _water(parent: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GiantLand.FAR * 2.0, GiantLand.FAR * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = GiantLand.WATER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## A box from `a` to `c`, `w` wide and `h` tall.
static func _beam(b: MeshBuilder, a: Vector3, c: Vector3, w: float, h: float, col: Color) -> void:
	var dir := (c - a).normalized()
	var right := dir.cross(Vector3.UP)
	if right.length() < 0.1:
		right = Vector3.RIGHT
	right = right.normalized() * w * 0.5
	var up := right.cross(dir).normalized() * h * 0.5
	if up.y < 0.0:
		up = -up
	var corners := [-right - up, right - up, right + up, -right + up]
	var faces := [[0, 1], [1, 2], [2, 3], [3, 0]]
	for f in faces:
		var o0: Vector3 = corners[f[0]]
		var o1: Vector3 = corners[f[1]]
		var nrm := (o0 + o1).normalized()
		b.quad(b.add(a + o0, nrm, col), b.add(a + o1, nrm, col), b.add(c + o1, nrm, col), b.add(c + o0, nrm, col))
	for end in [[a, -dir], [c, dir]]:
		var p: Vector3 = end[0]
		var nrm: Vector3 = end[1]
		var ids := []
		for o in corners:
			ids.append(b.add(p + o, nrm, col))
		b.quad(ids[0], ids[1], ids[2], ids[3])


## Boardwalk posts where the deck is over water, and railings along both sides.
static func _railings(parent: Node3D, route: Route, mat: Material) -> void:
	var b := MeshBuilder.new()
	var n := route.count()
	var hw := Route.HALF_WIDTH
	for m in n:
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		var q := route.points[(m + 1) % n]
		var tq := route.tangent_index((m + 1) % n)
		var rq := Vector3(-tq.z, 0.0, tq.x)
		for sgn: float in [-1.0, 1.0]:
			var off := right * (hw + 0.05) * sgn
			var offq := rq * (hw + 0.05) * sgn
			_beam(b, p + off + Vector3(0.0, 1.0, 0.0), q + offq + Vector3(0.0, 1.0, 0.0), 0.12, 0.12, WOOD)
			if m % 4 == 0:
				_beam(b, p + off, p + off + Vector3(0.0, 1.08, 0.0), 0.14, 0.14, WOOD)
	_mesh(parent, b.commit(), mat, false)


static func _piers(parent: Node3D, land: GiantLand, route: Route, rng: RandomNumberGenerator, mat: Material) -> void:
	var b := MeshBuilder.new()
	var n := route.count()
	var hw := Route.HALF_WIDTH
	for m in range(0, n, 8):
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		for sgn: float in [-1.0, 1.0]:
			var off := right * (hw + 0.15) * sgn
			var foot := maxf(land.natural(p.x + off.x, p.z + off.z), GiantLand.WATER) - 0.4
			_beam(b, p + off + Vector3(0.0, -0.35, 0.0),
				Vector3(p.x + off.x, foot, p.z + off.z), 0.38, 0.58, WOOD.darkened(0.2 + rng.randf() * 0.15))
	_mesh(parent, b.commit(), mat, false)


## Giant trees: the same TreeGen models at 10x scale, only on islands.
static func _giant_trees(parent: Node3D, land: GiantLand, route: Route,
		rng: RandomNumberGenerator, mat: Material) -> void:
	TreeGen.reset()
	var broad := Instancer.new(TREE_CHUNK)
	var pine := Instancer.new(TREE_CHUNK)
	var forest := FastNoiseLite.new()
	forest.seed = seed_for(rng)
	forest.frequency = 0.006
	forest.fractal_octaves = 3
	var count := 3200
	for _k in count:
		var px := rng.randf_range(-GiantLand.HALF + 60.0, GiantLand.HALF - 60.0)
		var pz := rng.randf_range(-GiantLand.HALF + 60.0, GiantLand.HALF - 60.0)
		var h := land.natural(px, pz)
		if h < GiantLand.WATER + 1.4 or h > 300.0:
			continue
		if _road_distance(route, px, pz) < Route.HALF_WIDTH + 14.0:
			continue
		var dense := smoothstep(0.12, 0.45, forest.get_noise_2d(px, pz))
		if rng.randf() > dense * 0.65 + 0.012:
			continue
		var tint := Color(1.0, 1.0, 1.0).lerp(Color(1.12, 1.08, 0.78), rng.randf() * 0.55)
		tint = tint.darkened(rng.randf() * 0.12)
		var s := rng.randf_range(0.75, 1.35) * 10.0
		var pos := Vector3(px, h, pz)
		if rng.randf() < 0.35:
			pine.put(pos, rng.randf() * TAU, s, s * rng.randf_range(0.85, 1.25), tint)
		else:
			broad.put(pos, rng.randf() * TAU, s, s * rng.randf_range(0.9, 1.15), tint)
	var bl := TreeGen.lods(rng, func(r: RandomNumberGenerator, lod: int) -> ArrayMesh:
		return TreeGen.branching(r, TreeGen.BROADLEAF, Meshes.LEAF_DARK, Meshes.LEAF_LIGHT, TreeGen.BARK, false, lod))
	var cf := TreeGen.lods(rng, func(r: RandomNumberGenerator, lod: int) -> ArrayMesh:
		return TreeGen.spruce(r, 13.0, 3.2, 8, Meshes.NEEDLE_DARK, Meshes.NEEDLE_LIGHT, lod))
	var blob: ShaderMaterial = TreeGen.materials(3)[0]
	var n := broad.build_tiers(parent, [[bl[0], null, 0.0, TREE_NEAR, true, TreeGen.materials(0), 200.0],
		[bl[1], null, TREE_NEAR, TREE_MID, false, TreeGen.materials(1), 300.0],
		[bl[2], null, TREE_MID, TREE_FAR, false, TreeGen.materials(2), 500.0],
		[Meshes.broadleaf_far(rng), blob, TREE_FAR, TREE_VISIBLE, false, [blob], 700.0]], "trees")
	n += pine.build_tiers(parent, [[cf[0], null, 0.0, TREE_NEAR, true, TreeGen.materials(0), 200.0],
		[cf[1], null, TREE_NEAR, TREE_MID, false, TreeGen.materials(1), 300.0],
		[cf[2], null, TREE_MID, TREE_FAR, false, TreeGen.materials(2), 500.0],
		[Meshes.conifer_far(13.0, 3.2), blob, TREE_FAR, TREE_VISIBLE, false, [blob], 700.0]], "trees")
	print("  giant trees: ", n)


## Reeds and cattails along the island shores.
static func _reeds(parent: Node3D, land: GiantLand, route: Route,
		rng: RandomNumberGenerator, mat: Material) -> void:
	var inst := Instancer.new(REEDS_CHUNK)
	for _k in 6000:
		var px := rng.randf_range(-GiantLand.HALF + 40.0, GiantLand.HALF - 40.0)
		var pz := rng.randf_range(-GiantLand.HALF + 40.0, GiantLand.HALF - 40.0)
		var h := land.natural(px, pz)
		if h < GiantLand.WATER + 0.25 or h > GiantLand.WATER + 2.6:
			continue
		if _road_distance(route, px, pz) < Route.HALF_WIDTH + 3.0:
			continue
		var tint := Color(0.58, 0.62, 0.30).lerp(Color(0.72, 0.60, 0.32), rng.randf())
		inst.put(Vector3(px, h, pz), rng.randf() * TAU, rng.randf_range(0.8, 1.35), rng.randf_range(1.2, 2.1), tint)
	print("  reeds: ", inst.build(parent, Meshes.reeds_leaning(rng), mat, REEDS_VISIBLE, false, 0.0, "reeds"))


static func _road_distance(route: Route, x: float, z: float) -> float:
	var best := INF
	for m in route.count():
		var p: Vector3 = route.points[m]
		var dx: float = p.x - x
		var dz: float = p.z - z
		var d := dx * dx + dz * dz
		if d < best:
			best = d
	return sqrt(best)


static func seed_for(rng: RandomNumberGenerator) -> int:
	return rng.randi()
