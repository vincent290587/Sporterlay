class_name EndlessLand
extends RefCounted
## The endless world's ground, as functions of position: thread-safe (noise objects
## are only read), so tiles are built on worker threads.
##
## `base_height` is the gentle land the road follows. Away from the road, `relief`
## adds hills and mountains, so the road always finds a way through. Near the road
## the tile carves its own flat bed from the road points it was given.

const TILE := 256.0
const STEP := 4.0
const N := 65                   # TILE / STEP + 1
const FAR_TILE := 1024.0
const FAR_STEP := 16.0
const ROAD_REACH := 48.0
const FINE := 60.0              # road distance is exact within this
const COARSE := 32.0            # elsewhere it comes from a 32 m grid

const MEADOW := Color(0.42, 0.58, 0.24)
const MEADOW_DEEP := Color(0.30, 0.47, 0.20)
const DRY := Color(0.70, 0.66, 0.40)
const ROCK := Color(0.52, 0.50, 0.46)
const SNOW := Color(0.93, 0.94, 0.97)
const DIRT := Color(0.58, 0.48, 0.34)

var base_noise := FastNoiseLite.new()
var hills := FastNoiseLite.new()
var peaks := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var tint := FastNoiseLite.new()


func setup(seed: int) -> void:
	base_noise.seed = seed
	base_noise.frequency = 0.0006
	base_noise.fractal_octaves = 3
	hills.seed = seed + 1
	hills.frequency = 0.0028
	hills.fractal_octaves = 3
	peaks.seed = seed + 2
	peaks.frequency = 0.0007
	peaks.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	peaks.fractal_octaves = 5
	detail.seed = seed + 3
	detail.frequency = 0.02
	detail.fractal_octaves = 2
	tint.seed = seed + 4
	tint.frequency = 0.004
	tint.fractal_octaves = 3


func base_height(x: float, z: float) -> float:
	return base_noise.get_noise_2d(x, z) * 45.0


## Height before the road's bed is carved, `d` m from the road.
func natural(x: float, z: float, d: float) -> float:
	var h := base_height(x, z) + detail.get_noise_2d(x, z) * 1.5
	h += hills.get_noise_2d(x, z) * 22.0 * smoothstep(30.0, 220.0, d)
	h += (120.0 + 520.0 * (peaks.get_noise_2d(x, z) * 0.5 + 0.5)) * smoothstep(350.0, 1300.0, d)
	return h


func color(x: float, z: float, h: float, ny: float, rd: float) -> Color:
	var t := tint.get_noise_2d(x, z) * 0.5 + 0.5
	var c := MEADOW_DEEP.lerp(MEADOW, smoothstep(0.3, 0.72, t))
	c = c.lerp(DRY, smoothstep(0.62, 0.82, tint.get_noise_2d(x * 3.1 + 500.0, z * 3.1)) * 0.5)
	c = c.lerp(ROCK, 1.0 - smoothstep(0.62, 0.8, ny))
	c = c.lerp(SNOW, smoothstep(300.0, 360.0, h + 60.0 * t) * smoothstep(0.55, 0.72, ny))
	c = c.lerp(DIRT, 1.0 - smoothstep(Route.HALF_WIDTH + 0.5, Route.HALF_WIDTH + 2.5, rd))
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
	# road distance: exact near the road (stamped from every point), coarse further out
	var g := n + 2   # with a border ring for normals
	var rd := PackedFloat32Array()
	var rh := PackedFloat32Array()
	rd.resize(g * g)
	rh.resize(g * g)
	rd.fill(1e9)
	if not far:
		var reach := int(ceil(FINE / step))
		for p in rp:
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
	# coarse distance on a 32 m lattice (every 4th road point), interpolated
	var cs := COARSE if not far else 128.0
	var cn := int(size / cs) + 3
	var cd := PackedFloat32Array()
	cd.resize(cn * cn)
	for j in cn:
		for i in cn:
			var px := x0 + (i - 1) * cs
			var pz := z0 + (j - 1) * cs
			var best := 1e9
			for q in range(0, rp.size(), 4):
				var dx := rp[q].x - px
				var dz := rp[q].z - pz
				best = minf(best, dx * dx + dz * dz)
			cd[j * cn + i] = sqrt(best)
	var heights := PackedFloat32Array()
	heights.resize(g * g)
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
			var h := natural(x, z, d)
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
			b.add(Vector3(x, heights[k], z), nrm, color(x, z, heights[k], nrm.y, rd[k] if rd[k] < FINE else 1e9))
	for j in n - 1:
		for i in n - 1:
			var k := j * n + i
			b.tri(k, k + 1, k + n)
			b.tri(k + 1, k + n + 1, k + n)
	return {"key": key, "far": far, "mesh": b.commit(), "heights": heights, "dist": dist, "g": g, "step": step, "origin": Vector2(x0, z0)}
