class_name EndlessScatter
extends RefCounted
## Where plants and rocks go on a near tile, worked out on the tile's worker thread
## from its heights, road distances and biome weights. Each spot picks a biome by
## its weights, then that biome's rules choose what grows there. Returns one
## Instancer per kind (see EndlessKit).

const CELL := 7.0


static func scatter(tile: Dictionary, road: Array, land: EndlessLand, seed: int) -> Dictionary:
	var biomes := land.biomes
	var key: Vector2i = tile.key
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, seed))
	var sets := {}
	var put := func(kind: String, pos: Vector3, yaw: float, sxz: float, sy: float, col: Color) -> void:
		if not sets.has(kind):
			sets[kind] = Instancer.new(128.0)
		(sets[kind] as Instancer).put(pos, yaw, sxz, sy, col)
	var o: Vector2 = tile.origin
	var forest := FastNoiseLite.new()
	forest.seed = seed + 900
	forest.frequency = 0.004
	forest.fractal_octaves = 3

	# trees, shrubs, cacti, rocks: one candidate per cell
	var x := 0.0
	while x < EndlessLand.TILE:
		var z := 0.0
		while z < EndlessLand.TILE:
			var px := o.x + x + rng.randf() * CELL
			var pz := o.y + z + rng.randf() * CELL
			z += CELL
			var at := _sample(tile, px, pz)
			if at.is_empty():
				continue
			var rd: float = at.rd
			var ny: float = at.ny
			if rd < Route.HALF_WIDTH + 4.0 or ny < 0.78:
				continue
			if land.pad_inside(px, pz, 90.0):   # a clearing round each landmark, so it's seen
				continue
			var b := _pick(rng, at.w)
			var dense := smoothstep(-0.15, 0.35, forest.get_noise_2d(px, pz))
			var pos := Vector3(px, float(at.h) - 0.1, pz)
			var yaw := rng.randf() * TAU
			var tint := Color(1, 1, 1).darkened(rng.randf() * 0.15)
			var r := rng.randf()
			match b:
				EndlessBiomes.VALLEY:
					if r < dense * 0.45 + 0.004:
						var s := rng.randf_range(0.7, 1.35)
						put.call(("pine%d" if rng.randf() < 0.3 else "broad%d") % (rng.randi() % 3), pos, yaw, s, s * rng.randf_range(0.9, 1.2), tint)
					elif r < 0.52 and rng.randf() < 0.05:
						_rock(put, rng, pos, rd)
				EndlessBiomes.AUTUMN:
					if r < dense * 0.55 + 0.006:
						var s := rng.randf_range(0.7, 1.3)
						var pick := rng.randf()
						var kind := "orange" if pick < 0.35 else ("red" if pick < 0.55 else ("yellow" if pick < 0.75 else ("birch" if pick < 0.9 else "broad")))
						put.call("%s%d" % [kind, rng.randi() % 3], pos, yaw, s, s * rng.randf_range(0.9, 1.15), tint)
					elif r < 0.65 and rng.randf() < 0.12:
						put.call("bush", pos, yaw, rng.randf_range(0.8, 1.4), rng.randf_range(0.7, 1.1), Color(0.75, 0.55, 0.3).darkened(rng.randf() * 0.2))
				EndlessBiomes.DUSK:
					if r < dense * 0.6 + 0.03:
						var s := rng.randf_range(0.75, 1.3)
						var pick := rng.randf()
						if pick < 0.14:
							put.call("dead%d" % (rng.randi() % 5), pos, yaw, s * 0.8, s * 0.8, Color(0.8, 0.8, 0.85))
						elif pick < 0.22:
							put.call("twisted%d" % (rng.randi() % 5), pos, yaw, s, s, tint)
						elif pick < 0.4:
							put.call("beech%d" % (rng.randi() % 3), pos, yaw, s, s * rng.randf_range(0.9, 1.1), tint.darkened(0.1))
						else:
							put.call("spruce%d" % (rng.randi() % 3), pos, yaw, s, s * rng.randf_range(0.95, 1.2), tint)
					elif rng.randf() < 0.05:
						_rock(put, rng, pos, rd)
				_:
					if ny < 0.86:
						continue
					if r < 0.04:
						var s := rng.randf_range(0.35, 0.7)
						put.call("juniper%d" % (rng.randi() % 3), pos, yaw, s, s, tint)
					elif r < 0.08:
						var s := rng.randf_range(0.5, 1.1)
						put.call("bush", pos, yaw, s * 1.3, s * 0.8, Color(0.62, 0.66, 0.52).darkened(rng.randf() * 0.2))
					elif r < 0.1 and rd > Route.HALF_WIDTH + 6.0:
						var s := rng.randf_range(0.65, 1.35)
						put.call("saguaro%d" % (rng.randi() % 4), pos, yaw, s, s, tint)
					elif r < 0.13:
						var s := rng.randf_range(0.6, 1.3)
						put.call(("barrel%d" if rng.randf() < 0.5 else "pear%d") % (rng.randi() % 2), pos, yaw, s, s, tint)
					elif r < 0.135 and rd > 20.0:
						var h := rng.randf_range(5.0, 15.0)
						put.call("hoodoo%d" % (rng.randi() % 2), pos - Vector3(0, 0.5, 0), yaw, rng.randf_range(1.6, 3.0) * (0.6 + h / 25.0), h, tint)
					elif r < 0.15:
						_rock(put, rng, pos, rd)
		x += CELL

	# grass and flowers by the road, thinning out to ~120 m; ferns in the dusk forest
	var rp: PackedVector3Array = road[0]
	for q in range(0, rp.size(), 2):
		var p := rp[q]
		if p.x < o.x - 10.0 or p.z < o.y - 10.0 or p.x > o.x + EndlessLand.TILE + 10.0 or p.z > o.y + EndlessLand.TILE + 10.0:
			continue
		for _k in 30:
			var a := rng.randf() * TAU
			var u := rng.randf()
			var dist := Route.HALF_WIDTH + 0.6 + u * u * 120.0
			var px := p.x + cos(a) * dist
			var pz := p.z + sin(a) * dist
			if px < o.x or pz < o.y or px >= o.x + EndlessLand.TILE or pz >= o.y + EndlessLand.TILE:
				continue
			var at := _sample(tile, px, pz)
			if at.is_empty() or float(at.rd) < Route.HALF_WIDTH + 0.6 or float(at.ny) < 0.8:
				continue
			if land.pad_inside(px, pz, 4.0):
				continue   # no grass through the village houses or in the lake
			var b := _pick(rng, at.w)
			var pos := Vector3(px, float(at.h) - 0.03, pz)
			var yaw := rng.randf() * TAU
			var r := rng.randf()
			match b:
				EndlessBiomes.VALLEY:
					if r < 0.5:
						put.call("grass_short", pos, yaw, rng.randf_range(0.8, 1.3), rng.randf_range(0.7, 1.1), Color(0.62, 0.78, 0.36).darkened(rng.randf() * 0.2))
					elif r < 0.85:
						put.call("grass_mid", pos, yaw, rng.randf_range(0.8, 1.3), rng.randf_range(0.7, 1.1), Color(0.55, 0.72, 0.30).darkened(rng.randf() * 0.2))
					elif r < 0.93:
						put.call("grass_tall", pos, yaw, rng.randf_range(0.8, 1.2), rng.randf_range(0.7, 1.0), Color(0.62, 0.74, 0.34))
					else:
						put.call("flowers_y" if rng.randf() < 0.5 else "flowers_p", pos, yaw, 1.0, rng.randf_range(0.7, 1.1), Color.WHITE)
				EndlessBiomes.AUTUMN:
					if r < 0.55:
						put.call("grass_mid", pos, yaw, rng.randf_range(0.8, 1.3), rng.randf_range(0.7, 1.1), Color(0.84, 0.70, 0.36).darkened(rng.randf() * 0.2))
					elif r < 0.9:
						put.call("grass_tall", pos, yaw, rng.randf_range(0.8, 1.2), rng.randf_range(0.7, 1.0), Color(0.78, 0.56, 0.30).darkened(rng.randf() * 0.2))
					else:
						put.call("grass_short", pos, yaw, 1.2, 0.8, Color(0.70, 0.62, 0.32))
				EndlessBiomes.DUSK:
					if r < 0.25 and float(at.rd) > Route.HALF_WIDTH + 1.8:
						put.call("fern", pos, yaw, rng.randf_range(0.7, 1.3), rng.randf_range(0.7, 1.3), Color(0.45, 0.5, 0.42).darkened(rng.randf() * 0.3))
					elif r < 0.6:
						put.call("grass_mid", pos, yaw, rng.randf_range(0.8, 1.2), rng.randf_range(0.7, 1.0), Color(0.30, 0.38, 0.22).darkened(rng.randf() * 0.2))
				_:
					if r < 0.35:
						put.call("grass_short", pos, yaw, rng.randf_range(0.8, 1.5), rng.randf_range(0.6, 1.2), Color(0.88, 0.75, 0.48).darkened(rng.randf() * 0.2))
					elif r < 0.55:
						put.call("grass_tall", pos, yaw, rng.randf_range(0.7, 1.1), rng.randf_range(0.5, 0.85), Color(0.92, 0.80, 0.52).darkened(rng.randf() * 0.15))
					elif r < 0.62:
						put.call("flowers_y", pos, yaw, 1.0, rng.randf_range(0.6, 0.9), Color.WHITE)
	return sets


static func _rock(put: Callable, rng: RandomNumberGenerator, pos: Vector3, rd: float) -> void:
	var big := rng.randf() < 0.1
	var s := (rng.randf_range(2.5, 6.0) if big else rng.randf_range(0.5, 1.5)) * 0.6
	if rd < Route.HALF_WIDTH + 1.0 + s * 1.4:
		return
	put.call("rock%d" % (rng.randi() % 3), pos - Vector3(0, s * 0.15, 0), rng.randf() * TAU, s, s * rng.randf_range(0.6, 1.0), Color(1, 1, 1).darkened(rng.randf() * 0.2))


## Picks a biome by the weights.
static func _pick(rng: RandomNumberGenerator, w: PackedFloat32Array) -> int:
	var r := rng.randf()
	for b in EndlessBiomes.COUNT:
		r -= w[b]
		if r <= 0.0:
			return b
	return EndlessBiomes.COUNT - 1


## Height, slope, road distance and biome weights at a point of the tile.
static func _sample(tile: Dictionary, x: float, z: float) -> Dictionary:
	var g: int = tile.g
	var step: float = tile.step
	var o: Vector2 = tile.origin
	var fx := (x - o.x) / step + 1.0
	var fz := (z - o.y) / step + 1.0
	var i := int(fx)
	var j := int(fz)
	if i < 1 or j < 1 or i >= g - 2 or j >= g - 2:
		return {}
	var hs: PackedFloat32Array = tile.heights
	var k := j * g + i
	var tx := fx - i
	var tz := fz - j
	var h := lerpf(lerpf(hs[k], hs[k + 1], tx), lerpf(hs[k + g], hs[k + g + 1], tx), tz)
	var nrm := Vector3(hs[k - 1] - hs[k + 1], 2.0 * step, hs[k - g] - hs[k + g]).normalized()
	var rd: PackedFloat32Array = tile.road_d
	return {"h": h, "ny": nrm.y, "rd": rd[k], "w": tile.weights[k]}
