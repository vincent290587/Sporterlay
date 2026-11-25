class_name EndlessClimbs
extends RefCounted
## The endless road's cols: every 5-15 km a climb of 150-450 m over 3-7 km (about
## 5 % on average, the steepest ramps ~9 %), a short summit, and a descent. The
## profile is a function of road distance; the road follows it (StreamRoute) and the
## land rises with it round the road (EndlessLand), so it's a pass, not a ramp.
## Thread-safe after setup().

const FIRST := 3000.0
const REACH := 2.0e6
const SUMMIT := 250.0

var starts := PackedFloat32Array()    # where each climb starts...
var ups := PackedFloat32Array()       # ...its length up
var heights := PackedFloat32Array()   # ...how high it goes
var downs := PackedFloat32Array()     # ...its descent


func setup(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 55
	var s := FIRST + rng.randf_range(0.0, 3000.0)
	while s < REACH:
		var up := rng.randf_range(3000.0, 7000.0)
		var grade := rng.randf_range(0.04, 0.058)   # average: the eased profile's steepest is ~1.57 x
		var h := clampf(up * grade, 150.0, 450.0)
		var down := up * rng.randf_range(0.8, 1.3)
		starts.append(s)
		ups.append(up)
		heights.append(h)
		downs.append(down)
		s += up + SUMMIT + down + rng.randf_range(5000.0, 15000.0)


func _index(s: float) -> int:
	var lo := 0
	var hi := starts.size() - 1
	if hi < 0 or s < starts[0]:
		return -1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if starts[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


## Height added at road distance `s`.
func height_at(s: float) -> float:
	var i := _index(s)
	if i < 0:
		return 0.0
	var t := s - starts[i]
	var up := ups[i]
	var h := heights[i]
	if t < up:
		return h * (0.5 - 0.5 * cos(PI * t / up))
	t -= up
	if t < SUMMIT:
		return h
	t -= SUMMIT
	if t < downs[i]:
		return h * (0.5 + 0.5 * cos(PI * t / downs[i]))
	return 0.0


## 1 on a col (from a little before its foot to a little after its end), 0 away
## from them: the land's own bumps are flattened under it so the profile is clean.
func on_climb(s: float) -> float:
	var i := _index(s + 400.0)
	if i < 0:
		return 0.0
	var a := starts[i]
	var e := a + ups[i] + SUMMIT + downs[i]
	return smoothstep(a - 400.0, a, s) * (1.0 - smoothstep(e, e + 400.0, s))


## The summit (road distance of its middle) and height of each climb starting
## before `s_max`, from index `from`.
func summits(from: int, s_max: float) -> Array:
	var out := []
	for i in range(from, starts.size()):
		if starts[i] > s_max:
			break
		out.append([i, starts[i] + ups[i] + SUMMIT * 0.5, heights[i], ups[i]])
	return out
