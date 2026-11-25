class_name Route
extends RefCounted
## The road: a closed loop sampled every ~2 m. Each world gives the rough shape; heights
## follow the land, smoothed and limited to MAX_GRADE so it stays a road. The grade only
## drives the world's own physics; nothing goes back to Sporterlay.

const HALF_WIDTH := 2.6
const SPACING := 2.0
const MAX_GRADE := 0.075

var points := PackedVector3Array()   # road surface centre line
var length := 0.0
var spacing := SPACING


## Builds the road from a rough closed loop (x, z points in order). `height` gives the
## ground height at (x, z), `min_height` the lowest the road may go there (over water).
func build_loop(raw: PackedVector2Array, height: Callable, min_height: Callable) -> void:
	var raw_n := raw.size()
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
		h.append(height.call(p.x, p.y))
	for _i in 3:
		h = _smooth_loop1(h, 20)
	_limit_grade(h)
	for m in count:
		h[m] = maxf(h[m], min_height.call(flat[m].x, flat[m].y))
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


## Caps the grade at MAX_GRADE with the least cut and fill: the highest profile under
## the land and the lowest one over it that both respect the cap, averaged (the average
## of two profiles within the cap is within it too). Two laps each way cover the loop.
func _limit_grade(h: PackedFloat32Array) -> void:
	var lim := MAX_GRADE * spacing
	var n := h.size()
	var under := h.duplicate()
	var over := h.duplicate()
	for _lap in 2:
		for i in range(1, n + 1):
			var k := i % n
			var p := i - 1
			under[k] = minf(under[k], under[p] + lim)
			over[k] = maxf(over[k], over[p] - lim)
		for i in range(n - 2, -2, -1):
			var k := (i + n) % n
			var q := (i + 1) % n
			under[k] = minf(under[k], under[q] + lim)
			over[k] = maxf(over[k], over[q] - lim)
	for i in n:
		h[i] = (under[i] + over[i]) * 0.5


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


static func smooth_loop2(a: PackedVector2Array, w: int) -> PackedVector2Array:
	var n := a.size()
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var sum := Vector2.ZERO
		for k in range(-w, w + 1):
			sum += a[(i + k + n) % n]
		out[i] = sum / (2 * w + 1)
	return out
