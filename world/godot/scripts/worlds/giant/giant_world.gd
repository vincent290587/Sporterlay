class_name GiantWorld
extends RefCounted
## A giant flooded world: a wooden boardwalk over water, islands and a
## mountain skirt, with trees at 10x normal size. See GiantLand and GiantScenery.

const TITLE := "Giant Wetland"

var route := Route.new()
var land := GiantLand.new()


func build(parent: Node3D, seed: int) -> void:
	land.setup(seed)
	var loop := _loop(seed)
	route.build_loop(loop, land.natural, func(_x: float, _z: float) -> float:
		return GiantLand.WATER + 1.4)
	Look.apply(parent, {
		"sky_top": Color(0.20, 0.42, 0.55),
		"sky_horizon": Color(0.72, 0.86, 0.82),
		"sky_ground": Color(0.28, 0.38, 0.34),
		"sun_color": Color(1.0, 0.92, 0.72),
		"sun_sky_color": Color(1.0, 0.88, 0.62),
		"cloud_shade": Color(0.68, 0.80, 0.82),
		"sun_pitch": -22.0,
		"sun_yaw": -35.0,
		"sun_energy": 1.15,
		"ambient": Color(0.48, 0.62, 0.68),
		"ambient_energy": 0.55,
		"fog": Color(0.74, 0.84, 0.82),
		"fog_density": 0.00045,
		"saturation": 1.05,
		"shadow_distance": 900.0,
	})
	GiantScenery.build(parent, land, route, seed)


## A circle whose radius wobbles with periodic noise, so it can't cross itself:
## broad lobes plus a faster meander, ~16 km around, inside the mountain ring.
func _loop(seed: int) -> PackedVector2Array:
	var shape := FastNoiseLite.new()
	shape.seed = seed + 20
	shape.frequency = 0.45
	shape.fractal_octaves = 3
	var meander := FastNoiseLite.new()
	meander.seed = seed + 21
	meander.frequency = 0.45
	meander.fractal_octaves = 2
	var raw := PackedVector2Array()
	var n := 2400
	for k in n:
		var a := TAU * k / n
		var c := Vector2(cos(a), sin(a))
		var r := 2150.0 + 480.0 * shape.get_noise_2dv(c * 1.6) + 130.0 * meander.get_noise_2dv(c * 9.0)
		raw.append(c * minf(r, GiantLand.RING - 220.0))
	for _i in 3:
		raw = Route.smooth_loop2(raw, 3)
	return raw
