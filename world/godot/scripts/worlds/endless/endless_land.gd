class_name EndlessLand
extends RefCounted
## The endless world's ground, as functions of position: thread-safe (noise objects
## are only read), so tiles are built on worker threads.
##
## `base_height` is the gentle land the road follows. Away from the road each biome
## (EndlessBiomes) adds its own relief, blended by where along the road a point is,
## so the road always finds a way through. Near the road the tile carves its own
## flat bed from the road points it was given.

const TILE := 256.0
const STEP := 4.0
const N := 65                   # TILE / STEP + 1
const FAR_TILE := 1024.0
const FAR_STEP := 16.0
const ROAD_REACH := 48.0
const FINE := 60.0              # road distance is exact within this
const COARSE := 32.0            # elsewhere it comes from a 32 m grid

const DIRT := Color(0.58, 0.48, 0.34)

var base_noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var biomes := EndlessBiomes.new()
var seed := 0
## Landmark pads [centre, radius, height, falloff]: the ground is set to `height`
## inside, blending out over `falloff`. Replaced (never changed in place) when one
## is added, so worker threads always read a whole list.
var pads: Array = []


func setup(p_seed: int) -> void:
	seed = p_seed
	base_noise.seed = seed
	base_noise.frequency = 0.0006
	base_noise.fractal_octaves = 3
	detail.seed = seed + 3
	detail.frequency = 0.02
	detail.fractal_octaves = 2
	biomes.setup(seed)


func base_height(x: float, z: float) -> float:
	return base_noise.get_noise_2d(x, z) * 45.0


func add_pad(centre: Vector2, radius: float, height: float, falloff: float) -> void:
	var list := pads.duplicate()
	list.append([centre, radius, height, falloff])
	pads = list


## How far (m) a point is inside a pad's flat (negative outside); for the scatter.
func pad_inside(x: float, z: float, margin: float) -> bool:
	for p: Array in pads:
		if Vector2(x, z).distance_to(p[0]) < float(p[1]) + margin:
			return true
	return false


## Height before the road's bed is carved, `d` m from the road, with biome weights `w`.
func natural(x: float, z: float, d: float, w: PackedFloat32Array) -> float:
	var h := base_height(x, z) + detail.get_noise_2d(x, z) * 1.5
	for k in EndlessBiomes.COUNT:
		if w[k] > 0.001:
			h += w[k] * biomes.relief(k, x, z, d)
	for p: Array in pads:
		var pd := Vector2(x, z).distance_to(p[0])
		if pd < float(p[1]) + float(p[3]):
			# a crag: steep sides, a little rough
			var t := smoothstep(float(p[1]), float(p[1]) + float(p[3]), pd + detail.get_noise_2d(x * 3.0, z * 3.0) * 6.0)
			h = lerpf(p[2], minf(h, p[2]), t) if t < 1.0 else h
	return h


func color(x: float, z: float, h: float, ny: float, rd: float, w: PackedFloat32Array) -> Color:
	var c := Color(0, 0, 0, 0)
	for k in EndlessBiomes.COUNT:
		if w[k] > 0.001:
			c += biomes.color(k, x, z, h, ny) * w[k]
	var a := c.a
	c = c.lerp(DIRT, 1.0 - smoothstep(Route.HALF_WIDTH + 0.5, Route.HALF_WIDTH + 2.5, rd))
	c.a = a
	return c


## Everything a tile needs, computed off the main thread: a dictionary with the
## mesh (and, for near tiles, the heights for scattering props later).
## `road` is [points, distances] from StreamRoute.points_near.
func build_tile(key: Vector2i, far: bool, road: Array) -> Dictionary:
	var size := FAR_TILE if far else TILE
	var step := FAR_STEP if far else STEP
	var n := int(size / step) + 1
	var x0 := key.x * size
	var z0 := key.y * size
	var rp: PackedVector3Array = road[0]
	var rs: PackedFloat32Array = road[1]
	# road distance: exact near the road (stamped from every point), coarse further out
	var g := n + 2   # with a border ring for normals
	var rd := PackedFloat32Array()
	var rh := PackedFloat32Array()
	var rss := PackedFloat32Array()
	rd.resize(g * g)
	rh.resize(g * g)
	rss.resize(g * g)
	rd.fill(1e9)
	if not far:
		var reach := int(ceil(FINE / step))
		for q in rp.size():
			var p := rp[q]
			var ci := int(round((p.x - x0) / step)) + 1
			var cj := int(round((p.z - z0) / step)) + 1
			if ci < -reach or cj < -reach or ci > g + reach or cj > g + reach:
				continue
			for j in range(maxi(cj - reach, 0), mini(cj + reach, g - 1) + 1):
				var dz := z0 + (j - 1) * step - p.z
				for i in range(maxi(ci - reach, 0), mini(ci + reach, g - 1) + 1):
					var dx := x0 + (i - 1) * step - p.x
					var d := sqrt(dx * dx + dz * dz)
					var k := j * g + i
					if d < rd[k]:
						rd[k] = d
						rh[k] = p.y
						rss[k] = rs[q]
	# coarse distance on a 32 m lattice (every 4th road point), interpolated
	var cs := COARSE if not far else 128.0
	var cn := int(size / cs) + 3
	var cd := PackedFloat32Array()
	var csd := PackedFloat32Array()
	cd.resize(cn * cn)
	csd.resize(cn * cn)
	for j in cn:
		for i in cn:
			var px := x0 + (i - 1) * cs
			var pz := z0 + (j - 1) * cs
			var best := 1e9
			var best_s := 0.0
			for q in range(0, rp.size(), 4):
				var dx := rp[q].x - px
				var dz := rp[q].z - pz
				var dd := dx * dx + dz * dz
				if dd < best:
					best = dd
					best_s = rs[q]
			cd[j * cn + i] = sqrt(best)
			csd[j * cn + i] = best_s
	var heights := PackedFloat32Array()
	heights.resize(g * g)
	var wts := []
	var dist := PackedFloat32Array()
	dist.resize(g * g)
	for j in g:
		var z := z0 + (j - 1) * step
		for i in g:
			var x := x0 + (i - 1) * step
			var k := j * g + i
			var fx := (x - x0) / cs + 1.0
			var fz := (z - z0) / cs + 1.0
			var ii := clampi(int(fx), 0, cn - 2)
			var jj := clampi(int(fz), 0, cn - 2)
			var tx := fx - ii
			var tz := fz - jj
			var d_coarse := lerpf(lerpf(cd[jj * cn + ii], cd[jj * cn + ii + 1], tx), lerpf(cd[(jj + 1) * cn + ii], cd[(jj + 1) * cn + ii + 1], tx), tz)
			var d := minf(rd[k], d_coarse) if rd[k] < FINE else maxf(d_coarse, FINE)
			dist[k] = d
			var s_near := rss[k] if rd[k] < FINE else lerpf(lerpf(csd[jj * cn + ii], csd[jj * cn + ii + 1], tx), lerpf(csd[(jj + 1) * cn + ii], csd[(jj + 1) * cn + ii + 1], tx), tz)
			var w := biomes.weights(s_near)
			wts.append(w)
			var h := natural(x, z, d, w)
			if rd[k] < ROAD_REACH:
				h = lerpf(rh[k] - 0.15, h, smoothstep(Route.HALF_WIDTH + 6.0, ROAD_REACH, rd[k]))
			# far tiles sit under the near ones, well under near the road (their
			# coarse road distance can't match the near tiles' exactly)
			heights[k] = h - ((1.5 + 10.0 * (1.0 - smoothstep(500.0, 900.0, d))) if far else 0.0)
	var b := MeshBuilder.new()
	for j in range(1, g - 1):
		for i in range(1, g - 1):
			var k := j * g + i
			var nrm := Vector3(heights[k - 1] - heights[k + 1], 2.0 * step, heights[k - g] - heights[k + g]).normalized()
			var x := x0 + (i - 1) * step
			var z := z0 + (j - 1) * step
			b.add(Vector3(x, heights[k], z), nrm, color(x, z, heights[k], nrm.y, rd[k] if rd[k] < FINE else 1e9, wts[k]))
	for j in n - 1:
		for i in n - 1:
			var k := j * n + i
			b.tri(k, k + 1, k + n)
			b.tri(k + 1, k + n + 1, k + n)
	return {"key": key, "far": far, "mesh": b.commit(), "heights": heights, "dist": dist, "road_d": dist, "weights": wts, "g": g, "step": step, "origin": Vector2(x0, z0)}
