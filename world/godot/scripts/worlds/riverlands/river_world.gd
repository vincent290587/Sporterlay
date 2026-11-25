class_name RiverWorld
extends RefCounted
## The second world: an autumn river basin shaped by simulated water, with biomes
## read from terrain analysis maps, a road planned over the land, a cliff tool and an
## ecosystem of competing species (see RiverLand, RiverRoad, RiverCliffs, RiverEcology,
## RiverScenery, and docs/riverlands-generation.md).

const TITLE := "Riverlands"

var route := Route.new()
var land := RiverLand.new()


func build(parent: Node3D, seed: int) -> void:
	land.setup(seed)
	land.build()
	var t := Time.get_ticks_msec()
	var loop := RiverRoad.plan(land, seed)
	route.build_loop(loop, func(x: float, z: float) -> float: return land.field(land.ha, x, z), land.road_floor)
	print("  road planned: %d ms" % (Time.get_ticks_msec() - t))
	land.make_heights()
	land.carve(route)
	t = Time.get_ticks_msec()
	var cliffs := RiverCliffs.new()
	cliffs.setup(land, seed)
	land.strata = cliffs
	cliffs.simulate_scree(seed)
	print("  rock fall: %d ms" % (Time.get_ticks_msec() - t))
	Look.apply(parent, {
		"sky_top": Color(0.40, 0.58, 0.86),
		"sky_horizon": Color(0.93, 0.87, 0.78),
		"sky_ground": Color(0.75, 0.70, 0.66),
		"sun_color": Color(1.0, 0.90, 0.74),
		"sun_sky_color": Color(1.0, 0.86, 0.62),
		"cloud_shade": Color(0.80, 0.74, 0.76),
		"sun_pitch": RiverLand.SUN_PITCH,
		"sun_yaw": RiverLand.SUN_YAW,
		"sun_energy": 1.2,
		"ambient": Color(0.66, 0.66, 0.80),
		"fog": Color(0.88, 0.82, 0.76),
		"fog_density": 0.00036,
		"saturation": 1.1,
	})
	var bridges := _bridges()
	var spans := []
	for m in route.count():
		if bridges[m] != 0 and bridges[(m - 1 + route.count()) % route.count()] == 0:
			spans.append("%d m" % int(m * route.spacing))
	print("  bridges at: ", ", ".join(spans))
	RiverScenery.build(parent, land, route, bridges, cliffs, seed)
	# the land and the cliff tool point at each other: break the loop once built, or
	# neither is ever freed (a leak on every world switch, reported at exit)
	land.strata = null
	cliffs.land = null


## Route points over water, widened a little for the abutments.
func _bridges() -> PackedByteArray:
	var n := route.count()
	var wet := PackedByteArray()
	wet.resize(n)
	for m in n:
		var p := route.points[m]
		if land.water_at(p.x, p.z) != RiverLand.DRY:
			wet[m] = 1
	var out := PackedByteArray()
	out.resize(n)
	for m in n:
		if wet[m] != 0:
			for k in range(-4, 5):
				out[(m + k + n) % n] = 1
	return out


func save_map(path: String) -> void:
	land.save_map(path, route)
