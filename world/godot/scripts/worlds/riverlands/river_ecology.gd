class_name RiverEcology
extends RefCounted
## Vegetation as an ecosystem: each species has a viability (how much it likes a spot),
## built by combining terrain maps; species compete for ground; trees get a size from
## their age (how deep into the forest they stand); and trees change what's around them.
##
##   viability   per tree species, from the analysis maps (altitude, sun, occlusion,
##               moisture, distance to water, convexity) times the forest sub-biome,
##               plus a noise warped by the terrain normal, minus exclusions: water,
##               road, cliffs, scree, runoff lines on steep slopes, dry south faces.
##   competition candidates are visited from the most viable down; one is dropped when
##               it stands inside the radius of a stronger one. Trees (priority 10)
##               keep a large radius among themselves but only a small "priority
##               radius" against the understory (priority 0), so bushes and ferns can
##               grow close to trunks while trees stay apart.
##   age         signed distance into the forest. Young, small trees at the edges, old
##               tall ones in the core, a band of young regrowth inside, smaller trees
##               higher up, a few dead trees in old forest.
##   influence   the trees' crowns are splatted into canopy maps: leaf litter or needles
##               on the ground, the forest floor raised a little (roots hold the soil),
##               ferns in the shade, mossy rocks around the conifers.

const TREE_CHUNK := 200.0
const TREE_DETAIL := 450.0
const TREE_VISIBLE := 2200.0
const SMALL_CHUNK := 64.0
const SMALL_VISIBLE := 350.0
const FERN_VISIBLE := 160.0

const TREE_PRIORITY_RADIUS := 1.0   # how close understory may grow to a trunk
const TREE_RADIUS := 6.0            # trees' viability radius at size 1 (big trees keep more room)
const SIZES := [0.6, 0.75, 0.9, 1.05, 1.25]
const AGE_DEPTH := 25.0             # m into the forest where trees are fully grown
const REGROWTH := Vector2(12.0, 20.0)
const FOREST_EDGE := 0.28           # viability where the forest begins

const GREEN := [Color(0.20, 0.38, 0.17), Color(0.42, 0.62, 0.24)]
const YELLOW := [Color(0.58, 0.45, 0.10), Color(0.96, 0.80, 0.26)]
const ORANGE := [Color(0.58, 0.26, 0.08), Color(0.96, 0.56, 0.18)]
const RED := [Color(0.46, 0.11, 0.08), Color(0.84, 0.30, 0.16)]
const BIRCH := [Color(0.62, 0.50, 0.10), Color(1.0, 0.86, 0.36)]
const BUSH_TINTS := [Color(0.40, 0.58, 0.24), Color(0.80, 0.44, 0.20), Color(0.70, 0.26, 0.18), Color(0.82, 0.68, 0.28)]
const FERN_TINTS := [Color(0.82, 0.62, 0.22), Color(0.72, 0.38, 0.16), Color(0.46, 0.62, 0.26)]

enum { BROAD, PINE, SPRUCE, BIRCH_TREE, DEAD }


## Footprints of what's been placed: (x, z, radius among equals, radius against lower priority).
class Footprints:
	const CELL := 8.0
	var grid := {}

	## Free if no stored footprint covers (x, z): `against_lower` uses the stored
	## priority radius (for a lower-priority newcomer), else the viability radius.
	func free_at(x: float, z: float, against_lower: bool) -> bool:
		var ci := floori(x / CELL)
		var cj := floori(z / CELL)
		for dj in range(-1, 2):
			for di in range(-1, 2):
				var list: Array = grid.get(Vector2i(ci + di, cj + dj), [])
				for v: Vector4 in list:
					var r := v.w if against_lower else v.z
					if (v.x - x) * (v.x - x) + (v.y - z) * (v.y - z) < r * r:
						return false
		return true

	func add(x: float, z: float, radius: float, priority_radius: float) -> void:
		var key := Vector2i(floori(x / CELL), floori(z / CELL))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(Vector4(x, z, radius, priority_radius))


var land: RiverLand
var rng := RandomNumberGenerator.new()
var trees := Footprints.new()
var under := Footprints.new()
var viability := []                 # per tree species, PackedFloat32Array on the analysis grid
var age := PackedFloat32Array()     # m into the forest (negative outside)
var exclude := PackedFloat32Array() # 1 = fine, 0 = nothing grows
var placed := []                    # [x, z, species, scale, hue] per tree


func _init(l: RiverLand, seed: int) -> void:
	land = l
	rng.seed = seed + 100


func _ax(i: int) -> float:
	return -RiverLand.HALF + i * RiverLand.A_STEP


# --- viability ---------------------------------------------------------------

static func ramp(v: float, a: float, b: float) -> float:
	return smoothstep(a, b, v)


static func band(v: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, v) * (1.0 - smoothstep(c, d, v))


## Where nothing grows, from the earlier tools and the land itself.
func _exclusions() -> void:
	var na := RiverLand.NA
	exclude.resize(na * na)
	for c in na * na:
		var s := land.slope[c]
		var e := smoothstep(4.0, 9.0, land.dw[c])                       # water
		e *= 1.0 - smoothstep(0.24, 0.3, s)                             # cliffs
		e *= 1.0 - land.scree[c]                                        # rock fall
		e *= 1.0 - smoothstep(0.12, 0.25, s) * smoothstep(4.5, 7.0, log(land.acc[c]))  # runoff lines on steep slopes
		e *= 1.0 - 0.6 * smoothstep(0.75, 0.95, land.sun[c]) * smoothstep(0.08, 0.2, s)  # baked south faces
		exclude[c] = e


func _viabilities(seed: int) -> void:
	var na := RiverLand.NA
	var noises := []
	for k in 4:
		var nz := FastNoiseLite.new()
		nz.seed = seed + 200 + k
		nz.frequency = 0.006
		nz.fractal_octaves = 3
		noises.append(nz)
	for k in 4:
		var v := PackedFloat32Array()
		v.resize(na * na)
		viability.append(v)
	var vb: PackedFloat32Array = viability[BROAD]
	var vp: PackedFloat32Array = viability[PINE]
	var vs: PackedFloat32Array = viability[SPRUCE]
	var vbi: PackedFloat32Array = viability[BIRCH_TREE]
	for j in na:
		for i in na:
			var c := j * na + i
			var x := _ax(i)
			var z := _ax(j)
			var h := land.ha[c]
			var e := exclude[c]
			if e <= 0.0:
				continue
			# noise warped by the terrain normal: patches stretch along slopes
			var nx := (land.ha[j * na + mini(i + 1, na - 1)] - land.ha[j * na + maxi(i - 1, 0)]) * 3.0
			var nz := (land.ha[mini(j + 1, na - 1) * na + i] - land.ha[maxi(j - 1, 0) * na + i]) * 3.0
			var forest := land.forest[c]
			var moist := land.moist[c]
			var occl := land.occl[c]
			var sun := land.sun[c]
			var wet := exp(-land.dw[c] / 40.0)
			var ridge := clampf(-land.conc[c] / 8.0, 0.0, 1.0)
			# broadleaf: moist, sheltered low ground
			vb[c] = forest * (0.45 + 0.6 * moist + 0.5 * occl) * (1.0 - ramp(h, 120.0, 220.0)) \
				* (0.75 + 0.5 * (noises[0] as FastNoiseLite).get_noise_2d(x + nx, z + nz)) * e
			# spruce: high or shady
			vs[c] = forest * (ramp(h, 60.0, 180.0) + 1.2 * (0.5 - sun) + 0.3 * occl) \
				* (0.75 + 0.5 * (noises[1] as FastNoiseLite).get_noise_2d(x + nx, z + nz)) * e
			# pine: drier, sunnier, convex ground
			vp[c] = forest * (0.5 * ramp(h, 20.0, 120.0) + 0.6 * ramp(sun, 0.5, 0.8) + 0.5 * ridge) \
				* (0.75 + 0.5 * (noises[2] as FastNoiseLite).get_noise_2d(x + nx, z + nz)) * e
			# birch: near water, thin woods
			vbi[c] = (forest * 0.5 + 0.25) * (1.2 * wet + 0.3 * (1.0 - forest)) \
				* (0.75 + 0.5 * (noises[3] as FastNoiseLite).get_noise_2d(x + nx, z + nz)) * e


## Signed distance into the forest (m): positive inside, negative outside.
func _age() -> void:
	var na := RiverLand.NA
	var n := na * na
	var inside := PackedByteArray()
	inside.resize(n)
	for c in n:
		var best := 0.0
		for v: PackedFloat32Array in viability:
			best = maxf(best, v[c])
		inside[c] = 1 if best > FOREST_EDGE else 0
	var d_in := _distance(inside, 0)    # inside cells: distance to the nearest outside cell
	var d_out := _distance(inside, 1)
	age.resize(n)
	for c in n:
		age[c] = d_in[c] if inside[c] == 1 else -d_out[c]


## Chamfer distance from every cell to the nearest cell whose `mask` equals `target`.
func _distance(mask: PackedByteArray, target: int) -> PackedFloat32Array:
	var na := RiverLand.NA
	var d := PackedFloat32Array()
	d.resize(na * na)
	for c in na * na:
		d[c] = 0.0 if mask[c] == target else 1e9
	var s := RiverLand.A_STEP
	var diag := s * 1.4142
	for j in na:
		for i in na:
			var c := j * na + i
			if i > 0: d[c] = minf(d[c], d[c - 1] + s)
			if j > 0: d[c] = minf(d[c], d[c - na] + s)
			if i > 0 and j > 0: d[c] = minf(d[c], d[c - na - 1] + diag)
			if i < na - 1 and j > 0: d[c] = minf(d[c], d[c - na + 1] + diag)
	for j in range(na - 1, -1, -1):
		for i in range(na - 1, -1, -1):
			var c := j * na + i
			if i < na - 1: d[c] = minf(d[c], d[c + 1] + s)
			if j < na - 1: d[c] = minf(d[c], d[c + na] + s)
			if i < na - 1 and j < na - 1: d[c] = minf(d[c], d[c + na + 1] + diag)
			if i > 0 and j < na - 1: d[c] = minf(d[c], d[c + na - 1] + diag)
	return d


# --- trees -------------------------------------------------------------------

## Picks every tree: species by viability, survivors by competition, size by age.
## Then fills the canopy maps and raises the forest floor (RiverLand.deform_under_trees).
func place_trees(seed: int) -> void:
	var t := Time.get_ticks_msec()
	_exclusions()
	_viabilities(seed)
	_age()
	# candidates on a jittered 4 m grid, then visited best first (counting sort on
	# viability; packed arrays inside an Array would be copied on every append)
	var cands := PackedVector4Array()
	var keys := PackedInt32Array()
	var lim := RiverLand.HALF - 80.0
	var x := -lim
	while x < lim:
		var z := -lim
		while z < lim:
			var px := x + rng.randf() * 4.0
			var pz := z + rng.randf() * 4.0
			z += 4.0
			var c := land.cell(px, pz)
			var best := -1
			var bv := 0.0
			for k in 4:
				var v: float = (viability[k] as PackedFloat32Array)[c]
				if v > bv:
					bv = v
					best = k
			# the odd lone tree out in the meadow
			if bv < FOREST_EDGE:
				if exclude[c] < 0.5 or rng.randf() > 0.004:
					continue
				best = BIRCH_TREE if rng.randf() < 0.5 else BROAD
				bv = FOREST_EDGE
			if land.road_distance_at(px, pz) < Route.HALF_WIDTH + 4.0:
				continue
			cands.append(Vector4(px, pz, best, bv))
			keys.append(100 - clampi(int(bv * 60.0), 0, 100))
		x += 4.0
	var hue := FastNoiseLite.new()
	hue.seed = seed + 210
	hue.frequency = 0.012
	var counts := PackedInt32Array()
	counts.resize(102)
	for k in keys:
		counts[k + 1] += 1
	for k in 101:
		counts[k + 1] += counts[k]
	var order := PackedInt32Array()
	order.resize(cands.size())
	for i in cands.size():
		order[counts[keys[i]]] = i
		counts[keys[i]] += 1
	for oi in order:
		var cand := cands[oi]
		var c := land.cell(cand.x, cand.y)
		var a := age[c]
		var h := land.ha[c]
		# size from age (mostly) and viability, smaller up high
		var v_rel := clampf((cand.w - FOREST_EDGE) / (1.0 - FOREST_EDGE), 0.0, 1.0)
		var size_t := lerpf(v_rel, clampf(a / AGE_DEPTH, 0.0, 1.0), 0.7)
		size_t *= 1.0 - 0.45 * smoothstep(120.0, 300.0, h)
		if a > REGROWTH.x and a < REGROWTH.y and rng.randf() < 0.5:
			size_t = rng.randf() * 0.3     # young regrowth inside the forest
		var idx := clampi(int(size_t * SIZES.size()), 0, SIZES.size() - 1)
		var scale: float = SIZES[idx] * rng.randf_range(0.9, 1.1)   # bridges the size steps
		var r := TREE_RADIUS * scale
		if not trees.free_at(cand.x, cand.y, false):
			continue
		trees.add(cand.x, cand.y, r, TREE_PRIORITY_RADIUS * scale)
		var species := int(cand.z)
		if a > AGE_DEPTH * 0.85 and rng.randf() < 0.04:
			species = DEAD
		placed.append([cand.x, cand.y, species, scale, hue.get_noise_2d(cand.x, cand.y)])
	print("  trees chosen: %d in %d ms" % [placed.size(), Time.get_ticks_msec() - t])
	_canopy()
	land.deform_under_trees()


## Splats each crown onto the canopy maps (broadleaf vs conifer), then softens them.
func _canopy() -> void:
	var na := RiverLand.NA
	var cb := PackedFloat32Array()
	cb.resize(na * na)
	var cc := PackedFloat32Array()
	cc.resize(na * na)
	for p: Array in placed:
		var c := land.cell(p[0], p[1])
		var crown: float = p[3] * 0.6
		if p[2] == PINE or p[2] == SPRUCE:
			cc[c] += crown
		elif p[2] != DEAD:
			cb[c] += crown
	cb = land._blur(cb, 1)
	cc = land._blur(cc, 1)
	for c in na * na:
		land.canopy_broad[c] = clampf(cb[c] * 1.5, 0.0, 1.0)
		land.canopy_conifer[c] = clampf(cc[c] * 1.5, 0.0, 1.0)


func build_trees(parent: Node3D, mat: Material) -> void:
	var palettes := [GREEN, YELLOW, ORANGE, RED]
	var broad: Array[Instancer] = []
	for _p in palettes:
		broad.append(Instancer.new(TREE_CHUNK))
	var birch := Instancer.new(TREE_CHUNK)
	var pine := Instancer.new(TREE_CHUNK)
	var spruce := Instancer.new(TREE_CHUNK)
	var dead := Instancer.new(TREE_CHUNK)
	for p: Array in placed:
		var pos := Vector3(p[0], land.height_at(p[0], p[1]), p[1])
		var s: float = p[3]
		var yaw := rng.randf() * TAU
		var tint := Color(1, 1, 1).darkened(rng.randf() * 0.12)
		match int(p[2]):
			BROAD:
				var v: float = p[4] * 0.5 + 0.5 + rng.randf_range(-0.25, 0.25)
				broad[clampi(int(v * 4.0), 0, 3)].put(pos, yaw, s, s * rng.randf_range(0.9, 1.1), tint)
			PINE:
				pine.put(pos, yaw, s, s * rng.randf_range(0.95, 1.15), tint)
			SPRUCE:
				spruce.put(pos, yaw, s, s * rng.randf_range(0.95, 1.2), tint)
			BIRCH_TREE:
				birch.put(pos, yaw, s, s * rng.randf_range(0.95, 1.15), tint)
			DEAD:
				dead.put(pos, yaw, s, s, tint)
	var n := 0
	for k in palettes.size():
		var pal: Array = palettes[k]
		n += broad[k].build_lod(parent, Meshes.broadleaf(rng, pal[0], pal[1]), Meshes.broadleaf_far(rng, pal[0], pal[1]), mat, TREE_DETAIL, TREE_VISIBLE)
	n += birch.build_lod(parent, Meshes.birch(rng, BIRCH[0], BIRCH[1]), Meshes.birch_far(rng, BIRCH[0], BIRCH[1]), mat, TREE_DETAIL, TREE_VISIBLE)
	n += pine.build_lod(parent, Meshes.conifer(rng), Meshes.conifer_far(12.6, 3.4), mat, TREE_DETAIL, TREE_VISIBLE)
	n += spruce.build_lod(parent, Meshes.conifer(rng, Meshes.SPRUCE_LAYERS), Meshes.conifer_far(16.0, 2.7), mat, TREE_DETAIL, TREE_VISIBLE)
	n += dead.build(parent, Meshes.dead_tree(rng), mat, TREE_DETAIL, true)
	print("  trees: ", n)


# --- understory --------------------------------------------------------------

## Upright along the slope by `amount` (0 upright, 1 on the slope), turned by yaw.
func _slope_basis(x: float, z: float, yaw: float, sxz: float, sy: float, amount: float) -> Basis:
	var up := Vector3.UP.lerp(land.normal_at(x, z), amount).normalized()
	var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := up.cross(fwd).normalized()
	fwd = side.cross(up).normalized()
	return Basis(side * sxz, up * sy, fwd * sxz)


## One understory layer: `chance(cell)` is worked out once per 10 m cell and gives
## the expected share of `spacing`-sized spots there that get a plant; each must be
## clear of tree trunks (their priority radius) and of other understory (`radius`).
func _layer(spacing: float, radius: float, chance: Callable, put: Callable) -> void:
	var na := RiverLand.NA
	var per_cell := (RiverLand.A_STEP * RiverLand.A_STEP) / (spacing * spacing)
	var lim := RiverLand.HALF - 80.0
	for c in na * na:
		var cx := _ax(c % na)
		var cz := _ax(c / na)
		if absf(cx) > lim or absf(cz) > lim:
			continue
		var p: float = chance.call(c)
		if p <= 0.0:
			continue
		var expect := p * per_cell
		var count := int(expect) + (1 if rng.randf() < expect - floorf(expect) else 0)
		for _k in count:
			var px := cx + rng.randf_range(-5.0, 5.0)
			var pz := cz + rng.randf_range(-5.0, 5.0)
			if land.road_distance_at(px, pz) < Route.HALF_WIDTH + 1.5:
				continue
			if not trees.free_at(px, pz, true) or not under.free_at(px, pz, false):
				continue
			under.add(px, pz, radius, 0.0)
			put.call(px, pz, c)


func build_understory(parent: Node3D, mat: Material, grass_mat: Material, ledges: PackedVector3Array) -> void:
	var t := Time.get_ticks_msec()
	var bushes := Instancer.new(SMALL_CHUNK)
	var ferns := Instancer.new(SMALL_CHUNK)
	var rocks := Instancer.new(SMALL_CHUNK)
	var crumbled := Instancer.new(SMALL_CHUNK)
	var logs := Instancer.new(SMALL_CHUNK)
	var stumps := Instancer.new(SMALL_CHUNK)
	var boulders := Instancer.new(TREE_CHUNK)

	# bushes: thickest along the forest edge (age around 0), and by water
	_layer(3.0, 1.1, func(c: int) -> float:
		return (band(age[c], -14.0, -4.0, 6.0, 16.0) * 0.6 + land.wet[c] * 0.3 + land.heath[c] * 0.08) * exclude[c],
		func(px: float, pz: float, _c: int) -> void:
			var tint: Color = BUSH_TINTS[0] if rng.randf() < 0.45 else BUSH_TINTS[rng.randi() % BUSH_TINTS.size()]
			var s := rng.randf_range(0.6, 1.3)
			bushes.put(Vector3(px, land.height_at(px, pz), pz), rng.randf() * TAU, s, s * rng.randf_range(0.8, 1.2), tint.darkened(rng.randf() * 0.15)))
	# ferns: in the shade of the canopy where it's moist
	_layer(2.2, 0.7, func(c: int) -> float:
		var shade := clampf(land.canopy_broad[c] + land.canopy_conifer[c], 0.0, 1.0)
		return shade * (0.3 + land.moist[c]) * (0.6 + land.occl[c]) * 0.55 * exclude[c],
		func(px: float, pz: float, _c: int) -> void:
			var tint: Color = FERN_TINTS[rng.randi() % FERN_TINTS.size()]
			var s := rng.randf_range(0.8, 1.4)
			ferns.put(Vector3(px, land.height_at(px, pz) - 0.05, pz), rng.randf() * TAU, s, s, tint.darkened(rng.randf() * 0.1)))
	# mossy rocks around the conifers (their canopy map is this layer's viability)
	_layer(6.0, 1.2, func(c: int) -> float:
		return land.canopy_conifer[c] * 0.35 * exclude[c],
		func(px: float, pz: float, _c: int) -> void:
			var s := rng.randf_range(0.5, 1.4)
			rocks.put_basis(Vector3(px, land.height_at(px, pz) - s * 0.15, pz), _slope_basis(px, pz, rng.randf() * TAU, s, s * 0.7, 0.8),
				Color(0.80, 0.92, 0.72).darkened(rng.randf() * 0.2)))
	# logs and stumps in old forest, logs lying along the slope
	_layer(12.0, 1.8, func(c: int) -> float:
		return smoothstep(10.0, AGE_DEPTH, age[c]) * 0.4 * exclude[c],
		func(px: float, pz: float, _c: int) -> void:
			var y := land.height_at(px, pz) - 0.1
			if rng.randf() < 0.6:
				var s := rng.randf_range(0.7, 1.1)
				logs.put_basis(Vector3(px, y, pz), _slope_basis(px, pz, rng.randf() * TAU, s, 1.0, 1.0), Color.WHITE)
			else:
				stumps.put(Vector3(px, y, pz), rng.randf() * TAU, rng.randf_range(0.8, 1.3), rng.randf_range(0.7, 1.4), Color.WHITE))
	# crumbled rock on the scree, in the colour of the cliff it fell from
	_layer(3.0, 0.6, func(c: int) -> float:
		return land.scree[c] * 0.55,
		func(px: float, pz: float, c: int) -> void:
			var s := rng.randf_range(0.3, 1.2)
			var col: Color = land.scree_col[c]
			var tint := Color(col.r / 0.6, col.g / 0.6, col.b / 0.6).darkened(rng.randf() * 0.15)
			crumbled.put_basis(Vector3(px, land.height_at(px, pz) - s * 0.1, pz), _slope_basis(px, pz, rng.randf() * TAU, s, s * 0.7, 0.9), tint))
	# boulders on open, high and dry ground
	_layer(16.0, 1.5, func(c: int) -> float:
		return (0.04 + land.alpine[c] * 0.3 + land.heath[c] * 0.12) * smoothstep(4.0, 9.0, land.dw[c]),
		func(px: float, pz: float, _c: int) -> void:
			var s := rng.randf_range(0.8, 3.5)
			boulders.put_basis(Vector3(px, land.height_at(px, pz) - s * 0.15, pz), _slope_basis(px, pz, rng.randf() * TAU, s, s * rng.randf_range(0.6, 1.0), 0.6),
				Color(1, 1, 1).darkened(rng.randf() * 0.2)))
	# plants on the cliff ledges
	var ledge_plants := 0
	for p in ledges:
		if rng.randf() > 0.35:
			continue
		var tint: Color = BUSH_TINTS[rng.randi() % BUSH_TINTS.size()]
		var s := rng.randf_range(0.4, 0.8)
		bushes.put(p - Vector3(0.0, 0.1, 0.0), rng.randf() * TAU, s, s, tint)
		ledge_plants += 1

	var n := bushes.build(parent, Meshes.bush(rng), mat, SMALL_VISIBLE, true)
	n += rocks.build(parent, Meshes.rock(rng), mat, SMALL_VISIBLE, true)
	n += crumbled.build(parent, Meshes.rock(rng), mat, SMALL_VISIBLE, true)
	n += logs.build(parent, Meshes.fallen_log(rng), mat, SMALL_VISIBLE, true)
	n += stumps.build(parent, Meshes.stump(rng), mat, SMALL_VISIBLE, true)
	n += boulders.build(parent, Meshes.rock(rng), mat, TREE_VISIBLE, true)
	var nf := ferns.build(parent, Meshes.fern(rng), grass_mat, FERN_VISIBLE, false)
	print("  understory: %d props, %d ferns, %d on ledges, in %d ms" % [n, nf, ledge_plants, Time.get_ticks_msec() - t])
