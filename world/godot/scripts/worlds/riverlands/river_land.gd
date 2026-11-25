class_name RiverLand
extends RefCounted
## Riverlands terrain, built in the order big open-world pipelines use:
##   1. a base height field (warped hills, a basin tilted towards an outlet, mountains),
##      worn by droplet erosion (gullies, fans);
##   2. freshwater: where rain would run (priority flood + flow accumulation), which
##      carves valleys, then rivers and lakes from a second pass;
##   3. analysis maps on a 10 m grid: slope, concavity, sun exposure, moisture,
##      distance to water;
##   4. biome fields from those maps (forest, conifer share, wetland, heath, alpine),
##      read by the scatter and by the ground colours.

const HALF := 1800.0
const A_STEP := 5.0           # analysis grid (m)
const NA := 721
const STEP := 5.0             # render grid
const N := 721
const FAR := 10000.0
const SKIRT_LEVELS := 36
const ROAD_REACH := 48.0
const RIVER_ACC := 450.0      # upstream area (in 100 m² units) before a cell is a river: 0.045 km²
const LAKE_DEPTH := 2.0       # shallower hollows silt up into flats
const SHEET_REACH := 12.0     # m: the water sheet extends this far under the banks
const SILT := 0.8             # how much of each hollow fills with sediment
const DROPLETS := 150000      # erosion: rain drops, and how each one behaves
const DROP_STEPS := 60
const DROP_INERTIA := 0.05
const DROP_CAPACITY := 4.0
const DROP_MIN_SLOPE := 0.01
const DROP_DEPOSIT := 0.3
const DROP_ERODE := 0.3
const DROP_GRAVITY := 4.0
const DROP_EVAPORATE := 0.02
const DRY := -1e9
const SUN_PITCH := -30.0
const SUN_YAW := -60.0
const SNOW := 600.0

const DX := [1, -1, 0, 0, 1, 1, -1, -1]
const DZ := [0, 0, 1, -1, 1, -1, 1, -1]

# autumn palette (sRGB)
const MEADOW := Color(0.52, 0.66, 0.28)
const MEADOW_GOLD := Color(0.70, 0.70, 0.32)
const HEATH := Color(0.66, 0.58, 0.36)
const HEATHER := Color(0.55, 0.40, 0.52)
const LITTER := Color(0.62, 0.44, 0.22)
const LITTER_FALL := Color(0.74, 0.46, 0.20)   # fresh autumn leaves under the trees
const NEEDLES := Color(0.33, 0.40, 0.22)
const LUSH := Color(0.30, 0.52, 0.24)
const MUD := Color(0.50, 0.44, 0.32)
const ROCK := Color(0.56, 0.53, 0.49)
const ROCK_HIGH := Color(0.50, 0.50, 0.54)
const SNOW_COLOR := Color(0.95, 0.96, 0.99)
const DIRT := Color(0.62, 0.52, 0.36)

var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var warp := FastNoiseLite.new()
var ridges := FastNoiseLite.new()
var patches := FastNoiseLite.new()
var tint := FastNoiseLite.new()
var outlet := Vector2.RIGHT
var sun_dir := Vector3.UP

# analysis grid (NA x NA)
var ha := PackedFloat32Array()      # final height
var acc := PackedFloat32Array()     # cells draining through
var wl := PackedFloat32Array()      # water surface, DRY where dry
var dw := PackedFloat32Array()      # distance to water (m)
var wnear := PackedFloat32Array()   # level of the nearest water
var slope := PackedFloat32Array()   # 1 - normal.y
var conc := PackedFloat32Array()    # concavity: + in hollows (m)
var sun := PackedFloat32Array()     # 0..1
var moist := PackedFloat32Array()
var forest := PackedFloat32Array()
var conifer := PackedFloat32Array()
var wet := PackedFloat32Array()
var heath := PackedFloat32Array()
var alpine := PackedFloat32Array()
var ground := PackedColorArray()
var occl := PackedFloat32Array()    # share of the sky hidden by the land around, 0..1
var wind_x := PackedFloat32Array()  # wind direction, bending around hills
var wind_z := PackedFloat32Array()
# written by later tools (cliffs, ecology), read by the ground colours
var scree := PackedFloat32Array()   # rock fall below cliffs, 0..1
var scree_col := PackedColorArray()
var canopy_broad := PackedFloat32Array()
var canopy_conifer := PackedFloat32Array()
var canopy_col := PackedColorArray()   # average crown colour (sRGB), for the far ground
var woods := FastNoiseLite.new()       # forest patches on the far hills (the skirt)
var strata: RiverCliffs             # cliff layer colours, once the cliffs are made

# render grid (N x N)
var heights := PackedFloat32Array()
var road_d := PackedFloat32Array()


func setup(seed: int) -> void:
	hills.seed = seed
	hills.frequency = 0.0011
	hills.fractal_octaves = 5
	detail.seed = seed + 1
	detail.frequency = 0.03
	detail.fractal_octaves = 2
	warp.seed = seed + 2
	warp.frequency = 0.0009
	ridges.seed = seed + 3
	ridges.frequency = 0.0007
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 5
	patches.seed = seed + 4
	patches.frequency = 0.0045
	patches.fractal_octaves = 3
	tint.seed = seed + 5
	tint.frequency = 0.006
	tint.fractal_octaves = 3
	woods.seed = seed + 6
	woods.frequency = 0.0022
	woods.fractal_octaves = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a := rng.randf() * TAU
	outlet = Vector2(cos(a), sin(a))
	sun_dir = Basis.from_euler(Vector3(deg_to_rad(SUN_PITCH), deg_to_rad(SUN_YAW), 0.0)).z


## The land before water shapes it.
func base(x: float, z: float) -> float:
	var px := x + warp.get_noise_2d(x, z) * 160.0
	var pz := z + warp.get_noise_2d(x + 917.0, z - 411.0) * 160.0
	var h := hills.get_noise_2d(px, pz) * 80.0
	h -= clampf(outlet.dot(Vector2(x, z)), -HALF, HALF) * 0.035   # the basin drains to the outlet
	var r := Vector2(x, z).length()
	var m := smoothstep(HALF * 0.6, HALF * 1.85, r)   # mountains rise past ~60 % of the way out
	if m > 0.0:
		var gap := smoothstep(0.80, 0.96, outlet.dot(Vector2(x, z) / maxf(r, 1.0)))
		h += m * (1.0 - 0.85 * gap) * (180.0 + 650.0 * (ridges.get_noise_2d(x, z) * 0.5 + 0.5))
	return h


func _ax(i: int) -> float:
	return -HALF + i * A_STEP


func _edge(x: float, z: float) -> float:
	return smoothstep(HALF - 260.0, HALF - 40.0, maxf(absf(x), absf(z)))


func build() -> void:
	var t := Time.get_ticks_msec()
	var n := NA * NA
	var h0 := PackedFloat32Array()
	h0.resize(n)
	for j in NA:
		for i in NA:
			h0[j * NA + i] = base(_ax(i), _ax(j))

	_erode(h0, int(hills.seed))
	print("  erosion: %d ms" % (Time.get_ticks_msec() - t))

	# 1st pass: let the water carve valleys; hollows mostly silt up into flat plains
	var flood := _flood(h0)
	var a0 := _accumulate(flood)
	var silted: PackedFloat32Array = flood.filled
	var inc := PackedFloat32Array()
	inc.resize(n)
	for c in n:
		inc[c] = minf(24.0, 3.2 * log(1.0 + a0[c] / 6.0))
	inc = blur_m(blur_m(inc, 20.0), 20.0)
	var h1 := PackedFloat32Array()
	h1.resize(n)
	for j in NA:
		for i in NA:
			var c := j * NA + i
			var keep := 1.0 - _edge(_ax(i), _ax(j))
			h1[c] = lerpf(h0[c], silted[c] - 0.002 * a0[c] / (a0[c] + 50.0), SILT * keep) - inc[c] * keep
	print("  valleys carved: %d ms" % (Time.get_ticks_msec() - t))

	# 2nd pass: rivers and lakes
	flood = _flood(h1)
	acc = _accumulate(flood)
	var filled: PackedFloat32Array = flood.filled
	ha = h1.duplicate()
	wl.resize(n)
	wl.fill(DRY)
	var widen := []
	var lake := _lakes(filled, h1)
	for c in n:
		var x := _ax(c % NA)
		var z := _ax(c / NA)
		if _edge(x, z) > 0.0:
			continue
		if lake[c] != 0:
			wl[c] = filled[c] - 0.2
		elif acc[c] >= RIVER_ACC:
			var depth := clampf(0.8 + 0.5 * log(acc[c] / RIVER_ACC), 0.8, 3.5)
			wl[c] = h1[c] - 0.3
			ha[c] = wl[c] - depth
			if acc[c] >= RIVER_ACC * 12.0:
				widen.append(c)
	# keep channels 4-connected: where water steps to a diagonal cell, also wet the
	# lower of the two cells between them (else banks split a stream into pools)
	var parent: PackedInt32Array = flood.parent
	for c in n:
		if wl[c] == DRY or lake[c] != 0:
			continue
		var p := parent[c]
		if p < 0 or wl[p] == DRY:
			continue
		var ci := c % NA
		var cj := c / NA
		var pi := p % NA
		var pj := p / NA
		if ci == pi or cj == pj:
			continue
		var a := cj * NA + pi
		var b := pj * NA + ci
		var mid := a if h1[a] < h1[b] else b
		if wl[mid] == DRY:
			wl[mid] = (wl[c] + wl[p]) * 0.5
			ha[mid] = minf(ha[mid], (ha[c] + ha[p]) * 0.5)
	for c in widen:
		for d in 8:
			var ni: int = c % NA + DX[d]
			var nj: int = c / NA + DZ[d]
			if ni < 0 or nj < 0 or ni >= NA or nj >= NA:
				continue
			var nb := nj * NA + ni
			if wl[nb] == DRY and h1[nb] > wl[c]:
				wl[nb] = wl[c]
				ha[nb] = minf(ha[nb], wl[c] - 0.8)
	# soften the beds: the cut is per cell, so the banks dropped as square steps; a
	# blurred copy of the cut slopes them down to the water instead, and the shoreline
	# (where the ground rises through the water sheet) follows that slope
	var cut := PackedFloat32Array()
	cut.resize(n)
	for c in n:
		cut[c] = maxf(h1[c] - ha[c], 0.0)
	var soft := blur_m(blur_m(cut, A_STEP), A_STEP)
	for c in n:
		var bank := h1[c] - soft[c] * 1.4
		ha[c] = minf(ha[c], bank) if wl[c] != DRY else minf(h1[c], bank)
	print("  rivers and lakes: %d ms" % (Time.get_ticks_msec() - t))

	_analyse()
	print("  analysis and biomes: %d ms" % (Time.get_ticks_msec() - t))


## Droplet erosion: rain drops start at random, run downhill with a little inertia,
## pick up sediment while they speed up (up to a capacity that grows with slope, speed
## and water) and drop it when they slow down or overflow, then evaporate. That cuts
## gullies into the slopes and leaves fans where they flatten out. The change is
## softened once before it's applied, to keep it from pitting single cells.
func _erode(h: PackedFloat32Array, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 7
	var before := h.duplicate()
	for _d in DROPLETS:
		var px := rng.randf_range(1.0, NA - 2.0)
		var pz := rng.randf_range(1.0, NA - 2.0)
		if _edge(-HALF + px * A_STEP, -HALF + pz * A_STEP) > 0.0:
			continue
		var dx := 0.0
		var dz := 0.0
		var speed := 1.0
		var water := 1.0
		var sediment := 0.0
		for _s in DROP_STEPS:
			var i := int(px)
			var j := int(pz)
			var u := px - i
			var v := pz - j
			var k := j * NA + i
			var h00 := h[k]
			var h10 := h[k + 1]
			var h01 := h[k + NA]
			var h11 := h[k + NA + 1]
			var gx := (h10 - h00) * (1.0 - v) + (h11 - h01) * v
			var gz := (h01 - h00) * (1.0 - u) + (h11 - h10) * u
			var here := lerpf(lerpf(h00, h10, u), lerpf(h01, h11, u), v)
			dx = dx * DROP_INERTIA - gx * (1.0 - DROP_INERTIA)
			dz = dz * DROP_INERTIA - gz * (1.0 - DROP_INERTIA)
			var l := sqrt(dx * dx + dz * dz)
			if l < 1e-6:
				break
			dx /= l
			dz /= l
			var nx := px + dx
			var nz := pz + dz
			if nx < 1.0 or nz < 1.0 or nx >= NA - 2.0 or nz >= NA - 2.0:
				break
			var ni := int(nx)
			var nj := int(nz)
			var nk := nj * NA + ni
			var nu := nx - ni
			var nv := nz - nj
			var there := lerpf(lerpf(h[nk], h[nk + 1], nu), lerpf(h[nk + NA], h[nk + NA + 1], nu), nv)
			var dh := there - here
			var cap := maxf(-dh, DROP_MIN_SLOPE) * speed * water * DROP_CAPACITY
			var w00 := (1.0 - u) * (1.0 - v)
			var w10 := u * (1.0 - v)
			var w01 := (1.0 - u) * v
			var w11 := u * v
			if sediment > cap or dh > 0.0:
				# uphill: fill the pit behind; overloaded: drop some
				var drop := minf(dh, sediment) if dh > 0.0 else (sediment - cap) * DROP_DEPOSIT
				sediment -= drop
				h[k] += drop * w00
				h[k + 1] += drop * w10
				h[k + NA] += drop * w01
				h[k + NA + 1] += drop * w11
			else:
				var take := minf((cap - sediment) * DROP_ERODE, -dh)
				sediment += take
				h[k] -= take * w00
				h[k + 1] -= take * w10
				h[k + NA] -= take * w01
				h[k + NA + 1] -= take * w11
			speed = sqrt(maxf(0.0, speed * speed - dh * DROP_GRAVITY))
			water *= 1.0 - DROP_EVAPORATE
			px = nx
			pz = nz
	var change := PackedFloat32Array()
	change.resize(NA * NA)
	for c in NA * NA:
		change[c] = h[c] - before[c]
	change = _blur(change, 1)
	for c in NA * NA:
		h[c] = before[c] + change[c]


## Lake cells (hollows filled deeper than LAKE_DEPTH), dropping every lake that reaches
## into the edge zone: clipping it there would leave a straight shore.
func _lakes(filled: PackedFloat32Array, h: PackedFloat32Array) -> PackedByteArray:
	var n := NA * NA
	var lake := PackedByteArray()
	lake.resize(n)
	for c in n:
		if filled[c] - h[c] > LAKE_DEPTH:
			lake[c] = 1
	var seen := PackedByteArray()
	seen.resize(n)
	for start in n:
		if lake[start] == 0 or seen[start] != 0:
			continue
		var group := PackedInt32Array([start])
		seen[start] = 1
		var k := 0
		var touches_edge := false
		while k < group.size():
			var c := group[k]
			k += 1
			if _edge(_ax(c % NA), _ax(c / NA)) > 0.0:
				touches_edge = true
			for d in 4:
				var ni: int = c % NA + DX[d]
				var nj: int = c / NA + DZ[d]
				if ni < 0 or nj < 0 or ni >= NA or nj >= NA:
					continue
				var nb := nj * NA + ni
				if lake[nb] != 0 and seen[nb] == 0:
					seen[nb] = 1
					group.append(nb)
		if touches_edge:
			for c in group:
				lake[c] = 0
	return lake


## Priority flood: fills every hollow up to its spill height (lakes) and records where
## each cell drains (`parent`) and the order cells were reached in.
func _flood(h: PackedFloat32Array) -> Dictionary:
	var n := NA * NA
	var filled := h.duplicate()
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var order := PackedInt32Array()
	var heap := MinHeap.new()
	for k in NA:
		for c in [k, (NA - 1) * NA + k, k * NA, k * NA + NA - 1]:
			if closed[c] == 0:
				closed[c] = 1
				heap.push(filled[c], c)
	while not heap.is_empty():
		var c := heap.pop()
		order.append(c)
		var ci := c % NA
		var cj := c / NA
		for d in 8:
			var ni: int = ci + DX[d]
			var nj: int = cj + DZ[d]
			if ni < 0 or nj < 0 or ni >= NA or nj >= NA:
				continue
			var nb := nj * NA + ni
			if closed[nb] != 0:
				continue
			closed[nb] = 1
			filled[nb] = maxf(filled[nb], filled[c] + 0.001)
			parent[nb] = c
			heap.push(filled[nb], nb)
	return {"filled": filled, "parent": parent, "order": order}


func _accumulate(flood: Dictionary) -> PackedFloat32Array:
	var order: PackedInt32Array = flood.order
	var parent: PackedInt32Array = flood.parent
	var a := PackedFloat32Array()
	a.resize(NA * NA)
	a.fill(A_STEP * A_STEP / 100.0)   # each cell's own rain, as area in 100 m² units
	for k in range(order.size() - 1, -1, -1):
		var c := order[k]
		if parent[c] >= 0:
			a[parent[c]] += a[c]
	return a


## Box blur of radius `metres`.
func blur_m(src: PackedFloat32Array, metres: float) -> PackedFloat32Array:
	return _blur(src, maxi(1, int(round(metres / A_STEP))))


## Box blur of radius r cells, separable.
func _blur(src: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(NA * NA)
	var out := PackedFloat32Array()
	out.resize(NA * NA)
	var w := 2 * r + 1
	for j in NA:
		var sum := 0.0
		for k in range(-r, r + 1):
			sum += src[j * NA + clampi(k, 0, NA - 1)]
		for i in NA:
			tmp[j * NA + i] = sum / w
			sum += src[j * NA + mini(i + r + 1, NA - 1)] - src[j * NA + maxi(i - r, 0)]
	for i in NA:
		var sum := 0.0
		for k in range(-r, r + 1):
			sum += tmp[clampi(k, 0, NA - 1) * NA + i]
		for j in NA:
			out[j * NA + i] = sum / w
			sum += tmp[mini(j + r + 1, NA - 1) * NA + i] - tmp[maxi(j - r, 0) * NA + i]
	return out


func _analyse() -> void:
	var n := NA * NA
	dw.resize(n)
	wnear.resize(n)
	slope.resize(n)
	conc.resize(n)
	sun.resize(n)
	moist.resize(n)
	forest.resize(n)
	conifer.resize(n)
	wet.resize(n)
	heath.resize(n)
	alpine.resize(n)
	scree.resize(n)
	scree_col.resize(n)
	canopy_broad.resize(n)
	canopy_conifer.resize(n)
	canopy_col.resize(n)
	ground.resize(n)

	# distance to water: two-pass chamfer, carrying the nearest water level along
	for c in n:
		dw[c] = 0.0 if wl[c] != DRY else 1e9
		wnear[c] = wl[c]
	var diag := A_STEP * 1.4142
	for j in NA:
		for i in NA:
			_relax(i, j, i - 1, j, A_STEP)
			_relax(i, j, i, j - 1, A_STEP)
			_relax(i, j, i - 1, j - 1, diag)
			_relax(i, j, i + 1, j - 1, diag)
	for j in range(NA - 1, -1, -1):
		for i in range(NA - 1, -1, -1):
			_relax(i, j, i + 1, j, A_STEP)
			_relax(i, j, i, j + 1, A_STEP)
			_relax(i, j, i + 1, j + 1, diag)
			_relax(i, j, i - 1, j + 1, diag)

	var smooth := blur_m(blur_m(ha, 60.0), 60.0)
	for j in NA:
		for i in NA:
			var c := j * NA + i
			var x := _ax(i)
			var z := _ax(j)
			var l := ha[j * NA + maxi(i - 1, 0)]
			var r := ha[j * NA + mini(i + 1, NA - 1)]
			var d := ha[maxi(j - 1, 0) * NA + i]
			var u := ha[mini(j + 1, NA - 1) * NA + i]
			var nrm := Vector3(l - r, 2.0 * A_STEP, d - u).normalized()
			var h := ha[c]
			slope[c] = 1.0 - nrm.y
			conc[c] = smooth[c] - h
			sun[c] = clampf(nrm.dot(sun_dir) / maxf(sun_dir.y, 0.2) * 0.5, 0.0, 1.0)
			moist[c] = clampf(0.55 * exp(-dw[c] / 45.0) + 0.3 * clampf(log(acc[c]) / 7.0, 0.0, 1.0)
				+ clampf(conc[c] / 15.0, -0.3, 0.3), 0.0, 1.0)

			var pn := patches.get_noise_2d(x, z)
			var al := maxf(smoothstep(230.0, 330.0, h + 40.0 * pn), smoothstep(0.32, 0.5, slope[c]))
			var we := exp(-dw[c] / 14.0) * (1.0 - smoothstep(0.06, 0.18, slope[c])) * (1.0 - al)
			var fo := smoothstep(0.0, 0.45, pn * 0.9 + moist[c] * 0.7 - 0.12) * (1.0 - al) * (1.0 - we * 0.8)
			fo *= 1.0 - smoothstep(0.25, 0.4, slope[c]) * 0.5
			var co := clampf(smoothstep(60.0, 190.0, h) + (0.45 - sun[c]) * 0.9 + patches.get_noise_2d(x * 3.0, z * 3.0) * 0.3, 0.0, 1.0)
			var he := smoothstep(0.7, 0.95, sun[c] + (1.0 - moist[c]) * 0.3 - conc[c] * 0.03) * (1.0 - fo) * (1.0 - al) * (1.0 - we)
			alpine[c] = al
			wet[c] = we
			forest[c] = fo
			conifer[c] = co
			heath[c] = he
			ground[c] = _ground_color(x, z, h, c)
	_occlusion()
	_wind()


## Horizon occlusion, sampled on every other cell: in 8 directions, the steepest rise
## of the land within 140 m; the average of sin(angle) is the share of sky hidden.
func _occlusion() -> void:
	var n := NA * NA
	occl.resize(n)
	var half := (NA + 1) / 2
	var coarse := PackedFloat32Array()
	coarse.resize(half * half)
	var dists := [15.0 / A_STEP, 35.0 / A_STEP, 70.0 / A_STEP, 140.0 / A_STEP]   # in cells
	for hj in half:
		for hi in half:
			var i := mini(hi * 2, NA - 1)
			var j := mini(hj * 2, NA - 1)
			var h := ha[j * NA + i]
			var sum := 0.0
			for d in 8:
				var best := 0.0
				for r: float in dists:
					var si := clampi(i + int(round(DX[d] * r)), 0, NA - 1)
					var sj := clampi(j + int(round(DZ[d] * r)), 0, NA - 1)
					var dist := r * A_STEP * (1.4142 if d >= 4 else 1.0)
					best = maxf(best, (ha[sj * NA + si] - h) / dist)
				sum += best / sqrt(1.0 + best * best)
			coarse[hj * half + hi] = sum / 8.0
	for j in NA:
		for i in NA:
			var fx := i * 0.5
			var fz := j * 0.5
			var i0 := mini(int(fx), half - 2)
			var j0 := mini(int(fz), half - 2)
			var tx := fx - i0
			var tz := fz - j0
			var k := j0 * half + i0
			occl[j * NA + i] = lerpf(lerpf(coarse[k], coarse[k + 1], tx), lerpf(coarse[k + half], coarse[k + half + 1], tx), tz)


## Prevailing wind (the grass shader's direction), turned to flow around hills: the
## part blowing up or down a broad slope is taken out.
func _wind() -> void:
	var n := NA * NA
	wind_x.resize(n)
	wind_z.resize(n)
	var base := Vector2(0.8, 0.6).normalized()
	var broad := blur_m(blur_m(ha, 80.0), 80.0)
	for j in NA:
		for i in NA:
			var c := j * NA + i
			var g := Vector2(broad[j * NA + mini(i + 1, NA - 1)] - broad[j * NA + maxi(i - 1, 0)],
				broad[mini(j + 1, NA - 1) * NA + i] - broad[maxi(j - 1, 0) * NA + i]) / (2.0 * A_STEP)
			var w := base
			var gl := g.length()
			if gl > 0.001:
				var gn := g / gl
				w -= gn * base.dot(gn) * smoothstep(0.02, 0.15, gl)
			w = w.normalized() if w.length() > 0.05 else base
			wind_x[c] = w.x
			wind_z[c] = w.y


## Wind direction at (x, z).
func wind_at(x: float, z: float) -> Vector2:
	var w := Vector2(field(wind_x, x, z), field(wind_z, x, z))
	return w.normalized() if w.length() > 0.01 else Vector2(0.8, 0.6).normalized()


## Horizontal direction towards the nearest water.
func water_dir(x: float, z: float) -> Vector2:
	var g := Vector2(field(dw, x + A_STEP, z) - field(dw, x - A_STEP, z), field(dw, x, z + A_STEP) - field(dw, x, z - A_STEP))
	return -g.normalized() if g.length() > 0.01 else Vector2.ZERO


## Soil held together by roots: the forest floor sits a little higher than the meadow
## (up to 0.3 m where the canopy is thickest), except along the road and by water. Each
## trunk also gets its own mound (RiverEcology.build_trees).
func deform_under_trees() -> void:
	for j in N:
		var z := _rx(j)
		for i in N:
			var x := _rx(i)
			var k := j * N + i
			var cover := clampf(field(canopy_broad, x, z) + field(canopy_conifer, x, z), 0.0, 1.0)
			if cover <= 0.01:
				continue
			var keep := smoothstep(Route.HALF_WIDTH + 4.0, Route.HALF_WIDTH + 14.0, road_d[k]) * smoothstep(6.0, 18.0, field(dw, x, z))
			heights[k] += 0.3 * cover * keep


func _relax(i: int, j: int, ni: int, nj: int, cost: float) -> void:
	if ni < 0 or nj < 0 or ni >= NA or nj >= NA:
		return
	var c := j * NA + i
	var nb := nj * NA + ni
	if dw[nb] + cost < dw[c]:
		dw[c] = dw[nb] + cost
		wnear[c] = wnear[nb]


func _ground_color(x: float, z: float, h: float, c: int) -> Color:
	var t := tint.get_noise_2d(x, z) * 0.5 + 0.5
	var col := MEADOW.lerp(MEADOW_GOLD, smoothstep(0.35, 0.75, t))
	col = col.lerp(HEATH, heath[c])
	col = col.lerp(HEATHER, heath[c] * smoothstep(0.5, 0.7, tint.get_noise_2d(x * 2.7 + 300.0, z * 2.7)))
	col = col.lerp(LITTER, forest[c] * (1.0 - conifer[c]) * 0.4)
	col = col.lerp(NEEDLES, forest[c] * conifer[c] * 0.4)
	col = col.lerp(LUSH, wet[c])
	col = col.lerp(ROCK, alpine[c])
	col = col.lerp(ROCK_HIGH, smoothstep(250.0, 400.0, h))
	return col


## Bilinear sample of an analysis map.
func field(a: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + HALF) / A_STEP, 0.0, NA - 1.001)
	var fz := clampf((z + HALF) / A_STEP, 0.0, NA - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * NA + i
	return lerpf(lerpf(a[k], a[k + 1], tx), lerpf(a[k + NA], a[k + NA + 1], tx), tz)


func cell(x: float, z: float) -> int:
	var i := clampi(int(round((x + HALF) / A_STEP)), 0, NA - 1)
	var j := clampi(int(round((z + HALF) / A_STEP)), 0, NA - 1)
	return j * NA + i


## Water surface at the nearest analysis cell, or DRY.
func water_at(x: float, z: float) -> float:
	return wl[cell(x, z)]


func ground_at(x: float, z: float) -> Color:
	var fx := clampf((x + HALF) / A_STEP, 0.0, NA - 1.001)
	var fz := clampf((z + HALF) / A_STEP, 0.0, NA - 1.001)
	var i := int(fx)
	var j := int(fz)
	var k := j * NA + i
	return ground[k].lerp(ground[k + 1], fx - i).lerp(ground[k + NA].lerp(ground[k + NA + 1], fx - i), fz - j)


## Ground height for the road: never below the water next to it.
func road_floor(x: float, z: float) -> float:
	var w := water_at(x, z)
	return w + 2.2 if w != DRY else -1e9


# --- render grid -------------------------------------------------------------

func _rx(i: int) -> float:
	return -HALF + i * STEP


func make_heights() -> void:
	heights.resize(N * N)
	road_d.resize(N * N)
	for j in N:
		var z := _rx(j)
		for i in N:
			var x := _rx(i)
			var near_water := 1.0 - exp(-field(dw, x, z) / 12.0)
			heights[j * N + i] = field(ha, x, z) + detail.get_noise_2d(x, z) * 0.8 * near_water
			road_d[j * N + i] = ROAD_REACH


## Flattens the land under the road, except where it crosses water (bridges).
func carve(route: Route) -> void:
	var road_h := PackedFloat32Array()
	road_h.resize(N * N)
	var reach := int(ceil(ROAD_REACH / STEP))
	for m in range(0, route.count(), 2):
		var p := route.points[m]
		var ci := int(round((p.x + HALF) / STEP))
		var cj := int(round((p.z + HALF) / STEP))
		for j in range(maxi(cj - reach, 0), mini(cj + reach, N - 1) + 1):
			var dz := _rx(j) - p.z
			for i in range(maxi(ci - reach, 0), mini(ci + reach, N - 1) + 1):
				var dx := _rx(i) - p.x
				var d := sqrt(dx * dx + dz * dz)
				var k := j * N + i
				if d < road_d[k]:
					road_d[k] = d
					road_h[k] = p.y
	for k in N * N:
		if road_d[k] < ROAD_REACH:
			var x := _rx(k % N)
			var z := _rx(k / N)
			var w := field(dw, x, z)
			var t := smoothstep(Route.HALF_WIDTH + 8.0, ROAD_REACH, road_d[k])
			t = maxf(t, 1.0 - smoothstep(8.0, 20.0, w))   # leave river banks and beds alone, slope up to the road beyond
			heights[k] = lerpf(road_h[k] - 0.15, heights[k], t)


func _sample(a: PackedFloat32Array, x: float, z: float, outside: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	if fx < 0.0 or fz < 0.0 or fx >= N - 1 or fz >= N - 1:
		return outside
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * N + i
	return lerpf(lerpf(a[k], a[k + 1], tx), lerpf(a[k + N], a[k + N + 1], tx), tz)


func height_at(x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	if fx < 0.0 or fz < 0.0 or fx >= N - 1 or fz >= N - 1:
		return base(x, z)
	return _sample(heights, x, z, 0.0)


func road_distance_at(x: float, z: float) -> float:
	return _sample(road_d, x, z, ROAD_REACH)


func normal_at(x: float, z: float) -> Vector3:
	var e := STEP
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e,
		height_at(x, z - e) - height_at(x, z + e)).normalized()


## Ground colour for a render vertex: the biome colour plus mud by the water, snow,
## rock on steep ground and dirt along the road.
func vertex_color(x: float, z: float, h: float, ny: float, rd: float) -> Color:
	var c := ground_at(x, z)
	var wn := field(wnear, x, z)
	if wn > DRY * 0.5:
		c = c.lerp(MUD, (1.0 - smoothstep(wn + 0.3, wn + 1.6, h)) * (1.0 - smoothstep(10.0, 30.0, field(dw, x, z))))
	# what the trees drop: leaf litter under broadleaves, needles under conifers
	c = c.lerp(LITTER_FALL, clampf(field(canopy_broad, x, z), 0.0, 1.0) * 0.75)
	c = c.lerp(NEEDLES, clampf(field(canopy_conifer, x, z), 0.0, 1.0) * 0.7)
	# rock fall below cliffs keeps the colour of the layer it came from
	var sc := field(scree, x, z)
	if sc > 0.01:
		var k := cell(x, z)
		c = c.lerp(scree_col[k].darkened(0.08), clampf(sc, 0.0, 1.0) * 0.85)
	var rock := ROCK if strata == null else strata.color_at(x, h, z)
	c = c.lerp(rock, 1.0 - smoothstep(0.62, 0.8, ny))
	c = c.lerp(SNOW_COLOR, smoothstep(SNOW - 40.0, SNOW + 20.0, h + 60.0 * tint.get_noise_2d(x, z)) * smoothstep(0.55, 0.72, ny))
	c = c.lerp(DIRT, 1.0 - smoothstep(Route.HALF_WIDTH + 0.5, Route.HALF_WIDTH + 2.5, rd))
	return c


## Forest on the far hills (outside the simulated basin): patches on lower, gentler
## slopes. Colour (sRGB) and cover in alpha; conifers higher up.
func skirt_woods(x: float, z: float, h: float, ny: float) -> Color:
	var cover := smoothstep(-0.1, 0.25, woods.get_noise_2d(x, z)) * (1.0 - smoothstep(480.0, 620.0, h)) \
		* smoothstep(0.6, 0.78, ny) * smoothstep(-30.0, 10.0, h)
	if cover <= 0.0:
		return Color(0, 0, 0, 0)
	var conifer := smoothstep(220.0, 380.0, h + 80.0 * tint.get_noise_2d(x * 2.0, z * 2.0))
	var hue := woods.get_noise_2d(x * 4.0 + 900.0, z * 4.0)
	var col := RiverEcology.crown_color(RiverEcology.SPRUCE if conifer > 0.5 else RiverEcology.BROAD, hue)
	col.a = cover
	return col


func _far_color(x: float, z: float, h: float, ny: float) -> Color:
	var t := tint.get_noise_2d(x, z) * 0.5 + 0.5
	var c := NEEDLES.lerp(MEADOW_GOLD, t * 0.6)
	c = c.lerp(ROCK, 1.0 - smoothstep(0.62, 0.8, ny))
	c = c.lerp(ROCK_HIGH, smoothstep(250.0, 400.0, h))
	c = c.lerp(SNOW_COLOR, smoothstep(SNOW - 40.0, SNOW + 20.0, h + 60.0 * (t - 0.5) * 2.0) * smoothstep(0.55, 0.72, ny))
	return c


## CUSTOM0 for a ground vertex: the canopy colour above it and its cover (0..1), which
## the ground shader blends in with distance so far forests read as forests.
func _custom_canopy(b: MeshBuilder, x: float, z: float) -> void:
	var cover := clampf(field(canopy_broad, x, z) + field(canopy_conifer, x, z), 0.0, 1.0)
	var col := canopy_col[cell(x, z)]
	if _edge(x, z) > 0.0:   # blend into the far woods at the edge of the basin
		var w := skirt_woods(x, z, height_at(x, z), 1.0)
		var e := _edge(x, z)
		col = col.lerp(Color(w.r, w.g, w.b), e) if cover > 0.01 else Color(w.r, w.g, w.b)
		cover = lerpf(cover, w.a, e)
	b.custom.append_array(PackedFloat32Array([col.r, col.g, col.b, cover]))


func _grid_normal(i: int, j: int) -> Vector3:
	var l := heights[j * N + maxi(i - 1, 0)]
	var r := heights[j * N + mini(i + 1, N - 1)]
	var d := heights[maxi(j - 1, 0) * N + i]
	var u := heights[mini(j + 1, N - 1) * N + i]
	return Vector3(l - r, 2.0 * STEP, d - u).normalized()


func build_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	for j in N:
		var z := _rx(j)
		for i in N:
			var x := _rx(i)
			var k := j * N + i
			var n := _grid_normal(i, j)
			b.add(Vector3(x, heights[k], z), n, vertex_color(x, z, heights[k], n.y, road_d[k]))
			_custom_canopy(b, x, z)
	for j in N - 1:
		for i in N - 1:
			var k := j * N + i
			b.tri(k, k + 1, k + N)
			b.tri(k + 1, k + N + 1, k + N)

	# skirt out to the horizon, sharing the edge vertices
	var prev := PackedInt32Array()
	for i in N - 1:
		prev.append(i)
	for j in N - 1:
		prev.append(j * N + N - 1)
	for i in range(N - 1, 0, -1):
		prev.append((N - 1) * N + i)
	for j in range(N - 1, 0, -1):
		prev.append(j * N)
	var edge := prev.duplicate()
	var p_count := edge.size()
	for l in range(1, SKIRT_LEVELS + 1):
		var t := pow(float(l) / SKIRT_LEVELS, 2.0)
		var row := PackedInt32Array()
		for a in p_count:
			var inner := b.verts[edge[a]]
			var dir := Vector2(inner.x, inner.z)
			var r0 := dir.length()
			var r := lerpf(r0, FAR, t)
			var x := dir.x / r0 * r
			var z := dir.y / r0 * r
			var h := base(x, z)
			var e := maxf(STEP, r * 0.004)
			var n := Vector3(base(x - e, z) - base(x + e, z), 2.0 * e, base(x, z - e) - base(x, z + e)).normalized()
			row.append(b.add(Vector3(x, h, z), n, _far_color(x, z, h, n.y)))
			var w := skirt_woods(x, z, h, n.y)
			b.custom.append_array(PackedFloat32Array([w.r, w.g, w.b, w.a]))
		for a in p_count:
			var a2 := (a + 1) % p_count
			b.tri(prev[a], prev[a2], row[a])
			b.tri(prev[a2], row[a2], row[a])
		prev = row
	return b.commit()


## Water level for a dry vertex at the edge of the water: just under the level of the
## wet cells beside it, so the surface stays a flat sheet that the banks cut off (it
## used to dip under the ground there, which made narrow streams look like tents).
func _shore_level(c: int) -> float:
	if dw.size() == NA * NA and wnear[c] != DRY and dw[c] < SHEET_REACH:
		var ground := heights[c] if heights.size() == NA * NA else ha[c]
		if dw[c] > SHEET_REACH - A_STEP * 1.5:
			return ground - 0.4   # the sheet's last ring always ends under the ground
		return minf(wnear[c] - 0.05, ground - 0.25)
	var best := DRY
	var ci := c % NA
	var cj := c / NA
	for d in 8:
		var ni: int = ci + DX[d]
		var nj: int = cj + DZ[d]
		if ni < 0 or nj < 0 or ni >= NA or nj >= NA:
			continue
		best = maxf(best, wl[nj * NA + ni])
	if best == DRY:
		return ha[c] - 1.5
	# never above the ground there (the render grid has the same 5 m cells): where a bank
	# is lower than the stream, the sheet slips under it instead of ending in a square edge
	var ground := heights[c] if heights.size() == NA * NA else ha[c]
	return minf(best - 0.05, ground - 0.25)


## Rivers and lakes on the analysis grid: wet vertices at the water level, dry ones at
## the level of the water beside them, so the banks cut the surface off.
func water_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	var vid := PackedInt32Array()
	vid.resize(NA * NA)
	vid.fill(-1)
	for j in NA - 1:
		for i in NA - 1:
			var quad := [j * NA + i, j * NA + i + 1, (j + 1) * NA + i + 1, (j + 1) * NA + i]
			# the sheet reaches a little under the banks, so the shoreline is where the
			# ground rises through it (following the land), not the grid cells' edges
			var any := false
			for c in quad:
				if wl[c] != DRY or (dw.size() == NA * NA and dw[c] < SHEET_REACH):
					any = true
			if not any:
				continue
			for c in quad:
				if vid[c] < 0:
					var y := wl[c] if wl[c] != DRY else _shore_level(c)
					vid[c] = b.add(Vector3(_ax(c % NA), y, _ax(c / NA)), Vector3.UP, Color.WHITE)
			b.quad(vid[quad[0]], vid[quad[1]], vid[quad[2]], vid[quad[3]])
	return b.commit()


## Top-down debug picture of the biomes (for --map=path.png).
func save_map(path: String, route: Route) -> void:
	var img := Image.create(NA, NA, false, Image.FORMAT_RGB8)
	for j in NA:
		for i in NA:
			var c := j * NA + i
			var col := ground[c]
			col = col.lerp(Color(0.10, 0.35, 0.12), forest[c] * 0.7)
			if wl[c] != DRY:
				col = Color(0.2, 0.45, 0.85)
			img.set_pixel(i, j, col)
	for p in route.points:
		var i := clampi(int((p.x + HALF) / A_STEP), 0, NA - 1)
		var j := clampi(int((p.z + HALF) / A_STEP), 0, NA - 1)
		img.set_pixel(i, j, Color(0.95, 0.2, 0.2))
	img.resize(NA * 3, NA * 3, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
