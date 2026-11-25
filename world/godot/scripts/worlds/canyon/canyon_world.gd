class_name CanyonWorld
extends RefCounted
## Canyon country at golden hour: a ~10 km loop over a sandy desert floor among red
## mesas and buttes, down a long canyon to ancient ruins carved into its wall, and
## past an oasis with palms round a pool. See CanyonLand, CanyonRuins, CanyonOasis,
## CanyonScenery.

const TITLE := "Canyon"

var route := Route.new()
var land := CanyonLand.new()
var ruins_s := 0.0
var oasis_s := 0.0


func build(parent: Node3D, seed: int) -> void:
	land.setup(seed)
	route.build_loop(land.loop, land.natural, func(_x: float, _z: float) -> float: return -1000.0)
	ruins_s = _nearest_s(land.loop[land.ruins_i])
	oasis_s = _nearest_s(land.loop[land.oasis_i])
	var oasis := CanyonOasis.new()
	oasis.setup(route, oasis_s, seed)
	land.hollows.append([oasis.centre2, CanyonOasis.BASIN, CanyonOasis.DEPTH])
	land.greens.append([oasis.centre2, CanyonOasis.BASIN * 0.95])
	land.carve(route)
	var ruins := CanyonRuins.new()
	ruins.setup(route, ruins_s, seed)
	ruins.level(land)

	# the sun low on the plaza's open side, so its light falls on the carved facade
	var right := route.right_at(ruins_s)
	var fwd := route.tangent_at(ruins_s)
	var from := (right + fwd * 0.35).normalized()   # towards the sun
	Look.apply(parent, {
		"sky_top": Color(0.33, 0.50, 0.78),
		"sky_horizon": Color(0.99, 0.80, 0.56),
		"sky_ground": Color(0.80, 0.62, 0.46),
		"sun_color": Color(1.0, 0.74, 0.46),
		"sun_sky_color": Color(1.0, 0.70, 0.38),
		"cloud_shade": Color(0.92, 0.62, 0.50),
		"sun_pitch": -13.0,
		"sun_yaw": rad_to_deg(atan2(from.x, from.z)),
		"sun_energy": 1.45,
		"ambient": Color(0.52, 0.52, 0.70),
		"ambient_energy": 0.5,
		"fog": Color(0.96, 0.76, 0.56),
		"fog_density": 0.00032,
		"fog_aerial": 0.4,
		"saturation": 1.12,
		"shadow_distance": 700.0,
	})
	CanyonScenery.build(parent, land, route, seed, func(x: float, z: float) -> bool: return oasis.blocks(x, z) or ruins.blocks(x, z))
	oasis.build(parent, land)
	ruins.build(parent)
	CanyonBirds.build(parent, route, ruins_s, oasis_s, seed)


func _nearest_s(p: Vector2) -> float:
	var best := 0
	var bd := INF
	for m in route.count():
		var d := Vector2(route.points[m].x, route.points[m].z).distance_squared_to(p)
		if d < bd:
			bd = d
			best = m
	return best * route.spacing
