class_name TransScenery
extends RefCounted
## Puts Transylvania together: ground, road, black pools, the forest (spruce higher
## up, late-autumn beech lower down, dead and twisted trees near the castle and in the
## misty hollows), rocks and ferns.

const TOON := preload("res://shaders/toon_vcol.gdshader")
const WATER := preload("res://shaders/water.gdshader")

const TREE_CHUNK := 200.0
const TREE_VISIBLE := 1400.0
const TREE_NEAR := 220.0
const TREE_MID := 520.0
const TREE_FAR := 950.0
const SMALL_CHUNK := 40.0
const FERN_VISIBLE := 120.0

const BEECH := [Color(0.28, 0.15, 0.08), Color(0.44, 0.27, 0.12)]       # rust, late autumn
const BEECH_DARK := [Color(0.20, 0.12, 0.07), Color(0.33, 0.21, 0.10)]
const SPRUCE := [Color(0.07, 0.13, 0.10), Color(0.15, 0.24, 0.16)]
const ROAD := [Color(0.27, 0.24, 0.21), Color(0.33, 0.30, 0.26), Color(0.36, 0.33, 0.29)]   # wet dark ruts

enum { SPRUCE_T, BEECH_T, BEECH_DARK_T, DEAD_T, TWISTED_T }


static func build(parent: Node3D, land: TransLand, route: Route, seed: int, blocked := Callable()) -> void:
	for c in [["trees", 1.0], ["ferns", 0.3], ["boulders", 0.4]]:
		Lod.category(c[0], c[1])
	var toon := ShaderMaterial.new()
	toon.shader = TOON
	_mesh(parent, land.build_mesh(), toon, false)   # its low-poly crests make hard-edged bands in moonlight
	_mesh(parent, Roads.ribbon(route, PackedByteArray(), ROAD), toon, false)
	_water(parent)
	_mist(parent)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	_trees(parent, land, rng, blocked)
	_rocks(parent, land, rng, toon, blocked)
	_ferns(parent, land, route, rng, blocked)


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _water(parent: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(TransLand.HALF * 2.0, TransLand.HALF * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = TransLand.WATER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Mist lying in the hollows, below TransLand.MIST (volumetric: it's drawn out to the
## environment's volumetric fog length, the height fog carries it further).
static func _mist(parent: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mist.gdshader")
	mat.set_shader_parameter("top", TransLand.MIST)
	var v := FogVolume.new()
	v.size = Vector3(TransLand.HALF * 2.0, 160.0, TransLand.HALF * 2.0)
	v.position = Vector3(0.0, TransLand.MIST - 40.0, 0.0)
	v.material = mat
	parent.add_child(v)


static func _is_blocked(blocked: Callable, x: float, z: float) -> bool:
	return blocked.is_valid() and blocked.call(x, z)


## A dense forest with clearings; which species grows depends on height, the mist and
## how near the castle it is.
static func _trees(parent: Node3D, land: TransLand, rng: RandomNumberGenerator, blocked: Callable) -> void:
	var forest := FastNoiseLite.new()
	forest.seed = rng.randi()
	forest.frequency = 0.004
	forest.fractal_octaves = 3
	var mix := FastNoiseLite.new()
	mix.seed = rng.randi()
	mix.frequency = 0.006
	var castle := land.loop[land.castle_i]
	var sets := {}
	var cell := 7.0
	var lim := TransLand.HALF - 20.0
	var x := -lim
	while x < lim:
		var z := -lim
		while z < lim:
			var px := x + rng.randf() * cell
			var pz := z + rng.randf() * cell
			z += cell
			var dense := smoothstep(-0.25, 0.15, forest.get_noise_2d(px, pz))
			if rng.randf() > dense * 0.62 + 0.01:
				continue
			if land.road_distance_at(px, pz) < Route.HALF_WIDTH + 5.0 or _is_blocked(blocked, px, pz):
				continue
			var h := land.height_at(px, pz)
			if h < TransLand.WATER + 0.8:
				continue
			var ny := land.normal_at(px, pz).y
			if ny < 0.62:
				continue
			var near_castle := 1.0 - smoothstep(120.0, 700.0, Vector2(px, pz).distance_to(castle))
			var hollow := 1.0 - smoothstep(TransLand.MIST - 6.0, TransLand.MIST + 8.0, h)
			var kind := SPRUCE_T
			var r := rng.randf()
			if r < 0.10 + near_castle * 0.5 + hollow * 0.35:
				kind = DEAD_T if rng.randf() < 0.65 else TWISTED_T
			else:
				var beech := smoothstep(-0.2, 0.3, mix.get_noise_2d(px, pz)) * (1.0 - smoothstep(10.0, 90.0, h))
				if rng.randf() < beech * 0.85:
					kind = BEECH_T if rng.randf() < 0.6 else BEECH_DARK_T
			var variants := 5 if kind in [DEAD_T, TWISTED_T] and MegaKit.available() else 3
			var key := Vector2i(kind, rng.randi() % variants)
			if not sets.has(key):
				sets[key] = Instancer.new(TREE_CHUNK)
			var s := rng.randf_range(0.75, 1.3)
			var sy := s * rng.randf_range(0.9, 1.2)
			(sets[key] as Instancer).put(Vector3(px, h - 0.1, pz), rng.randf() * TAU, s, sy, Color(1, 1, 1).darkened(rng.randf() * 0.2))
		x += cell
	var n := 0
	var blob: ShaderMaterial = TreeGen.materials(3)[0]
	for key: Vector2i in sets:
		var inst: Instancer = sets[key]
		var models: Array
		var far: Mesh
		match key.x:
			SPRUCE_T:
				models = TreeGen.lods(rng, func(r: RandomNumberGenerator, lod: int) -> ArrayMesh:
					return TreeGen.spruce(r, 17.0, 3.0, 9, SPRUCE[0], SPRUCE[1], lod))
				far = Meshes.conifer_far(17.0, 2.8, SPRUCE[0], SPRUCE[1])
			BEECH_T, BEECH_DARK_T:
				var pal: Array = BEECH if key.x == BEECH_T else BEECH_DARK
				models = TreeGen.lods(rng, func(r: RandomNumberGenerator, lod: int) -> ArrayMesh:
					return TreeGen.branching(r, TreeGen.BROADLEAF, pal[0], pal[1], TreeGen.BARK, false, lod))
				far = Meshes.broadleaf_far(rng, pal[0], pal[1])
			TWISTED_T when MegaKit.available():
				var name := "TwistedTree_%d" % (key.y + 1)
				models = [MegaKit.mesh(name, MegaKit.TREE, 0), MegaKit.mesh(name, MegaKit.TREE, 1), MegaKit.mesh(name, MegaKit.TREE, 2)]
				n += inst.build_tiers(parent, [
					[models[0], null, 0.0, TREE_NEAR, true, MegaKit.materials_of(models[0]), 100.0],
					[models[1], null, TREE_NEAR, TREE_MID, false, MegaKit.materials_of(models[1]), 150.0],
					[models[2], null, TREE_MID, TREE_FAR, false, MegaKit.materials_of(models[2]), 300.0]], "trees")
				continue
			_:
				if MegaKit.available():
					var name := "DeadTree_%d" % (key.y + 1)
					var d0 := MegaKit.mesh(name, MegaKit.SOLID, 0)
					var d1 := MegaKit.mesh(name, MegaKit.SOLID, 1)
					n += inst.build_tiers(parent, [[d0, null, 0.0, TREE_NEAR, true, MegaKit.materials_of(d0), 100.0],
						[d1, null, TREE_NEAR, TREE_MID, false, MegaKit.materials_of(d1), 150.0]], "trees")
				else:
					n += inst.build_tiers(parent, [[TreeGen.dead(rng), null, 0.0, TREE_MID, true, TreeGen.materials(4), 150.0]], "trees")
				continue
		n += inst.build_tiers(parent, [
			[models[0], null, 0.0, TREE_NEAR, true, TreeGen.materials(0), 100.0],
			[models[1], null, TREE_NEAR, TREE_MID, false, TreeGen.materials(1), 150.0],
			[models[2], null, TREE_MID, TREE_FAR, false, TreeGen.materials(2), 300.0],
			[far, blob, TREE_FAR, TREE_VISIBLE, false, [blob], 500.0]], "trees")
	print("  trees: %d" % n)


static func _rocks(parent: Node3D, land: TransLand, rng: RandomNumberGenerator, mat: Material, blocked: Callable) -> void:
	var rocks := Instancer.new(TREE_CHUNK)
	var mk: MegaKit.Mix = MegaKit.mix(TREE_CHUNK, ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"], MegaKit.SOLID) if MegaKit.available() else null
	var castle := land.loop[land.castle_i]
	for _k in 5000:
		var px := rng.randf_range(-TransLand.HALF, TransLand.HALF)
		var pz := rng.randf_range(-TransLand.HALF, TransLand.HALF)
		# more of them on the crag's flanks
		if Vector2(px, pz).distance_to(castle) > 500.0 and rng.randf() < 0.5:
			continue
		var h := land.height_at(px, pz)
		if h < TransLand.WATER - 1.0:
			continue
		var big := rng.randf() < 0.1
		var s := rng.randf_range(2.5, 7.0) if big else rng.randf_range(0.4, 1.6)
		if mk != null:
			s *= 0.6
		# big rocks keep clear of the road by their own size
		if land.road_distance_at(px, pz) < Route.HALF_WIDTH + 1.0 + s * (1.4 if mk != null else 0.7) or _is_blocked(blocked, px, pz):
			continue
		var tint := Color(0.8, 0.8, 0.88).darkened(rng.randf() * 0.25)
		(mk.pick(rng) if mk != null else rocks).put(Vector3(px, h - s * 0.15, pz), rng.randf() * TAU, s, s * rng.randf_range(0.7, 1.1), tint)
	var n := rocks.build(parent, Meshes.rock(rng), mat, TREE_VISIBLE, true, 0.0, "boulders")
	if mk != null:
		n += mk.build(parent, TREE_VISIBLE, true, "boulders")
	print("  rocks: %d" % n)


## Ferns along the road's edges and into the forest, where the torchlight catches them.
static func _ferns(parent: Node3D, land: TransLand, route: Route, rng: RandomNumberGenerator, blocked: Callable) -> void:
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	var ferns: MegaKit.Mix = MegaKit.mix(SMALL_CHUNK, ["Fern_1"], MegaKit.PLANT) if MegaKit.available() \
		else MegaKit.Mix.new(SMALL_CHUNK, [[Meshes.fern(rng), grass_mat]])
	var hw := Route.HALF_WIDTH
	for m in route.count():
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		for _k in 5:
			var u := rng.randf_range(-1.0, 1.0)
			var side := hw + 1.2 + u * u * 40.0
			var pos := p + t * rng.randf_range(-1.0, 1.0) + right * side * signf(u)
			if land.road_distance_at(pos.x, pos.z) < hw + 1.0 or _is_blocked(blocked, pos.x, pos.z):
				continue
			var ny := land.normal_at(pos.x, pos.z).y
			if ny < 0.75:
				continue
			pos.y = land.height_at(pos.x, pos.z) - 0.05
			var s := rng.randf_range(0.7, 1.3)
			ferns.pick(rng).put(pos, rng.randf() * TAU, s, s, Color(0.45, 0.5, 0.42).darkened(rng.randf() * 0.3))
	print("  ferns: %d" % ferns.build(parent, FERN_VISIBLE, false, "ferns"))
