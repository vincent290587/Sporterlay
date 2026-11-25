class_name GalleryWorld
extends RefCounted
## A test bench for models: every tree on flat ground, in rows by level of detail
## (front row full detail, then light, then far crown), to judge them side by side.
## If the Stylized Nature MegaKit is in assets/megakit, its trees and small props stand
## in two rows in front, as shipped.
## Use with --cam=x,y,z,tx,ty,tz and --shot.

const TITLE := "Gallery"

var route := Route.new()


func build(parent: Node3D, seed: int) -> void:
	Look.apply(parent)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	ground.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon_vcol.gdshader")
	ground.material_override = mat
	plane.material = mat
	parent.add_child(ground)
	var g := MeshBuilder.new()   # a flat green ground with vertex colour
	var green := Color(0.52, 0.66, 0.28)
	var a := g.add(Vector3(-300, 0, -300), Vector3.UP, green)
	var b := g.add(Vector3(300, 0, -300), Vector3.UP, green)
	var c := g.add(Vector3(300, 0, 300), Vector3.UP, green)
	var d := g.add(Vector3(-300, 0, 300), Vector3.UP, green)
	g.quad(a, b, c, d)
	ground.mesh = g.commit()
	var makers := [
		func(r: RandomNumberGenerator, lod: int) -> ArrayMesh: return TreeGen.branching(r, TreeGen.BROADLEAF, RiverEcology.ORANGE[0], RiverEcology.ORANGE[1], TreeGen.BARK, false, lod),
		func(r: RandomNumberGenerator, lod: int) -> ArrayMesh: return TreeGen.branching(r, TreeGen.BROADLEAF, Meshes.LEAF_DARK, Meshes.LEAF_LIGHT, TreeGen.BARK, false, lod),
		func(r: RandomNumberGenerator, lod: int) -> ArrayMesh: return TreeGen.birch(r, RiverEcology.BIRCH[0], RiverEcology.BIRCH[1], lod),
		func(r: RandomNumberGenerator, lod: int) -> ArrayMesh: return TreeGen.branching(r, TreeGen.PINE, Meshes.NEEDLE_DARK, Meshes.NEEDLE_LIGHT, TreeGen.PINE_BARK, false, lod),
		func(r: RandomNumberGenerator, lod: int) -> ArrayMesh: return TreeGen.spruce(r, 16.0, 2.9, 9, Meshes.NEEDLE_DARK.darkened(0.1), Meshes.NEEDLE_LIGHT, lod),
	]
	for k in makers.size():
		var models := TreeGen.lods(rng, makers[k])
		for lod in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = models[lod]
			mi.position = Vector3((k - (makers.size() - 1) * 0.5) * 11.0, 0.0, -lod * 14.0)
			parent.add_child(mi)
	# grass types, a patch each, left to right: short, average, tall (at x = -60)
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	for kind in 3:
		var inst := Instancer.new(32.0)
		for _i in 160:
			var p := Vector3(-66.0 + kind * 6.0 + rng.randf_range(-2.4, 2.4), 0.0, rng.randf_range(-3.0, 3.0))
			inst.put(p, rng.randf() * TAU, rng.randf_range(0.8, 1.3), rng.randf_range(0.7, 1.15), Color(0.56, 0.70, 0.30))
		inst.build(parent, Meshes.grass(rng, kind), grass_mat, 0.0, false)
	var heads := [["plume", Color(0.93, 0.88, 0.74)], ["plume", Color(0.74, 0.52, 0.4)], ["haze", Color(0.66, 0.42, 0.78)],
		["star", Color(0.55, 0.35, 0.85)], ["star", Color(0.97, 0.97, 0.93)], ["star", Color(1.0, 0.85, 0.2)]]
	for k in heads.size():
		var m: ShaderMaterial = grass_mat.duplicate()
		m.set_shader_parameter("head_color", heads[k][1])
		var inst := Instancer.new(32.0)
		for _i in 70:
			inst.put(Vector3(-75.0 + k * 5.0 + rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-10.0, -6.0)), rng.randf() * TAU,
				rng.randf_range(0.8, 1.2), rng.randf_range(0.75, 1.1), Color(0.56, 0.70, 0.30))
		inst.build(parent, Meshes.grass(rng, Meshes.GRASS_FLOWERING, Vector3.ZERO, heads[k][0]), m, 0.0, false)

	# MegaKit trees at each level of detail (--megakit=lods): columns per tier
	if "--megakit=lods" in OS.get_cmdline_user_args() and MegaKit.available():
		var models := [["TwistedTree_1", MegaKit.TREE], ["TwistedTree_3", MegaKit.TREE], ["DeadTree_1", MegaKit.SOLID]]
		for k in models.size():
			for tier in 3:
				var m := MegaKit.mesh(models[k][0], models[k][1], tier)
				print("%s tier %d: %d triangles" % [models[k][0], tier, MegaKit.triangles(m)])
				var mi := MeshInstance3D.new()
				mi.mesh = m
				mi.position = Vector3(80.0 + (tier - 1) * 14.0, 0.0, k * 18.0)
				parent.add_child(mi)
		_road()
		return

	# Quaternius' Stylized Nature MegaKit, as shipped, in front: trees, then small props
	if DirAccess.dir_exists_absolute("res://assets/megakit"):
		var trees := ["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_5", "DeadTree_1", "DeadTree_3", "Bush_Common"]
		for k in trees.size():
			_place(parent, trees[k], Vector3((k - (trees.size() - 1) * 0.5) * 9.0, 0.0, 16.0))
		var small := ["Bush_Common", "Bush_Common_Flowers", "Fern_1", "Plant_1", "Plant_1_Big", "Plant_7", "Plant_7_Big",
			"Mushroom_Common", "Mushroom_Laetiporus",
			"Rock_Medium_1", "Rock_Medium_3", "Pebble_Round_1", "Pebble_Square_2"]
		for k in small.size():
			_place(parent, small[k], Vector3((k - (small.size() - 1) * 0.5) * 2.6, 0.0, 26.0))

	_road()


## A road loop far around, so the rider has somewhere to be.
func _road() -> void:
	var loop := PackedVector2Array()
	for n in 64:
		var ang := TAU * n / 64
		loop.append(Vector2(cos(ang), sin(ang)) * 200.0)
	route.build_loop(loop, func(_x: float, _z: float) -> float: return 0.0, func(_x: float, _z: float) -> float: return 0.0)


## A MegaKit model: as shipped, or (--megakit=toon) through MegaKit with our shading.
func _place(parent: Node3D, model: String, at: Vector3) -> void:
	if "--megakit=toon" in OS.get_cmdline_user_args():
		var style := MegaKit.SOLID
		if model.begins_with("TwistedTree") or model.begins_with("CommonTree") or model.begins_with("Pine") or model.begins_with("Bush"):
			style = MegaKit.TREE
		elif not (model.begins_with("Rock") or model.begins_with("Pebble") or model.begins_with("Mushroom") or model.begins_with("DeadTree")):
			style = MegaKit.PLANT
		var mi := MeshInstance3D.new()
		mi.mesh = MegaKit.mesh(model, style)
		mi.position = at
		parent.add_child(mi)
		return
	var scene: PackedScene = load("res://assets/megakit/%s.gltf" % model)
	if scene == null:
		push_warning("no model " + model)
		return
	var node: Node3D = scene.instantiate()
	node.position = at
	parent.add_child(node)
