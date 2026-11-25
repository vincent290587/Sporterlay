class_name Scenery
extends RefCounted
## Puts the world together: ground, road, lake, grass, trees and rocks.

const TOON := preload("res://shaders/toon_vcol.gdshader")
const GRASS := preload("res://shaders/grass.gdshader")
const WATER := preload("res://shaders/water.gdshader")

const GRASS_PER_SAMPLE := 120     # clumps per 2 m of road, both sides
const GRASS_REACH := 110.0        # m from the road
const GRASS_CHUNK := 32.0
const GRASS_VISIBLE := 125.0
const TREE_CHUNK := 200.0
const TREE_VISIBLE := 1500.0


## Instance data for one chunk: 12 floats of transform + 4 of colour each.
class Chunk:
	var origin := Vector3.ZERO
	var data := PackedFloat32Array()


static func build(parent: Node3D, terrain: Terrain, route: Route, seed: int) -> void:
	var toon := ShaderMaterial.new()
	toon.shader = TOON
	_mesh(parent, terrain.build_mesh(), toon, true)
	_mesh(parent, _road(route), toon, false)
	_water(parent)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_grass(parent, terrain, route, rng)
	_trees(parent, terrain, rng, toon)
	_rocks(parent, terrain, rng, toon)


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _road(route: Route) -> ArrayMesh:
	var hw := Route.HALF_WIDTH
	var cols := [-hw, -hw * 0.45, 0.0, hw * 0.45, hw]
	var edge := Color(0.66, 0.56, 0.40)
	var track := Color(0.74, 0.64, 0.47)
	var centre := Color(0.80, 0.71, 0.53)
	var tints := [edge, track, centre, track, edge]
	var b := MeshBuilder.new()
	var n := route.count()
	for m in n:
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		for c in cols.size():
			var off: float = cols[c]
			b.add(p + right * off + Vector3(0.0, 0.02 - 0.03 * absf(off) / hw, 0.0), Vector3.UP, tints[c])
	var w := cols.size()
	for m in n:
		var a := m * w
		var z := ((m + 1) % n) * w
		for c in w - 1:
			b.quad(a + c, a + c + 1, z + c + 1, z + c)
	return b.commit()


static func _water(parent: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(Terrain.HALF * 2.0, Terrain.HALF * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = Terrain.WATER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _put(chunks: Dictionary, size: float, pos: Vector3, yaw: float, sxz: float, sy: float, col: Color) -> void:
	var key := Vector2i(floori(pos.x / size), floori(pos.z / size))
	var ch: Chunk = chunks.get(key)
	if ch == null:
		ch = Chunk.new()
		ch.origin = Vector3((key.x + 0.5) * size, 0.0, (key.y + 0.5) * size)
		chunks[key] = ch
	var c := cos(yaw)
	var s := sin(yaw)
	var o := pos - ch.origin
	ch.data.append_array(PackedFloat32Array([
		c * sxz, 0.0, s * sxz, o.x,
		0.0, sy, 0.0, o.y,
		-s * sxz, 0.0, c * sxz, o.z,
		col.r, col.g, col.b, col.a]))


static func _instances(parent: Node3D, mesh: Mesh, mat: Material, chunks: Dictionary, visible: float, shadows: bool) -> int:
	var total := 0
	for key in chunks:
		var ch: Chunk = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = ch.data.size() / 16
		mm.buffer = ch.data
		total += mm.instance_count
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.position = ch.origin
		mi.visibility_range_end = visible
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	return total


## Grass along the road, densest at its edges.
static func _grass(parent: Node3D, terrain: Terrain, route: Route, rng: RandomNumberGenerator) -> void:
	var chunks := {}
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
			if h < Terrain.WATER + 0.3 or h > 250.0:
				continue
			var ny := terrain.normal_at(pos.x, pos.z).y
			if ny < 0.78:
				continue
			pos.y = h
			var col := terrain.color_at(pos.x, pos.z, h, ny, 1e9)
			_put(chunks, GRASS_CHUNK, pos, rng.randf() * TAU, rng.randf_range(0.8, 1.3), rng.randf_range(0.6, 1.1), col)
	var mat := ShaderMaterial.new()
	mat.shader = GRASS
	var mesh := Meshes.grass_clump(rng)
	print("grass clumps: ", _instances(parent, mesh, mat, chunks, GRASS_VISIBLE, false))


## Trees in clustered woods, with a few loners in the meadows.
static func _trees(parent: Node3D, terrain: Terrain, rng: RandomNumberGenerator, mat: Material) -> void:
	var forest := FastNoiseLite.new()
	forest.seed = rng.randi()
	forest.frequency = 0.0035
	forest.fractal_octaves = 3
	var broad := {}
	var pine := {}
	var cell := 8.0
	var x := -Terrain.HALF
	while x < Terrain.HALF:
		var z := -Terrain.HALF
		while z < Terrain.HALF:
			var px := x + rng.randf() * cell
			var pz := z + rng.randf() * cell
			z += cell
			var dense := smoothstep(0.12, 0.42, forest.get_noise_2d(px, pz))
			if rng.randf() > dense * 0.55 + 0.004:
				continue
			if terrain.road_distance_at(px, pz) < Route.HALF_WIDTH + 5.0:
				continue
			var h := terrain.height_at(px, pz)
			if h < Terrain.WATER + 1.0 or h > 330.0:
				continue
			if terrain.normal_at(px, pz).y < 0.8:
				continue
			var tint := Color(1.0, 1.0, 1.0).lerp(Color(1.15, 1.1, 0.8), rng.randf() * 0.6).darkened(rng.randf() * 0.15)
			var s := rng.randf_range(0.7, 1.35)
			var pos := Vector3(px, h, pz)
			if rng.randf() < 0.25 + smoothstep(30.0, 150.0, h) * 0.6:
				_put(pine, TREE_CHUNK, pos, rng.randf() * TAU, s, s * rng.randf_range(0.9, 1.25), tint)
			else:
				_put(broad, TREE_CHUNK, pos, rng.randf() * TAU, s, s * rng.randf_range(0.85, 1.1), tint)
		x += cell
	var n := _instances(parent, Meshes.broadleaf(rng), mat, broad, TREE_VISIBLE, true)
	n += _instances(parent, Meshes.conifer(rng), mat, pine, TREE_VISIBLE, true)
	print("trees: ", n)


static func _rocks(parent: Node3D, terrain: Terrain, rng: RandomNumberGenerator, mat: Material) -> void:
	var chunks := {}
	for _k in 2500:
		var px := rng.randf_range(-Terrain.HALF, Terrain.HALF)
		var pz := rng.randf_range(-Terrain.HALF, Terrain.HALF)
		if terrain.road_distance_at(px, pz) < Route.HALF_WIDTH + 1.5:
			continue
		var h := terrain.height_at(px, pz)
		if h < Terrain.WATER - 1.0:
			continue
		var big := rng.randf() < 0.08
		var s := rng.randf_range(2.5, 7.0) if big else rng.randf_range(0.4, 1.6)
		_put(chunks, TREE_CHUNK, Vector3(px, h - s * 0.15, pz), rng.randf() * TAU, s, s * rng.randf_range(0.7, 1.1),
			Color(1, 1, 1).darkened(rng.randf() * 0.2))
	print("rocks: ", _instances(parent, Meshes.rock(rng), mat, chunks, TREE_VISIBLE, true))
