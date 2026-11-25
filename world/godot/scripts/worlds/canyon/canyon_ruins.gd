class_name CanyonRuins
extends RefCounted
## The ruins in the canyon's plaza: a temple front carved into the left wall in the
## manner of Petra's Treasury (two orders of columns, a pediment, a round pavilion on
## top), a colonnaded street along the road with broken columns and fallen drums, a
## gate arch the road passes under, and low house foundations on the open side.
##
## Laid out in the ruins' own frame: x to the right of the road, z along it, y up from
## the road at the centre. Built straight in world space (`_w`).

const STONE := Color(0.88, 0.58, 0.45)
const STONE_DARK := Color(0.74, 0.46, 0.36)
const SHADOW := Color(0.09, 0.05, 0.04)

const FRONT := -50.0       # the temple front stands this far left of the road
const HALF_W := 13.0       # half its width along the road
const STREET := 7.2        # the colonnade's columns stand this far either side
const GATE_Z := -118.0     # the arch, before the plaza

var centre := Vector3.ZERO
var _route: Route
var _s := 0.0
var right := Vector3.RIGHT
var fwd := Vector3.FORWARD
var _rng := RandomNumberGenerator.new()


func setup(route: Route, s: float, seed: int) -> void:
	_rng.seed = seed + 600
	_route = route
	_s = s
	centre = route.position_at(s)
	var d := route.position_at(s + 60.0) - route.position_at(s - 60.0)
	fwd = Vector3(d.x, 0.0, d.z).normalized()
	right = Vector3(-fwd.z, 0.0, fwd.x)


## Frame to world. Heights follow the road's own height at that z, so everything
## sits on the ground as the road rises or falls through the plaza.
func _w(p: Vector3) -> Vector3:
	return centre + right * p.x + Vector3.UP * (p.y + _road_dy(p.z)) + fwd * p.z


func _road_dy(z: float) -> float:
	return _route.position_at(_s + z).y - centre.y


func _wn(n: Vector3) -> Vector3:
	return (right * n.x + Vector3.UP * n.y + fwd * n.z).normalized()


func local(x: float, z: float) -> Vector2:
	var d := Vector3(x - centre.x, 0.0, z - centre.z)
	return Vector2(d.dot(right), d.dot(fwd))


func _outside(x: float, z: float, x0: float, x1: float, z0: float, z1: float) -> float:
	var l := local(x, z)
	return Vector2(maxf(maxf(x0 - l.x, l.x - x1), 0.0), maxf(maxf(z0 - l.y, l.y - z1), 0.0)).length()


func blocks(x: float, z: float) -> bool:
	return _outside(x, z, -90.0, 50.0, GATE_Z - 15.0, 135.0) <= 0.0


## Levels the plaza floor across, to the road's height along it.
func level(land: CanyonLand) -> void:
	land.flatten(func(x: float, z: float) -> float: return _outside(x, z, FRONT - 4.0, 40.0, -125.0, 125.0),
		func(x: float, z: float) -> float: return centre.y + _road_dy(local(x, z).y) - 0.15, 18.0)


func build(parent: Node3D) -> void:
	var b := MeshBuilder.new()
	var dark := MeshBuilder.new()
	_temple(b, dark)
	_colonnade(b)
	_gate(b)
	_foundations(b)
	var toon := ShaderMaterial.new()
	toon.shader = load("res://shaders/toon_vcol.gdshader")
	toon.set_shader_parameter("paint", 0.16)
	_add(parent, b.commit(), toon, true)
	var unlit := ShaderMaterial.new()
	unlit.shader = load("res://shaders/toon_vcol.gdshader")
	_add(parent, dark.commit(), unlit, false)


func _add(parent: Node3D, mesh: Mesh, mat: Material, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _stone() -> Color:
	return STONE.lerp(STONE_DARK, _rng.randf() * 0.45)


# --- primitives (ruins frame) -------------------------------------------------

func _box(b: MeshBuilder, lo: Vector3, hi: Vector3, col: Color) -> void:
	var faces := [
		[Vector3.RIGHT, [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z)]],
		[Vector3.LEFT, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]],
		[Vector3.UP, [Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)]],
		[Vector3.BACK, [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
		[Vector3.FORWARD, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z)]],
	]
	for f: Array in faces:
		var n := _wn(f[0])
		var q: Array = f[1]
		var i := b.add(_w(q[0]), n, col)
		b.add(_w(q[1]), n, col)
		b.add(_w(q[2]), n, col)
		b.add(_w(q[3]), n, col)
		b.quad(i, i + 1, i + 2, i + 3)


## A column from y0 to y1 with a base and a capital (fluted look from flat facets).
func _column(b: MeshBuilder, x: float, z: float, r: float, y0: float, y1: float, capital := true) -> void:
	var col := _stone()
	_cyl(b, Vector3(x, 0.0, z), r, y0, y1, 12, col)
	_box(b, Vector3(x - r * 1.35, y0 - 0.1, z - r * 1.35), Vector3(x + r * 1.35, y0 + r * 0.6, z + r * 1.35), col.darkened(0.05))
	if capital:
		_box(b, Vector3(x - r * 1.4, y1, z - r * 1.4), Vector3(x + r * 1.4, y1 + r * 0.9, z + r * 1.4), col.lightened(0.04))


func _cyl(b: MeshBuilder, c: Vector3, r: float, y0: float, y1: float, segs: int, col: Color) -> void:
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var am := (a0 + a1) * 0.5
		var n := _wn(Vector3(cos(am), 0.0, sin(am)))
		var shade := col.darkened(0.05 * (k % 2))
		var i := b.add(_w(Vector3(c.x + cos(a0) * r, y0, c.z + sin(a0) * r)), n, shade)
		b.add(_w(Vector3(c.x + cos(a1) * r, y0, c.z + sin(a1) * r)), n, shade)
		b.add(_w(Vector3(c.x + cos(a1) * r, y1, c.z + sin(a1) * r)), n, shade)
		b.add(_w(Vector3(c.x + cos(a0) * r, y1, c.z + sin(a0) * r)), n, shade)
		b.quad(i, i + 1, i + 2, i + 3)
	var up := _wn(Vector3.UP)
	var m := b.add(_w(Vector3(c.x, y1, c.z)), up, col)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var i := b.add(_w(Vector3(c.x + cos(a0) * r, y1, c.z + sin(a0) * r)), up, col)
		b.add(_w(Vector3(c.x + cos(a1) * r, y1, c.z + sin(a1) * r)), up, col)
		b.tri(m, i, i + 1)


## A cylinder lying on its side along `dir` (x, z), for fallen drums.
func _drum(b: MeshBuilder, c: Vector3, dir: Vector2, r: float, length: float) -> void:
	var ax := Vector3(dir.x, 0.0, dir.y).normalized()
	var u := Vector3.UP
	var v := ax.cross(u)
	var col := _stone()
	var segs := 10
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var o0 := u * cos(a0) * r + v * sin(a0) * r
		var o1 := u * cos(a1) * r + v * sin(a1) * r
		var n := _wn(((o0 + o1) * 0.5).normalized())
		var i := b.add(_w(c + o0), n, col)
		b.add(_w(c + o1), n, col)
		b.add(_w(c + o1 + ax * length), n, col)
		b.add(_w(c + o0 + ax * length), n, col)
		b.quad(i, i + 1, i + 2, i + 3)
	for end: float in [0.0, 1.0]:
		var n := _wn(ax * (end * 2.0 - 1.0))
		var e := c + ax * length * end
		var m := b.add(_w(e), n, col.darkened(0.08))
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var i := b.add(_w(e + u * cos(a0) * r + v * sin(a0) * r), n, col.darkened(0.08))
			b.add(_w(e + u * cos(a1) * r + v * sin(a1) * r), n, col.darkened(0.08))
			b.tri(m, i, i + 1)


## A triangular pediment facing +x at x, spanning z0..z1, from y up by `rise`.
func _pediment(b: MeshBuilder, x0: float, x1: float, z0: float, z1: float, y: float, rise: float) -> void:
	var zm := (z0 + z1) * 0.5
	var col := _stone()
	var nf := _wn(Vector3.RIGHT)
	var i := b.add(_w(Vector3(x1, y, z0)), nf, col)
	b.add(_w(Vector3(x1, y, z1)), nf, col)
	b.add(_w(Vector3(x1, y + rise, zm)), nf, col)
	b.tri(i, i + 1, i + 2)
	for side: float in [-1.0, 1.0]:
		var ze := z0 if side < 0.0 else z1
		var n := _wn(Vector3(0.0, (z1 - z0) * 0.5, side * rise))
		var j := b.add(_w(Vector3(x0, y, ze)), n, col.lightened(0.05))
		b.add(_w(Vector3(x1, y, ze)), n, col.lightened(0.05))
		b.add(_w(Vector3(x1, y + rise, zm)), n, col.lightened(0.05))
		b.add(_w(Vector3(x0, y + rise, zm)), n, col.lightened(0.05))
		b.quad(j, j + 1, j + 2, j + 3)


## A dark opening on the face x = `x` (facing +x).
func _opening(d: MeshBuilder, x: float, z0: float, z1: float, y0: float, y1: float) -> void:
	var n := _wn(Vector3.RIGHT)
	var i := d.add(_w(Vector3(x + 0.04, y0, z0)), n, SHADOW)
	d.add(_w(Vector3(x + 0.04, y0, z1)), n, SHADOW)
	d.add(_w(Vector3(x + 0.04, y1, z1)), n, SHADOW)
	d.add(_w(Vector3(x + 0.04, y1, z0)), n, SHADOW)
	d.quad(i, i + 1, i + 2, i + 3)


# --- parts --------------------------------------------------------------------

## The temple front, carved out of the cliff: everything rises from a block of rock
## behind it, so it reads as cut from the wall.
func _temple(b: MeshBuilder, d: MeshBuilder) -> void:
	var x := FRONT
	# the rock it's cut into, and the recess round the facade
	_box(b, Vector3(x - 32.0, -6.0, -HALF_W - 9.0), Vector3(x - 1.2, 46.0, HALF_W + 9.0), STONE_DARK)
	_box(b, Vector3(x - 3.0, -6.0, -HALF_W - 9.0), Vector3(x + 1.0, 46.0, -HALF_W - 1.0), STONE_DARK)
	_box(b, Vector3(x - 3.0, -6.0, HALF_W + 1.0), Vector3(x + 1.0, 46.0, HALF_W + 9.0), STONE_DARK)
	# steps
	for k in 3:
		_box(b, Vector3(x - 1.0, -2.0, -HALF_W), Vector3(x + 3.0 - k * 0.9, 0.4 + k * 0.4, HALF_W), STONE.darkened(0.05 * k))
	var floor_y := 1.2
	# lower order: six columns, the entablature, a pediment over the middle four
	for z: float in [-11.0, -6.6, -2.2, 2.2, 6.6, 11.0]:
		_column(b, x + 1.4, z, 0.85, floor_y, 13.0)
	_box(b, Vector3(x - 1.2, 13.8, -HALF_W - 0.4), Vector3(x + 2.8, 17.0, HALF_W + 0.4), _stone())
	_box(b, Vector3(x - 1.2, 16.6, -HALF_W - 0.7), Vector3(x + 3.0, 17.2, HALF_W + 0.7), STONE.lightened(0.05))
	_pediment(b, x - 1.0, x + 2.9, -8.0, 8.0, 17.2, 4.2)
	# the hall behind: a doorway and two side doors
	_opening(d, x - 1.2, -2.0, 2.0, floor_y, 9.5)
	_opening(d, x - 1.2, -9.4, -7.9, floor_y, 6.0)
	_opening(d, x - 1.2, 7.9, 9.4, floor_y, 6.0)
	# upper order: two side pavilions with broken half-pediments, the round tholos
	var y2 := 22.0
	for side: float in [-1.0, 1.0]:
		var z0 := side * 6.8
		var z1 := side * HALF_W
		var lo := minf(z0, z1)
		var hi := maxf(z0, z1)
		_box(b, Vector3(x - 1.2, y2 - 1.0, lo), Vector3(x + 0.8, y2 + 11.5, hi), _stone())
		_column(b, x + 1.4, lo + 1.2, 0.65, y2, y2 + 10.5)
		_column(b, x + 1.4, hi - 1.2, 0.65, y2, y2 + 10.5)
		_box(b, Vector3(x - 1.2, y2 + 11.2, lo - 0.3), Vector3(x + 2.4, y2 + 12.6, hi + 0.3), _stone())
		_opening(d, x + 0.8, lo + 2.4, hi - 2.4, y2 + 1.0, y2 + 7.5)
		# the half pediment rising towards the tholos
		var n := _wn(Vector3(0.0, 1.0, -side * 0.7))
		var outer := z1
		var inner := z0
		var i := b.add(_w(Vector3(x - 1.2, y2 + 12.6, outer)), n, STONE.lightened(0.05))
		b.add(_w(Vector3(x + 2.4, y2 + 12.6, outer)), n, STONE.lightened(0.05))
		b.add(_w(Vector3(x + 2.4, y2 + 15.4, inner)), n, STONE.lightened(0.05))
		b.add(_w(Vector3(x - 1.2, y2 + 15.4, inner)), n, STONE.lightened(0.05))
		b.quad(i, i + 1, i + 2, i + 3)
	_box(b, Vector3(x - 1.2, y2 - 1.0, -6.8), Vector3(x - 0.2, y2 + 14.0, 6.8), STONE_DARK)   # back of the tholos niche
	var tc := Vector3(x - 1.4, 0.0, 0.0)
	_cyl(b, tc, 3.0, y2, y2 + 11.5, 16, _stone())
	_opening(d, x + 1.55, -0.9, 0.9, y2 + 1.0, y2 + 6.5)
	for k in 8:
		var a := -PI * 0.5 + PI * (k + 0.5) / 8.0
		_column(b, tc.x + cos(a) * 4.1, sin(a) * 4.1, 0.45, y2, y2 + 10.5, false)
	_cyl(b, tc, 4.6, y2 + 10.5, y2 + 12.0, 16, _stone())
	# its conical roof and the urn on top
	var tip := Vector3(tc.x, y2 + 16.5, 0.0)
	for k in 16:
		var a0 := TAU * k / 16.0
		var a1 := TAU * (k + 1) / 16.0
		var am := (a0 + a1) * 0.5
		var n := _wn(Vector3(cos(am), 1.0, sin(am)))
		var col := _stone().lightened(0.04)
		var i := b.add(_w(Vector3(tc.x + cos(a0) * 4.4, y2 + 12.0, sin(a0) * 4.4)), n, col)
		b.add(_w(Vector3(tc.x + cos(a1) * 4.4, y2 + 12.0, sin(a1) * 4.4)), n, col)
		b.add(_w(tip), n, col)
		b.tri(i, i + 1, i + 2)
	_cyl(b, Vector3(tc.x, 0.0, 0.0), 0.7, y2 + 16.0, y2 + 18.2, 10, _stone())
	_cyl(b, Vector3(tc.x, 0.0, 0.0), 1.0, y2 + 16.8, y2 + 17.6, 10, _stone())


## Columns either side of the road through the plaza and beyond; a third are broken
## off, their drums lying in the sand; lintels still bridge a few standing pairs.
func _colonnade(b: MeshBuilder) -> void:
	for side: float in [-1.0, 1.0]:
		var prev_whole := false
		var z := -100.0
		while z < 125.0:
			# keep the temple's forecourt open
			if side < 0.0 and absf(z) < HALF_W + 10.0:
				z += 6.0
				prev_whole = false
				continue
			var x := side * STREET
			var r := _rng.randf()
			var h := 8.5
			if r < 0.12:
				prev_whole = false   # gone: only the base
				_box(b, Vector3(x - 1.0, -0.4, z - 1.0), Vector3(x + 1.0, 0.5, z + 1.0), _stone())
			elif r < 0.42:
				var top := _rng.randf_range(1.5, 6.0)
				_column(b, x, z, 0.62, 0.3, top, false)
				prev_whole = false
				# its drums fell outwards, away from the road
				var lie := Vector2(side * _rng.randf_range(0.5, 1.0), _rng.randf_range(-0.6, 0.6)).normalized()
				var at := Vector3(x + side * 2.0, 0.55, z + _rng.randf_range(-1.5, 1.5))
				for k in _rng.randi_range(1, 3):
					_drum(b, at, lie, 0.6, _rng.randf_range(1.2, 1.8))
					at += Vector3(lie.x, 0.0, lie.y) * 2.1 + Vector3(0.0, 0.0, _rng.randf_range(-0.4, 0.4))
			else:
				_column(b, x, z, 0.62, 0.3, h)
				if prev_whole and _rng.randf() < 0.6:
					_box(b, Vector3(x - 0.9, h + 0.55, z - 6.0), Vector3(x + 0.9, h + 1.6, z), _stone())
				prev_whole = true
			z += 6.0


## A Roman-style arch over the road at the plaza's mouth: two piers with pilasters,
## a stepped arch head and an attic.
func _gate(b: MeshBuilder) -> void:
	var z := GATE_Z
	var half := 5.0
	for side: float in [-1.0, 1.0]:
		var x0 := side * half
		var x1 := side * (half + 4.2)
		_box(b, Vector3(minf(x0, x1), -1.0, z - 2.2), Vector3(maxf(x0, x1), 12.0, z + 2.2), _stone())
		_column(b, side * (half + 2.1), z - 2.7, 0.5, 0.0, 10.5)
		_column(b, side * (half + 2.1), z + 2.7, 0.5, 0.0, 10.5)
	# the arch: voussoirs round a half circle from pier to pier
	var steps := 9
	for k in steps:
		var a0 := PI * k / steps
		var a1 := PI * (k + 1) / steps
		var p0 := Vector2(cos(a0), sin(a0)) * half
		var p1 := Vector2(cos(a1), sin(a1)) * half
		var lo := Vector3(minf(p0.x, p1.x), 9.0 + minf(p0.y, p1.y), z - 2.2)
		var hi := Vector3(maxf(p0.x, p1.x), 9.0 + maxf(p0.y, p1.y) + 1.4, z + 2.2)
		_box(b, lo, hi, STONE.lightened(0.04 * (k % 2)))
	# the spandrels and the attic above
	for side: float in [-1.0, 1.0]:
		_box(b, Vector3(minf(side * 2.5, side * half), 12.0, z - 2.2), Vector3(maxf(side * 2.5, side * half), 14.4, z + 2.2), _stone())
	_box(b, Vector3(-half - 4.6, 14.4, z - 2.6), Vector3(half + 4.6, 15.4, z + 2.6), STONE.lightened(0.05))
	_box(b, Vector3(-half - 4.2, 15.4, z - 2.2), Vector3(half + 4.2, 18.6, z + 2.2), _stone())


## Low walls of fallen houses on the open, sunlit side.
func _foundations(b: MeshBuilder) -> void:
	for _k in 9:
		var cx := _rng.randf_range(16.0, 40.0)
		var cz := _rng.randf_range(-90.0, 110.0)
		var w := _rng.randf_range(4.0, 8.0)
		var d := _rng.randf_range(4.0, 7.0)
		for e: Array in [[Vector3(cx - w, -0.5, cz - d), Vector3(cx + w, 1.0, cz - d + 0.7)], [Vector3(cx - w, -0.5, cz + d - 0.7), Vector3(cx + w, 1.0, cz + d)],
				[Vector3(cx - w, -0.5, cz - d), Vector3(cx - w + 0.7, 1.0, cz + d)], [Vector3(cx + w - 0.7, -0.5, cz - d), Vector3(cx + w, 1.0, cz + d)]]:
			if _rng.randf() < 0.75:
				var lo: Vector3 = e[0]
				var hi: Vector3 = e[1]
				hi.y = _rng.randf_range(0.4, 2.4)
				_box(b, lo, hi, _stone().darkened(0.05))
