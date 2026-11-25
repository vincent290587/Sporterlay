class_name StreamRoute
extends Route
## An endless road, generated from the seed as it's needed and dropped behind the
## rider. The same seed always gives the same road: everything is integrated from
## s = 0 (catching up to a far start takes a moment, nothing more).
##
## Heading: a slow wander of at most ±70 deg round one general direction (+x) plus
## smaller bends, so the road always moves on and can never cross itself.
## Height: it follows the land's base height (`base_height`) looked at a little ahead,
## with the grade eased in and capped at MAX_GRADE_E.
##
## Only a window of points is kept: `points[0]` is global index `base`.

const MAX_GRADE_E := 0.09
const GRADE_RATE := 0.0012     # grade change per metre (0 to 6 % in 50 m)
const LOOK := [60.0, 150.0, 280.0, 420.0]

var base := 0
var base_height: Callable     # (x, z) -> m, the land the road follows
var climb: Callable           # (s) -> m, the cols (EndlessClimbs) on top of it
var on_climb: Callable        # (s) -> 0..1, how much the land is flattened for a col
var _wander := FastNoiseLite.new()
var _bend := FastNoiseLite.new()
var _wiggle := FastNoiseLite.new()
var _next := 0
var _x := 0.0
var _z := 0.0
var _h := 0.0
var _g := 0.0


func setup(seed: int, height: Callable, climb_at: Callable, on_climb_at: Callable) -> void:
	base_height = height
	climb = climb_at
	on_climb = on_climb_at
	length = 1e12
	spacing = SPACING
	_wander.seed = seed + 31
	_wander.frequency = 0.00035
	_bend.seed = seed + 32
	_bend.frequency = 0.0025
	_wiggle.seed = seed + 33
	_wiggle.frequency = 0.008
	_h = height.call(0.0, 0.0)


func heading_at(s: float) -> float:
	return 1.2 * _wander.get_noise_1d(s) + 0.35 * _bend.get_noise_1d(s) + 0.12 * _wiggle.get_noise_1d(s)


## Generates points up to road distance `s`.
func ensure(s: float) -> void:
	var want := int(ceil(s / spacing)) + 2
	while _next <= want:
		var sd := _next * spacing
		if _next > 0:
			var a := heading_at(sd - spacing * 0.5)
			_x += cos(a) * spacing
			_z += sin(a) * spacing
			# follow the land a little ahead, easing the grade in
			var target := 0.0
			var a2 := heading_at(sd)
			for d: float in LOOK:
				target += base_height.call(_x + cos(a2) * d, _z + sin(a2) * d) * (1.0 - 0.8 * on_climb.call(sd + d)) + climb.call(sd + d)
			target /= LOOK.size()
			# the land's bumps only gently (they cap at 6 %), the cols fully
			var cap := MAX_GRADE_E if climb.call(sd + 70.0) > 1.0 else 0.06
			var want_g := clampf((target - _h) / 260.0, -cap, cap)
			_g += clampf(want_g - _g, -GRADE_RATE * spacing, GRADE_RATE * spacing)
			_h += _g * spacing
		points.append(Vector3(_x, _h, _z))
		_next += 1


## Drops the points before road distance `s`.
func trim(s: float) -> void:
	var k := int(floor(s / spacing)) - base
	if k > 0 and k < points.size() - 4:
		points = points.slice(k)
		base += k


func first_s() -> float:
	return base * spacing


func last_s() -> float:
	return (base + points.size() - 1) * spacing


func position_at(s: float) -> Vector3:
	ensure(s + 4.0)
	var f := maxf(s / spacing - base, 0.0)
	var i := mini(int(f), points.size() - 2)
	return points[i].lerp(points[i + 1], clampf(f - i, 0.0, 1.0))


## Points (with their road distance) within `reach` of the rectangle lo..hi (x, z).
func points_near(lo: Vector2, hi: Vector2, reach: float) -> Array:
	var out_p := PackedVector3Array()
	var out_s := PackedFloat32Array()
	for i in points.size():
		var p := points[i]
		if p.x > lo.x - reach and p.x < hi.x + reach and p.z > lo.y - reach and p.z < hi.y + reach:
			out_p.append(p)
			out_s.append((base + i) * spacing)
	return [out_p, out_s]
