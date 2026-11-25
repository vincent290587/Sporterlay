class_name RiverScenery
extends RefCounted
## Puts the Riverlands together in the order the tools depend on each other:
## trees (RiverEcology) first, because they raise and colour the ground; then the
## ground, cliff skin, road and water meshes; then the understory (it reads the canopy
## and the ledges); then ground cover along the road (grass combed by the wind,
## leaning to water by the shore, reeds, flowers); then bridges and fences.

const TOON := preload("res://shaders/toon_vcol.gdshader")
const GRASS := preload("res://shaders/grass.gdshader")
const WATER := preload("res://shaders/water.gdshader")

const GRASS_CHUNK := 32.0
const GRASS_VISIBLE := 210.0
const GRASS_PER_SAMPLE := 200
const GRASS_REACH := 200.0
const WOOD := Color(0.50, 0.36, 0.24)
const RUST := Color(0.70, 0.42, 0.22)
## MegaKit flowers we use: the purple ones only (by choice: not their yellow or pink
## flowers, clover or grass)
const FLOWERS := ["Plant_7", "Plant_7_Big"]


static func build(parent: Node3D, land: RiverLand, route: Route, bridge: PackedByteArray, cliffs: RiverCliffs, seed: int) -> void:
	var toon := ShaderMaterial.new()
	toon.shader = TOON
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = GRASS
	# what matters most when frame time is short (see Lod): the trees and grass by the road
	for c in [["trees", 1.0], ["grass", 0.9], ["cliffs", 0.7], ["reeds", 0.6], ["bushes", 0.6], ["plants", 0.5],
			["props", 0.45], ["boulders", 0.4], ["ferns", 0.4], ["mounds", 0.3]]:
		Lod.category(c[0], c[1])
	Lod.add_param("grass", grass_mat, "fade_start", 130.0)
	Lod.add_param("grass", grass_mat, "fade_end", 190.0)
	var t := Time.get_ticks_msec()
	var eco := RiverEcology.new(land, seed)
	eco.place_trees(seed)
	eco.build_trees(parent, toon)
	print("  trees built: %d ms" % (Time.get_ticks_msec() - t))
	var ground := ShaderMaterial.new()
	ground.shader = preload("res://shaders/toon_ground.gdshader")
	Lod.add_param("trees", ground, "canopy_near", 500.0)
	Lod.add_param("trees", ground, "canopy_far", 1600.0)
	_mesh(parent, land.build_mesh(), ground, true)
	_far_woods(parent, land, seed)
	print("  ground mesh: %d ms" % (Time.get_ticks_msec() - t))
	cliffs.build_skin_tiles(parent, toon)
	print("  cliff skin: %d ms" % (Time.get_ticks_msec() - t))
	_mesh(parent, Roads.ribbon(route, bridge), toon, true)
	var water := ShaderMaterial.new()
	water.shader = WATER
	_mesh(parent, land.water_mesh(), water, false)
	print("  meshes: %d ms (%d ledges)" % [Time.get_ticks_msec() - t, cliffs.ledges.size()])
	eco.build_understory(parent, toon, grass_mat, cliffs.ledges)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 300
	_reeds(parent, land, rng, grass_mat)
	_grass(parent, land, route, rng, grass_mat)
	var b := MeshBuilder.new()
	_bridges(b, land, route, bridge)
	_fences(b, land, route, bridge, rng)
	_mesh(parent, b.commit(), toon, true)
	print("  small props: %d ms" % (Time.get_ticks_msec() - t))


## Blob trees on the far hills around the basin, where the woods (RiverLand.skirt_woods)
## are, out to FAR_WOODS m from the centre; cheap and shadowless.
const FAR_WOODS := 4500.0


static func _far_woods(parent: Node3D, land: RiverLand, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 400
	var toon := ShaderMaterial.new()
	toon.shader = TOON
	var palettes := [RiverEcology.GREEN, RiverEcology.YELLOW, RiverEcology.ORANGE, RiverEcology.RED]
	var broad: Array[Instancer] = []
	for _p in palettes:
		broad.append(Instancer.new(500.0))
	var pine := Instancer.new(500.0)
	var cell := 14.0
	var x := -FAR_WOODS
	while x < FAR_WOODS:
		var z := -FAR_WOODS
		while z < FAR_WOODS:
			var px := x + rng.randf() * cell
			var pz := z + rng.randf() * cell
			z += cell
			if maxf(absf(px), absf(pz)) < RiverLand.HALF - 40.0 or Vector2(px, pz).length() > FAR_WOODS:
				continue
			var h := land.base(px, pz)
			var e := 6.0
			var ny := Vector3(land.base(px - e, pz) - land.base(px + e, pz), 2.0 * e, land.base(px, pz - e) - land.base(px, pz + e)).normalized().y
			var w := land.skirt_woods(px, pz, h, ny)
			if rng.randf() > w.a * 0.8:
				continue
			var s := rng.randf_range(1.0, 1.5)
			var pos := Vector3(px, h - 0.5, pz)
			if w.g > w.r and w.b > 0.15:   # the conifer colour
				pine.put(pos, rng.randf() * TAU, s, s * rng.randf_range(1.0, 1.3), Color.WHITE)
			else:
				var k := clampi(int((land.woods.get_noise_2d(px * 4.0 + 900.0, pz * 4.0) * 0.5 + 0.5) * 4.0 + rng.randf_range(-0.6, 0.6)), 0, 3)
				broad[k].put(pos, rng.randf() * TAU, s, s, Color.WHITE)
		x += cell
	var n := pine.build(parent, Meshes.conifer_far(12.6, 3.4), toon, FAR_WOODS + 1500.0, false, 0.0, "trees")
	for k in palettes.size():
		var pal: Array = palettes[k]
		n += broad[k].build(parent, Meshes.broadleaf_far(rng, pal[0], pal[1]), toon, FAR_WOODS + 1500.0, false, 0.0, "trees")
	print("  far woods: ", n)


## Yaw that turns local +x (the way leaning blades tip) towards `dir`.
static func _yaw_to(dir: Vector2) -> float:
	return atan2(-dir.y, dir.x)


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Reeds and cattails along the shallow edges of rivers and lakes.
static func _reeds(parent: Node3D, land: RiverLand, rng: RandomNumberGenerator, mat: Material) -> void:
	var reeds := Instancer.new(GRASS_CHUNK)
	var na := RiverLand.NA
	for c in na * na:
		if land.dw[c] > 15.0 or land.dw[c] <= 0.0 and land.wl[c] == RiverLand.DRY:
			continue
		var cx := -RiverLand.HALF + (c % na) * RiverLand.A_STEP
		var cz := -RiverLand.HALF + (c / na) * RiverLand.A_STEP
		if absf(cx) > RiverLand.HALF - 300.0 or absf(cz) > RiverLand.HALF - 300.0:
			continue
		var level := land.wnear[c]
		for _k in maxi(1, int(4.0 * RiverLand.A_STEP * RiverLand.A_STEP / 100.0)):
			var x := cx + rng.randf_range(-0.5, 0.5) * RiverLand.A_STEP
			var z := cz + rng.randf_range(-0.5, 0.5) * RiverLand.A_STEP
			var h := land.height_at(x, z)
			if h < level - 0.7 or h > level + 0.9 or land.road_distance_at(x, z) < Route.HALF_WIDTH + 1.0:
				continue
			var tint := Color(0.56, 0.62, 0.30).lerp(Color(0.72, 0.62, 0.34), rng.randf())
			var to_water := land.water_dir(x, z)
			var yaw := _yaw_to(to_water) + rng.randf_range(-0.5, 0.5) if to_water != Vector2.ZERO else rng.randf() * TAU
			reeds.put(Vector3(x, h, z), yaw, rng.randf_range(0.8, 1.3), rng.randf_range(0.8, 1.2), tint)
	print("  reeds: ", reeds.build(parent, Meshes.reeds_leaning(rng), mat, 220.0, false, 0.0, "reeds"))


## Grass and wildflowers along the road, as thick as the biome allows.
static func _grass(parent: Node3D, land: RiverLand, route: Route, rng: RandomNumberGenerator, mat: Material) -> void:
	var grass := Instancer.new(GRASS_CHUNK)
	var petals := [Color(0.95, 0.95, 0.92), Color(0.98, 0.82, 0.22), Color(0.62, 0.42, 0.85)]
	var mk := MegaKit.available()
	var flowers: MegaKit.Mix
	if mk:   # the MegaKit's purple flowers
		flowers = MegaKit.mix(GRASS_CHUNK, FLOWERS, MegaKit.PLANT)
	else:
		var own := []
		for c: Color in petals:
			own.append([Meshes.flowers(rng, c), mat])
		flowers = MegaKit.Mix.new(GRASS_CHUNK, own)
	var hw := Route.HALF_WIDTH
	for m in route.count():
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		for _k in GRASS_PER_SAMPLE:
			var u := rng.randf_range(-1.0, 1.0)
			var side := hw + 0.6 + u * u * GRASS_REACH
			var pos := p + t * rng.randf_range(-1.0, 1.0) + right * side * signf(u)
			if land.road_distance_at(pos.x, pos.z) < hw + 0.6 or land.field(land.dw, pos.x, pos.z) < 3.0:
				continue
			var fo := land.field(land.forest, pos.x, pos.z)
			var al := land.field(land.alpine, pos.x, pos.z)
			if rng.randf() > clampf(1.0 - 0.7 * fo - 0.85 * al, 0.1, 1.0):
				continue
			var ny := land.normal_at(pos.x, pos.z).y
			if ny < 0.78:
				continue
			pos.y = land.height_at(pos.x, pos.z)
			var col := land.ground_at(pos.x, pos.z)
			var dw := land.field(land.dw, pos.x, pos.z)
			# wetland grass turns rusty towards the water, and leans to it
			col = col.lerp(RUST, band01(dw, 3.0, 8.0, 20.0, 35.0) * land.field(land.wet, pos.x, pos.z) * 0.7)
			var dir := land.water_dir(pos.x, pos.z) if dw < 25.0 else land.wind_at(pos.x, pos.z)
			if dir == Vector2.ZERO:
				dir = land.wind_at(pos.x, pos.z)
			grass.put(pos, _yaw_to(dir) + rng.randf_range(-0.4, 0.4), rng.randf_range(0.8, 1.3), rng.randf_range(0.6, 1.2), col)
			var meadow := clampf(1.0 - fo * 1.5 - land.field(land.heath, pos.x, pos.z) * 0.5 - land.field(land.wet, pos.x, pos.z) - al, 0.0, 1.0)
			if rng.randf() < meadow * 0.06:
				flowers.pick(rng).put(pos, rng.randf() * TAU, rng.randf_range(0.8, 1.2), rng.randf_range(0.8, 1.2), Color.WHITE)
	print("  grass clumps: ", grass.build(parent, Meshes.grass_clump(rng, Vector3(0.18, 0.0, 0.0)), mat, GRASS_VISIBLE, false, 0.0, "grass"))
	print("  flowers: ", flowers.build(parent, GRASS_VISIBLE, false, "grass"))


static func band01(v: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, v) * (1.0 - smoothstep(c, d, v))


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


## Railings, side beams and piers where the road crosses water.
static func _bridges(b: MeshBuilder, land: RiverLand, route: Route, bridge: PackedByteArray) -> void:
	var n := route.count()
	var hw := Route.HALF_WIDTH
	for m in n:
		if bridge[m] == 0:
			continue
		var m2 := (m + 1) % n
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		for sgn: float in [-1.0, 1.0]:
			var off := right * (hw + 0.05) * sgn
			var q := route.points[m2] + Vector3(-route.tangent_index(m2).z, 0.0, route.tangent_index(m2).x) * (hw + 0.05) * sgn
			_beam(b, p + off + Vector3(0.0, -0.3, 0.0), q + Vector3(0.0, -0.3, 0.0), 0.3, 0.6, WOOD.darkened(0.2))
			if bridge[m2] != 0:
				_beam(b, p + off + Vector3(0.0, 1.0, 0.0), q + Vector3(0.0, 1.0, 0.0), 0.12, 0.12, WOOD)
			if m % 2 == 0:
				_beam(b, p + off, p + off + Vector3(0.0, 1.08, 0.0), 0.14, 0.14, WOOD)
			if m % 6 == 0:
				var foot := land.height_at(p.x + off.x, p.z + off.z) - 1.0
				if foot < p.y - 1.0:
					_beam(b, p + off * 0.85 + Vector3(0.0, -0.5, 0.0), Vector3(p.x + off.x * 0.85, foot, p.z + off.z * 0.85), 0.5, 0.5, WOOD.darkened(0.3))


## Wooden fences along the road through open meadow, a run at a time on one side.
static func _fences(b: MeshBuilder, land: RiverLand, route: Route, bridge: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var n := route.count()
	var side := 1.0
	var prev := Vector3.ZERO
	var running := false
	for m in range(0, n, 2):
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		var post := p + right * (Route.HALF_WIDTH + 1.4) * side
		var open := land.field(land.forest, post.x, post.z) < 0.15 and land.field(land.alpine, post.x, post.z) < 0.2 \
			and land.field(land.dw, post.x, post.z) > 8.0 and bridge[m] == 0
		if not open:
			if running and rng.randf() < 0.5:
				side = -side
			running = false
			continue
		post.y = land.height_at(post.x, post.z)
		_beam(b, post + Vector3(0.0, -0.3, 0.0), post + Vector3(0.0, 1.15, 0.0), 0.14, 0.14, WOOD)
		if running and prev.distance_to(post) < 6.0:
			for y in [0.5, 0.95]:
				_beam(b, prev + Vector3(0.0, y, 0.0), post + Vector3(0.0, y, 0.0), 0.08, 0.12, WOOD.lightened(0.08))
		prev = post
		running = true
