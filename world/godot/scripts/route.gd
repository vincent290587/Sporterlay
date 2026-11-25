class_name Route
extends RefCounted
## The road: a closed, wobbly loop around the middle of the valley, sampled every
## ~2 m. Heights follow the land, smoothed and limited to MAX_GRADE so it stays a road.
## The grade only drives this world's own physics; nothing goes back to Sporterlay.

const HALF_WIDTH := 2.6
const SPACING := 2.0
const MAX_GRADE := 0.075

var points := PackedVector3Array()   # road surface centre line
var length := 0.0
var spacing := SPACING


func build(seed: int, terrain: Terrain) -> void:
	var shape := FastNoiseLite.new()
	shape.seed = seed + 20
	shape.frequency = 0.55
	shape.fractal_octaves = 3
	var raw := PackedVector2Array()
	var raw_n := 900
	for n in raw_n:
		var a := TAU * n / raw_n
		var c := Vector2(cos(a), sin(a))
		raw.append(c * (630.0 + 230.0 * shape.get_noise_2dv(c * 1.7)))
	for _i in 4:
		raw = _smooth_loop2(raw, 3)

	# even spacing
	var cum := PackedFloat32Array([0.0])
	for n in raw_n:
		cum.append(cum[n] + raw[n].distance_to(raw[(n + 1) % raw_n]))
	length = cum[raw_n]
	var count := int(round(length / SPACING))
	spacing = length / count
	var flat := PackedVector2Array()
	var seg := 0
	for m in count:
		var s := m * spacing
		while cum[seg + 1] < s:
			seg += 1
		var t := (s - cum[seg]) / (cum[seg + 1] - cum[seg])
		flat.append(raw[seg].lerp(raw[(seg + 1) % raw_n], t))

	var h := PackedFloat32Array()
	for p in flat:
		h.append(terrain.natural(p.x, p.y))
	for _i in 3:
		h = _smooth_loop1(h, 20)
	_limit_grade(h)
	for m in count:
		h[m] = maxf(h[m], Terrain.WATER + 2.5)
	_limit_grade(h)
	h = _smooth_loop1(h, 4)
	points.resize(count)
	for m in count:
		points[m] = Vector3(flat[m].x, h[m], flat[m].y)


func count() -> int:
	return points.size()


func position_at(s: float) -> Vector3:
	var f := fposmod(s, length) / spacing
	var i := int(f) % points.size()
	return points[i].lerp(points[(i + 1) % points.size()], f - floorf(f))


## Horizontal direction of travel.
func tangent_at(s: float) -> Vector3:
	var d := position_at(s + 2.0) - position_at(s - 2.0)
	return Vector3(d.x, 0.0, d.z).normalized()


func right_at(s: float) -> Vector3:
	var t := tangent_at(s)
	return Vector3(-t.z, 0.0, t.x)


func tangent_index(m: int) -> Vector3:
	var n := points.size()
	var d := points[(m + 1) % n] - points[(m - 1 + n) % n]
	return Vector3(d.x, 0.0, d.z).normalized()


## Grade in % over ±15 m.
func grade_at(s: float) -> float:
	return (position_at(s + 15.0).y - position_at(s - 15.0).y) / 30.0 * 100.0


func _limit_grade(h: PackedFloat32Array) -> void:
	var lim := MAX_GRADE * spacing
	var n := h.size()
	for _it in 600:
		var changed := false
		for i in n:
			var j := (i + 1) % n
			var d := h[j] - h[i]
			if absf(d) > lim:
				var ex := (absf(d) - lim) * 0.5 * signf(d)
				h[i] += ex
				h[j] -= ex
				changed = true
		if not changed:
			break


static func _smooth_loop1(a: PackedFloat32Array, w: int) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var sum := 0.0
	for k in range(-w, w + 1):
		sum += a[(k + n) % n]
	for i in n:
		out[i] = sum / (2 * w + 1)
		sum += a[(i + w + 1) % n] - a[(i - w + n) % n]
	return out


static func _smooth_loop2(a: PackedVector2Array, w: int) -> PackedVector2Array:
	var n := a.size()
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var sum := Vector2.ZERO
		for k in range(-w, w + 1):
			sum += a[(i + k + n) % n]
		out[i] = sum / (2 * w + 1)
	return out
