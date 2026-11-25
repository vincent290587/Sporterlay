class_name ValleyWorld
extends RefCounted
## The first world: a green valley ringed by snowy mountains, the road a wobbly loop
## around its middle. Pure noise, no simulation.

const TITLE := "Valley"

var route := Route.new()


func build(parent: Node3D, seed: int) -> void:
	var terrain := ValleyTerrain.new()
	terrain.setup(seed)
	route.build_loop(_loop(seed), terrain.natural, func(_x: float, _z: float) -> float:
		return ValleyTerrain.WATER + 2.5)
	terrain.carve(route)
	Look.apply(parent)
	ValleyScenery.build(parent, terrain, route, seed)


## A circle whose radius wobbles with periodic noise, so it can't cross itself.
func _loop(seed: int) -> PackedVector2Array:
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
		raw = Route.smooth_loop2(raw, 3)
	return raw
