class_name TransLand
extends RefCounted
## Transylvania's ground: wooded hills with misty hollows, and one long ridge the road
## climbs to the castle crag. The ridge is stamped along the road's own loop, so the
## climb follows a spine with steep flanks, cliffs only near the top.

const HALF := 1600.0        # the height field covers -HALF..HALF in x and z (m)
const STEP := 5.0
const N := 641              # 2 * HALF / STEP + 1
const FAR := 9000.0         # the mountain skirt reaches this radius
const SKIRT_LEVELS := 36
const ROAD_REACH := 48.0
const RADIUS := 1050.0      # the loop's mean radius (m): ~6.6 km of road
const CLIMB := 120.0        # the castle plateau above the hills (m)
const PLATEAU := 75.0       # half its length along the road (m)
const RAMP := 2600.0        # the climb on each side of it (m along the road)
const MIST := -4.0          # mist lies below this height
const WATER := -16.0        # black pools in the deepest hollows

const MOSS := Color(0.24, 0.30, 0.17)
const MOSS_DARK := Color(0.15, 0.19, 0.12)
const NEEDLES := Color(0.26, 0.21, 0.15)   # forest floor under the conifers
const MUD := Color(0.22, 0.19, 0.15)
const ROCK := Color(0.37, 0.36, 0.40)
const ROCK_DARK := Color(0.24, 0.23, 0.27)
const VERGE := Color(0.30, 0.26, 0.21)
const SNOW := Color(0.52, 0.55, 0.64)
const SNOW_LINE := 820.0

var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var peaks := FastNoiseLite.new()
var tint := FastNoiseLite.new()
var crag := FastNoiseLite.new()
var loop := PackedVector2Array()      # the road's rough loop (x, z)
var loop_s := PackedFloat32Array()    # arc length at each loop point
var castle_i := 0                     # loop index of the castle
var ridge := PackedFloat32Array()     # the ridge's extra height on the grid
var heights := PackedFloat32Array()
var road_d := PackedFloat32Array()


func setup(seed: int) -> void:
	hills.seed = seed
	hills.frequency = 0.0019
	hills.fractal_octaves = 4
	detail.seed = seed + 1
	detail.frequency = 0.014
	detail.fractal_octaves = 2
	peaks.seed = seed + 2
	peaks.frequency = 0.0009
	peaks.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	peaks.fractal_octaves = 5
	tint.seed = seed + 3
	tint.frequency = 0.006
	tint.fractal_octaves = 3
	crag.seed = seed + 4
	crag.frequency = 0.035
	crag.fractal_octaves = 3
	_make_loop(seed)
	_stamp_ridge()


## A wobbly circle (it can't cross itself), straightened through the castle so the
## road runs true through both gates. The castle is halfway round from the start.
func _make_loop(seed: int) -> void:
	var shape := FastNoiseLite.new()
	shape.seed = seed + 20
	shape.frequency = 0.5
	shape.fractal_octaves = 3
	var n := 900
	for k in n:
		var a := TAU * k / n
		var c := Vector2(cos(a), sin(a))
		loop.append(c * (RADIUS + 200.0 * shape.get_noise_2dv(c * 1.7)))
	for _i in 4:
		loop = Route.smooth_loop2(loop, 3)
	castle_i = n / 2
	_measure()
	# straighten: blend the points near the castle onto the chord through it
	var a0 := _index_at(loop_s[castle_i] - 220.0)
	var a1 := _index_at(loop_s[castle_i] + 220.0)
	var p0 := loop[a0]
	var p1 := loop[a1]
	var out := loop.duplicate()
	for k in range(a0, a1 + 1):
		var u := absf(loop_s[k] - loop_s[castle_i])
		var w := 1.0 - smoothstep(110.0, 220.0, u)
		var t := (loop_s[k] - loop_s[a0]) / (loop_s[a1] - loop_s[a0])
		out[k] = loop[k].lerp(p0.lerp(p1, t), w)
	loop = out
	_measure()


func _measure() -> void:
	loop_s.resize(loop.size())
	var s := 0.0
	for k in loop.size():
		loop_s[k] = s
		s += loop[k].distance_to(loop[(k + 1) % loop.size()])


func _index_at(s: float) -> int:
	var best := 0
	for k in loop.size():
		if absf(loop_s[k] - s) < absf(loop_s[best] - s):
			best = k
	return best


## Road distance from the castle along the loop (either way round).
func _from_castle(k: int) -> float:
	var total := loop_s[loop.size() - 1] + loop[loop.size() - 1].distance_to(loop[0])
	var d := absf(loop_s[k] - loop_s[castle_i])
	return minf(d, total - d)


## The climb's height at `u` m from the castle: flat on the plateau, then a long
## eased descent whose steepest part stays under the road's grade cap.
static func climb_at(u: float) -> float:
	var t := clampf((u - PLATEAU) / RAMP, 0.0, 1.0)
	return CLIMB * (0.5 + 0.5 * cos(PI * t))


## The ridge, stamped from every loop point on the climb: a flat top (wide on the
## plateau, a spine lower down) falling away at a slope that steepens near the top.
func _stamp_ridge() -> void:
	ridge.resize(N * N)
	ridge.fill(0.0)
	for k in loop.size():
		var u := _from_castle(k)
		var top := climb_at(u)
		if top <= 0.5:
			continue
		var near := 1.0 - smoothstep(PLATEAU, PLATEAU + 500.0, u)
		var flat := lerpf(16.0, 62.0, 1.0 - smoothstep(PLATEAU * 0.6, PLATEAU + 40.0, u))
		var slope := lerpf(0.42, 1.9, near)   # rise per metre on the flanks
		var reach := flat + top / slope
		var p := loop[k]
		var ci := int(round((p.x + HALF) / STEP))
		var cj := int(round((p.y + HALF) / STEP))
		var r := int(ceil(reach / STEP))
		for j in range(maxi(cj - r, 0), mini(cj + r, N - 1) + 1):
			var dz := -HALF + j * STEP - p.y
			for i in range(maxi(ci - r, 0), mini(ci + r, N - 1) + 1):
				var dx := -HALF + i * STEP - p.x
				var d := sqrt(dx * dx + dz * dz)
				var v := top - maxf(d - flat, 0.0) * slope
				var idx := j * N + i
				if v > ridge[idx]:
					ridge[idx] = v


func _ridge_at(x: float, z: float) -> float:
	return _sample(ridge, x, z, 0.0)


## Height before the road is carved in.
func natural(x: float, z: float) -> float:
	var h := hills.get_noise_2d(x, z) * 34.0 + detail.get_noise_2d(x, z) * 2.0
	var r := _ridge_at(x, z)
	if r > 0.0:
		# broken rock on the steep flanks, none on the flat top
		var rough := smoothstep(4.0, 30.0, CLIMB - r) * smoothstep(0.0, 20.0, r)
		h += r + crag.get_noise_2d(x, z) * 5.0 * rough
	# the Carpathians all round: high, jagged, snow on the tops
	var m := smoothstep(1900.0, 4200.0, Vector2(x, z).length())
	if m > 0.0:
		h += m * (140.0 + 950.0 * pow(peaks.get_noise_2d(x, z) * 0.5 + 0.5, 1.5))
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
	for m in route.count():
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
			# a steep cut or fill where the road leaves the ridge's spine
			var t := smoothstep(Route.HALF_WIDTH + 6.0, ROAD_REACH * 0.7, road_d[k])
			heights[k] = lerpf(road_h[k] - 0.15, heights[k], t)


## Flattens a footprint (castle) to height `h`, blending out over `edge` m.
func flatten(inside: Callable, h: float, edge: float) -> void:
	for j in N:
		var z := -HALF + j * STEP
		for i in N:
			var d: float = inside.call(-HALF + i * STEP, z)
			if d < edge:
				var k := j * N + i
				heights[k] = lerpf(h, heights[k], smoothstep(0.0, edge, d))


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
	var c := MOSS_DARK.lerp(MOSS, smoothstep(0.3, 0.75, t))
	c = c.lerp(NEEDLES, smoothstep(0.55, 0.8, tint.get_noise_2d(x * 2.3 + 400.0, z * 2.3)) * 0.7)
	c = c.lerp(MUD, 1.0 - smoothstep(WATER + 0.3, WATER + 3.0, h))
	c = c.lerp(ROCK_DARK.lerp(ROCK, t), 1.0 - smoothstep(0.55, 0.78, ny))
	c = c.lerp(SNOW, smoothstep(SNOW_LINE - 60.0, SNOW_LINE + 40.0, h + 120.0 * t) * smoothstep(0.45, 0.65, ny))
	c = c.lerp(VERGE, 1.0 - smoothstep(Route.HALF_WIDTH + 0.4, Route.HALF_WIDTH + 2.5, rd))
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
