class_name TreeGen
extends RefCounted
## Procedural trees with a real structure, for the cel-shaded worlds.
##
## Broadleaf and birch: a trunk forks into bending limbs (each level shorter, thinner,
## turned up towards the light); leaf clusters sit at the branch tips, so the crown
## follows the branches. A cluster is a solid lumpy core plus leaf cards cut out as
## scalloped clumps by foliage.gdshader. Every leaf normal points away from the crown's
## centre, so the toon light shades the whole crown as one soft volume. Colour runs
## from `dark` (inside, underneath) to `light` (outside, on top).
## Pine: the same growth, Scots-pine style: a tall bare orange trunk, near-level limbs
## high up and flat clumps of spiky needle tufts.
## Spruce: stacked solid skirts with jagged hems and a needle fringe.
##
## Meshes have two surfaces: bark (toon_vcol) and leaves (foliage). Sizes match the old
## blob trees: a broadleaf is ~10 m tall with a ~7 m crown at scale 1.

const BARK := Color(0.44, 0.32, 0.22)
const SWAY := 0.25    # m of sway 10 m up (bark and leaves together)
const BIRCH_BARK := Color(0.90, 0.88, 0.82)
const PINE_BARK := Color(0.62, 0.38, 0.24)     # Scots pine: orange-brown
const DEAD_BARK := Color(0.56, 0.52, 0.48)
const SOLID := 0.0
const NEEDLES := 0.5
const TUFT := 0.75
const CLUMP := 1.0

const BROADLEAF := {
	"trunk": 2.6, "trunk_r": 0.36, "depth": 3, "kids": Vector2i(2, 3), "spread": Vector2(0.5, 0.95),
	"length": 2.3, "decay": 0.74, "up": 0.3, "taper": 0.62, "cluster": 1.9, "cards": 12,
}
const PINE := {
	"trunk": 5.6, "trunk_r": 0.3, "depth": 3, "kids": Vector2i(2, 3), "spread": Vector2(0.8, 1.2),
	"length": 2.2, "decay": 0.7, "up": 0.18, "taper": 0.6, "cluster": 1.45, "cards": 14,
	"flat": 0.42, "kind": TUFT,
}
const BIRCH := {
	"trunk": 3.4, "trunk_r": 0.21, "depth": 3, "kids": Vector2i(2, 3), "spread": Vector2(0.3, 0.6),
	"length": 2.0, "decay": 0.74, "up": 0.6, "taper": 0.6, "cluster": 1.35, "cards": 10,
}

## Materials per detail tier ([bark, leaves]): each tier needs its own, because the LOD
## manager sets the tier's fade distances on them. Tiers: 0 full, 1 light, 2 far crown,
## 3 blob (bark material only), 4 dead trees.
static var _mats := {}


static func materials(tier: int) -> Array:
	if not _mats.has(tier):
		var bark := ShaderMaterial.new()
		bark.shader = load("res://shaders/toon_lod.gdshader")
		var leaf := ShaderMaterial.new()
		leaf.shader = load("res://shaders/foliage.gdshader")
		for m: ShaderMaterial in [bark, leaf]:   # one sway for the whole tree
			m.set_shader_parameter("sway", SWAY)
			m.set_shader_parameter("sway_height", 10.0)
		_mats[tier] = [bark, leaf]
	return _mats[tier]


## Forget the materials (a new world registers fresh ones with the LOD manager).
static func reset() -> void:
	_mats.clear()


static func _commit(bark: MeshBuilder, leaves: MeshBuilder, tier: int) -> ArrayMesh:
	var mats := materials(tier)
	var mesh := ArrayMesh.new()
	for pair in [[bark, mats[0]], [leaves, mats[1]]]:
		var b: MeshBuilder = pair[0]
		if b.indices.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.verts
		arrays[Mesh.ARRAY_NORMAL] = b.normals
		arrays[Mesh.ARRAY_COLOR] = b.colors
		arrays[Mesh.ARRAY_TEX_UV] = b.uvs
		arrays[Mesh.ARRAY_INDEX] = b.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	return mesh


## A broadleaf (or birch, with BIRCH and white bark) in two colours. `leafless` gives a
## dead tree.
static func branching(rng: RandomNumberGenerator, p: Dictionary, dark: Color, light: Color,
		bark_col := BARK, leafless := false, lod := 0) -> ArrayMesh:
	var bark := MeshBuilder.new()
	var leaves := MeshBuilder.new()
	var tips: Array[Vector3] = []
	var lean := Vector3(rng.randf_range(-0.08, 0.08), 1.0, rng.randf_range(-0.08, 0.08)).normalized()
	# root flare, then the trunk
	Meshes.limb(bark, Vector3(0.0, -0.6, 0.0), Vector3(0.0, 0.5, 0.0), p.trunk_r * 1.6, p.trunk_r, 7, bark_col.darkened(0.1))
	var mids: Array[Vector3] = []
	_grow(bark, tips, mids, rng, Vector3(0.0, 0.5, 0.0), lean, p.trunk, p.trunk_r, p.depth, p, bark_col, lod)
	if bark_col == BIRCH_BARK:
		for i in bark.colors.size():
			if rng.randf() < 0.22:
				bark.colors[i] = BIRCH_BARK.darkened(0.75)
	if leafless:
		return _commit(bark, leaves, 4)
	# full detail: clusters at the tips and along the outer limbs; lighter: tips only,
	# a bit bigger, with fewer cards and a coarser core
	var spots: Array[Vector3] = []
	if lod < 2:
		spots = tips.duplicate()
	else:
		for i in range(0, tips.size(), 2):   # far: every other tip, bigger clusters
			spots.append(tips[i])
	if lod == 0:
		spots.append_array(mids)
	var grow: float = [1.0, 1.25, 1.55][lod]
	var cards: int = [int(p.cards), 4, 0][lod]
	var crown := Vector3.ZERO
	for t in spots:
		crown += t
	crown /= spots.size()
	var crown_r := 0.0
	for t in spots:
		crown_r = maxf(crown_r, t.distance_to(crown))
	crown_r += p.cluster
	for t in spots:
		# smaller clusters low in the crown, bigger ones outside and on top
		var outer := clampf(t.distance_to(crown) / crown_r + (t.y - crown.y) / crown_r * 0.5, 0.0, 1.0)
		var r: float = p.cluster * rng.randf_range(0.8, 1.15) * lerpf(0.7, 1.05, outer) * grow
		_cluster(leaves, rng, t + Vector3(0.0, r * 0.25, 0.0), r, crown, crown_r, dark, light, cards, lod,
			p.get("flat", 1.0), p.get("kind", CLUMP))
	return _commit(bark, leaves, lod)


## One limb in two bending segments, then its children.
static func _grow(bark: MeshBuilder, tips: Array[Vector3], mids: Array[Vector3], rng: RandomNumberGenerator,
		start: Vector3, dir: Vector3, length: float, radius: float, depth: int, p: Dictionary, col: Color, lod: int) -> void:
	var up: float = p.up
	var taper: float = p.taper
	var decay: float = p.decay
	var side := dir.cross(Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5))
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var mid_dir := dir.rotated(side, rng.randf_range(-0.18, 0.18))
	var mid := start + mid_dir * length * 0.5
	var end_dir := (mid_dir.rotated(side, rng.randf_range(-0.18, 0.18)) + Vector3.UP * up).normalized()
	var end := mid + end_dir * length * 0.5
	var r_end := radius * taper
	var segs := 6 if depth >= 2 else 4
	if lod == 0 or depth >= 2 + int(lod >= 2):   # far away the thin limbs are hidden in the crown anyway
		Meshes.limb(bark, start, mid, radius, (radius + r_end) * 0.5, segs if lod == 0 else 4, col)
		Meshes.limb(bark, mid, end, (radius + r_end) * 0.5, r_end, segs if lod == 0 else 4, col)
	if depth <= 1:
		mids.append(mid)   # leaves along the outer limbs too, not only at their ends
	if depth == 0:
		tips.append(end)
		return
	var kids_range: Vector2i = p.kids
	var spread: Vector2 = p.spread
	var kids := rng.randi_range(kids_range.x, kids_range.y)
	var spin := rng.randf() * TAU
	var perp0 := end_dir.cross(Vector3.UP)
	perp0 = perp0.normalized() if perp0.length() > 0.01 else Vector3.RIGHT
	for k in kids:
		var perp := perp0.rotated(end_dir, spin + TAU * k / kids + rng.randf_range(-0.35, 0.35))
		var t := rng.randf_range(spread.x, spread.y)
		var child_dir := (end_dir * cos(t) + perp * sin(t)).normalized()
		var from := end - end_dir * length * rng.randf_range(0.0, 0.25)
		_grow(bark, tips, mids, rng, from, child_dir, length * decay * rng.randf_range(0.85, 1.1), r_end * 0.9, depth - 1, p, col, lod)


## Shade from where a point sits in the crown: inside and underneath dark, outside and
## on top light.
static func _shade(pos: Vector3, crown: Vector3, crown_r: float, dark: Color, light: Color) -> Color:
	var d := pos - crown
	var out := clampf(d.length() / crown_r, 0.0, 1.0)
	var up := d.normalized().y * 0.5 + 0.5 if d.length() > 0.01 else 0.5
	return dark.lerp(light, clampf(out * 0.55 + up * 0.55 - 0.1, 0.0, 1.0))


static func _crown_normal(pos: Vector3, crown: Vector3, local: Vector3) -> Vector3:
	var d := pos - crown
	var n := d.normalized() if d.length() > 0.01 else Vector3.UP
	return (n * 0.75 + local * 0.25).normalized()


## A leaf cluster: a solid lumpy core and cut-out leaf cards around it.
static func _cluster(b: MeshBuilder, rng: RandomNumberGenerator, c: Vector3, r: float, crown: Vector3,
		crown_r: float, dark: Color, light: Color, cards: int, lod := 0, flat := 1.0, kind := CLUMP) -> void:
	# core
	var rings := 4 if lod == 0 else 3
	var segs: int = [6, 5, 5][lod]
	var core_r := r * 0.72
	var first := b.verts.size()
	var bottom := _leaf_vert(b, c - Vector3(0.0, core_r * flat, 0.0), Vector3.DOWN, crown, crown_r, dark, light, SOLID, Vector2(0.5, 0.5))
	for ri in range(1, rings):
		var lat := PI * ri / rings - PI / 2.0
		for s in segs:
			var lon := TAU * s / segs + ri * 0.4
			var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var off := dir * core_r * rng.randf_range(0.85, 1.12)
			off.y *= flat
			_leaf_vert(b, c + off, dir, crown, crown_r, dark, light, SOLID, Vector2(0.5, 0.5))
	var top := _leaf_vert(b, c + Vector3(0.0, core_r * flat, 0.0), Vector3.UP, crown, crown_r, dark, light, SOLID, Vector2(0.5, 0.5))
	var ring0 := first + 1
	for s in segs:
		var s2 := (s + 1) % segs
		b.tri(bottom, ring0 + s, ring0 + s2)
		for ri in rings - 2:
			var a := ring0 + ri * segs
			b.quad(a + s, a + s2, a + segs + s2, a + segs + s)
		var last := ring0 + (rings - 2) * segs
		b.tri(top, last + s, last + s2)
	# leaf cards, facing mostly outwards from the crown
	var outward := (c - crown).normalized() if c.distance_to(crown) > 0.01 else Vector3.UP
	for _k in cards:
		var rand := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1) * flat, rng.randf_range(-1, 1)).normalized()
		var dir := (rand + outward * 0.7).normalized()
		if flat < 1.0:
			# flat pads: cards lie mostly level, like layered clouds of needles
			dir = (rand * 0.6 + outward * 0.3 + Vector3.UP * (1.0 - flat) * 1.6).normalized()
		var pos := c + dir * r * rng.randf_range(0.55, 0.9) * Vector3(1.0, flat, 1.0)
		var size := r * rng.randf_range(0.55, 0.8) * (1.0 if flat >= 1.0 else 0.8)
		var t1 := dir.cross(Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5)).normalized()
		var t2 := dir.cross(t1)
		var corners := [pos - t1 * size - t2 * size, pos + t1 * size - t2 * size, pos + t1 * size + t2 * size, pos - t1 * size + t2 * size]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var ids := []
		for q in 4:
			var cp: Vector3 = corners[q]
			ids.append(_leaf_vert(b, cp, dir, crown, crown_r, dark, light, kind, uvs[q]))
		b.tri_raw(ids[0], ids[1], ids[2])
		b.tri_raw(ids[0], ids[2], ids[3])


static func _leaf_vert(b: MeshBuilder, pos: Vector3, local: Vector3, crown: Vector3, crown_r: float,
		dark: Color, light: Color, kind: float, uv: Vector2) -> int:
	var col := _shade(pos, crown, crown_r, dark, light)
	col.a = kind
	return b.add(pos, _crown_normal(pos, crown, local), col, uv)


## A spruce: stacked solid skirts, one cone per tier, each with a jagged drooping hem,
## a dark underside and (full detail) a fringe of needle cards along the hem. Normals
## point out and up, so each tier gets a lit top and a shaded lower edge. `height`,
## `radius` at scale 1 (~16 m, ~2.8 m).
static func spruce(rng: RandomNumberGenerator, height: float, radius: float, tiers: int, dark: Color, light: Color, lod := 0) -> ArrayMesh:
	var bark := MeshBuilder.new()
	var leaves := MeshBuilder.new()
	Meshes.limb(bark, Vector3(0.0, -0.6, 0.0), Vector3(0.0, height * 0.9, 0.0), 0.36, 0.06, [7, 5, 4][lod], BARK.darkened(0.1))
	var segs: int = [16, 12, 8][lod]
	var count: int = [tiers, tiers - 1, maxi(tiers - 3, 3)][lod]
	for t in count:
		var f := float(t) / (count - 1)
		var top_y := lerpf(height * 0.3, height, f) + rng.randf_range(-0.2, 0.2)
		var span := lerpf(height * 0.26, height * 0.14, f)
		var rim_y := top_y - span
		var reach := (radius * (1.0 - f * 0.85) + 0.3) * rng.randf_range(0.92, 1.08)
		var spin := rng.randf() * TAU
		var tier_dark := dark.lerp(light, f * 0.35)
		var tier_light := light.lerp(dark, (1.0 - f) * 0.25)
		var apex_col := tier_light
		apex_col.a = SOLID
		var apex := leaves.add(Vector3(0.0, top_y, 0.0), Vector3.UP, apex_col, Vector2(0.5, 0.5))
		var rim := PackedInt32Array()
		var under := PackedInt32Array()
		var dirs := []
		for k in segs:
			var a := spin + TAU * k / segs
			var d := Vector3(cos(a), 0.0, sin(a))
			dirs.append(d)
			var point := k % 2 == 0              # every other rim point sticks out and droops
			var r := reach * (1.0 if point else 0.8) * rng.randf_range(0.94, 1.06)
			var y := rim_y - (reach * 0.22 if point else 0.0)
			var n := (d * 1.0 + Vector3.UP * 0.75).normalized()
			var c := tier_dark.lerp(tier_light, 0.35)
			c.a = SOLID
			rim.append(leaves.add(d * r + Vector3(0.0, y, 0.0), n, c, Vector2(0.5, 0.5)))
			var cu := tier_dark.darkened(0.35)
			cu.a = SOLID
			under.append(leaves.add(d * reach * 0.3 + Vector3(0.0, rim_y + span * 0.3, 0.0), (d * 0.3 + Vector3.DOWN).normalized(), cu, Vector2(0.5, 0.5)))
		for k in segs:
			var k2 := (k + 1) % segs
			leaves.tri(apex, rim[k], rim[k2])
			leaves.quad(rim[k], under[k], under[k2], rim[k2])
		# a fringe of needles hanging from the hem points
		if lod == 0:
			for k in range(0, segs, 2):
				var d: Vector3 = dirs[k]
				var side := Vector3(-d.z, 0.0, d.x)
				var root := d * reach * 0.75 + Vector3(0.0, rim_y + 0.05, 0.0)
				var tip := d * reach * 1.18 + Vector3(0.0, rim_y - reach * 0.38, 0.0)
				var w := reach * 0.28
				var n := (d + Vector3.UP * 0.6).normalized()
				var c0 := tier_dark.lerp(tier_light, 0.3)
				c0.a = NEEDLES
				var c1 := tier_dark.lerp(tier_light, 0.55)
				c1.a = NEEDLES
				var i0 := leaves.add(root - side * w, n, c0, Vector2(0.0, 0.0))
				var i1 := leaves.add(root + side * w, n, c0, Vector2(1.0, 0.0))
				var i2 := leaves.add(tip + side * w * 0.6, n, c1, Vector2(1.0, 1.0))
				var i3 := leaves.add(tip - side * w * 0.6, n, c1, Vector2(0.0, 1.0))
				leaves.tri_raw(i0, i1, i2)
				leaves.tri_raw(i0, i2, i3)
	return _commit(bark, leaves, lod)


## A birch: slender, white bark with dark marks, small clusters on upright branches.
static func birch(rng: RandomNumberGenerator, dark: Color, light: Color, lod := 0) -> ArrayMesh:
	return branching(rng, BIRCH, dark, light, BIRCH_BARK, false, lod)


## The same tree at three levels of detail [full, light, far], grown from one random
## state so all have the same branches.
static func lods(rng: RandomNumberGenerator, make: Callable) -> Array:
	var state := rng.state
	var out := []
	var after := state
	for lod in 3:
		rng.state = state
		out.append(make.call(rng, lod))
		if lod == 0:
			after = rng.state
	rng.state = after
	return out


static func dead(rng: RandomNumberGenerator) -> ArrayMesh:
	return branching(rng, BROADLEAF, Color.BLACK, Color.BLACK, DEAD_BARK, true)
