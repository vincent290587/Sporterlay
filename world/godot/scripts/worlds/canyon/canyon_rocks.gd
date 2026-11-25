class_name CanyonRocks
extends RefCounted
## Rock formations that give the open desert something to look at: hoodoo gardens
## (stacked spires with a hard caprock) near the road, tall lone spires further out,
## and a natural stone arch the road passes under. All drawn with the canyon ground
## material, so they carry the same strata lines as the cliffs.

const ARCH_AT := 0.36        # where round the loop (fraction) the arch stands
const RED := Color(0.72, 0.36, 0.22)
const ORANGE := Color(0.83, 0.50, 0.30)
const CREAM := Color(0.90, 0.78, 0.60)
const CAP := Color(0.62, 0.56, 0.50)


static func build(parent: Node3D, land: CanyonLand, route: Route, seed: int, mat: Material, blocked: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 500
	var free := func(x: float, z: float, clear: float) -> bool:
		return land.road_distance_at(x, z) > Route.HALF_WIDTH + clear and not (blocked.is_valid() and blocked.call(x, z)) \
			and land.normal_at(x, z).y > 0.8

	# hoodoo gardens: clusters a little way off the road, away from the canyon
	var hoodoos: Array[Instancer] = [Instancer.new(150.0), Instancer.new(150.0), Instancer.new(150.0)]
	var gardens := 0
	var s := rng.randf_range(300.0, 600.0)
	while s < route.length:
		var u := absf(s - route.length * CanyonLand.RUINS_AT)
		if u > CanyonLand.CANYON + 200.0:
			gardens += 1
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var c := route.position_at(s) + route.right_at(s) * side * rng.randf_range(35.0, 120.0)
			var count := rng.randi_range(14, 34)
			for _k in count:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * rng.randf_range(35.0, 70.0)
				var x := c.x + cos(a) * r
				var z := c.z + sin(a) * r
				if not free.call(x, z, 6.0):
					continue
				var h := rng.randf_range(5.0, 17.0)
				var w := rng.randf_range(1.6, 3.2) * (0.6 + h / 25.0)
				hoodoos[rng.randi() % 3].put(Vector3(x, land.height_at(x, z) - 0.5, z), rng.randf() * TAU, w, h, Color(1, 1, 1).darkened(rng.randf() * 0.12))
		s += rng.randf_range(700.0, 1200.0)
	var n := 0
	for i in 3:
		n += hoodoos[i].build(parent, _hoodoo(rng), mat, 1200.0, true, 0.0, "boulders")

	# lone spires and buttes out in the desert
	var spires := Instancer.new(400.0)
	var placed := 0
	var tries := 0
	while placed < 40 and tries < 3000:
		tries += 1
		var x := rng.randf_range(-CanyonLand.HALF + 100.0, CanyonLand.HALF - 100.0)
		var z := rng.randf_range(-CanyonLand.HALF + 100.0, CanyonLand.HALF - 100.0)
		# well away from the road (its distance field stops at ROAD_REACH)
		if land.road_distance_at(x, z) < CanyonLand.ROAD_REACH - 0.5 or not free.call(x, z, 0.0):
			continue
		var h := rng.randf_range(22.0, 55.0)
		spires.put(Vector3(x, land.height_at(x, z) - 1.0, z), rng.randf() * TAU, rng.randf_range(5.0, 11.0), h, Color(1, 1, 1).darkened(rng.randf() * 0.1))
		placed += 1
	n += spires.build(parent, _spire(rng), mat, 2500.0, true)

	# the arch over the road
	var arch_s := route.length * ARCH_AT
	var mi := MeshInstance3D.new()
	mi.mesh = _arch(rng, route.position_at(arch_s), route.right_at(arch_s), route.tangent_at(arch_s))
	mi.material_override = mat
	parent.add_child(mi)
	print("  rock formations: %d hoodoos in %d gardens, %d spires, an arch at %.1f km" % [n - placed, gardens, placed, arch_s / 1000.0])


## A surface of revolution: `profile` is [height 0..1, radius, colour] from the
## bottom up; each ring wobbles a little so it reads as eroded rock.
static func _lathe(rng: RandomNumberGenerator, profile: Array, sides: int, wobble: float) -> MeshBuilder:
	var b := MeshBuilder.new()
	var rings := []
	var phase := rng.randf() * TAU
	for p: Array in profile:
		var ring := []
		for k in sides:
			var a := TAU * k / sides
			var r: float = p[1] * (1.0 + (rng.randf() - 0.5) * wobble + sin(a * 3.0 + phase) * wobble * 0.5)
			ring.append(Vector3(cos(a) * r, p[0], sin(a) * r))
		rings.append(ring)
	for i in rings.size() - 1:
		var lo: Array = rings[i]
		var hi: Array = rings[i + 1]
		var col: Color = profile[i][2]
		for k in sides:
			var k2 := (k + 1) % sides
			var n: Vector3 = ((lo[k] + lo[k2]) * 0.5 - Vector3(0.0, lo[k].y, 0.0)).normalized()
			var slope: Vector3 = (hi[k] + hi[k2]) * 0.5 - (lo[k] + lo[k2]) * 0.5
			n = (n - slope.normalized() * n.dot(slope.normalized())).normalized()
			if n.length() < 0.1:
				n = Vector3.UP
			var j := b.add(lo[k], n, col)
			b.add(lo[k2], n, col)
			b.add(hi[k2], n, col)
			b.add(hi[k], n, col)
			b.quad(j, j + 1, j + 2, j + 3)
	# flat top
	var top: Array = rings[rings.size() - 1]
	var tc := Vector3(0.0, top[0].y, 0.0)
	var m := b.add(tc, Vector3.UP, profile[profile.size() - 1][2])
	for k in sides:
		var j := b.add(top[k], Vector3.UP, profile[profile.size() - 1][2])
		b.add(top[(k + 1) % sides], Vector3.UP, profile[profile.size() - 1][2])
		b.tri(m, j, j + 1)
	return b


## A hoodoo, unit height: a bulging, necked column of soft red rock under a wider
## slab of hard grey caprock.
static func _hoodoo(rng: RandomNumberGenerator) -> ArrayMesh:
	var profile := []
	var segs := 7
	for i in segs + 1:
		var t := float(i) / segs
		var r := lerpf(1.0, 0.55, t) * (0.82 + 0.22 * sin(t * PI * rng.randf_range(2.5, 4.0) + rng.randf()))
		profile.append([t * 0.88, r, RED.lerp(ORANGE, t * 0.8).lerp(CREAM, smoothstep(0.6, 0.9, t) * 0.5)])
	profile.append([0.88, 0.85, CAP])
	profile.append([0.95, 0.9, CAP])
	profile.append([1.0, 0.7, CAP])
	return _lathe(rng, profile, 9, 0.18).faceted().commit()


## A spire, unit height: stepped like the mesas (cliff, bench, cliff), flat-topped.
static func _spire(rng: RandomNumberGenerator) -> ArrayMesh:
	var profile := [[0.0, 1.6, RED], [0.08, 1.35, RED], [0.12, 1.0, ORANGE], [0.45, 0.95, ORANGE], [0.5, 0.78, CREAM],
		[0.55, 0.7, RED], [0.9, 0.62, ORANGE], [1.0, 0.55, CREAM]]
	return _lathe(rng, profile, 11, 0.12).faceted().commit()


## A natural arch across the road: a thick, eroded band of rock swept along a tall
## half-ellipse in the plane across the road, its feet sunk into rock piles.
static func _arch(rng: RandomNumberGenerator, at: Vector3, right: Vector3, fwd: Vector3) -> ArrayMesh:
	var b := MeshBuilder.new()
	var span := 17.0
	var rise := 22.0
	var steps := 36
	var around := 10
	var rings := []
	for i in steps + 1:
		var t := lerpf(-0.18, PI + 0.18, float(i) / steps)
		var centre := at + right * cos(t) * span + Vector3.UP * sin(t) * rise
		var tangent := (right * -sin(t) * span + Vector3.UP * cos(t) * rise).normalized()
		var outward := tangent.cross(fwd).normalized()
		if outward.dot(centre - at) < 0.0:
			outward = -outward
		var thick := lerpf(3.2, 5.5, absf(cos(t)))   # thicker at the feet
		var deep := lerpf(4.5, 7.0, absf(cos(t)))
		var ring := []
		for k in around:
			var a := TAU * k / around
			var w := 1.0 + (rng.randf() - 0.5) * 0.25
			ring.append(centre + outward * cos(a) * thick * w + fwd * sin(a) * deep * w)
		rings.append(ring)
	for i in steps:
		var y0 := (rings[i][0] as Vector3).y - at.y
		var col := RED.lerp(ORANGE, smoothstep(0.0, rise, y0)).lerp(CREAM, smoothstep(rise * 0.8, rise * 1.2, y0) * 0.5)
		for k in around:
			var k2 := (k + 1) % around
			var p0: Vector3 = rings[i][k]
			var p1: Vector3 = rings[i][k2]
			var p2: Vector3 = rings[i + 1][k2]
			var p3: Vector3 = rings[i + 1][k]
			var c: Vector3 = (rings[i][0] + rings[i][around / 2] + rings[i + 1][0] + rings[i + 1][around / 2]) * 0.25
			var n: Vector3 = ((p0 + p1 + p2 + p3) * 0.25 - c).normalized()
			var j := b.add(p0, n, col)
			b.add(p1, n, col)
			b.add(p2, n, col)
			b.add(p3, n, col)
			b.quad(j, j + 1, j + 2, j + 3)
	# the feet: heaps of fallen blocks
	for side: float in [-1.0, 1.0]:
		var foot := at + right * side * span
		for _k in 6:
			var c := foot + right * side * rng.randf_range(-2.0, 6.0) + fwd * rng.randf_range(-6.0, 6.0) + Vector3.UP * rng.randf_range(-1.0, 2.5)
			Meshes.blob(b, c, Vector3(rng.randf_range(2.0, 4.0), rng.randf_range(1.5, 3.0), rng.randf_range(2.0, 4.0)), 3, 6, rng, 0.25, RED.darkened(0.1), ORANGE)
	return b.faceted().commit()
