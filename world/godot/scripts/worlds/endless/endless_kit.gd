class_name EndlessKit
extends RefCounted
## Every model the endless world scatters, made once on the main thread when the
## world loads (TreeGen, Meshes, MegaKit, the canyon's cacti and hoodoos), and how
## each is drawn: tiers for trees, a single mesh and draw distance for the rest.
## Tiles fill one Instancer per kind on a worker thread; `build()` turns them into
## nodes.

const NEAR := 220.0
const MID := 520.0
const FAR := 950.0
const VISIBLE := 1300.0

var kinds := {}      # name -> {"tiers": [...]} or {"mesh", "mat", "far", "shadows", "lod"}
var _rng := RandomNumberGenerator.new()


func setup(seed: int) -> void:
	_rng.seed = seed + 300
	for c in [["trees", 1.0], ["grass", 0.6], ["boulders", 0.5], ["props", 0.4], ["ferns", 0.3]]:
		Lod.category(c[0], c[1])
	var toon := ShaderMaterial.new()
	toon.shader = load("res://shaders/toon_vcol.gdshader")
	var rock := ShaderMaterial.new()
	rock.shader = load("res://shaders/canyon_ground.gdshader")
	var grass := ShaderMaterial.new()
	grass.shader = load("res://shaders/grass.gdshader")
	Lod.add_param("grass", grass, "fade_start", 120.0)
	Lod.add_param("grass", grass, "fade_end", 170.0)
	var blob: ShaderMaterial = TreeGen.materials(3)[0]
	var mk := MegaKit.available()

	# trees: three variants per kind, each with TreeGen's tiers and a far blob
	var broad := func(pal: Array) -> Callable:
		return func(r: RandomNumberGenerator, lod: int) -> ArrayMesh:
			return TreeGen.branching(r, TreeGen.BROADLEAF, pal[0], pal[1], TreeGen.BARK, false, lod)
	var tree_sets := {
		"broad": [broad.call([Meshes.LEAF_DARK, Meshes.LEAF_LIGHT]), Meshes.broadleaf_far(_rng)],
		"pine": [func(r: RandomNumberGenerator, lod: int) -> ArrayMesh: return TreeGen.spruce(r, 13.0, 3.2, 8, Meshes.NEEDLE_DARK, Meshes.NEEDLE_LIGHT, lod),
			Meshes.conifer_far(12.6, 3.4)],
		"orange": [broad.call(RiverEcology.ORANGE), Meshes.broadleaf_far(_rng, RiverEcology.ORANGE[0], RiverEcology.ORANGE[1])],
		"red": [broad.call(RiverEcology.RED), Meshes.broadleaf_far(_rng, RiverEcology.RED[0], RiverEcology.RED[1])],
		"yellow": [broad.call(RiverEcology.YELLOW), Meshes.broadleaf_far(_rng, RiverEcology.YELLOW[0], RiverEcology.YELLOW[1])],
		"birch": [func(r: RandomNumberGenerator, lod: int) -> ArrayMesh: return TreeGen.birch(r, RiverEcology.BIRCH[0], RiverEcology.BIRCH[1], lod),
			Meshes.birch_far(_rng, RiverEcology.BIRCH[0], RiverEcology.BIRCH[1])],
		"spruce": [func(r: RandomNumberGenerator, lod: int) -> ArrayMesh: return TreeGen.spruce(r, 17.0, 3.0, 9, TransScenery.SPRUCE[0], TransScenery.SPRUCE[1], lod),
			Meshes.conifer_far(17.0, 2.8, TransScenery.SPRUCE[0], TransScenery.SPRUCE[1])],
		"beech": [broad.call(TransScenery.BEECH), Meshes.broadleaf_far(_rng, TransScenery.BEECH[0], TransScenery.BEECH[1])],
	}
	for name: String in tree_sets:
		var make: Callable = tree_sets[name][0]
		var far: Mesh = tree_sets[name][1]
		for v in 3:
			var m := TreeGen.lods(_rng, make)
			kinds["%s%d" % [name, v]] = {"tiers": [
				[m[0], null, 0.0, NEAR, true, TreeGen.materials(0), 100.0],
				[m[1], null, NEAR, MID, false, TreeGen.materials(1), 150.0],
				[m[2], null, MID, FAR, false, TreeGen.materials(2), 300.0],
				[far, blob, FAR, VISIBLE, false, [blob], 500.0]]}
	for v in 3:
		var j := TreeGen.lods(_rng, func(r: RandomNumberGenerator, lod: int) -> ArrayMesh:
			return TreeGen.branching(r, TreeGen.BROADLEAF, CanyonScenery.JUNIPER[0], CanyonScenery.JUNIPER[1], TreeGen.BARK, false, lod))
		kinds["juniper%d" % v] = {"tiers": [
			[j[0], null, 0.0, NEAR, true, TreeGen.materials(0), 100.0],
			[j[1], null, NEAR, MID, false, TreeGen.materials(1), 150.0],
			[j[2], null, MID, VISIBLE, false, TreeGen.materials(2), 300.0]]}
	for v in 5:
		if mk:
			var d0 := MegaKit.mesh("DeadTree_%d" % (v + 1), MegaKit.SOLID, 0)
			var d1 := MegaKit.mesh("DeadTree_%d" % (v + 1), MegaKit.SOLID, 1)
			kinds["dead%d" % v] = {"tiers": [[d0, null, 0.0, NEAR, true, MegaKit.materials_of(d0), 100.0],
				[d1, null, NEAR, MID, false, MegaKit.materials_of(d1), 150.0]]}
			var t := "TwistedTree_%d" % (v + 1)
			var t0 := MegaKit.mesh(t, MegaKit.TREE, 0)
			var t1 := MegaKit.mesh(t, MegaKit.TREE, 1)
			var t2 := MegaKit.mesh(t, MegaKit.TREE, 2)
			kinds["twisted%d" % v] = {"tiers": [[t0, null, 0.0, NEAR, true, MegaKit.materials_of(t0), 100.0],
				[t1, null, NEAR, MID, false, MegaKit.materials_of(t1), 150.0], [t2, null, MID, FAR, false, MegaKit.materials_of(t2), 300.0]]}
		else:
			kinds["dead%d" % v] = {"tiers": [[TreeGen.dead(_rng), null, 0.0, MID, true, TreeGen.materials(4), 150.0]]}
			kinds["twisted%d" % v] = kinds["dead%d" % v]

	# cacti and hoodoos from the canyon
	for v in 4:
		kinds["saguaro%d" % v] = {"mesh": CanyonCacti._saguaro(_rng, v), "mat": toon, "far": 1300.0, "shadows": true, "lod": "trees"}
	for v in 2:
		kinds["barrel%d" % v] = {"mesh": CanyonCacti._barrel(_rng, v == 1), "mat": toon, "far": 300.0, "shadows": true, "lod": "props"}
		kinds["pear%d" % v] = {"mesh": CanyonCacti._pear(_rng), "mat": toon, "far": 300.0, "shadows": true, "lod": "props"}
		kinds["hoodoo%d" % v] = {"mesh": CanyonRocks._hoodoo(_rng), "mat": rock, "far": 1300.0, "shadows": true, "lod": "boulders"}
	kinds["bush"] = {"mesh": Meshes.bush(_rng), "mat": toon, "far": MID, "shadows": true, "lod": "props"}
	if mk:
		for v in 3:
			var r := MegaKit.mesh("Rock_Medium_%d" % (v + 1), MegaKit.SOLID, MegaKit.PROP)
			kinds["rock%d" % v] = {"mesh": r, "mat": null, "far": VISIBLE, "shadows": true, "lod": "boulders"}
		kinds["fern"] = {"mesh": MegaKit.mesh("Fern_1", MegaKit.PLANT, MegaKit.PROP), "mat": null, "far": 130.0, "shadows": false, "lod": "ferns"}
	else:
		for v in 3:
			kinds["rock%d" % v] = {"mesh": Meshes.rock(_rng), "mat": toon, "far": VISIBLE, "shadows": true, "lod": "boulders"}
		kinds["fern"] = {"mesh": Meshes.fern(_rng), "mat": grass, "far": 130.0, "shadows": false, "lod": "ferns"}

	# grass: the valley's four types, flowers, all tinted per instance
	kinds["grass_short"] = {"mesh": Meshes.grass(_rng, Meshes.GRASS_SHORT), "mat": grass, "far": 170.0, "shadows": false, "lod": "grass"}
	kinds["grass_mid"] = {"mesh": Meshes.grass(_rng, Meshes.GRASS_AVERAGE), "mat": grass, "far": 170.0, "shadows": false, "lod": "grass"}
	kinds["grass_tall"] = {"mesh": Meshes.grass(_rng, Meshes.GRASS_TALL), "mat": grass, "far": 170.0, "shadows": false, "lod": "grass"}
	kinds["flowers_y"] = {"mesh": Meshes.flowers(_rng, Color(1.0, 0.82, 0.18)), "mat": grass, "far": 170.0, "shadows": false, "lod": "grass"}
	kinds["flowers_p"] = {"mesh": Meshes.flowers(_rng, Color(0.62, 0.40, 0.85)), "mat": grass, "far": 170.0, "shadows": false, "lod": "grass"}


## Turns one kind's instancer into nodes under `parent`.
func build_one(parent: Node3D, name: String, inst: Instancer) -> void:
	if inst.count() == 0 or not kinds.has(name):
		return
	if true:
		var k: Dictionary = kinds[name]
		# one node per kind and tier per tile: few nodes, so a tile lands in one frame
		if k.has("tiers"):
			var tiers := []
			for t: Array in k.tiers:
				var t2 := t.duplicate()
				t2[6] = EndlessLand.TILE * 0.5
				tiers.append(t2)
			inst.build_tiers(parent, tiers, "trees")
		else:
			inst.build(parent, k.mesh, k.mat, k.far, k.shadows, 0.0, k.lod, 0.0, EndlessLand.TILE)
