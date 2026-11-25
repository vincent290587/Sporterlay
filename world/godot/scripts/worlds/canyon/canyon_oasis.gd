class_name CanyonOasis
extends RefCounted
## The oasis: a hollow beside the road with a spring-fed pool, a ring of date palms,
## reeds at the water, green ground, and a hamlet of mud-brick houses round it, a few
## with a little dome.

const BASIN := 125.0        # the hollow's radius (m)
const DEPTH := 8.0          # dug this deep at its middle
const OFFSET := 62.0        # its centre lies this far left of the road
const POOL_UP := 2.6        # the water stands this far above the hollow's floor

const TRUNK := Color(0.45, 0.34, 0.24)
const TRUNK_DARK := Color(0.34, 0.25, 0.18)
const FROND := Color(0.27, 0.44, 0.17)
const FROND_TIP := Color(0.48, 0.58, 0.25)
const FROND_DEAD := Color(0.58, 0.44, 0.26)
const MUD := Color(0.80, 0.62, 0.45)
const MUD_DARK := Color(0.68, 0.50, 0.36)
const DOOR := Color(0.16, 0.10, 0.07)
const GREEN := Color(0.40, 0.52, 0.22)

var centre := Vector3.ZERO
var centre2 := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func setup(route: Route, s: float, seed: int) -> void:
	_rng.seed = seed + 800
	var p := route.position_at(s)
	centre = p - route.right_at(s) * OFFSET
	centre2 = Vector2(centre.x, centre.z)


func blocks(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(centre2) < BASIN * 0.95


func build(parent: Node3D, land: CanyonLand) -> void:
	var floor_h := land.height_at(centre.x, centre.z)
	var level := floor_h + POOL_UP
	# the pool: a plane at the water level, the hollow's sides hide the rest of it
	var plane := PlaneMesh.new()
	plane.size = Vector2(BASIN * 1.6, BASIN * 1.6)
	var water := ShaderMaterial.new()
	water.shader = load("res://shaders/water.gdshader")
	water.set_shader_parameter("shallow", Color(0.30, 0.66, 0.58))
	water.set_shader_parameter("deep", Color(0.07, 0.28, 0.36))
	var wi := MeshInstance3D.new()
	wi.mesh = plane
	wi.material_override = water
	wi.position = Vector3(centre.x, level, centre.z)
	wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(wi)

	var toon := ShaderMaterial.new()
	toon.shader = load("res://shaders/toon_vcol.gdshader")
	var palms: Array[Instancer] = [Instancer.new(100.0), Instancer.new(100.0), Instancer.new(100.0)]
	var reeds := Instancer.new(48.0)
	var grass := Instancer.new(48.0)
	var n_palms := 0
	for _k in 2600:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * BASIN * 1.05
		var x := centre.x + cos(a) * r
		var z := centre.z + sin(a) * r
		if land.road_distance_at(x, z) < Route.HALF_WIDTH + 1.5:
			continue
		var h := land.height_at(x, z)
		var above := h - level
		if above < -0.05:
			# in the water: reeds in the shallows only
			if above > -0.6 and _rng.randf() < 0.5:
				reeds.put(Vector3(x, h, z), _rng.randf() * TAU, _rng.randf_range(0.8, 1.3), _rng.randf_range(0.9, 1.4), Color(0.75, 0.8, 0.55))
			continue
		if land.normal_at(x, z).y < 0.75:
			continue
		var pos := Vector3(x, h - 0.05, z)
		if above < 1.2 and _rng.randf() < 0.6:
			reeds.put(pos, _rng.randf() * TAU, _rng.randf_range(0.8, 1.3), _rng.randf_range(0.9, 1.5), Color(0.8, 0.85, 0.55))
		elif above < 7.0 and _rng.randf() < 0.05 and land.road_distance_at(x, z) > Route.HALF_WIDTH + 4.0:
			var s := _rng.randf_range(0.8, 1.25)
			palms[_rng.randi() % 3].put(pos, _rng.randf() * TAU, s, s * _rng.randf_range(0.85, 1.2), Color(1, 1, 1).darkened(_rng.randf() * 0.15))
			n_palms += 1
		elif _rng.randf() < 0.7:
			grass.put(pos, _rng.randf() * TAU, _rng.randf_range(0.8, 1.4), _rng.randf_range(0.7, 1.2), GREEN.lerp(Color(0.6, 0.62, 0.3), _rng.randf() * 0.5))
	for i in 3:
		palms[i].build(parent, _palm(), toon, 1500.0, true, 0.0, "trees")
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/grass.gdshader")
	reeds.build(parent, Meshes.reeds(_rng), gm, 250.0, false, 0.0, "grass")
	grass.build(parent, Meshes.grass(_rng, Meshes.GRASS_AVERAGE), gm, 250.0, false, 0.0, "grass")
	var plaster := ShaderMaterial.new()
	plaster.shader = load("res://shaders/canyon_ground.gdshader")
	plaster.set_shader_parameter("plaster", 1.0)
	_add(parent, _hamlet(land, level), plaster)
	print("  oasis: %d palms, %d reeds, %d grass" % [n_palms, reeds.count(), grass.count()])


func _add(parent: Node3D, mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)


# --- palms ----------------------------------------------------------------------

## A date palm about 10 m tall: a leaning, ringed trunk and a crown of arching
## fronds (both sides drawn), a few dead ones hanging below.
func _palm() -> ArrayMesh:
	var b := MeshBuilder.new()
	var lean := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() * _rng.randf_range(0.6, 1.6)
	var height := _rng.randf_range(8.5, 11.0)
	var segs := 9
	var sides := 7
	var prev := PackedInt32Array()
	var top := Vector3.ZERO
	for k in segs + 1:
		var t := float(k) / segs
		var c := Vector3(0.0, t * height, 0.0) + lean * t * t
		var r := lerpf(0.32, 0.19, t)
		var ring := PackedInt32Array()
		for i in sides:
			var a := TAU * i / sides
			var n := Vector3(cos(a), 0.0, sin(a))
			ring.append(b.add(c + n * r, n, TRUNK if k % 2 == 0 else TRUNK_DARK))
		if k > 0:
			for i in sides:
				b.quad(prev[i], prev[(i + 1) % sides], ring[(i + 1) % sides], ring[i])
		prev = ring
		top = c
	var fronds := 14
	for f in fronds + 3:
		var dead := f >= fronds
		var a := TAU * f / fronds + _rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0.0, sin(a))
		var rise := _rng.randf_range(0.5, 1.1) if not dead else -1.2
		var length := _rng.randf_range(3.8, 5.0) if not dead else 2.6
		_frond(b, top + Vector3.UP * 0.2, out, rise, length, dead)
	return b.commit()


## One frond: an arching strip with a raised spine, narrow at both ends, drawn from
## both sides.
func _frond(b: MeshBuilder, root: Vector3, out: Vector3, rise: float, length: float, dead: bool) -> void:
	var across := out.cross(Vector3.UP).normalized()
	var steps := 7
	var rows := []
	for k in steps + 1:
		var t := float(k) / steps
		# up and out, then drooping under its own weight
		var p := root + out * length * t + Vector3.UP * (rise * length * t - 0.9 * length * t * t * (0.6 if not dead else 0.2))
		var w := sin(t * PI) * 0.55 + 0.05
		var col := FROND_DEAD if dead else FROND.lerp(FROND_TIP, t)
		rows.append([p - across * w + Vector3.DOWN * w * 0.25, p + Vector3.UP * 0.06, p + across * w + Vector3.DOWN * w * 0.25, col])
	for side: float in [1.0, -1.0]:
		var idx := []
		for row: Array in rows:
			var l: Vector3 = row[0]
			var m: Vector3 = row[1]
			var r: Vector3 = row[2]
			var n := (r - l).cross(out).normalized() * side
			if n.y * side < 0.0:
				n = -n
			idx.append([b.add(l, n, row[3]), b.add(m, n, row[3]), b.add(r, n, row[3])])
		for k in steps:
			var a: Array = idx[k]
			var c: Array = idx[k + 1]
			b.quad(a[0], a[1], c[1], c[0])
			b.quad(a[1], a[2], c[2], c[1])


# --- houses ---------------------------------------------------------------------

## Mud-brick houses round the far side of the pool and a couple across the road:
## flat roofs with a parapet, a dark door and small windows, some with a dome.
func _hamlet(land: CanyonLand, level: float) -> ArrayMesh:
	var b := MeshBuilder.new()
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 12 and tries < 400:
		tries += 1
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(BASIN * 0.6, BASIN * 1.1)
		var p := centre2 + Vector2(cos(a), sin(a)) * r
		if land.road_distance_at(p.x, p.y) < 20.0:
			continue
		var h := land.height_at(p.x, p.y)
		if h < level + 1.0 or land.normal_at(p.x, p.y).y < 0.9:
			continue
		var clash := false
		for q in placed:
			if q.distance_to(p) < 14.0:
				clash = true
		if clash:
			continue
		placed.append(p)
		# face the pool
		var face := (centre2 - p).normalized()
		var size := Vector3(_rng.randf_range(4.5, 7.0), _rng.randf_range(2.8, 3.6), _rng.randf_range(4.5, 6.5))
		var base := Vector3(p.x, h - 0.3, p.y)
		var f3 := Vector3(face.x, 0.0, face.y)
		_house(b, base, f3, size)
		_yard(b, land, base, f3, size)
	return b.commit()


func _house(b: MeshBuilder, base: Vector3, face: Vector3, size: Vector3) -> void:
	var side := Vector3(-face.z, 0.0, face.x)
	var col := MUD.lerp(MUD_DARK, _rng.randf() * 0.6)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var w := func(x: float, y: float, z: float) -> Vector3: return base + side * x + Vector3.UP * y + face * z
	_block(b, w, Vector3(-hx, -1.5, -hz), Vector3(hx, size.y, hz), side, face, col)
	# parapet
	for e: Array in [[Vector3(-hx, size.y, -hz), Vector3(hx, size.y + 0.5, -hz + 0.3)], [Vector3(-hx, size.y, hz - 0.3), Vector3(hx, size.y + 0.5, hz)],
			[Vector3(-hx, size.y, -hz), Vector3(-hx + 0.3, size.y + 0.5, hz)], [Vector3(hx - 0.3, size.y, -hz), Vector3(hx, size.y + 0.5, hz)]]:
		_block(b, w, e[0], e[1], side, face, col.darkened(0.05))
	# a door facing the pool, small windows all round, roof beams poking out
	var front := hz + 0.03
	_quad(b, w.call(-0.5, 0.0, front), w.call(0.5, 0.0, front), w.call(0.5, 2.0, front), w.call(-0.5, 2.0, front), face, DOOR)
	for x: float in [-hx * 0.6, hx * 0.6]:
		_quad(b, w.call(x - 0.25, 1.4, front), w.call(x + 0.25, 1.4, front), w.call(x + 0.25, 1.9, front), w.call(x - 0.25, 1.9, front), face, DOOR)
		_quad(b, w.call(x + 0.25, 1.4, -front), w.call(x - 0.25, 1.4, -front), w.call(x - 0.25, 1.9, -front), w.call(x + 0.25, 1.9, -front), -face, DOOR)
	for z: float in [-hz * 0.4, hz * 0.4]:
		_quad(b, w.call(hx + 0.03, 1.4, z - 0.25), w.call(hx + 0.03, 1.4, z + 0.25), w.call(hx + 0.03, 1.9, z + 0.25), w.call(hx + 0.03, 1.9, z - 0.25), side, DOOR)
		_quad(b, w.call(-hx - 0.03, 1.4, z + 0.25), w.call(-hx - 0.03, 1.4, z - 0.25), w.call(-hx - 0.03, 1.9, z - 0.25), w.call(-hx - 0.03, 1.9, z + 0.25), -side, DOOR)
	var beams := int(size.x / 0.9)
	for k in beams:
		var x := -hx + (k + 0.5) * size.x / beams
		for zz: float in [hz, -hz - 0.5]:
			_block(b, w, Vector3(x - 0.09, size.y - 0.45, zz), Vector3(x + 0.09, size.y - 0.27, zz + 0.5), side, face, Color(0.36, 0.26, 0.18))
	# some have an upper room set back on the roof
	if _rng.randf() < 0.4:
		var ux := hx * _rng.randf_range(0.45, 0.6)
		var uz := hz * _rng.randf_range(0.45, 0.6)
		var ox := hx - ux
		_block(b, w, Vector3(ox - ux, size.y, -uz), Vector3(ox + ux, size.y + 2.6, uz), side, face, col.lightened(0.03))
		_quad(b, w.call(ox - 0.4, size.y, uz + 0.03), w.call(ox + 0.4, size.y, uz + 0.03), w.call(ox + 0.4, size.y + 1.8, uz + 0.03), w.call(ox - 0.4, size.y + 1.8, uz + 0.03), face, DOOR)
	if _rng.randf() < 0.35:
		var c: Vector3 = w.call(0.0, size.y, 0.0)
		var r := minf(hx, hz) * 0.6
		for i in 5:
			for k in 12:
				var a0 := TAU * k / 12.0
				var a1 := TAU * (k + 1) / 12.0
				var e0 := PI * 0.5 * i / 5.0
				var e1 := PI * 0.5 * (i + 1) / 5.0
				var p := [Vector3(cos(a0) * cos(e0), sin(e0), sin(a0) * cos(e0)), Vector3(cos(a1) * cos(e0), sin(e0), sin(a1) * cos(e0)),
					Vector3(cos(a1) * cos(e1), sin(e1), sin(a1) * cos(e1)), Vector3(cos(a0) * cos(e1), sin(e1), sin(a0) * cos(e1))]
				var n: Vector3 = (p[0] + p[2]).normalized()
				_quad(b, c + p[0] * r, c + p[1] * r, c + p[2] * r, c + p[3] * r, n, col.lightened(0.05))


func _block(b: MeshBuilder, w: Callable, lo: Vector3, hi: Vector3, side: Vector3, face: Vector3, col: Color) -> void:
	var c := [w.call(lo.x, lo.y, lo.z), w.call(hi.x, lo.y, lo.z), w.call(hi.x, lo.y, hi.z), w.call(lo.x, lo.y, hi.z),
		w.call(lo.x, hi.y, lo.z), w.call(hi.x, hi.y, lo.z), w.call(hi.x, hi.y, hi.z), w.call(lo.x, hi.y, hi.z)]
	_quad(b, c[4], c[5], c[6], c[7], Vector3.UP, col.lightened(0.04))
	_quad(b, c[0], c[1], c[5], c[4], -face, col)
	_quad(b, c[3], c[2], c[6], c[7], face, col)
	_quad(b, c[0], c[3], c[7], c[4], -side, col.darkened(0.04))
	_quad(b, c[1], c[2], c[6], c[5], side, col.darkened(0.04))


func _quad(b: MeshBuilder, a: Vector3, c: Vector3, d: Vector3, e: Vector3, n: Vector3, col: Color) -> void:
	var i := b.add(a, n, col)
	b.add(c, n, col)
	b.add(d, n, col)
	b.add(e, n, col)
	b.quad(i, i + 1, i + 2, i + 3)


## What lies round a house: a ladder up to the roof, clay jars by the door, and
## sometimes a low garden wall on one side.
func _yard(b: MeshBuilder, land: CanyonLand, base: Vector3, face: Vector3, size: Vector3) -> void:
	var side := Vector3(-face.z, 0.0, face.x)
	var wood := Color(0.40, 0.29, 0.19)
	if _rng.randf() < 0.6:
		# leaning on the side wall
		var s := 1.0 if _rng.randf() < 0.5 else -1.0
		var foot := base + side * s * (size.x * 0.5 + 1.0) + face * _rng.randf_range(-1.0, 1.0)
		var top := base + side * s * (size.x * 0.5 + 0.1) + Vector3.UP * (size.y + 0.8)
		for o: float in [-0.25, 0.25]:
			_beam(b, foot + face * o, top + face * o, 0.05, wood)
		for k in 7:
			var t := (k + 0.6) / 7.6
			_beam(b, foot.lerp(top, t) - face * 0.25, foot.lerp(top, t) + face * 0.25, 0.03, wood)
	# jars by the door
	for _k in _rng.randi_range(1, 4):
		var at := base + face * (size.z * 0.5 + _rng.randf_range(0.6, 1.4)) + side * _rng.randf_range(-size.x * 0.45, size.x * 0.45)
		at.y = land.height_at(at.x, at.z)
		_jar(b, at, _rng.randf_range(0.6, 1.1))
	if _rng.randf() < 0.5:
		var s := 1.0 if _rng.randf() < 0.5 else -1.0
		var c := base + side * s * (size.x * 0.5 + 4.0)
		var w := 3.5
		var hgt := _rng.randf_range(1.1, 1.6)
		for e: Array in [[c - face * w - side * s * 3.5, c - face * w + side * s * 3.5], [c + face * w - side * s * 3.5, c + face * w + side * s * 3.5],
				[c - face * w + side * s * 3.5, c + face * w + side * s * 3.5]]:
			var a: Vector3 = e[0]
			var z: Vector3 = e[1]
			a.y = land.height_at(a.x, a.z) - 0.4
			z.y = land.height_at(z.x, z.z) - 0.4
			_wall(b, a, z, hgt + 0.4, 0.35, MUD_DARK)


## A thin square beam from a to b.
func _beam(b: MeshBuilder, a: Vector3, e: Vector3, r: float, col: Color) -> void:
	var d := (e - a).normalized()
	var u := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized() * r
	var v := d.cross(u).normalized() * r
	var corners := [u + v, u - v, -u - v, -u + v]
	for k in 4:
		var c0: Vector3 = corners[k]
		var c1: Vector3 = corners[(k + 1) % 4]
		var n := (c0 + c1).normalized()
		_quad(b, a + c0, a + c1, e + c1, e + c0, n, col)


## A straight mud wall from a to e (both at its foot), with a rounded-off top.
func _wall(b: MeshBuilder, a: Vector3, e: Vector3, h: float, t: float, col: Color) -> void:
	var d := Vector3(e.x - a.x, 0.0, e.z - a.z).normalized()
	var n := Vector3(-d.z, 0.0, d.x)
	var up := Vector3.UP
	_quad(b, a + n * t, e + n * t, e + n * t + up * h, a + n * t + up * h, n, col)
	_quad(b, e - n * t, a - n * t, a - n * t + up * h, e - n * t + up * h, -n, col)
	_quad(b, a + n * t + up * h, e + n * t + up * h, e + up * (h + 0.15), a + up * (h + 0.15), (n + up).normalized(), col.lightened(0.04))
	_quad(b, e - n * t + up * h, a - n * t + up * h, a + up * (h + 0.15), e + up * (h + 0.15), (up - n).normalized(), col.lightened(0.04))
	_quad(b, a - n * t, a + n * t, a + n * t + up * h, a - n * t + up * h, -d, col)
	_quad(b, e + n * t, e - n * t, e - n * t + up * h, e + n * t + up * h, d, col)


## A round-bellied clay jar `h` m tall.
func _jar(b: MeshBuilder, at: Vector3, h: float) -> void:
	var profile := [[0.0, 0.18], [0.15, 0.32], [0.45, 0.38], [0.75, 0.3], [0.88, 0.14], [0.95, 0.12], [1.0, 0.16]]
	var col := Color(0.70, 0.42, 0.28).darkened(_rng.randf() * 0.2)
	var sides := 8
	for i in profile.size() - 1:
		var y0: float = profile[i][0] * h
		var y1: float = profile[i + 1][0] * h
		var r0: float = profile[i][1] * h
		var r1: float = profile[i + 1][1] * h
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var am := (a0 + a1) * 0.5
			var n := Vector3(cos(am), (r0 - r1) / maxf(y1 - y0, 0.01), sin(am)).normalized()
			_quad(b, at + Vector3(cos(a0) * r0, y0, sin(a0) * r0), at + Vector3(cos(a1) * r0, y0, sin(a1) * r0),
				at + Vector3(cos(a1) * r1, y1, sin(a1) * r1), at + Vector3(cos(a0) * r1, y1, sin(a0) * r1), n, col)
