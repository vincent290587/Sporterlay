class_name RiverScenery
extends RefCounted
## Populates the Riverlands in layers, biggest first, each reading the biome maps and
## keeping clear of the footprints of what came before (cliffs, trees, bushes, logs,
## boulders), then the small stuff without footprints (reeds, grass, flowers), then
## the man-made bits (bridges, fences).

const TOON := preload("res://shaders/toon_vcol.gdshader")
const GRASS := preload("res://shaders/grass.gdshader")
const WATER := preload("res://shaders/water.gdshader")

const TREE_CHUNK := 200.0
const TREE_DETAIL := 450.0       # full trees out to here, simple ones beyond
const TREE_VISIBLE := 2200.0
const SMALL_CHUNK := 64.0
const SMALL_VISIBLE := 350.0
const GRASS_CHUNK := 32.0
const GRASS_VISIBLE := 125.0
const GRASS_PER_SAMPLE := 110
const GRASS_REACH := 110.0
const WOOD := Color(0.50, 0.36, 0.24)

# leaf palettes: [shadow side, lit side]
const GREEN := [Color(0.20, 0.38, 0.17), Color(0.42, 0.62, 0.24)]
const YELLOW := [Color(0.58, 0.45, 0.10), Color(0.96, 0.80, 0.26)]
const ORANGE := [Color(0.58, 0.26, 0.08), Color(0.96, 0.56, 0.18)]
const RED := [Color(0.46, 0.11, 0.08), Color(0.84, 0.30, 0.16)]
const BIRCH := [Color(0.62, 0.50, 0.10), Color(1.0, 0.86, 0.36)]
const BUSH_TINTS := [Color(0.40, 0.58, 0.24), Color(0.80, 0.44, 0.20), Color(0.70, 0.26, 0.18), Color(0.82, 0.68, 0.28)]


## Where things already stand: (x, z, radius) in 12 m cells.
class Footprints:
	const CELL := 12.0
	var grid := {}

	func free_at(x: float, z: float, r: float) -> bool:
		var ci := floori(x / CELL)
		var cj := floori(z / CELL)
		for dj in range(-1, 2):
			for di in range(-1, 2):
				var list: Array = grid.get(Vector2i(ci + di, cj + dj), [])
				for v: Vector3 in list:
					var rr := v.z + r
					if (v.x - x) * (v.x - x) + (v.y - z) * (v.y - z) < rr * rr:
						return false
		return true

	func add(x: float, z: float, r: float) -> void:
		var key := Vector2i(floori(x / CELL), floori(z / CELL))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(Vector3(x, z, r))


static func build(parent: Node3D, land: RiverLand, route: Route, bridge: PackedByteArray, seed: int) -> void:
	var toon := ShaderMaterial.new()
	toon.shader = TOON
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = GRASS
	var t := Time.get_ticks_msec()
	_mesh(parent, land.build_mesh(), toon, true)
	_mesh(parent, Roads.ribbon(route, bridge), toon, true)
	var water := ShaderMaterial.new()
	water.shader = WATER
	_mesh(parent, land.water_mesh(), water, false)
	print("  meshes: %d ms" % (Time.get_ticks_msec() - t))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 100
	var fp := Footprints.new()
	_cliffs(parent, land, rng, fp, toon)
	_trees(parent, land, rng, fp, toon)
	_undergrowth(parent, land, rng, fp, toon)
	print("  big props: %d ms" % (Time.get_ticks_msec() - t))
	_reeds(parent, land, rng, grass_mat)
	_grass(parent, land, route, rng, grass_mat)
	var b := MeshBuilder.new()
	_bridges(b, land, route, bridge)
	_fences(b, land, route, bridge, rng)
	_mesh(parent, b.commit(), toon, true)
	print("  small props: %d ms" % (Time.get_ticks_msec() - t))


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Jittered grid of candidate points over the land (not the faded edge).
static func _candidates(spacing: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var out := PackedVector2Array()
	var lim := RiverLand.HALF - 80.0
	var x := -lim
	while x < lim:
		var z := -lim
		while z < lim:
			out.append(Vector2(x + rng.randf() * spacing, z + rng.randf() * spacing))
			z += spacing
		x += spacing
	return out


static func _dry(land: RiverLand, x: float, z: float, clearance: float) -> bool:
	return land.field(land.dw, x, z) > clearance and land.road_distance_at(x, z) > Route.HALF_WIDTH + clearance


## Rock faces wherever the ground is too steep for soil.
static func _cliffs(parent: Node3D, land: RiverLand, rng: RandomNumberGenerator, fp: Footprints, mat: Material) -> void:
	var rocks := Instancer.new(TREE_CHUNK)
	for p in _candidates(11.0, rng):
		var s := land.field(land.slope, p.x, p.y)
		if rng.randf() > smoothstep(0.22, 0.4, s) or not _dry(land, p.x, p.y, 4.0):
			continue
		var size := rng.randf_range(5.0, 10.0)
		if not fp.free_at(p.x, p.y, size * 0.45):
			continue
		fp.add(p.x, p.y, size * 0.45)
		var up := land.normal_at(p.x, p.y).lerp(Vector3.UP, 0.4).normalized()
		var side := up.cross(Vector3(cos(rng.randf() * TAU), 0.0, sin(rng.randf() * TAU))).normalized()
		var fwd := side.cross(up)
		var basis := Basis(side * size, up * size * rng.randf_range(0.6, 1.0), fwd * size * rng.randf_range(0.7, 1.1))
		rocks.put_basis(Vector3(p.x, land.height_at(p.x, p.y) - size * 0.15, p.y), basis, Color(1, 1, 1).darkened(rng.randf() * 0.15))
	print("  cliffs: ", rocks.build(parent, Meshes.cliff(rng), mat, TREE_VISIBLE, true))


static func _trees(parent: Node3D, land: RiverLand, rng: RandomNumberGenerator, fp: Footprints, mat: Material) -> void:
	var hue := FastNoiseLite.new()
	hue.seed = rng.randi()
	hue.frequency = 0.012
	var palettes := [GREEN, YELLOW, ORANGE, RED]
	var broad: Array[Instancer] = []
	for _p in palettes:
		broad.append(Instancer.new(TREE_CHUNK))
	var birch := Instancer.new(TREE_CHUNK)
	var pine := Instancer.new(TREE_CHUNK)
	var spruce := Instancer.new(TREE_CHUNK)
	for p in _candidates(7.5, rng):
		var fo := land.field(land.forest, p.x, p.y)
		var al := land.field(land.alpine, p.x, p.y)
		if rng.randf() > fo * 0.9 + 0.012 * (1.0 - al):
			continue
		if not _dry(land, p.x, p.y, 4.0) or land.normal_at(p.x, p.y).y < 0.75:
			continue
		if not fp.free_at(p.x, p.y, 2.4):
			continue
		fp.add(p.x, p.y, 2.4)
		var pos := Vector3(p.x, land.height_at(p.x, p.y), p.y)
		var s := rng.randf_range(0.75, 1.3)
		var yaw := rng.randf() * TAU
		var tint := Color(1, 1, 1).darkened(rng.randf() * 0.15)
		var dw := land.field(land.dw, p.x, p.y)
		if rng.randf() < land.field(land.conifer, p.x, p.y):
			(pine if rng.randf() < 0.5 else spruce).put(pos, yaw, s, s * rng.randf_range(0.9, 1.2), tint)
		elif (dw < 60.0 and rng.randf() < 0.45) or (fo < 0.3 and rng.randf() < 0.3):
			birch.put(pos, yaw, s, s * rng.randf_range(0.9, 1.15), tint)
		else:
			# patches of one colour, with strays
			var v := hue.get_noise_2d(p.x, p.y) * 0.5 + 0.5 + rng.randf_range(-0.25, 0.25)
			var k := clampi(int(v * 4.0), 0, 3)
			broad[k].put(pos, yaw, s, s * rng.randf_range(0.85, 1.1), tint)
	var n := 0
	for k in palettes.size():
		var pal: Array = palettes[k]
		n += broad[k].build_lod(parent, Meshes.broadleaf(rng, pal[0], pal[1]), Meshes.broadleaf_far(rng, pal[0], pal[1]), mat, TREE_DETAIL, TREE_VISIBLE)
	n += birch.build_lod(parent, Meshes.birch(rng, BIRCH[0], BIRCH[1]), Meshes.birch_far(rng, BIRCH[0], BIRCH[1]), mat, TREE_DETAIL, TREE_VISIBLE)
	n += pine.build_lod(parent, Meshes.conifer(rng), Meshes.conifer_far(12.6, 3.4), mat, TREE_DETAIL, TREE_VISIBLE)
	n += spruce.build_lod(parent, Meshes.conifer(rng, Meshes.SPRUCE_LAYERS), Meshes.conifer_far(16.0, 2.7), mat, TREE_DETAIL, TREE_VISIBLE)
	print("  trees: ", n)


## Bushes thickest at forest edges and by water, logs and stumps in the woods,
## boulders on open and high ground.
static func _undergrowth(parent: Node3D, land: RiverLand, rng: RandomNumberGenerator, fp: Footprints, mat: Material) -> void:
	var bushes := Instancer.new(SMALL_CHUNK)
	for p in _candidates(3.5, rng):
		var fo := land.field(land.forest, p.x, p.y)
		var edge := 4.0 * fo * (1.0 - fo)
		var chance := edge * 0.35 + land.field(land.wet, p.x, p.y) * 0.2 + land.field(land.heath, p.x, p.y) * 0.08 + fo * 0.04
		if rng.randf() > chance or not _dry(land, p.x, p.y, 2.0) or not fp.free_at(p.x, p.y, 1.0):
			continue
		fp.add(p.x, p.y, 1.0)
		var tint: Color = BUSH_TINTS[0] if rng.randf() < 0.5 else BUSH_TINTS[rng.randi() % BUSH_TINTS.size()]
		var s := rng.randf_range(0.6, 1.3)
		bushes.put(Vector3(p.x, land.height_at(p.x, p.y), p.y), rng.randf() * TAU, s, s * rng.randf_range(0.8, 1.2), tint.darkened(rng.randf() * 0.15))
	var logs := Instancer.new(SMALL_CHUNK)
	var stumps := Instancer.new(SMALL_CHUNK)
	for p in _candidates(14.0, rng):
		if rng.randf() > land.field(land.forest, p.x, p.y) * 0.35 or not _dry(land, p.x, p.y, 3.0) or not fp.free_at(p.x, p.y, 1.8):
			continue
		fp.add(p.x, p.y, 1.8)
		var pos := Vector3(p.x, land.height_at(p.x, p.y) - 0.1, p.y)
		if rng.randf() < 0.6:
			logs.put(pos, rng.randf() * TAU, rng.randf_range(0.7, 1.1), 1.0, Color.WHITE)
		else:
			stumps.put(pos, rng.randf() * TAU, rng.randf_range(0.8, 1.3), rng.randf_range(0.7, 1.4), Color.WHITE)
	var boulders := Instancer.new(TREE_CHUNK)
	for p in _candidates(16.0, rng):
		var chance := 0.05 + land.field(land.alpine, p.x, p.y) * 0.35 + land.field(land.heath, p.x, p.y) * 0.15
		if rng.randf() > chance or not _dry(land, p.x, p.y, 2.0) or not fp.free_at(p.x, p.y, 1.5):
			continue
		fp.add(p.x, p.y, 1.5)
		var s := rng.randf_range(0.8, 3.5)
		boulders.put(Vector3(p.x, land.height_at(p.x, p.y) - s * 0.15, p.y), rng.randf() * TAU, s, s * rng.randf_range(0.6, 1.0), Color(1, 1, 1).darkened(rng.randf() * 0.2))
	var n := bushes.build(parent, Meshes.bush(rng), mat, SMALL_VISIBLE, true)
	n += logs.build(parent, Meshes.fallen_log(rng), mat, SMALL_VISIBLE, true)
	n += stumps.build(parent, Meshes.stump(rng), mat, SMALL_VISIBLE, true)
	n += boulders.build(parent, Meshes.rock(rng), mat, TREE_VISIBLE, true)
	print("  undergrowth: ", n)


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
		for _k in 4:
			var x := cx + rng.randf_range(-5.0, 5.0)
			var z := cz + rng.randf_range(-5.0, 5.0)
			var h := land.height_at(x, z)
			if h < level - 0.7 or h > level + 0.9 or land.road_distance_at(x, z) < Route.HALF_WIDTH + 1.0:
				continue
			var tint := Color(0.56, 0.62, 0.30).lerp(Color(0.72, 0.62, 0.34), rng.randf())
			reeds.put(Vector3(x, h, z), rng.randf() * TAU, rng.randf_range(0.8, 1.3), rng.randf_range(0.8, 1.2), tint)
	print("  reeds: ", reeds.build(parent, Meshes.reeds(rng), mat, 200.0, false))


## Grass and wildflowers along the road, as thick as the biome allows.
static func _grass(parent: Node3D, land: RiverLand, route: Route, rng: RandomNumberGenerator, mat: Material) -> void:
	var grass := Instancer.new(GRASS_CHUNK)
	var petals := [Color(0.95, 0.95, 0.92), Color(0.98, 0.82, 0.22), Color(0.62, 0.42, 0.85)]
	var flowers: Array[Instancer] = []
	for _p in petals:
		flowers.append(Instancer.new(GRASS_CHUNK))
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
			grass.put(pos, rng.randf() * TAU, rng.randf_range(0.8, 1.3), rng.randf_range(0.6, 1.2), col)
			var meadow := clampf(1.0 - fo * 1.5 - land.field(land.heath, pos.x, pos.z) * 0.5 - land.field(land.wet, pos.x, pos.z) - al, 0.0, 1.0)
			if rng.randf() < meadow * 0.06:
				flowers[rng.randi() % flowers.size()].put(pos, rng.randf() * TAU, rng.randf_range(0.8, 1.2), rng.randf_range(0.8, 1.2), Color.WHITE)
	print("  grass clumps: ", grass.build(parent, Meshes.grass_clump(rng), mat, GRASS_VISIBLE, false))
	var n := 0
	for k in petals.size():
		n += flowers[k].build(parent, Meshes.flowers(rng, petals[k]), mat, GRASS_VISIBLE, false)
	print("  flower clumps: ", n)


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
