class_name ValleyTerrain
extends RefCounted
## The ground: a height field around the ride with the road carved in, and a skirt of
## mountains out to the horizon. Colours are baked into the vertices (sRGB).

const HALF := 1200.0        # the height field covers -HALF..HALF in x and z (m)
const STEP := 5.0
const N := 481              # vertices per side: 2 * HALF / STEP + 1
const FAR := 9000.0         # the mountain skirt reaches this radius
const SKIRT_LEVELS := 36
const WATER := -11.0        # lake level (m)
const SNOW := 560.0
const ROAD_REACH := 48.0    # the road flattens the land this far out

const MEADOW_LIGHT := Color(0.60, 0.72, 0.30)
const MEADOW_DEEP := Color(0.33, 0.53, 0.22)
const DRY := Color(0.76, 0.72, 0.42)
const SAND := Color(0.82, 0.76, 0.56)
const DIRT := Color(0.62, 0.52, 0.36)
const ROCK := Color(0.56, 0.53, 0.48)
const ROCK_HIGH := Color(0.50, 0.50, 0.53)
const SNOW_COLOR := Color(0.95, 0.96, 0.99)

var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var ridges := FastNoiseLite.new()
var tint := FastNoiseLite.new()
var heights := PackedFloat32Array()
var road_d := PackedFloat32Array()


func setup(seed: int) -> void:
	hills.seed = seed
	hills.frequency = 0.0016
	hills.fractal_octaves = 4
	detail.seed = seed + 1
	detail.frequency = 0.012
	detail.fractal_octaves = 2
	ridges.seed = seed + 2
	ridges.frequency = 0.0007
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 5
	tint.seed = seed + 3
	tint.frequency = 0.005
	tint.fractal_octaves = 3


## Height before the road is carved in.
func natural(x: float, z: float) -> float:
	var h := hills.get_noise_2d(x, z) * 42.0 + detail.get_noise_2d(x, z) * 2.5
	var m := smoothstep(1000.0, 2600.0, Vector2(x, z).length())
	if m > 0.0:
		h += m * (160.0 + 640.0 * (ridges.get_noise_2d(x, z) * 0.5 + 0.5))
	return h


func carve(route: Route) -> void:
	heights.resize(N * N)
	road_d.resize(N * N)
	var road_h := PackedFloat32Array()
	road_h.resize(N * N)
	for j in N:
		var z := -HALF + j * STEP
		for i in N:
			heights[j * N + i] = natural(-HALF + i * STEP, z)
			road_d[j * N + i] = ROAD_REACH
	var reach := int(ceil(ROAD_REACH / STEP))
	for m in range(0, route.count(), 2):
		var p := route.points[m]
		var ci := int(round((p.x + HALF) / STEP))
		var cj := int(round((p.z + HALF) / STEP))
		for j in range(maxi(cj - reach, 0), mini(cj + reach, N - 1) + 1):
			var dz := -HALF + j * STEP - p.z
			for i in range(maxi(ci - reach, 0), mini(ci + reach, N - 1) + 1):
				var dx := -HALF + i * STEP - p.x
				var d := sqrt(dx * dx + dz * dz)
				var k := j * N + i
				if d < road_d[k]:
					road_d[k] = d
					road_h[k] = p.y
	for k in N * N:
		if road_d[k] < ROAD_REACH:
			var t := smoothstep(Route.HALF_WIDTH + 8.0, ROAD_REACH, road_d[k])
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
		return natural(x, z)
	return _sample(heights, x, z, 0.0)


func road_distance_at(x: float, z: float) -> float:
	return _sample(road_d, x, z, ROAD_REACH)


func normal_at(x: float, z: float) -> Vector3:
	var e := STEP
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e,
		height_at(x, z - e) - height_at(x, z + e)).normalized()


func color_at(x: float, z: float, h: float, ny: float, rd: float) -> Color:
	var t := tint.get_noise_2d(x, z) * 0.5 + 0.5
	var c := MEADOW_DEEP.lerp(MEADOW_LIGHT, smoothstep(0.3, 0.72, t))
	c = c.lerp(DRY, smoothstep(0.62, 0.8, tint.get_noise_2d(x * 3.1 + 500.0, z * 3.1)) * 0.6)
	c = c.lerp(SAND, 1.0 - smoothstep(WATER + 0.4, WATER + 2.0, h))
	c = c.lerp(ROCK, 1.0 - smoothstep(0.62, 0.8, ny))
	c = c.lerp(ROCK_HIGH, smoothstep(140.0, 320.0, h))
	c = c.lerp(SNOW_COLOR, smoothstep(SNOW - 40.0, SNOW + 20.0, h + 60.0 * t) * smoothstep(0.55, 0.72, ny))
	c = c.lerp(DIRT, 1.0 - smoothstep(Route.HALF_WIDTH + 0.5, Route.HALF_WIDTH + 2.5, rd))
	return c


func _grid_normal(i: int, j: int) -> Vector3:
	var l := heights[j * N + maxi(i - 1, 0)]
	var r := heights[j * N + mini(i + 1, N - 1)]
	var d := heights[maxi(j - 1, 0) * N + i]
	var u := heights[mini(j + 1, N - 1) * N + i]
	return Vector3(l - r, 2.0 * STEP, d - u).normalized()


func build_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	for j in N:
		var z := -HALF + j * STEP
		for i in N:
			var x := -HALF + i * STEP
			var k := j * N + i
			var n := _grid_normal(i, j)
			b.add(Vector3(x, heights[k], z), n, color_at(x, z, heights[k], n.y, road_d[k]))
	for j in N - 1:
		for i in N - 1:
			var k := j * N + i
			b.tri(k, k + 1, k + N)
			b.tri(k + 1, k + N + 1, k + N)

	# skirt: rays from the height field's edge out to FAR, sharing the edge vertices
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
			var h := natural(x, z)
			var e := maxf(STEP, r * 0.004)
			var n := Vector3(natural(x - e, z) - natural(x + e, z), 2.0 * e,
				natural(x, z - e) - natural(x, z + e)).normalized()
			row.append(b.add(Vector3(x, h, z), n, color_at(x, z, h, n.y, 1e9)))
		for a in p_count:
			var a2 := (a + 1) % p_count
			b.tri(prev[a], prev[a2], row[a])
			b.tri(prev[a2], row[a2], row[a])
		prev = row
	return b.commit()
