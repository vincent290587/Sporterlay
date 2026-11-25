class_name CanyonLand
extends RefCounted
## Canyon country: a sandy desert floor among red-rock mesas and buttes with stepped
## cliffs, and one long canyon the road runs down, its walls stamped along the road's
## own loop around the ruins. Where the ruins stand the canyon widens into a plaza
## and its right-hand wall opens to the low sun, so the carved facade is lit.
##
## Mesas keep away from the open road; in the canyon the walls come in to the road.
## Everything is stepped into strata (`_terrace`) and coloured in bands by height.

const HALF := 2100.0
const STEP := 5.0
const N := 841             # 2 * HALF / STEP + 1
const FAR := 9000.0
const SKIRT_LEVELS := 36
const ROAD_REACH := 48.0
const REACH := 260.0        # the loop's distance field reaches this far
const RADIUS := 1520.0      # the loop's mean radius (m): ~10 km of road
const RUINS_AT := 0.6       # where round the loop (fraction) the ruins stand
const OASIS_AT := 0.2       # and the oasis
const CANYON := 700.0       # the canyon runs this far (m of road) either side of the ruins
const PLAZA := 95.0         # within this of the ruins it's a wide plaza
const WALL := 130.0         # canyon wall height (m)
const MESA := 140.0         # tallest mesas (m)

const SAND := Color(0.86, 0.66, 0.45)
const SAND_PALE := Color(0.92, 0.78, 0.58)
const WASH := Color(0.78, 0.60, 0.44)
const REDROCK := Color(0.70, 0.34, 0.20)
const ORANGE := Color(0.82, 0.48, 0.28)
const CREAM := Color(0.90, 0.76, 0.58)
const SHALE := Color(0.56, 0.38, 0.34)
const VARNISH := Color(0.36, 0.22, 0.17)
const VERGE := Color(0.74, 0.54, 0.38)

var dunes := FastNoiseLite.new()
var swell := FastNoiseLite.new()
var mesas := FastNoiseLite.new()
var rim := FastNoiseLite.new()
var tint := FastNoiseLite.new()
var peaks := FastNoiseLite.new()
var loop := PackedVector2Array()
var loop_s := PackedFloat32Array()
var total := 0.0
var ruins_i := 0
var oasis_i := 0
var ld := PackedFloat32Array()    # distance to the loop (signed: + right of the road)
var lu := PackedFloat32Array()    # road distance from the ruins at the nearest loop point
var heights := PackedFloat32Array()
var road_d := PackedFloat32Array()
var hollows := []                 # [centre Vector2, radius, depth]: dug after (the oasis)
var greens := []                  # [centre Vector2, radius]: green ground (the oasis)


func setup(seed: int) -> void:
	dunes.seed = seed
	dunes.frequency = 0.012
	dunes.fractal_octaves = 2
	swell.seed = seed + 1
	swell.frequency = 0.0016
	swell.fractal_octaves = 3
	mesas.seed = seed + 2
	mesas.frequency = 0.0024
	mesas.fractal_octaves = 4
	rim.seed = seed + 3
	rim.frequency = 0.02
	rim.fractal_octaves = 3
	tint.seed = seed + 4
	tint.frequency = 0.008
	tint.fractal_octaves = 3
	peaks.seed = seed + 5
	peaks.frequency = 0.0008
	peaks.fractal_octaves = 4
	_make_loop(seed)
	_stamp()


## A wobbly circle, straightened through the plaza so the colonnade runs true.
func _make_loop(seed: int) -> void:
	var shape := FastNoiseLite.new()
	shape.seed = seed + 20
	shape.frequency = 0.5
	shape.fractal_octaves = 3
	var n := 900
	for k in n:
		var a := TAU * k / n
		var c := Vector2(cos(a), sin(a))
		loop.append(c * (RADIUS + 260.0 * shape.get_noise_2dv(c * 1.7)))
	for _i in 4:
		loop = Route.smooth_loop2(loop, 3)
	ruins_i = int(n * RUINS_AT)
	oasis_i = int(n * OASIS_AT)
	_measure()
	var a0 := _index_at(loop_s[ruins_i] - 200.0)
	var a1 := _index_at(loop_s[ruins_i] + 200.0)
	var p0 := loop[a0]
	var p1 := loop[a1]
	var out := loop.duplicate()
	for k in range(a0, a1 + 1):
		var u := absf(loop_s[k] - loop_s[ruins_i])
		var w := 1.0 - smoothstep(110.0, 200.0, u)
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
	total = s


func _index_at(s: float) -> int:
	var best := 0
	for k in loop.size():
		if absf(loop_s[k] - s) < absf(loop_s[best] - s):
			best = k
	return best


func from_ruins(k: int) -> float:
	var d := absf(loop_s[k] - loop_s[ruins_i])
	return minf(d, total - d)


## The loop's distance field: for each grid point, the distance to the nearest loop
## point (signed by side) and how far along the road that point is from the ruins.
func _stamp() -> void:
	ld.resize(N * N)
	lu.resize(N * N)
	ld.fill(REACH)
	lu.fill(1e9)
	var r := int(ceil(REACH / STEP))
	var n := loop.size()
	for k in n:
		var p := loop[k]
		var t := (loop[(k + 1) % n] - loop[(k - 1 + n) % n]).normalized()
		var right := Vector2(-t.y, t.x)
		var u := from_ruins(k)
		var ci := int(round((p.x + HALF) / STEP))
		var cj := int(round((p.y + HALF) / STEP))
		for j in range(maxi(cj - r, 0), mini(cj + r, N - 1) + 1):
			var dz := -HALF + j * STEP - p.y
			for i in range(maxi(ci - r, 0), mini(ci + r, N - 1) + 1):
				var dx := -HALF + i * STEP - p.x
				var d := sqrt(dx * dx + dz * dz)
				var idx := j * N + i
				if d < absf(ld[idx]):
					ld[idx] = d if dx * right.x + dz * right.y >= 0.0 else -d
					lu[idx] = u


## Stepped strata: t 0..1 up a slope becomes cliffs with benches between.
static func _terrace(t: float) -> float:
	return smoothstep(0.0, 0.05, t) * 0.55 + smoothstep(0.30, 0.35, t) * 0.28 + smoothstep(0.66, 0.70, t) * 0.17


## How wide the canyon is (half, m) at `u` m of road from the ruins: a slot most of
## the way, opening into the plaza, flaring at the ends.
static func canyon_half(u: float) -> float:
	var plaza := 1.0 - smoothstep(PLAZA - 30.0, PLAZA + 40.0, u)
	var flare := smoothstep(CANYON - 250.0, CANYON, u)
	var narrows := 1.0 - 0.5 * smoothstep(250.0, 330.0, u) * (1.0 - smoothstep(380.0, 460.0, u))   # the slot
	return lerpf(lerpf(24.0, 34.0, flare) * narrows, 58.0, plaza)


func natural(x: float, z: float) -> float:
	var h := swell.get_noise_2d(x, z) * 16.0 + dunes.get_noise_2d(x, z) * 2.5
	var sd := _sample(ld, x, z, REACH)
	var d := absf(sd)
	var u := _nearest_u(x, z)
	# mesas and buttes, kept off the open road
	var m := mesas.get_noise_2d(x, z) * 0.5 + 0.5
	var mt := clampf((m - 0.56) / 0.22, 0.0, 1.0) * smoothstep(55.0, 170.0, d)
	var top := MESA * _terrace(mt)
	# the canyon: walls stamped along the road around the ruins
	var inside := 1.0 - smoothstep(CANYON - 150.0, CANYON + 60.0, u)
	if inside > 0.0:
		var half := canyon_half(u) + rim.get_noise_2d(x, z) * 4.0
		var t := clampf((d - half) / 75.0, 0.0, 1.0)
		var wall := WALL * (0.85 + 0.3 * (tint.get_noise_2d(x * 0.3, z * 0.3) * 0.5 + 0.5)) * _terrace(t)
		# by the ruins the right-hand wall opens to the sun, and the left one the
		# temple is cut into rises sheer
		if sd > 0.0:
			wall *= smoothstep(PLAZA + 20.0, PLAZA + 160.0, u)
		else:
			var sheer := 1.0 - smoothstep(PLAZA - 40.0, PLAZA + 10.0, u)
			wall = lerpf(wall, WALL * 1.15 * smoothstep(0.0, 0.06, t), sheer)
		top = maxf(top, wall * inside)
	h += top
	var far := smoothstep(2400.0, 4800.0, Vector2(x, z).length())
	if far > 0.0:
		h += far * (60.0 + 260.0 * _terrace(clampf(peaks.get_noise_2d(x, z) * 0.9 + 0.5, 0.0, 1.0)))
	return h


func _nearest_u(x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	if fx < 0.0 or fz < 0.0 or fx >= N - 1 or fz >= N - 1:
		return 1e9
	return lu[int(round(fz)) * N + int(round(fx))]


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
			# in the canyon the walls stand right at the road's flat: blend over a short reach
			var t := smoothstep(Route.HALF_WIDTH + 5.0, ROAD_REACH * 0.55, road_d[k])
			heights[k] = lerpf(road_h[k] - 0.15, heights[k], t)
	for hw: Array in hollows:
		_dig(hw[0], hw[1], hw[2])


## Lowers a round hollow (the oasis basin) by `depth`, except under the road.
func _dig(c: Vector2, radius: float, depth: float) -> void:
	var r := int(ceil(radius / STEP))
	var ci := int(round((c.x + HALF) / STEP))
	var cj := int(round((c.y + HALF) / STEP))
	for j in range(maxi(cj - r, 0), mini(cj + r, N - 1) + 1):
		for i in range(maxi(ci - r, 0), mini(ci + r, N - 1) + 1):
			var d := Vector2(-HALF + i * STEP, -HALF + j * STEP).distance_to(c)
			var k := j * N + i
			var f := (1.0 - smoothstep(radius * 0.35, radius, d)) * smoothstep(Route.HALF_WIDTH + 2.0, 14.0, road_d[k])
			heights[k] -= depth * f


## Levels a footprint to `target(x, z)`, blending out over `edge` m.
func flatten(inside: Callable, target: Callable, edge: float) -> void:
	for j in N:
		var z := -HALF + j * STEP
		for i in N:
			var x := -HALF + i * STEP
			var d: float = inside.call(x, z)
			if d < edge:
				var k := j * N + i
				heights[k] = lerpf(target.call(x, z), heights[k], smoothstep(0.0, edge, d))


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


## Sand on the flats, rock in strata bands on the cliffs (by height, with a wobble),
## dark desert varnish streaking down the steepest faces.
func color_at(x: float, z: float, h: float, ny: float, rd: float) -> Color:
	var t := tint.get_noise_2d(x, z) * 0.5 + 0.5
	var c := SAND.lerp(SAND_PALE, smoothstep(0.35, 0.8, t))
	c = c.lerp(WASH, smoothstep(0.6, 0.85, tint.get_noise_2d(x * 2.7 + 300.0, z * 2.7)) * 0.6)
	var band := fposmod(h * 0.11 + tint.get_noise_2d(x * 0.5, z * 0.5) * 1.5, 4.0)
	var rock: Color
	if band < 1.4:
		rock = REDROCK
	elif band < 2.3:
		rock = ORANGE
	elif band < 3.1:
		rock = CREAM
	else:
		rock = SHALE
	var steep := 1.0 - smoothstep(0.5, 0.8, ny)
	c = c.lerp(rock, steep)
	c = c.lerp(VARNISH, (1.0 - smoothstep(0.15, 0.35, ny)) * smoothstep(0.55, 0.8, tint.get_noise_2d(x * 4.0, z * 0.6)) * 0.6)
	c = c.lerp(rock.lerp(SAND, 0.4), smoothstep(8.0, 30.0, h) * (1.0 - steep) * 0.6)   # mesa tops
	for g: Array in greens:
		var gd := Vector2(x, z).distance_to(g[0]) / float(g[1])
		c = c.lerp(CanyonOasis.GREEN.lerp(SAND, t * 0.4), (1.0 - smoothstep(0.55, 1.0, gd + t * 0.25)) * (1.0 - steep))
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
