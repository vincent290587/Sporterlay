class_name GalleryWorld
extends RefCounted
## A test bench for models: every tree on flat ground, in rows by level of detail
## (front row full detail, then light, then far crown), to judge them side by side.
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
	# a road loop far around, so the rider has somewhere to be
	var loop := PackedVector2Array()
	for n in 64:
		var ang := TAU * n / 64
		loop.append(Vector2(cos(ang), sin(ang)) * 200.0)
	route.build_loop(loop, func(_x: float, _z: float) -> float: return 0.0, func(_x: float, _z: float) -> float: return 0.0)
