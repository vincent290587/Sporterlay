class_name CanyonCacti
extends RefCounted
## Cacti over the open desert, thickest near the road: tall saguaros with arms that
## bend up (seen against the sky from far off), squat barrel cacti with a crown of
## flowers, and prickly pear clumps of flat paddles with magenta fruit. None in the
## canyon, the plaza or the oasis.

const GREEN := Color(0.30, 0.45, 0.24)
const GREEN_LIGHT := Color(0.42, 0.56, 0.30)
const PAD := Color(0.36, 0.52, 0.28)
const PAD_LIGHT := Color(0.50, 0.62, 0.34)
const FRUIT := Color(0.78, 0.16, 0.38)
const BLOSSOM := Color(0.97, 0.95, 0.86)

const SAGUARO_VISIBLE := 1600.0
const SMALL_VISIBLE := 320.0


static func build(parent: Node3D, land: CanyonLand, route: Route, seed: int, blocked: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 400
	var saguaros: Array[Instancer] = [Instancer.new(200.0), Instancer.new(200.0), Instancer.new(200.0), Instancer.new(200.0)]
	var barrels: Array[Instancer] = [Instancer.new(64.0), Instancer.new(64.0)]
	var pears: Array[Instancer] = [Instancer.new(64.0), Instancer.new(64.0), Instancer.new(64.0)]
	var patch := FastNoiseLite.new()
	patch.seed = rng.randi()
	patch.frequency = 0.004
	var hw := Route.HALF_WIDTH
	var ruins_s := route.length * CanyonLand.RUINS_AT
	for m in range(0, route.count(), 2):
		var s := m * route.spacing
		var u := absf(s - ruins_s)
		if minf(u, route.length - u) < CanyonLand.CANYON + 80.0:
			continue
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		for _k in 5:
			var v := rng.randf_range(-1.0, 1.0)
			var pos := p + t * rng.randf_range(-2.0, 2.0) + right * (hw + 2.0 + v * v * 360.0) * signf(v)
			if rng.randf() > smoothstep(-0.5, 0.4, patch.get_noise_2d(pos.x, pos.z)) * 0.75 + 0.05:
				continue
			var rd := land.road_distance_at(pos.x, pos.z)
			if rd < hw + 1.5 or (blocked.is_valid() and blocked.call(pos.x, pos.z)):
				continue
			if land.normal_at(pos.x, pos.z).y < 0.86:
				continue
			pos.y = land.height_at(pos.x, pos.z) - 0.1
			var r := rng.randf()
			var yaw := rng.randf() * TAU
			var tint := Color(1, 1, 1).darkened(rng.randf() * 0.15)
			if r < 0.22:
				if rd < hw + 3.0:
					continue   # not right on the verge: they're big
				var sc := rng.randf_range(0.65, 1.35)
				saguaros[rng.randi() % 4].put(pos, yaw, sc * rng.randf_range(0.9, 1.1), sc, tint)
			elif r < 0.6:
				var sc := rng.randf_range(0.6, 1.3)
				barrels[rng.randi() % 2].put(pos, yaw, sc, sc * rng.randf_range(0.8, 1.2), tint)
			else:
				var sc := rng.randf_range(0.6, 1.3)
				pears[rng.randi() % 3].put(pos, yaw, sc, sc, tint)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/toon_vcol.gdshader")
	var counts := [0, 0, 0]
	for i in 4:
		counts[0] += saguaros[i].build(parent, _saguaro(rng, i), mat, SAGUARO_VISIBLE, true, 0.0, "trees")
	for i in 2:
		counts[1] += barrels[i].build(parent, _barrel(rng, i == 1), mat, SMALL_VISIBLE, true, 0.0, "props")
	for i in 3:
		counts[2] += pears[i].build(parent, _pear(rng), mat, SMALL_VISIBLE, true, 0.0, "props")
	print("  cacti: %d saguaros, %d barrel, %d prickly pear" % counts)


## A ribbed tube along `path` (points) with radii `radii`, closed with a rounded top.
static func _tube(b: MeshBuilder, path: Array, radii: Array, ribs: int, col: Color, light: Color) -> void:
	var sides := ribs * 2
	var prev := PackedInt32Array()
	for i in path.size():
		var p: Vector3 = path[i]
		var d: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var a := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT).normalized()
		var c := d.cross(a).normalized()
		var ring := PackedInt32Array()
		for k in sides:
			var ang := TAU * k / sides
			var out := a * cos(ang) + c * sin(ang)
			var rib := 1.0 if k % 2 == 0 else 0.86
			ring.append(b.add(p + out * float(radii[i]) * rib, out, light if k % 2 == 0 else col))
		if i > 0:
			for k in sides:
				b.quad(prev[k], prev[(k + 1) % sides], ring[(k + 1) % sides], ring[k])
		prev = ring
	# rounded top: two shrinking rings and a tip
	var last: Vector3 = path[path.size() - 1]
	var dir: Vector3 = (last - path[path.size() - 2]).normalized()
	var r_end: float = radii[radii.size() - 1]
	var a2 := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
	var c2 := dir.cross(a2).normalized()
	for step: Array in [[0.45, 0.85], [0.8, 0.5]]:
		var ring := PackedInt32Array()
		for k in sides:
			var ang := TAU * k / sides
			var out := a2 * cos(ang) + c2 * sin(ang)
			var rib := 1.0 if k % 2 == 0 else 0.86
			ring.append(b.add(last + dir * r_end * float(step[0]) + out * r_end * float(step[1]) * rib, (out + dir * float(step[0])).normalized(), light if k % 2 == 0 else col))
		for k in sides:
			b.quad(prev[k], prev[(k + 1) % sides], ring[(k + 1) % sides], ring[k])
		prev = ring
	var tip := b.add(last + dir * r_end, dir, light)
	for k in sides:
		b.tri(prev[k], prev[(k + 1) % sides], tip)


## A saguaro about 7 m tall: a thick ribbed trunk and 0-4 arms that leave it
## sideways and bend up. Variant 0 has no arms.
static func _saguaro(rng: RandomNumberGenerator, variant: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	var height := rng.randf_range(6.0, 8.0)
	var r := 0.32
	var path := []
	var radii := []
	for i in 8:
		var t := float(i) / 7.0
		path.append(Vector3(sin(t * 2.0) * 0.08, t * height, 0.0))
		radii.append(r * (1.0 - t * 0.12))
	_tube(b, path, radii, 11, GREEN, GREEN_LIGHT)
	var arms := 0 if variant == 0 else rng.randi_range(1, 4)
	var base_a := rng.randf() * TAU
	for k in arms:
		var a := base_a + TAU * k / maxf(arms, 1) + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0.0, sin(a))
		var y0 := rng.randf_range(height * 0.35, height * 0.6)
		var reach := rng.randf_range(0.7, 1.2)
		var up := rng.randf_range(1.6, height - y0 - 0.3)
		var ar := r * rng.randf_range(0.6, 0.75)
		var arm := []
		var ar_list := []
		for i in 9:
			var t := float(i) / 8.0
			var bend := smoothstep(0.0, 0.45, t)
			# out from the trunk, round the elbow, then straight up
			var p := Vector3(0.0, y0, 0.0) + out * (reach * minf(t / 0.45, 1.0) + r * 0.6) + Vector3.UP * (maxf(t - 0.3, 0.0) / 0.7 * up + bend * 0.3)
			arm.append(p)
			ar_list.append(ar)
		_tube(b, arm, ar_list, 9, GREEN, GREEN_LIGHT)
	# blossoms crowning the trunk (late spring)
	if rng.randf() < 0.5:
		for k in 5:
			var a := TAU * k / 5.0 + rng.randf()
			var c := Vector3(cos(a) * r * 0.55, height + r * 0.75, sin(a) * r * 0.55)
			Meshes.blob(b, c, Vector3(0.09, 0.06, 0.09), 3, 5, rng, 0.1, BLOSSOM.darkened(0.1), BLOSSOM)
	return b.commit()


## A barrel cactus, ribbed and a little taller than wide, with a crown of flowers.
static func _barrel(rng: RandomNumberGenerator, red: bool) -> ArrayMesh:
	var b := MeshBuilder.new()
	var path := []
	var radii := []
	var h := 0.8
	for i in 6:
		var t := float(i) / 5.0
		path.append(Vector3(0.0, t * h, 0.0))
		radii.append(0.32 * (0.75 + 0.35 * sin(t * PI * 0.9 + 0.3)))
	_tube(b, path, radii, 13, GREEN.darkened(0.05), GREEN_LIGHT)
	var flower := Color(0.98, 0.78, 0.12) if not red else Color(0.92, 0.30, 0.12)
	for k in 7:
		var a := TAU * k / 7.0
		Meshes.blob(b, Vector3(cos(a) * 0.12, h + 0.08, sin(a) * 0.12), Vector3(0.06, 0.045, 0.06), 3, 5, rng, 0.15, flower.darkened(0.15), flower)
	return b.commit()


## A prickly pear: flat oval paddles growing out of each other in a clump, some
## edged with magenta fruit.
static func _pear(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var stack := [[Vector3.ZERO, 0.0, 0]]   # [base point, yaw, generation]
	var count := 0
	while not stack.is_empty() and count < 14:
		var it: Array = stack.pop_back()
		var base: Vector3 = it[0]
		var gen: int = it[2]
		var yaw: float = it[1] + rng.randf_range(-0.9, 0.9)
		var tilt := rng.randf_range(-0.5, 0.5) * (0.3 + gen * 0.3)
		var size := rng.randf_range(0.22, 0.3) * (1.0 - gen * 0.12)
		var up := Vector3(sin(tilt) * cos(yaw), cos(tilt), sin(tilt) * sin(yaw)).normalized()
		var c := base + up * size * 1.2
		var side := Vector3(cos(yaw + PI * 0.5), 0.0, sin(yaw + PI * 0.5))
		# the paddle: a flattened blob, thin along `side`
		var pb := MeshBuilder.new()
		Meshes.blob(pb, Vector3.ZERO, Vector3(size * 0.85, size * 1.25, 0.06), 5, 8, rng, 0.05, PAD, PAD_LIGHT)
		var basis := Basis(up.cross(side).normalized(), up, side)
		for v in pb.verts.size():
			pb.verts[v] = c + basis * pb.verts[v]
			pb.normals[v] = (basis * pb.normals[v]).normalized()
		var off := b.verts.size()
		b.verts.append_array(pb.verts)
		b.normals.append_array(pb.normals)
		b.colors.append_array(pb.colors)
		b.uvs.append_array(pb.uvs)
		for idx in pb.indices:
			b.indices.append(idx + off)
		count += 1
		if gen < 2:
			for _k in rng.randi_range(1, 2):
				stack.append([c + up * size * rng.randf_range(0.9, 1.1) + basis.x * size * rng.randf_range(-0.5, 0.5), yaw + rng.randf_range(-1.2, 1.2), gen + 1])
		elif rng.randf() < 0.6:
			for k in 3:
				var fp := c + up * size * 1.2 + basis.x * size * (k - 1) * 0.45
				Meshes.blob(b, fp, Vector3(0.05, 0.07, 0.05), 3, 5, rng, 0.1, FRUIT.darkened(0.2), FRUIT)
	return b.commit()
