class_name GiantScenery
extends RefCounted
## Puts the giant flooded world together: islands and a mountain skirt, a
## water plane, a wooden boardwalk, giant procedural trees (10x normal),
## and reeds along the shores.

const TOON := preload("res://shaders/toon_vcol.gdshader")
const GRASS := preload("res://shaders/grass.gdshader")
const WATER := preload("res://shaders/swamp_water.gdshader")
const BOARDWALK := preload("res://shaders/boardwalk.gdshader")
const RIPPLE := preload("res://shaders/ripple.gdshader")
const RIPPLE_VISIBLE := 700.0
const ROOTS_VISIBLE := 1400.0

const TREE_NEAR := 650.0         # full TreeGen models out to here
const TREE_MID := 1800.0         # lighter TreeGen models out to here
const TREE_FAR := 3600.0         # far crowns out to here, blobs beyond
const TREE_VISIBLE := 6200.0
const TREE_CHUNK := 200.0
const REEDS_CHUNK := 32.0
const REEDS_VISIBLE := 350.0
const LILY_VISIBLE := 300.0
const LILY_CHUNK := 24.0
const LILY_MIN_DEPTH := 0.3        # shallow water, m below the surface
const LILY_MAX_DEPTH := 3.0
const LILY_DARK := Color(0.44, 0.68, 0.24)
const LILY_LIGHT := Color(0.86, 1.0, 0.46)
const FLOWER_WHITE := Color(1.0, 0.96, 0.92)
const FLOWER_PINK := Color(1.0, 0.68, 0.76)

const WOOD := Color(0.52, 0.38, 0.25)
const RUST := Color(0.64, 0.40, 0.24)
const SWAMP_DEPTH := 7.0         # swamp trees stand in water up to this deep
## A swamp tree (bald-cypress like): a tall, stout trunk and a loose, flat crown.
const SWAMP := {
	"trunk": 4.4, "trunk_r": 0.44, "depth": 3, "kids": Vector2i(2, 3), "spread": Vector2(0.6, 1.15),
	"length": 2.0, "decay": 0.72, "up": 0.2, "taper": 0.6, "cluster": 1.55, "cards": 12, "flat": 0.6,
}
const SWAMP_DARK := Color(0.22, 0.32, 0.16)
const SWAMP_LIGHT := Color(0.50, 0.56, 0.28)

## `sun` is the sun light (the water's glitter points at it).
static func build(parent: Node3D, land: GiantLand, route: Route, seed: int, sun: DirectionalLight3D) -> void:
	for c in [["trees", 1.0], ["reeds", 0.65], ["props", 0.5]]:
		Lod.category(c[0], c[1])
	var toon := ShaderMaterial.new()
	toon.shader = TOON
	_mesh(parent, land.build_mesh(), toon, true)
	_water(parent, sun)
	var deck := ShaderMaterial.new()
	deck.shader = BOARDWALK
	deck.set_shader_parameter("half_width", Route.HALF_WIDTH)
	_mesh(parent, _deck(route), deck, true)
	_railings(parent, route, toon)

	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = GRASS
	Lod.add_param("reeds", grass_mat, "fade_start", 120.0)
	Lod.add_param("reeds", grass_mat, "fade_end", 190.0)

	_index_road(route)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1
	_giant_trees(parent, land, route, rng, toon)
	_reeds(parent, land, route, rng, grass_mat)
	_piers(parent, land, route, rng, toon)
	_lily_pads(parent, land, route, rng, toon)


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _water(parent: Node3D, sun: DirectionalLight3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GiantLand.FAR * 2.0, GiantLand.FAR * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER
	mat.set_shader_parameter("sun_dir", sun.transform.basis.z)
	mat.set_shader_parameter("sky_top", GiantWorld.SKY_TOP)
	mat.set_shader_parameter("sky_horizon", GiantWorld.SKY_HORIZON)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = GiantLand.WATER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## The boardwalk deck: a top with UV (metres across, metres along) for the plank
## shader, and a fascia board down each side.
static func _deck(route: Route) -> ArrayMesh:
	var b := MeshBuilder.new()
	var n := route.count()
	var hw := Route.HALF_WIDTH
	var lift := Vector3(0.0, 0.02, 0.0)
	var drop := Vector3(0.0, -0.16, 0.0)
	var white := Color(1.0, 1.0, 1.0)
	var row := 6
	for m in n + 1:   # the last row repeats the first with s = length, so UVs don't wrap
		var p := route.points[m % n] + lift
		var t := route.tangent_index(m % n)
		var right := Vector3(-t.z, 0.0, t.x)
		var s := m * route.spacing
		b.add(p - right * hw, Vector3.UP, white, Vector2(-hw, s))
		b.add(p + right * hw, Vector3.UP, white, Vector2(hw, s))
		b.add(p - right * hw, -right, white, Vector2(-hw, s))
		b.add(p - right * hw + drop, -right, white, Vector2(-hw, s))
		b.add(p + right * hw, right, white, Vector2(hw, s))
		b.add(p + right * hw + drop, right, white, Vector2(hw, s))
	for m in n:
		var a := m * row
		var z := (m + 1) * row
		b.quad(a, a + 1, z + 1, z)
		b.quad(a + 2, a + 3, z + 3, z + 2)
		b.quad(a + 4, a + 5, z + 5, z + 4)
	return b.commit()


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
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var rail := [WOOD, WOOD]
	for m in n:
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		if m % 4 == 0:   # each rail runs ~8 m between posts, in its own shade
			for side in 2:
				rail[side] = WOOD.lerp(Color(0.50, 0.47, 0.42), rng.randf() * 0.6).darkened(rng.randf() * 0.25)
		var q := route.points[(m + 1) % n]
		var tq := route.tangent_index((m + 1) % n)
		var rq := Vector3(-tq.z, 0.0, tq.x)
		for side in 2:
			var sgn := -1.0 if side == 0 else 1.0
			var off := right * (hw + 0.05) * sgn
			var offq := rq * (hw + 0.05) * sgn
			_beam(b, p + off + Vector3(0.0, 1.0, 0.0), q + offq + Vector3(0.0, 1.0, 0.0), 0.12, 0.12, rail[side])
			if m % 4 == 0:
				_beam(b, p + off, p + off + Vector3(0.0, 1.08, 0.0), 0.14, 0.14, rail[side].darkened(0.12))
	_mesh(parent, b.commit(), mat, false)


static func _piers(parent: Node3D, land: GiantLand, route: Route, rng: RandomNumberGenerator, mat: Material) -> void:
	var b := MeshBuilder.new()
	var ripples := Instancer.new(TREE_CHUNK)
	var n := route.count()
	var hw := Route.HALF_WIDTH
	for m in range(0, n, 8):
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		for sgn: float in [-1.0, 1.0]:
			var off := right * (hw + 0.15) * sgn
			var ground := land.natural(p.x + off.x, p.z + off.z)
			var foot := maxf(ground, GiantLand.WATER) - 0.4
			if ground < GiantLand.WATER - 0.2:   # the post's radius is ~0.3 m
				ripples.put(Vector3(p.x + off.x, GiantLand.WATER + 0.05, p.z + off.z), rng.randf() * TAU, 1.5, 1.0, Color.WHITE)
			_beam(b, p + off + Vector3(0.0, -0.35, 0.0),
				Vector3(p.x + off.x, foot, p.z + off.z), 0.38, 0.58, WOOD.darkened(0.2 + rng.randf() * 0.15))
	_mesh(parent, b.commit(), mat, false)
	print("  post ripples: ", ripples.build(parent, _ripple_plane(), _ripple_mat(0.2), RIPPLE_VISIBLE, false, 0.0, "props"))


## Giant trees: the same TreeGen models at 10x scale on the islands, and swamp trees
## and dead snags standing in the shallow water.
static func _giant_trees(parent: Node3D, land: GiantLand, route: Route,
		rng: RandomNumberGenerator, mat: Material) -> void:
	TreeGen.reset()
	var broad := Instancer.new(TREE_CHUNK)
	var pine := Instancer.new(TREE_CHUNK)
	var swamp := Instancer.new(TREE_CHUNK)
	var snags := Instancer.new(TREE_CHUNK)
	var roots: Array[Instancer] = [Instancer.new(TREE_CHUNK), Instancer.new(TREE_CHUNK), Instancer.new(TREE_CHUNK)]
	var ripples := Instancer.new(TREE_CHUNK)
	var forest := FastNoiseLite.new()
	forest.seed = seed_for(rng)
	forest.frequency = 0.006
	forest.fractal_octaves = 3
	var count := 18000
	for _k in count:
		var px := rng.randf_range(-GiantLand.HALF + 60.0, GiantLand.HALF - 60.0)
		var pz := rng.randf_range(-GiantLand.HALF + 60.0, GiantLand.HALF - 60.0)
		var h := land.natural(px, pz)
		if h < GiantLand.WATER - SWAMP_DEPTH or h > 300.0:
			continue
		if _road_distance(route, px, pz) < Route.HALF_WIDTH + 14.0:
			continue
		var wet := h < GiantLand.WATER + 1.4
		var dense := smoothstep(0.12, 0.45, forest.get_noise_2d(px, pz))
		if wet:   # thinner in deeper water, but stands even where islands have none
			var depth := clampf((GiantLand.WATER + 1.4 - h) / (SWAMP_DEPTH + 1.4), 0.0, 1.0)
			dense = (dense * 0.6 + 0.25) * (1.0 - depth * 0.7)
		if rng.randf() > dense * 0.65 + 0.012:
			continue
		var tint := Color(1.0, 1.0, 1.0).lerp(Color(1.12, 1.08, 0.78), rng.randf() * 0.55)
		tint = tint.darkened(rng.randf() * 0.12)
		var s := rng.randf_range(0.75, 1.35) * 10.0
		var pos := Vector3(px, h, pz)
		if wet:
			var snag := rng.randf() < 0.14
			# trunk radius at the water line (m); roots and knees reach ~4 of them
			var trunk: float = (TreeGen.BROADLEAF.trunk_r * 0.9 if snag else SWAMP.trunk_r) * s * 1.15
			if _road_distance(route, px, pz) < Route.HALF_WIDTH + 3.0 + trunk * 4.2:
				continue
			if snag:
				snags.put(pos, rng.randf() * TAU, s * 0.9, s * rng.randf_range(0.9, 1.2), tint.darkened(0.1))
			else:
				swamp.put(pos, rng.randf() * TAU, s, s * rng.randf_range(1.0, 1.3), tint)
			var foot := Vector3(px, maxf(h, GiantLand.WATER), pz)
			roots[rng.randi() % roots.size()].put(foot, rng.randf() * TAU, trunk, trunk * rng.randf_range(0.6, 0.85), tint)
			if h < GiantLand.WATER - 0.2:
				var size := trunk * 3.8 / 0.26   # rings reach ~3.8 trunk radii
				ripples.put(Vector3(px, GiantLand.WATER + 0.05, pz), rng.randf() * TAU, size * 0.26, 1.0, Color.WHITE)
		elif rng.randf() < 0.35:
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
	var sw := TreeGen.lods(rng, func(r: RandomNumberGenerator, lod: int) -> ArrayMesh:
		return TreeGen.branching(r, SWAMP, SWAMP_DARK, SWAMP_LIGHT, TreeGen.BARK.darkened(0.15), false, lod))
	var w := swamp.build_tiers(parent, [[sw[0], null, 0.0, TREE_NEAR, true, TreeGen.materials(0), 200.0],
		[sw[1], null, TREE_NEAR, TREE_MID, false, TreeGen.materials(1), 300.0],
		[sw[2], null, TREE_MID, TREE_FAR, false, TreeGen.materials(2), 500.0],
		[Meshes.broadleaf_far(rng, SWAMP_DARK, SWAMP_LIGHT), blob, TREE_FAR, TREE_VISIBLE, false, [blob], 700.0]], "trees")
	w += snags.build_tiers(parent, [[TreeGen.dead(rng), null, 0.0, TREE_MID, true, TreeGen.materials(4), 300.0]], "trees")
	for inst in roots:
		inst.build(parent, _roots_mesh(rng, TreeGen.BARK.darkened(0.15)), mat, ROOTS_VISIBLE, true, 0.0, "trees")
	print("  ripples: ", ripples.build(parent, _ripple_plane(), _ripple_mat(0.26), RIPPLE_VISIBLE, false, 0.0, "props"))
	print("  giant trees: ", n, " on land, ", w, " in the water")


## Roots for a trunk of radius 1 standing at y = 0 (the water line): arched prop
## roots from the trunk out and down into the water, and cypress knees poking up.
static func _roots_mesh(rng: RandomNumberGenerator, bark: Color) -> ArrayMesh:
	var b := MeshBuilder.new()
	var n := rng.randi_range(7, 10)
	var a0 := rng.randf() * TAU
	for k in n:
		var a := a0 + TAU * k / n + rng.randf_range(-0.25, 0.25)
		var d := Vector3(cos(a), 0.0, sin(a))
		var col := bark.darkened(rng.randf() * 0.15)
		var start := d * 0.75 + Vector3(0.0, rng.randf_range(0.7, 1.6), 0.0)
		var reach := rng.randf_range(2.2, 3.4)
		var mid := d * (reach * 0.55) + Vector3(0.0, rng.randf_range(0.3, 0.7), 0.0)
		var end := d * reach + Vector3(0.0, -1.5, 0.0)
		var r := rng.randf_range(0.26, 0.38)
		Meshes.limb(b, start, mid, r, r * 0.75, 6, col)
		Meshes.limb(b, mid, end, r * 0.75, r * 0.45, 6, col)
	for k in rng.randi_range(6, 11):
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(2.0, 3.8)
		var top := rng.randf_range(0.15, 0.45)
		Meshes.limb(b, p + Vector3(0.0, -0.6, 0.0), p + Vector3(0.0, top * 0.6, 0.0),
			rng.randf_range(0.11, 0.17), 0.08, 7, bark.lightened(0.05))
		Meshes.limb(b, p + Vector3(0.0, top * 0.6, 0.0), p + Vector3(0.0, top, 0.0), 0.08, 0.03, 7, bark.lightened(0.08))
	return b.commit()


## A flat 2x2 plane for ripples, facing up.
static func _ripple_plane() -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	return plane


static func _ripple_mat(inner: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RIPPLE
	m.set_shader_parameter("inner", inner)
	m.render_priority = 1   # after the water
	return m


## Reeds and cattails along the island shores and in the shallows.
static func _reeds(parent: Node3D, land: GiantLand, route: Route,
		rng: RandomNumberGenerator, mat: Material) -> void:
	var inst := Instancer.new(REEDS_CHUNK)
	for _k in 40000:
		var px := rng.randf_range(-GiantLand.HALF + 40.0, GiantLand.HALF - 40.0)
		var pz := rng.randf_range(-GiantLand.HALF + 40.0, GiantLand.HALF - 40.0)
		var h := land.natural(px, pz)
		if h < GiantLand.WATER - 0.8 or h > GiantLand.WATER + 2.6:
			continue
		if _road_distance(route, px, pz) < Route.HALF_WIDTH + 3.0:
			continue
		var tint := Color(0.58, 0.62, 0.30).lerp(Color(0.72, 0.60, 0.32), rng.randf())
		inst.put(Vector3(px, h, pz), rng.randf() * TAU, rng.randf_range(0.8, 1.35), rng.randf_range(1.2, 2.1), tint)
	print("  reeds: ", inst.build(parent, Meshes.reeds_leaning(rng), mat, REEDS_VISIBLE, false, 0.0, "reeds"))

## Lily pads in calm shallow water: flat discs with a wedge-shaped notch, a few
## darker/lighter green tints, and a small white/pink flower on about 5 % of them.
## Dense mats around cluster centres, kept off the boardwalk. Unit pad radius 0.5,
## so the instance's x/z scale is the pad's width in metres.
static func _pad_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var notch := rng.randf_range(0.28, 0.44)   # half the notch's angle (rad)
	var a0 := rng.randf() * TAU
	var segs := 18
	var r := 0.5
	var a_start := a0 + notch
	var a_end := a0 + TAU - notch
	var center := b.add(Vector3(0.0, 0.012, 0.0), Vector3.UP, Color(1.0, 1.0, 1.0))
	var ring := PackedInt32Array()
	for k in segs:
		var f := float(k) / (segs - 1)
		var a := lerpf(a_start, a_end, f)
		var d := Vector3(cos(a), 0.0, sin(a))
		var rr := r * rng.randf_range(0.94, 1.05)
		ring.append(b.add(d * rr + Vector3(0.0, rng.randf_range(0.0, 0.025), 0.0),
			Vector3.UP, Color(0.78, 0.90, 0.66)))
	for k in range(segs - 1):
		b.tri(center, ring[k], ring[k + 1])
	return b.commit()

## A small water-lily bloom: five flat petals round a golden heart, unit radius
## ~0.55. The instance colour tints the petals white or pink.
static func _lily_flower_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var white := Color.WHITE
	var gold := Color(1.0, 0.86, 0.45)
	var center := b.add(Vector3(0.0, 0.10, 0.0), Vector3.UP, gold)
	var ring := PackedInt32Array()
	for k in 10:
		var a := TAU * k / 10 + rng.randf_range(-0.08, 0.08)
		var rr := 0.55 if k % 2 == 0 else 0.24   # five petals
		ring.append(b.add(Vector3(cos(a) * rr, 0.11 + rng.randf_range(0.0, 0.03),
			sin(a) * rr), Vector3.UP, white))
	for k in 10:
		b.tri(center, ring[k], ring[(k + 1) % 10])
	return b.commit()

static func _lily_pads(parent: Node3D, land: GiantLand, route: Route,
		rng: RandomNumberGenerator, mat: Material) -> void:
	var pads := Instancer.new(LILY_CHUNK)
	var blooms := Instancer.new(LILY_CHUNK)
	var patch := FastNoiseLite.new()
	patch.seed = seed_for(rng)
	patch.frequency = 0.035
	patch.fractal_octaves = 3
	var pad_mesh := _pad_mesh(rng)
	var bloom_mesh := _lily_flower_mesh(rng)

	# cluster centres in shallow water along the boardwalk, only where the
	# patch noise makes a zone, so mats don't line the whole shore
	var centres := PackedVector2Array()
	var n := route.count()
	for m in range(0, n, 16):
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		for sgn: float in [-1.0, 1.0]:
			var off := rng.randf_range(8.0, 150.0)
			var px := p.x + right.x * sgn * off
			var pz := p.z + right.z * sgn * off
			var h := land.natural(px, pz)
			var depth := GiantLand.WATER - h
			if depth < LILY_MIN_DEPTH or depth > LILY_MAX_DEPTH:
				continue
			if _road_distance(route, px, pz) < Route.HALF_WIDTH + 1.5:
				continue
			var zone := patch.get_noise_2d(px, pz) * 0.5 + 0.5
			if zone < 0.38:
				continue
			centres.append(Vector2(px, pz))

	# a few loose centres out in the open shallows
	for _k in 50:
		var px := rng.randf_range(-GiantLand.HALF + 40.0, GiantLand.HALF - 40.0)
		var pz := rng.randf_range(-GiantLand.HALF + 40.0, GiantLand.HALF - 40.0)
		var h := land.natural(px, pz)
		var depth := GiantLand.WATER - h
		if depth < LILY_MIN_DEPTH or depth > LILY_MAX_DEPTH:
			continue
		if _road_distance(route, px, pz) < Route.HALF_WIDTH + 1.5:
			continue
		centres.append(Vector2(px, pz))

	# dense mats around each centre, fading towards the edge
	for c: Vector2 in centres:
		var radius := rng.randf_range(2.0, 12.5)   # patch diameter 4-25 m
		var target := maxi(4, int(PI * radius * radius * rng.randf_range(0.45, 0.75) / 0.9))
		for _p in target:
			var dist := radius * rng.randf() * rng.randf()   # denser in the middle
			var a := rng.randf() * TAU
			var px := c.x + cos(a) * dist
			var pz := c.y + sin(a) * dist
			var h := land.natural(px, pz)
			var depth := GiantLand.WATER - h
			if depth < LILY_MIN_DEPTH or depth > LILY_MAX_DEPTH:
				continue
			if _road_distance(route, px, pz) < Route.HALF_WIDTH + 1.5:
				continue
			var size := rng.randf_range(0.6, 1.6)   # width across, m
			var tint := LILY_DARK.lerp(LILY_LIGHT, rng.randf())
			tint = tint.darkened(rng.randf() * 0.08)
			# a small per-pad lift keeps overlapping pads from z-fighting
			var pos := Vector3(px, GiantLand.WATER + 0.045 + rng.randf_range(0.002, 0.02), pz)
			pads.put(pos, rng.randf() * TAU, size, 1.0, tint)
			if rng.randf() < 0.05:
				var flower_tint := FLOWER_WHITE.lerp(FLOWER_PINK, rng.randf())
				blooms.put(pos + Vector3(0.0, 0.05, 0.0), rng.randf() * TAU,
					size * 0.22, 0.7, flower_tint)
	print("  lily patches: ", centres.size())
	print("  lily pads: ", pads.build(parent, pad_mesh, mat, LILY_VISIBLE, false, 0.0, "props"))
	print("  lily flowers: ", blooms.build(parent, bloom_mesh, mat, LILY_VISIBLE, false, 0.0, "props"))


const ROAD_CELL := 40.0
static var _road_grid := {}

## Buckets the road points by ROAD_CELL so `_road_distance` only looks nearby.
static func _index_road(route: Route) -> void:
	_road_grid = {}
	for m in route.count():
		var p := route.points[m]
		var key := Vector2i(floori(p.x / ROAD_CELL), floori(p.z / ROAD_CELL))
		if not _road_grid.has(key):
			_road_grid[key] = PackedVector2Array()
		_road_grid[key].append(Vector2(p.x, p.z))


## Distance to the nearest road point; exact up to ROAD_CELL, INF beyond.
static func _road_distance(_route: Route, x: float, z: float) -> float:
	var cx := floori(x / ROAD_CELL)
	var cz := floori(z / ROAD_CELL)
	var q := Vector2(x, z)
	var best := INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var pts: Variant = _road_grid.get(Vector2i(cx + dx, cz + dz))
			if pts == null:
				continue
			for p: Vector2 in pts:
				best = minf(best, q.distance_squared_to(p))
	return sqrt(best)


static func seed_for(rng: RandomNumberGenerator) -> int:
	return rng.randi()
