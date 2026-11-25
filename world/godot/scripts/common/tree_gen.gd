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
## Conifers: a trunk, a dark solid core and tiers of drooping needle fronds.
##
## Meshes have two surfaces: bark (toon_vcol) and leaves (foliage). Sizes match the old
## blob trees: a broadleaf is ~10 m tall with a ~7 m crown at scale 1.

const BARK := Color(0.44, 0.32, 0.22)
const BIRCH_BARK := Color(0.90, 0.88, 0.82)
const DEAD_BARK := Color(0.56, 0.52, 0.48)
const SOLID := 0.0
const NEEDLES := 0.5
const CLUMP := 1.0

const BROADLEAF := {
	"trunk": 2.6, "trunk_r": 0.36, "depth": 3, "kids": Vector2i(2, 3), "spread": Vector2(0.5, 0.95),
	"length": 2.3, "decay": 0.74, "up": 0.3, "taper": 0.62, "cluster": 1.9, "cards": 12,
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
		_cluster(leaves, rng, t + Vector3(0.0, r * 0.25, 0.0), r, crown, crown_r, dark, light, cards, lod)
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
		crown_r: float, dark: Color, light: Color, cards: int, lod := 0) -> void:
	# core
	var rings := 4 if lod == 0 else 3
	var segs: int = [6, 5, 5][lod]
	var core_r := r * 0.72
	var first := b.verts.size()
	var bottom := _leaf_vert(b, c - Vector3(0.0, core_r, 0.0), Vector3.DOWN, crown, crown_r, dark, light, SOLID, Vector2(0.5, 0.5))
	for ri in range(1, rings):
		var lat := PI * ri / rings - PI / 2.0
		for s in segs:
			var lon := TAU * s / segs + ri * 0.4
			var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			_leaf_vert(b, c + dir * core_r * rng.randf_range(0.85, 1.12), dir, crown, crown_r, dark, light, SOLID, Vector2(0.5, 0.5))
	var top := _leaf_vert(b, c + Vector3(0.0, core_r, 0.0), Vector3.UP, crown, crown_r, dark, light, SOLID, Vector2(0.5, 0.5))
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
		var rand := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var dir := (rand + outward * 0.7).normalized()
		var pos := c + dir * r * rng.randf_range(0.55, 0.9)
		var size := r * rng.randf_range(0.55, 0.8)
		var t1 := dir.cross(Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5)).normalized()
		var t2 := dir.cross(t1)
		var corners := [pos - t1 * size - t2 * size, pos + t1 * size - t2 * size, pos + t1 * size + t2 * size, pos - t1 * size + t2 * size]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var ids := []
		for q in 4:
			var cp: Vector3 = corners[q]
			ids.append(_leaf_vert(b, cp, dir, crown, crown_r, dark, light, CLUMP, uvs[q]))
		b.tri_raw(ids[0], ids[1], ids[2])
		b.tri_raw(ids[0], ids[2], ids[3])


static func _leaf_vert(b: MeshBuilder, pos: Vector3, local: Vector3, crown: Vector3, crown_r: float,
		dark: Color, light: Color, kind: float, uv: Vector2) -> int:
	var col := _shade(pos, crown, crown_r, dark, light)
	col.a = kind
	return b.add(pos, _crown_normal(pos, crown, local), col, uv)


## A conifer: trunk, dark solid core, tiers of drooping needle fronds. `height` and
## `radius` at scale 1 (pine ~13 m, spruce ~16 m).
static func conifer(rng: RandomNumberGenerator, height: float, radius: float, tiers: int, dark: Color, light: Color, lod := 0) -> ArrayMesh:
	var bark := MeshBuilder.new()
	var leaves := MeshBuilder.new()
	Meshes.limb(bark, Vector3(0.0, -0.6, 0.0), Vector3(0.0, height * 0.97, 0.0), 0.34, 0.05, 6, BARK)
	var axis := Vector3(0.0, height * 0.5, 0.0)
	# core: a narrow cone, so there are no see-through gaps between tiers
	var segs := 8
	var base := leaves.verts.size()
	for s in segs:
		var a := TAU * s / segs
		var d := Vector3(cos(a), 0.0, sin(a))
		var col := dark.darkened(0.15)
		col.a = SOLID
		leaves.add(d * radius * 0.5 + Vector3(0.0, 1.8, 0.0), (d + Vector3.UP * 0.5).normalized(), col, Vector2(0.5, 0.5))
	var tip_col := light
	tip_col.a = SOLID
	var apex := leaves.add(Vector3(0.0, height, 0.0), Vector3.UP, tip_col, Vector2(0.5, 0.5))
	for s in segs:
		leaves.tri(apex, base + s, base + (s + 1) % segs)
	# tiers of fronds, wide at the bottom
	for t in tiers:
		var f := float(t) / (tiers - 1)
		var y := lerpf(1.9, height * 0.93, f)
		var reach := (radius * pow(1.0 - f * 0.92, 0.9) + 0.35) * rng.randf_range(0.9, 1.1)
		if lod >= 2 and t % 2 == 1:
			continue   # far: every other tier
		var fronds := (8 if t < tiers - 2 else 6) if lod == 0 else (5 if lod == 1 else 4)
		var spin := rng.randf() * TAU
		for k in fronds:
			var a := spin + TAU * k / fronds + rng.randf_range(-0.2, 0.2)
			var d := Vector3(cos(a), 0.0, sin(a))
			var side := Vector3(-d.z, 0.0, d.x)
			var droop := reach * rng.randf_range(0.25, 0.45)
			var pts := [Vector3(0.0, y + 0.1, 0.0), d * reach * 0.5 + Vector3(0.0, y - droop * 0.3, 0.0), d * reach + Vector3(0.0, y - droop, 0.0)]
			var widths := [reach * 0.22, reach * 0.42, reach * 0.18]
			var vs := [0.0, 0.5, 1.0]
			var row := []
			for q in 3:
				var pq: Vector3 = pts[q]
				var w: float = widths[q]
				var n := (d * 0.8 + Vector3.UP * 0.7 + (pq - axis).normalized() * 0.3).normalized()
				var col := dark.lerp(light, clampf(0.25 + vs[q] * 0.5 + f * 0.35, 0.0, 1.0))
				col.a = NEEDLES
				row.append([leaves.add(pq - side * w, n, col, Vector2(0.0, vs[q])), leaves.add(pq + side * w, n, col, Vector2(1.0, vs[q]))])
			for q in 2:
				leaves.tri_raw(row[q][0], row[q][1], row[q + 1][1])
				leaves.tri_raw(row[q][0], row[q + 1][1], row[q + 1][0])
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
