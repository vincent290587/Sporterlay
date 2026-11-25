class_name RiverCliffs
extends RefCounted
## The cliff tool: a layered rock skin over every slope too steep for soil, the way
## sedimentary cliffs look (bands of rock of random thickness, some sticking out more
## than others), then rock fall below them, then plants on the ledges.
##
##   strata    the land is sliced into horizontal layers of random thickness (1.2-4.5 m),
##             tilted by one of three dips per region; a blocky noise splits the cliffs
##             into two groups with different layer sets, so lines don't run on forever.
##   skin      render-grid quads on steep ground, subdivided 5x5 (1 m), each vertex
##             pushed out along the slope by its layer's depth and some crag noise, faded
##             to nothing where the ground stops being steep.
##   colour    each layer has its colour; the terrain under and around the skin takes the
##             same colour (RiverLand.vertex_color), so it shows even far away.
##   scree     rock fall: particles start on cliff cells, roll down the steepest way until
##             the ground flattens out, and leave scree (with their layer's colour) behind;
##             crumbled rocks are scattered on it.
##   ledges    upward faces of the skin with no layer sticking out above get plants.

const CLIFF_NY_START := 0.77    # normal.y where the skin starts
const CLIFF_NY_FULL := 0.68     # and where it's fully out
const SUB := 5                  # quad subdivision up close (1 m)
const SUB_FAR := 2              # and further out (2.5 m)
const TILE := 64                # render quads per tile side (320 m)
const SKIN_NEAR := 400.0
const SKIN_FAR := 4000.0
const LEDGE_UP := 0.8           # face normal.y for a ledge
const STEPS := int(400.0 / RiverLand.A_STEP)   # rock fall travels up to 400 m

const ROCKS := [Color(0.74, 0.64, 0.50), Color(0.60, 0.57, 0.54), Color(0.68, 0.52, 0.44),
	Color(0.50, 0.47, 0.45), Color(0.80, 0.72, 0.58)]
const DIPS := [Vector2(0.0, 0.0), Vector2(0.12, 0.04), Vector2(-0.05, 0.2)]

var land: RiverLand
var tops := [PackedFloat32Array(), PackedFloat32Array()]   # layer top heights, per group
var depths := [PackedFloat32Array(), PackedFloat32Array()]
var colors := [PackedColorArray(), PackedColorArray()]
var split := FastNoiseLite.new()
var region := FastNoiseLite.new()
var crag := FastNoiseLite.new()
var ledges := PackedVector3Array()   # plant spots found while building the skin


func setup(l: RiverLand, seed: int) -> void:
	land = l
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 50
	for g in 2:
		var y := -300.0
		var t := PackedFloat32Array()
		var d := PackedFloat32Array()
		var c := PackedColorArray()
		while y < 1200.0:
			y += rng.randf_range(1.2, 4.5)
			t.append(y)
			d.append(rng.randf_range(0.0, 1.4))
			var base: Color = ROCKS[rng.randi() % ROCKS.size()]
			c.append(base.darkened(rng.randf_range(0.0, 0.12)))
		tops[g] = t
		depths[g] = d
		colors[g] = c
	split.seed = seed + 51
	split.noise_type = FastNoiseLite.TYPE_VALUE   # blocky
	split.frequency = 1.0 / 35.0
	region.seed = seed + 52
	region.frequency = 0.0015
	crag.seed = seed + 53
	crag.frequency = 0.25
	crag.fractal_octaves = 2


## Depth and colour of the layer at a point, in one lookup.
func _layer_info(x: float, y: float, z: float) -> Array:
	var l := _layer(x, y, z)
	return [(depths[l.x] as PackedFloat32Array)[l.y], (colors[l.x] as PackedColorArray)[l.y]]


## Which layer set, and which layer, a point belongs to.
func _layer(x: float, y: float, z: float) -> Vector2i:
	var g := 0 if split.get_noise_2d(x, z) < 0.0 else 1
	var r := clampi(int((region.get_noise_2d(x, z) * 0.5 + 0.5) * 3.0), 0, 2)
	var dip: Vector2 = DIPS[r]
	var t: PackedFloat32Array = tops[g]
	var band := t.bsearch(y + dip.x * x + dip.y * z)
	return Vector2i(g, mini(band, t.size() - 1))


func color_at(x: float, y: float, z: float) -> Color:
	var l := _layer(x, y, z)
	return (colors[l.x] as PackedColorArray)[l.y]


func _depth(x: float, y: float, z: float) -> float:
	var l := _layer(x, y, z)
	return (depths[l.x] as PackedFloat32Array)[l.y]


## Rock fall: every cliff cell sends a few particles down the steepest way; where they
## pass and stop becomes scree, coloured like the layer they started from.
func simulate_scree(seed: int) -> void:
	var na := RiverLand.NA
	var n := na * na
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 54
	var amount := PackedFloat32Array()
	amount.resize(n)
	var cr := PackedFloat32Array()
	cr.resize(n)
	var cg := PackedFloat32Array()
	cg.resize(n)
	var cb := PackedFloat32Array()
	cb.resize(n)
	for c in n:
		if land.slope[c] < 0.24 or land.wl[c] != RiverLand.DRY:
			continue
		var x := -RiverLand.HALF + (c % na) * RiverLand.A_STEP
		var z := -RiverLand.HALF + (c / na) * RiverLand.A_STEP
		var col := color_at(x, land.ha[c], z)
		for _p in 1:
			var cur := c
			for step in STEPS:
				var ci := cur % na
				var cj := cur / na
				# the lowest neighbour, sometimes the second lowest, so fans spread
				var best := -1
				var second := -1
				for d in 8:
					var ni: int = ci + RiverLand.DX[d]
					var nj: int = cj + RiverLand.DZ[d]
					if ni < 0 or nj < 0 or ni >= na or nj >= na:
						continue
					var nb := nj * na + ni
					if land.ha[nb] >= land.ha[cur]:
						continue
					if best < 0 or land.ha[nb] < land.ha[best]:
						second = best
						best = nb
					elif second < 0 or land.ha[nb] < land.ha[second]:
						second = nb
				if best < 0:
					break
				cur = second if second >= 0 and rng.randf() < 0.35 else best
				if land.wl[cur] != RiverLand.DRY:
					break
				var w := 1.0 - float(step) / STEPS
				amount[cur] += w
				cr[cur] += col.r * w
				cg[cur] += col.g * w
				cb[cur] += col.b * w
				if land.slope[cur] < 0.06:
					break
	for c in n:
		if amount[c] > 0.0:
			land.scree_col[c] = Color(cr[c] / amount[c], cg[c] / amount[c], cb[c] / amount[c])
	var soft := land.blur_m(amount, 10.0)
	for c in n:
		# cliffs themselves are skin, not scree
		land.scree[c] = clampf(soft[c] / 2.5, 0.0, 1.0) * (1.0 - smoothstep(0.22, 0.3, land.slope[c]))
		if amount[c] <= 0.0 and land.scree[c] > 0.0:
			# blurred into a cell no rock reached: the layer it sits on
			land.scree_col[c] = color_at(-RiverLand.HALF + (c % na) * RiverLand.A_STEP, land.ha[c],
				-RiverLand.HALF + (c / na) * RiverLand.A_STEP)


## How far out of steep (0) or fully cliff (1) a render vertex is.
func _cliffness(ny: float) -> float:
	return smoothstep(CLIFF_NY_START, CLIFF_NY_FULL, ny)


## The rock skin in tiles of TILE render quads, each at full detail (SUB) up to
## SKIN_NEAR m and coarser (SUB_FAR) beyond, so far cliffs cost little and tiles out of
## view aren't drawn. Ledges come from the full-detail skin.
func build_skin_tiles(parent: Node3D, mat: Material) -> void:
	ledges.clear()
	var near := _skin(SUB)
	var far := _skin(SUB_FAR)
	var count := 0
	for key in near:
		var b: MeshBuilder = near[key]
		var skin := b.faceted()
		_find_ledges(skin)
		count += _tile(parent, skin.commit(), mat, 0.0, SKIN_NEAR, true)
		if far.has(key):
			_tile(parent, (far[key] as MeshBuilder).faceted().commit(), mat, SKIN_NEAR, SKIN_FAR, true)
	print("  cliff tiles: %d" % count)


func _tile(parent: Node3D, mesh: ArrayMesh, mat: Material, from: float, to: float, shadows: bool) -> int:
	var aabb := mesh.get_aabb()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.visibility_range_begin = from
	mi.visibility_range_end = to
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return 1 if aabb.size != Vector3.ZERO else 0


## Skin builders per tile, each render quad split sub x sub.
func _skin(sub: int) -> Dictionary:
	var n := RiverLand.N
	var step := RiverLand.STEP
	var tiles := {}
	var nrm := PackedVector3Array()
	nrm.resize(n * n)
	for j in n:
		for i in n:
			nrm[j * n + i] = land._grid_normal(i, j)
	for j in n - 1:
		for i in n - 1:
			var k := j * n + i
			var corners := [k, k + 1, k + n + 1, k + n]
			var steep := false
			for c: int in corners:
				if nrm[c].y < CLIFF_NY_START:
					steep = true
			if not steep:
				continue
			var x0 := -RiverLand.HALF + i * step
			var z0 := -RiverLand.HALF + j * step
			if land.road_distance_at(x0, z0) < Route.HALF_WIDTH + 3.0 or land.field(land.dw, x0, z0) < 4.0:
				continue
			# ground colours at the corners only (the skin blends into them at its edges)
			var gc := []
			for c: int in corners:
				var cx := -RiverLand.HALF + (c % n) * step
				var cz := -RiverLand.HALF + (c / n) * step
				gc.append(land.vertex_color(cx, cz, land.heights[c], nrm[c].y, 999.0))
			var key := Vector2i(i / TILE, j / TILE)
			if not tiles.has(key):
				tiles[key] = MeshBuilder.new()
			var b: MeshBuilder = tiles[key]
			# (sub+1)^2 vertices over the quad, then 2 triangles per small quad
			var ids := PackedInt32Array()
			for sj in sub + 1:
				for si in sub + 1:
					var tx := float(si) / sub
					var tz := float(sj) / sub
					var h := lerpf(lerpf(land.heights[k], land.heights[k + 1], tx), lerpf(land.heights[k + n], land.heights[k + n + 1], tx), tz)
					var nv: Vector3 = nrm[k].lerp(nrm[k + 1], tx).lerp(nrm[k + n].lerp(nrm[k + n + 1], tx), tz).normalized()
					var x := x0 + tx * step
					var z := z0 + tz * step
					var w := _cliffness(nv.y)
					var out := Vector3(nv.x, 0.0, nv.z).normalized()
					var info := _layer_info(x, h, z)
					var push := w * (0.3 + float(info[0]) + crag.get_noise_2d(x, z + h) * 0.5) + 0.12
					var p := Vector3(x, h, z) + out * push + Vector3.UP * 0.05
					var ground: Color = (gc[0] as Color).lerp(gc[1], tx).lerp((gc[3] as Color).lerp(gc[2], tx), tz)
					var col := ground.lerp(info[1], w)
					ids.append(b.add(p, nv, col))
			for sj in sub:
				for si in sub:
					var a := ids[sj * (sub + 1) + si]
					var c2 := ids[(sj + 1) * (sub + 1) + si + 1]
					b.tri(a, ids[sj * (sub + 1) + si + 1], c2)
					b.tri(a, c2, ids[(sj + 1) * (sub + 1) + si])
	return tiles


## Upward faces well out on the cliff, with no layer above sticking out further.
func _find_ledges(skin: MeshBuilder) -> void:
	for t in range(0, skin.indices.size(), 3):
		var nv := skin.normals[skin.indices[t]]
		if nv.y < LEDGE_UP:
			continue
		var p := (skin.verts[skin.indices[t]] + skin.verts[skin.indices[t + 1]] + skin.verts[skin.indices[t + 2]]) / 3.0
		var ground := land.height_at(p.x, p.z)
		if p.y < ground + 0.2:
			continue   # not out on the rock
		if _depth(p.x, p.y + 1.5, p.z) > _depth(p.x, p.y - 0.5, p.z) + 0.2:
			continue   # the layer above overhangs it
		ledges.append(p)
