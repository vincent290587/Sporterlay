class_name EndlessLandmarks
extends Node3D
## Set pieces along the endless road, built from asset packs where they're imported
## (VillageKit: assets/village + assets/props; the local-only Raft pack in
## assets/local/raft), each falling back or skipped when its pack is missing:
##
## - every 10-20 km, by biome: a village the road runs through (valley), a lake with
##   a jetty and a boathouse (autumn), Transylvania's castle on a crag (dusk forest),
##   a natural arch and a ruined desert fort (canyon);
## - on every col's summit: a cairn with a banner.
##
## A landmark is planned when the road reaching it is generated (6 km ahead, before
## its tiles), which registers its pads with the land (EndlessLand.pads: the ground
## levelled, raised or dug for it); it's built as the rider comes within BUILD_AT and
## freed once DROP_AT behind. Villages and lakes keep off the cols.

const BUILD_AT := 2500.0
const DROP_AT := 800.0
const CASTLE_OFF := 115.0
const CASTLE_RISE := 38.0
const VILLAGE_HALF := 150.0   # m of road either side of its middle
const LAKE_OFF := 72.0
const LAKE_R := 52.0

var route: StreamRoute
var land: EndlessLand
var rider: Rider
var seed := 0
var planned: Array = []        # [s, kind, data, node or null]
var _next_s := 0.0
var _index := 0
var _summit := 0               # next col to plan a summit marker for


func plan_up_to(s_max: float) -> void:
	if _next_s == 0.0:
		_next_s = _gap(0) * 0.6   # the first one comes a little sooner
	while _next_s < s_max:
		var s := _next_s
		var b := land.biomes.kinds[land.biomes._segment(s)]
		# villages and lakes want flat ground in their own biome: the nearest such spot
		# within 6 km either way, or none
		if b == EndlessBiomes.VALLEY or b == EndlessBiomes.AUTUMN:
			var found := -1.0
			for k in 25:
				for sign: float in [1.0, -1.0]:
					var t := s + sign * k * 250.0
					var clear := land.climbs.on_climb(t - VILLAGE_HALF - 100.0) + land.climbs.on_climb(t + VILLAGE_HALF + 100.0) 						+ land.climbs.on_climb(t) == 0.0
					var same := land.biomes.kinds[land.biomes._segment(t - VILLAGE_HALF - 400.0)] == b 						and land.biomes.kinds[land.biomes._segment(t + VILLAGE_HALF + 400.0)] == b
					if found < 0.0 and clear and same and t > _next_s - 6000.0:
						found = t
			if found < 0.0:
				_index += 1
				_next_s = s + _gap(_index)
				continue
			s = found
		var p := route.position_at(s)
		var right := route.right_at(s)
		var fwd := route.tangent_at(s)
		var side := -1.0 if _rand(_index, 1) < 0.5 else 1.0
		match b:
			EndlessBiomes.DUSK:
				var c := p + right * side * CASTLE_OFF
				var h := p.y + CASTLE_RISE
				land.add_pad(Vector2(c.x, c.z), 80.0, h, 38.0)
				_plan(s, "castle", {"centre": Vector3(c.x, h, c.z), "fwd": fwd, "right": right})
			EndlessBiomes.CANYON:
				_plan(s, "arch", {"at": p, "right": right, "fwd": fwd})
				if MegaKit.has_pack("local/raft"):
					var fs := s + 260.0
					var fp := route.position_at(fs)
					var fr := route.right_at(fs) * side
					var fc := fp + fr * 45.0
					land.add_pad(Vector2(fc.x, fc.z), 26.0, fp.y, 18.0)
					_plan(fs, "fort", {"centre": Vector3(fc.x, fp.y, fc.z), "out": fr})
			EndlessBiomes.VALLEY:
				if VillageKit.available():
					var a := s - VILLAGE_HALF - 30.0
					while a <= s + VILLAGE_HALF + 30.0:
						var q := route.position_at(a)
						land.add_pad(Vector2(q.x, q.z), 42.0, q.y - 0.1, 26.0)
						a += 22.0
					_plan(s, "village", {"side": side})
			_:
				var lc := p + right * side * LAKE_OFF
				land.add_pad(Vector2(lc.x, lc.z), LAKE_R, p.y - 7.0, 22.0)
				_plan(s, "lake", {"centre": Vector3(lc.x, p.y, lc.z), "toward": -right * side})
		_index += 1
		_next_s = s + _gap(_index)
	# a marker on every col's summit
	for c: Array in land.climbs.summits(_summit, s_max):
		var ss: float = c[1]
		var sp := route.position_at(ss)
		var sr := route.right_at(ss)
		_plan(ss, "summit", {"at": sp + sr * (Route.HALF_WIDTH + 4.5), "right": sr})
		_summit = int(c[0]) + 1


func _plan(s: float, kind: String, data: Dictionary) -> void:
	planned.append([s, kind, data, null])
	print("  landmark: %s at %.1f km" % [kind, s / 1000.0])


func _gap(i: int) -> float:
	return lerpf(10000.0, 20000.0, _rand(i, 0))


func _rand(i: int, k: int) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector3i(seed, i, k))
	return r.randf()


func _process(_delta: float) -> void:
	if rider == null:
		return
	var s := rider.distance
	for p: Array in planned:
		var d: float = p[0] - s
		if p[3] == null and d < BUILD_AT and d > -DROP_AT:
			p[3] = _build(p[0], p[1], p[2])
		elif p[3] != null and (d < -DROP_AT or d > BUILD_AT + 500.0):
			(p[3] as Node).queue_free()
			p[3] = null
	planned = planned.filter(func(p: Array) -> bool: return p[3] != null or float(p[0]) - s > -DROP_AT)


func _build(s: float, kind: String, data: Dictionary) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(seed, int(s)))
	match kind:
		"castle":
			var castle := TransCastle.new()
			castle._rng.seed = rng.randi()
			castle.centre = data.centre
			castle.fwd = data.fwd
			castle.right = data.right
			castle.build(node)
		"arch":
			var mat := ShaderMaterial.new()
			mat.shader = load("res://shaders/canyon_ground.gdshader")
			var mi := MeshInstance3D.new()
			mi.mesh = CanyonRocks._arch(rng, data.at, data.right, data.fwd)
			mi.material_override = mat
			node.add_child(mi)
		"village":
			_village(node, s, data.side, rng)
		"lake":
			_lake(node, data, rng)
		"fort":
			_fort(node, data, rng)
		"summit":
			_summit_marker(node, data, rng)
	return node


## A building frame at the roadside: origin `off` m out on `side`, z pointing away
## from the road, x along it (VillageKit's frame: the front faces the road).
func _frame(s: float, side: float, off: float) -> Transform3D:
	var p := route.position_at(s)
	var z := route.right_at(s) * side
	var x := Vector3.UP.cross(z).normalized()
	return Transform3D(Basis(x, Vector3.UP, z), p + z * off - Vector3.UP * 0.1)


static func _yaw_of(v: Vector3) -> float:
	return atan2(v.x, v.z)


## Houses facing the road on both sides with gaps and fences between them, the church
## set back on one side with market stalls across from it, carts and barrels about.
func _village(node: Node3D, s0: float, church_side: float, rng: RandomNumberGenerator) -> void:
	var kit := VillageKit.new()
	kit.rng.seed = rng.randi()
	for side: float in [-1.0, 1.0]:
		var s := s0 - VILLAGE_HALF
		while s < s0 + VILLAGE_HALF:
			if side == church_side and s > s0 - 26.0 and s < s0 + 14.0:
				s = s0 + 14.0   # room for the church and its tower
				continue
			var w: int = [4, 6, 6, 8][rng.randi() % 4]
			var lens: Array = VillageKit.ROOFS[w]
			var l: int = lens[rng.randi() % lens.size()]
			var floors := 2 if rng.randf() < 0.45 else 1
			var mat := "UnevenBrick" if rng.randf() < 0.3 else "Plaster"
			# Nudge each house along and away from the road and turn it a few
			# degrees, so the row never reads as a perfectly parallel grid.
			var along := s + w * 0.5 + rng.randf_range(-1.0, 1.0)
			var off := Route.HALF_WIDTH + rng.randf_range(4.0, 7.0) + l * 0.5 + rng.randf_range(-0.5, 0.5)
			var yaw := rng.randf_range(-0.08, 0.08)
			var turn := Transform3D(Basis(Vector3.UP, yaw), Vector3())
			var house := _frame(along, side, off) * turn
			kit.house(house, w, l, floors, mat)
			var door := _frame(along, side, off - l * 0.5 - 1.0) * turn
			for _k in rng.randi_range(0, 3):
				var p := door * Vector3(rng.randf_range(-w * 0.5, w * 0.5), 0.0, rng.randf_range(-0.6, 0.6))
				kit.prop(["props/Barrel", "props/Crate_Wooden", "props/Bucket_Wooden_1", "village/Prop_Crate"][rng.randi() % 4], p, rng.randf() * TAU)
			s += w + rng.randf_range(3.2, 7.0)
			if rng.randf() < 0.35:
				var a := _frame(s - 1.5, side, Route.HALF_WIDTH + 3.0)
				kit.fence(a.origin, a.basis.z, 3, func(_x: float, _z: float) -> float: return a.origin.y + 0.1)
	var church := _frame(s0 - 6.0, church_side, Route.HALF_WIDTH + 4.0 + 10.0)
	kit.church(church)
	var square := _frame(s0, -church_side, Route.HALF_WIDTH + 2.5)
	kit.prop("props/Stall_Cart_Empty", square * Vector3(-3.0, 0.0, 0.0), _yaw_of(square.basis.z) + PI)
	kit.prop("props/Stall_Empty", square * Vector3(2.5, 0.0, 0.0), _yaw_of(square.basis.z) + PI)
	kit.prop("props/Bench", church * Vector3(5.0, 0.0, -10.0), _yaw_of(church.basis.z) + PI)
	var wagon := _frame(s0 + 40.0, church_side, Route.HALF_WIDTH + 2.5)
	kit.prop("village/Prop_Wagon", wagon.origin, _yaw_of(wagon.basis.x))
	var n := kit.build(node, 1600.0)
	print("  village built: %d modules" % n)


## A lake in a hollow beside the road: water, a jetty of planks on posts from the
## near shore, a boathouse beside it, and the raft (local pack) moored there.
func _lake(node: Node3D, data: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = data.centre
	var toward: Vector3 = data.toward   # from the lake to the road
	var level := c.y - 1.6
	var water := ShaderMaterial.new()
	water.shader = load("res://shaders/water.gdshader")
	water.set_shader_parameter("shallow", Color(0.30, 0.55, 0.50))
	water.set_shader_parameter("deep", Color(0.10, 0.26, 0.32))
	var disc := CylinderMesh.new()
	disc.top_radius = LAKE_R + 14.0
	disc.bottom_radius = LAKE_R + 14.0
	disc.height = 0.02
	disc.radial_segments = 48
	var wi := MeshInstance3D.new()
	wi.mesh = disc
	wi.material_override = water
	wi.position = Vector3(c.x, level, c.z)
	wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(wi)
	if not VillageKit.available():
		return
	var kit := VillageKit.new()
	kit.rng.seed = rng.randi()
	var out := -toward
	var yaw := _yaw_of(out)
	var side := out.cross(Vector3.UP).normalized()
	var shore := c + toward * (LAKE_R - 2.0)
	shore.y = level + 0.55
	for k in 9:
		var p := shore + out * (k * 2.0)
		kit.put("village/Floor_WoodDark", Transform3D(Basis(Vector3.UP, yaw), p))
		if k % 2 == 0:
			for sx: float in [-0.9, 0.9]:
				kit.put("village/Prop_Support", Transform3D(Basis(), p + side * sx - Vector3.UP * 2.6))
	kit.prop("props/Barrel", shore + out * 16.0 + side * 0.5, rng.randf() * TAU)
	# the boathouse on the bank beside the jetty, facing the water
	var bh := c + toward * (LAKE_R + 8.0) + side * 10.0
	var z := toward
	var x := Vector3.UP.cross(z).normalized()
	kit.house(Transform3D(Basis(x, Vector3.UP, z), Vector3(bh.x, c.y - 0.3, bh.z)), 4, 6, 1, "Plaster")
	kit.prop("props/Bench", c + toward * (LAKE_R + 6.0) - side * 6.0 + Vector3.UP * (c.y - 0.2 - c.y), yaw)
	kit.build(node, 1600.0)
	if MegaKit.has_pack("local/raft"):
		var raft := MeshInstance3D.new()
		raft.mesh = MegaKit.mesh("local/raft/EA04_Wehicule_Raft_01a", MegaKit.SOLID, MegaKit.PROP)
		raft.position = shore + out * 12.0 + side * 3.5
		raft.position.y = level - 0.5
		raft.rotation.y = yaw + 0.4
		node.add_child(raft)


## A ruined desert fort: two towers joined by broken walls round a yard with a fire,
## a cauldron, barrels, a flag and a washing line (Raft pack, local only).
func _fort(node: Node3D, data: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = data.centre
	var z: Vector3 = data.out
	var x := Vector3.UP.cross(z).normalized()
	var frame := Transform3D(Basis(x, Vector3.UP, z), c)
	var items := [
		["EA04_Bld_Tower_Main_01a", Vector3(-12, 0, -4), 0.3], ["EA04_Bld_Tower_Main_02a", Vector3(12, 0, 6), -2.6],
		["EA04_Bld_Wall_Straight_01a", Vector3(-2, 0, -9), 0.0], ["EA04_Bld_Wall_Straight_01c", Vector3(4, 0, 15), PI],
		["EA04_Bld_Wall_Straight_01e", Vector3(-15, 0, 8), PI * 0.5],
		["EA04_Prop_Fireplace_01a", Vector3(0, 0, 3), 0.0], ["EA04_Prop_cauldron_01a", Vector3(1.2, 0, 3.4), 0.0],
		["EA04_Prop_Barrel_01a", Vector3(-6, 0, 9), 0.0], ["EA04_Prop_Barrel_01a", Vector3(-5, 0, 10.2), 1.0],
		["EA04_Prop_Flag_01a", Vector3(9, 0, -6), 0.0], ["EA04_Prop_washing_Comp", Vector3(-4, 0, -2), 0.6],
		["EA04_Prop_Skull_01a", Vector3(6, 0, -10), 2.0], ["EA04_Prop_cover_01a", Vector3(-8, 0, 2), 0.2],
	]
	for it: Array in items:
		var mi := MeshInstance3D.new()
		mi.mesh = MegaKit.mesh("local/raft/" + it[0], MegaKit.SOLID, MegaKit.PROP)
		mi.transform = frame * Transform3D(Basis(Vector3.UP, it[2] + rng.randf_range(-0.1, 0.1)), it[1] - Vector3.UP * 0.2)
		node.add_child(mi)


## A cairn of stacked stones with a banner on a post, on the road's shoulder at a
## summit.
func _summit_marker(node: Node3D, data: Dictionary, rng: RandomNumberGenerator) -> void:
	var at: Vector3 = data.at - Vector3.UP * 0.2
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon_vcol.gdshader")
	for k in 4:
		var mi := MeshInstance3D.new()
		if MegaKit.available():
			mi.mesh = MegaKit.mesh("Rock_Medium_%d" % (rng.randi() % 3 + 1), MegaKit.SOLID, MegaKit.PROP)
		else:
			mi.mesh = Meshes.rock(rng)
			mi.material_override = mat
		mi.position = at + Vector3(rng.randf_range(-0.15, 0.15), k * 0.5, rng.randf_range(-0.15, 0.15))
		mi.scale = Vector3.ONE * (0.75 - k * 0.14)
		mi.rotation.y = rng.randf() * TAU
		node.add_child(mi)
	if VillageKit.available():
		var kit := VillageKit.new()
		var r: Vector3 = data.right
		var post := at + r * 1.6
		kit.put("village/Prop_Support", Transform3D(Basis(), post))
		kit.put("props/Banner_1", Transform3D(Basis(Vector3.UP, _yaw_of(r) - PI * 0.5), post + Vector3.UP * 3.0))
		kit.build(node, 1200.0)
