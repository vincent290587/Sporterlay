class_name CanyonScenery
extends RefCounted
## Puts the canyon country together: ground (canyon_ground.gdshader: strata, cracks,
## ripples, pebbles), road, rock formations (CanyonRocks), junipers, sagebrush, dead
## trees, rocks fallen from the cliffs, and desert grass everywhere: bunch grass, dry
## tufts, grey-green clumps and little yellow flowers, in patches.

const TOON := preload("res://shaders/toon_vcol.gdshader")

const CHUNK := 200.0
const VISIBLE := 1500.0
const NEAR := 220.0
const MID := 520.0
const SMALL_CHUNK := 48.0
const TUFT_VISIBLE := 200.0

const JUNIPER := [Color(0.22, 0.29, 0.21), Color(0.38, 0.44, 0.30)]
const ROAD := [Color(0.68, 0.45, 0.31), Color(0.75, 0.54, 0.38), Color(0.79, 0.59, 0.43)]


static func build(parent: Node3D, land: CanyonLand, route: Route, seed: int, blocked := Callable()) -> void:
	for c in [["trees", 1.0], ["grass", 0.5], ["boulders", 0.6], ["props", 0.4]]:
		Lod.category(c[0], c[1])
	var toon := ShaderMaterial.new()
	toon.shader = TOON
	var ground := ShaderMaterial.new()
	ground.shader = load("res://shaders/canyon_ground.gdshader")
	_mesh(parent, land.build_mesh(), ground, true)
	_mesh(parent, Roads.ribbon(route, PackedByteArray(), ROAD), toon, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	CanyonRocks.build(parent, land, route, seed, ground, blocked)
	_plants(parent, land, rng, toon, blocked)
	_rocks(parent, land, rng, toon, blocked)
	_grass(parent, land, route, rng, blocked)


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _is_blocked(blocked: Callable, x: float, z: float) -> bool:
	return blocked.is_valid() and blocked.call(x, z)


## Junipers, sagebrush and dead trees on flat-ish ground, in loose patches; more on
## the mesa tops and benches and along the canyon floor, few on open sand.
static func _plants(parent: Node3D, land: CanyonLand, rng: RandomNumberGenerator, mat: Material, blocked: Callable) -> void:
	var patch := FastNoiseLite.new()
	patch.seed = rng.randi()
	patch.frequency = 0.006
	patch.fractal_octaves = 2
	var junipers: Array[Instancer] = [Instancer.new(CHUNK), Instancer.new(CHUNK), Instancer.new(CHUNK)]
	var sage := Instancer.new(CHUNK)
	var dead: MegaKit.Mix = MegaKit.mix(CHUNK, ["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5"], MegaKit.SOLID) if MegaKit.available() else null
	var cell := 9.0
	var lim := CanyonLand.HALF - 20.0
	var x := -lim
	while x < lim:
		var z := -lim
		while z < lim:
			var px := x + rng.randf() * cell
			var pz := z + rng.randf() * cell
			z += cell
			var p := smoothstep(-0.1, 0.5, patch.get_noise_2d(px, pz)) * 0.28 + 0.015
			if rng.randf() > p:
				continue
			if land.road_distance_at(px, pz) < Route.HALF_WIDTH + 3.0 or _is_blocked(blocked, px, pz):
				continue
			var ny := land.normal_at(px, pz).y
			if ny < 0.82:
				continue
			var pos := Vector3(px, land.height_at(px, pz) - 0.1, pz)
			var r := rng.randf()
			var tint := Color(1, 1, 1).darkened(rng.randf() * 0.15)
			if r < 0.55:
				var s := rng.randf_range(0.6, 1.2)
				sage.put(pos, rng.randf() * TAU, s * 1.3, s * 0.8, Color(0.62, 0.66, 0.52).darkened(rng.randf() * 0.2))
			elif r < 0.93:
				var s := rng.randf_range(0.35, 0.7)
				junipers[rng.randi() % 3].put(pos, rng.randf() * TAU, s, s * rng.randf_range(0.8, 1.1), tint)
			elif dead != null:
				var s := rng.randf_range(0.5, 0.9)
				dead.pick(rng).put(pos, rng.randf() * TAU, s, s, Color(1.0, 0.85, 0.75))
		x += cell
	var n := 0
	for inst in junipers:
		var models := TreeGen.lods(rng, func(r: RandomNumberGenerator, lod: int) -> ArrayMesh:
			return TreeGen.branching(r, TreeGen.BROADLEAF, JUNIPER[0], JUNIPER[1], TreeGen.BARK, false, lod))
		n += inst.build_tiers(parent, [
			[models[0], null, 0.0, NEAR, true, TreeGen.materials(0), 100.0],
			[models[1], null, NEAR, MID, false, TreeGen.materials(1), 150.0],
			[models[2], null, MID, VISIBLE, false, TreeGen.materials(2), 300.0]], "trees")
	var ns := sage.build(parent, Meshes.bush(rng), mat, MID, true, 0.0, "props")
	var nd := dead.build(parent, VISIBLE, true, "trees") if dead != null else 0
	print("  junipers: %d, sagebrush: %d, dead trees: %d" % [n, ns, nd])


## Rocks: boulders fallen at the foot of the cliffs, and some scattered everywhere.
static func _rocks(parent: Node3D, land: CanyonLand, rng: RandomNumberGenerator, mat: Material, blocked: Callable) -> void:
	var rocks := Instancer.new(CHUNK)
	var mk: MegaKit.Mix = MegaKit.mix(CHUNK, ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"], MegaKit.SOLID) if MegaKit.available() else null
	var placed := 0
	var tries := 0
	while placed < 9000 and tries < 120000:
		tries += 1
		var px := rng.randf_range(-CanyonLand.HALF, CanyonLand.HALF)
		var pz := rng.randf_range(-CanyonLand.HALF, CanyonLand.HALF)
		var ny := land.normal_at(px, pz).y
		# at the foot of a cliff: flat here, steep a little way off
		var foot := ny > 0.8 and (land.normal_at(px + 9.0, pz).y < 0.6 or land.normal_at(px - 9.0, pz).y < 0.6 \
			or land.normal_at(px, pz + 9.0).y < 0.6 or land.normal_at(px, pz - 9.0).y < 0.6)
		if not foot and rng.randf() > 0.12:
			continue
		var big := rng.randf() < (0.3 if foot else 0.05)
		var s := rng.randf_range(2.0, 6.0) if big else rng.randf_range(0.4, 1.5)
		if mk != null:
			s *= 0.6
		if land.road_distance_at(px, pz) < Route.HALF_WIDTH + 1.0 + s * (1.4 if mk != null else 0.7) or _is_blocked(blocked, px, pz):
			continue
		var h := land.height_at(px, pz)
		var tint := Color(1.0, 0.72, 0.58).darkened(rng.randf() * 0.25)
		(mk.pick(rng) if mk != null else rocks).put(Vector3(px, h - s * 0.15, pz), rng.randf() * TAU, s, s * rng.randf_range(0.6, 1.0), tint)
		placed += 1
	var n := rocks.build(parent, Meshes.rock(rng), mat, VISIBLE, true, 0.0, "boulders")
	if mk != null:
		n += mk.build(parent, VISIBLE, true, "boulders")
	print("  rocks: %d" % n)


## Desert grass, thick by the road and thinning out to ~180 m, in patches: dry
## tufts, tall bunch grass, grey-green clumps and yellow flowers, plus scattered
## low shrubs. None on steep rock.
static func _grass(parent: Node3D, land: CanyonLand, route: Route, rng: RandomNumberGenerator, blocked: Callable) -> void:
	var patch := FastNoiseLite.new()
	patch.seed = rng.randi()
	patch.frequency = 0.02
	patch.fractal_octaves = 2
	var kinds: Array[Instancer] = [Instancer.new(SMALL_CHUNK), Instancer.new(SMALL_CHUNK), Instancer.new(SMALL_CHUNK), Instancer.new(SMALL_CHUNK)]
	var shrubs := Instancer.new(SMALL_CHUNK)
	var hw := Route.HALF_WIDTH
	for m in route.count():
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		for _k in 26:
			var u := rng.randf_range(-1.0, 1.0)
			var pos := p + t * rng.randf_range(-1.0, 1.0) + right * (hw + 0.6 + u * u * 180.0) * signf(u)
			var n := patch.get_noise_2d(pos.x, pos.z)
			if rng.randf() > smoothstep(-0.45, 0.35, n) * 0.85 + 0.1:
				continue
			if land.road_distance_at(pos.x, pos.z) < hw + 0.5 or _is_blocked(blocked, pos.x, pos.z):
				continue
			if land.normal_at(pos.x, pos.z).y < 0.84:
				continue
			pos.y = land.height_at(pos.x, pos.z) - 0.03
			var r := rng.randf()
			var yaw := rng.randf() * TAU
			if r < 0.4:
				kinds[0].put(pos, yaw, rng.randf_range(0.8, 1.5), rng.randf_range(0.6, 1.2), Color(0.88, 0.75, 0.48).darkened(rng.randf() * 0.2))
			elif r < 0.65:
				kinds[1].put(pos, yaw, rng.randf_range(0.7, 1.1), rng.randf_range(0.5, 0.85), Color(0.92, 0.80, 0.52).darkened(rng.randf() * 0.15))
			elif r < 0.88:
				kinds[2].put(pos, yaw, rng.randf_range(0.8, 1.3), rng.randf_range(0.7, 1.1), Color(0.62, 0.66, 0.50).darkened(rng.randf() * 0.2))
			elif r < 0.96:
				kinds[3].put(pos, yaw, rng.randf_range(0.7, 1.1), rng.randf_range(0.6, 0.9), Color.WHITE)
			else:
				var sc := rng.randf_range(0.35, 0.7)
				shrubs.put(pos, yaw, sc * 1.4, sc, Color(0.42, 0.48, 0.32).darkened(rng.randf() * 0.2))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	var meshes := [Meshes.grass(rng, Meshes.GRASS_SHORT), Meshes.grass(rng, Meshes.GRASS_TALL), Meshes.grass(rng, Meshes.GRASS_AVERAGE),
		Meshes.flowers(rng, Color(1.0, 0.82, 0.18))]
	var counts := []
	for i in 4:
		counts.append(kinds[i].build(parent, meshes[i], mat, TUFT_VISIBLE, false, 0.0, "grass"))
	var toon := ShaderMaterial.new()
	toon.shader = TOON
	counts.append(shrubs.build(parent, Meshes.bush(rng), toon, MID, true, 0.0, "props"))
	print("  grass: %d dry tufts, %d bunch grass, %d green clumps, %d flowers, %d shrubs" % counts)
	Lod.add_param("grass", mat, "fade_start", TUFT_VISIBLE * 0.65)
	Lod.add_param("grass", mat, "fade_end", TUFT_VISIBLE * 0.95)
