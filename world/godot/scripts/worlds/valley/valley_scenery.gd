class_name ValleyScenery
extends RefCounted
## Puts the world together: ground, road, lake, grass, trees and rocks.

const TOON := preload("res://shaders/toon_vcol.gdshader")
const GRASS := preload("res://shaders/grass.gdshader")
const WATER := preload("res://shaders/water.gdshader")

const GRASS_PER_SAMPLE := 210     # clumps per 2 m of road, both sides
const GRASS_REACH := 200.0        # m from the road
const GRASS_CHUNK := 32.0
const GRASS_VISIBLE := 210.0
const TREE_CHUNK := 200.0
const TREE_VISIBLE := 1500.0
const TREE_NEAR := 250.0         # full TreeGen models out to here
const TREE_MID := 600.0          # lighter ones out to here
const TREE_FAR := 1100.0         # far crowns out to here, blobs beyond


static func build(parent: Node3D, terrain: ValleyTerrain, route: Route, seed: int) -> void:
	for c in [["trees", 1.0], ["grass", 0.9], ["boulders", 0.4]]:
		Lod.category(c[0], c[1])
	var toon := ShaderMaterial.new()
	toon.shader = TOON
	_mesh(parent, terrain.build_mesh(), toon, true)
	_mesh(parent, Roads.ribbon(route), toon, false)
	_water(parent)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_grass(parent, terrain, route, rng)
	var tree_rng := RandomNumberGenerator.new()   # own generator: grass changes don't move the trees
	tree_rng.seed = seed + 1
	_trees(parent, terrain, tree_rng, toon)
	_rocks(parent, terrain, rng, toon)


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _water(parent: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(ValleyTerrain.HALF * 2.0, ValleyTerrain.HALF * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = ValleyTerrain.WATER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Grass along the road, densest at its edges.
static func _grass(parent: Node3D, terrain: ValleyTerrain, route: Route, rng: RandomNumberGenerator) -> void:
	var grass := Instancer.new(GRASS_CHUNK)
	var hw := Route.HALF_WIDTH
	for m in route.count():
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		for _k in GRASS_PER_SAMPLE:
			var u := rng.randf_range(-1.0, 1.0)
			var side := hw + 0.6 + u * u * GRASS_REACH
			var pos := p + t * rng.randf_range(-1.0, 1.0) + right * side * signf(u)
			if terrain.road_distance_at(pos.x, pos.z) < hw + 0.6:
				continue
			var h := terrain.height_at(pos.x, pos.z)
			if h < ValleyTerrain.WATER + 0.3 or h > 250.0:
				continue
			var ny := terrain.normal_at(pos.x, pos.z).y
			if ny < 0.78:
				continue
			pos.y = h
			var col := terrain.color_at(pos.x, pos.z, h, ny, 1e9)
			grass.put(pos, rng.randf() * TAU, rng.randf_range(0.8, 1.3), rng.randf_range(0.6, 1.1), col)
	var mat := ShaderMaterial.new()
	mat.shader = GRASS
	var mesh := Meshes.grass_clump(rng)
	print("grass clumps: ", grass.build(parent, mesh, mat, GRASS_VISIBLE, false, 0.0, "grass"))
	Lod.add_param("grass", mat, "fade_start", 130.0)
	Lod.add_param("grass", mat, "fade_end", 190.0)


## Trees in clustered woods, with a few loners in the meadows.
static func _trees(parent: Node3D, terrain: ValleyTerrain, rng: RandomNumberGenerator, mat: Material) -> void:
	var forest := FastNoiseLite.new()
	forest.seed = rng.randi()
	forest.frequency = 0.0035
	forest.fractal_octaves = 3
	var broad := Instancer.new(100.0)   # trees pick their own tier: small chunks waste little
	var pine := Instancer.new(100.0)
	var cell := 8.0
	var x := -ValleyTerrain.HALF
	while x < ValleyTerrain.HALF:
		var z := -ValleyTerrain.HALF
		while z < ValleyTerrain.HALF:
			var px := x + rng.randf() * cell
			var pz := z + rng.randf() * cell
			z += cell
			var dense := smoothstep(0.12, 0.42, forest.get_noise_2d(px, pz))
			if rng.randf() > dense * 0.55 + 0.004:
				continue
			if terrain.road_distance_at(px, pz) < Route.HALF_WIDTH + 5.0:
				continue
			var h := terrain.height_at(px, pz)
			if h < ValleyTerrain.WATER + 1.0 or h > 330.0:
				continue
			if terrain.normal_at(px, pz).y < 0.8:
				continue
			var tint := Color(1.0, 1.0, 1.0).lerp(Color(1.15, 1.1, 0.8), rng.randf() * 0.6).darkened(rng.randf() * 0.15)
			var s := rng.randf_range(0.7, 1.35)
			var pos := Vector3(px, h, pz)
			if rng.randf() < 0.25 + smoothstep(30.0, 150.0, h) * 0.6:
				pine.put(pos, rng.randf() * TAU, s, s * rng.randf_range(0.9, 1.25), tint)
			else:
				broad.put(pos, rng.randf() * TAU, s, s * rng.randf_range(0.85, 1.1), tint)
		x += cell
	var bl := TreeGen.lods(rng, func(r: RandomNumberGenerator, lod: int) -> ArrayMesh:
		return TreeGen.branching(r, TreeGen.BROADLEAF, Meshes.LEAF_DARK, Meshes.LEAF_LIGHT, TreeGen.BARK, false, lod))
	var cf := TreeGen.lods(rng, func(r: RandomNumberGenerator, lod: int) -> ArrayMesh:
		return TreeGen.conifer(r, 12.6, 3.4, 7, Meshes.NEEDLE_DARK, Meshes.NEEDLE_LIGHT, lod))
	var blob: ShaderMaterial = TreeGen.materials(3)[0]
	var n := broad.build_tiers(parent, [[bl[0], null, 0.0, TREE_NEAR, true, TreeGen.materials(0), 100.0],
		[bl[1], null, TREE_NEAR, TREE_MID, false, TreeGen.materials(1), 150.0], [bl[2], null, TREE_MID, TREE_FAR, false, TreeGen.materials(2), 300.0],
		[Meshes.broadleaf_far(rng), blob, TREE_FAR, TREE_VISIBLE, false, [blob], 500.0]], "trees")
	n += pine.build_tiers(parent, [[cf[0], null, 0.0, TREE_NEAR, true, TreeGen.materials(0), 100.0],
		[cf[1], null, TREE_NEAR, TREE_MID, false, TreeGen.materials(1), 150.0], [cf[2], null, TREE_MID, TREE_FAR, false, TreeGen.materials(2), 300.0],
		[Meshes.conifer_far(12.6, 3.4), blob, TREE_FAR, TREE_VISIBLE, false, [blob], 500.0]], "trees")
	print("trees: ", n)


static func _rocks(parent: Node3D, terrain: ValleyTerrain, rng: RandomNumberGenerator, mat: Material) -> void:
	var rocks := Instancer.new(TREE_CHUNK)
	for _k in 2500:
		var px := rng.randf_range(-ValleyTerrain.HALF, ValleyTerrain.HALF)
		var pz := rng.randf_range(-ValleyTerrain.HALF, ValleyTerrain.HALF)
		if terrain.road_distance_at(px, pz) < Route.HALF_WIDTH + 1.5:
			continue
		var h := terrain.height_at(px, pz)
		if h < ValleyTerrain.WATER - 1.0:
			continue
		var big := rng.randf() < 0.08
		var s := rng.randf_range(2.5, 7.0) if big else rng.randf_range(0.4, 1.6)
		rocks.put(Vector3(px, h - s * 0.15, pz), rng.randf() * TAU, s, s * rng.randf_range(0.7, 1.1),
			Color(1, 1, 1).darkened(rng.randf() * 0.2))
	print("rocks: ", rocks.build(parent, Meshes.rock(rng), mat, TREE_VISIBLE, true, 0.0, "boulders"))
