class_name TransWorld
extends RefCounted
## Transylvania at late dusk: a road through dark Carpathian forest, mist in the
## hollows, torches lighting the long climb to a vampire's castle on its crag, through
## the gatehouse and the courtyard, and down the other side. The moon rises behind the
## castle as you climb to it. See TransLand, TransCastle, TransTorches, TransScenery.

const TITLE := "Transylvania"

var route := Route.new()
var land := TransLand.new()
var castle_s := 0.0   # road distance of the castle's centre


func build(parent: Node3D, seed: int) -> void:
	land.setup(seed)
	route.build_loop(land.loop, land.natural, func(_x: float, _z: float) -> float:
		return TransLand.WATER + 1.5)
	land.carve(route)
	castle_s = _nearest_s(land.loop[land.castle_i])
	var castle := TransCastle.new()
	castle.setup(route, castle_s, seed)
	castle.level(land)

	# the moon behind the castle as seen from the climb; the sun went down off to the side
	var c := route.position_at(castle_s)
	var a := route.position_at(castle_s - 600.0)
	var v := Vector2(c.x - a.x, c.z - a.z).normalized()
	var moon_yaw := rad_to_deg(atan2(v.x, v.y)) + 8.0
	var glow := v.rotated(deg_to_rad(115.0))
	Look.apply(parent, {
		"sky_shader": "res://shaders/night_sky.gdshader",
		"sky_params": {"glow_dir": Vector3(glow.x, 0.0, glow.y)},
		"sky_top": Color(0.012, 0.016, 0.045),
		"sky_horizon": Color(0.07, 0.07, 0.13),
		"sky_ground": Color(0.03, 0.03, 0.05),
		"sun_color": Color(0.58, 0.66, 0.92),
		"sun_pitch": -14.0,
		"sun_yaw": moon_yaw,
		"sun_energy": 0.5,
		"ambient": Color(0.16, 0.18, 0.32),
		"ambient_energy": 0.45,
		"fog": Color(0.045, 0.05, 0.09),
		"fog_density": 0.0015,
		"fog_height": TransLand.MIST + 8.0,
		"fog_height_density": 0.012,
		"fog_aerial": 0.5,
		"saturation": 0.85,
		"glow_intensity": 0.8,
		"glow_bloom": 0.05,
		"shadow_distance": 250.0,
	})
	TransScenery.build(parent, land, route, seed, castle.blocks)
	castle.build(parent)
	var fire := TransTorches.new()
	fire.name = "Fire"
	fire.build(route, castle_s, castle, seed)
	parent.add_child(fire)


func _nearest_s(p: Vector2) -> float:
	var best := 0
	var bd := INF
	for m in route.count():
		var d := Vector2(route.points[m].x, route.points[m].z).distance_squared_to(p)
		if d < bd:
			bd = d
			best = m
	return best * route.spacing
