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
	var houses := _hamlet(land, level)
	_add(parent, houses, toon)
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
		_house(b, Vector3(p.x, h - 0.3, p.y), Vector3(face.x, 0.0, face.y), Vector3(_rng.randf_range(4.5, 7.0), _rng.randf_range(2.8, 3.6), _rng.randf_range(4.5, 6.5)))
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
