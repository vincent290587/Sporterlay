class_name EndlessWorld
extends RefCounted
## An endless road through a world built as you ride (EndlessStream): the road is
## generated from the seed ahead of the rider, ground tiles on worker threads. The
## same seed always gives the same road.

const TITLE := "Endless"

var route := StreamRoute.new()
var land := EndlessLand.new()
var stream := EndlessStream.new()
var sky := EndlessSky.new()


func build(parent: Node3D, seed: int) -> void:
	land.setup(seed)
	route.setup(seed, land.base_height)
	var plan := []
	for k in range(1, 7):
		plan.append("%s at %.1f km" % [EndlessBiomes.NAMES[land.biomes.kinds[k]], land.biomes.starts[k] / 1000.0])
	print("  ahead: valley, then ", ", ".join(plan))
	sky.name = "Sky"
	sky.biomes = land.biomes
	parent.add_child(sky)
	stream.name = "Stream"
	stream.route = route
	stream.land = land
	parent.add_child(stream)


## Called once the rider is placed: build what's around it before the first frame.
func attach(rider: Rider) -> void:
	stream.rider = rider
	sky.rider = rider
	sky.update(rider.distance)
	stream.prime(rider.distance)
