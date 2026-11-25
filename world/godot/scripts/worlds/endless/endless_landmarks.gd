class_name EndlessLandmarks
extends Node3D
## Set pieces every 10-20 km of road, chosen by the biome there: in the dusk forest
## Transylvania's castle on a crag beside the road, in the canyon a natural stone
## arch over it. Valley and autumn get none yet.
##
## A landmark is planned when the road reaching it is generated (6 km ahead of the
## rider, before any tile there is built), which registers its pad with the land
## (EndlessLand.pads) so the tiles raise the ground for it; it's built as the rider
## comes within BUILD_AT and freed once DROP_AT behind.

const BUILD_AT := 2500.0
const DROP_AT := 800.0
const CASTLE_OFF := 115.0     # castle centre from the road
const CASTLE_RISE := 38.0     # its crag above the road

var route: StreamRoute
var land: EndlessLand
var rider: Rider
var seed := 0
var planned: Array = []        # [s, kind, data, node or null]
var _next_s := 0.0
var _index := 0


func plan_up_to(s_max: float) -> void:
	if _next_s == 0.0:
		_next_s = _gap(0) * 0.6   # the first one comes a little sooner
	while _next_s < s_max:
		var s := _next_s
		var b := land.biomes.kinds[land.biomes._segment(s)]
		var p := route.position_at(s)
		var right := route.right_at(s)
		var fwd := route.tangent_at(s)
		if b == EndlessBiomes.DUSK:
			var side := -1.0 if _rand(_index, 1) < 0.5 else 1.0
			var c := p + right * side * CASTLE_OFF
			var h := p.y + CASTLE_RISE
			land.add_pad(Vector2(c.x, c.z), 80.0, h, 38.0)
			planned.append([s, "castle", {"centre": Vector3(c.x, h, c.z), "fwd": fwd, "right": right}, null])
		elif b == EndlessBiomes.CANYON:
			planned.append([s, "arch", {"at": p, "right": right, "fwd": fwd}, null])
		if b == EndlessBiomes.DUSK or b == EndlessBiomes.CANYON:
			print("  landmark: %s at %.1f km" % [planned.back()[1], s / 1000.0])
		_index += 1
		_next_s = s + _gap(_index)


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
			p[3] = _build(p[1], p[2])
		elif p[3] != null and (d < -DROP_AT or d > BUILD_AT + 500.0):
			(p[3] as Node).queue_free()
			p[3] = null
	planned = planned.filter(func(p: Array) -> bool: return p[3] != null or float(p[0]) - s > -DROP_AT)


func _build(kind: String, data: Dictionary) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(seed, int(data.get("centre", data.get("at", Vector3.ZERO)).x)))
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
	return node
