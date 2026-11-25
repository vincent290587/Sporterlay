class_name TransCastle
extends RefCounted
## The vampire's castle on the crag, in the style of Bran: pale stone, steep dark red
## roofs, round towers with spires, a gabled keep with corner turrets and one tall
## tower. The road runs in through the front gatehouse, across the courtyard and out
## through the back one.
##
## Laid out in the castle's own frame: x to the right of the road, z along it (the way
## the rider goes), y up from the road at the centre. Everything is built straight in
## world space (`_w`), so MeshBuilder winds the faces right.

const STONE := Color(0.60, 0.58, 0.55)
const STONE_DARK := Color(0.47, 0.45, 0.44)
const ROOF := Color(0.36, 0.13, 0.09)
const ROOF_DARK := Color(0.26, 0.10, 0.08)
const WOOD := Color(0.24, 0.16, 0.11)
const IRON := Color(0.09, 0.09, 0.10)
const WARM := Color(1.0, 0.58, 0.24)
const BLOOD := Color(0.95, 0.10, 0.06)
const DARK_WINDOW := Color(0.03, 0.03, 0.04)

# the curtain wall's rectangle
const XL := -44.0
const XR := 17.0
const ZB := -52.0     # front wall: the rider comes in here
const ZF := 52.0      # back wall
const WALL_H := 13.0
const WALL_T := 2.4
const GATE_HALF := 4.5   # half the gate opening
const GATE_H := 7.5
const FOOT := 40.0       # walls reach this far down into the crag

var centre := Vector3.ZERO   # road surface at the castle's centre
var right := Vector3.RIGHT
var fwd := Vector3.FORWARD
var gates: Array[Vector3] = []   # world positions of the gate openings (for torches)
var _rng := RandomNumberGenerator.new()


func setup(route: Route, s: float, seed: int) -> void:
	_rng.seed = seed + 900
	centre = route.position_at(s)
	var d := route.position_at(s + 60.0) - route.position_at(s - 60.0)
	fwd = Vector3(d.x, 0.0, d.z).normalized()
	right = Vector3(-fwd.z, 0.0, fwd.x)
	gates = [_w(Vector3(0.0, 0.0, ZB)), _w(Vector3(0.0, 0.0, ZF))]


func _w(p: Vector3) -> Vector3:
	return centre + right * p.x + Vector3.UP * p.y + fwd * p.z


func _wn(n: Vector3) -> Vector3:
	return (right * n.x + Vector3.UP * n.y + fwd * n.z).normalized()


## The castle's frame coordinates of a world point (x, z).
func local(x: float, z: float) -> Vector2:
	var d := Vector3(x - centre.x, 0.0, z - centre.z)
	return Vector2(d.dot(right), d.dot(fwd))


## How far (m) a world point is outside the footprint grown by `margin`; 0 inside.
func outside(x: float, z: float, margin: float) -> float:
	var l := local(x, z)
	var dx := maxf(maxf(XL - 7.0 - margin - l.x, l.x - XR - 7.0 - margin), 0.0)
	var dz := maxf(maxf(ZB - 7.0 - margin - l.y, l.y - ZF - 7.0 - margin), 0.0)
	return Vector2(dx, dz).length()


func blocks(x: float, z: float) -> bool:
	return outside(x, z, 4.0) <= 0.0


## Levels the crag under the castle.
func level(land: TransLand) -> void:
	land.flatten(func(x: float, z: float) -> float: return outside(x, z, 0.0), centre.y - 0.2, 26.0)


func build(parent: Node3D) -> void:
	var stone := MeshBuilder.new()
	var roof := MeshBuilder.new()
	var glow := MeshBuilder.new()
	_curtain(stone)
	for z: float in [ZB, ZF]:
		_gatehouse(stone, glow, z)
	for c: Vector2 in [Vector2(XL, ZB), Vector2(XL, ZF), Vector2(XR, ZB), Vector2(XR, ZF)]:
		_round_tower(stone, roof, glow, Vector3(c.x, 0.0, c.y), 5.6, 24.0, 15.0, 2)
	_round_tower(stone, roof, glow, Vector3(XL, 0.0, 0.0), 4.4, 21.0, 12.0, 1)
	_keep(stone, roof, glow)
	# the great tower: the silhouette against the moon on the way up
	_round_tower(stone, roof, glow, Vector3(-27.0, 0.0, -26.0), 6.8, 44.0, 22.0, 6)
	_lean_to(stone, roof, glow)
	_well(stone, roof, Vector3(-9.0, 0.0, 10.0))

	var toon := ShaderMaterial.new()
	toon.shader = load("res://shaders/toon_vcol.gdshader")
	toon.set_shader_parameter("paint", 0.14)
	_add(parent, stone.commit(), toon, true)
	_add(parent, roof.commit(), toon, true)
	var lit := ShaderMaterial.new()
	lit.shader = load("res://shaders/window.gdshader")
	_add(parent, glow.commit(), lit, false)
	_bats(parent)


## Bats circling the great tower and the keep (they fly in bat.gdshader).
func _bats(parent: Node3D) -> void:
	var b := MeshBuilder.new()
	var col := Color.BLACK
	var n := Vector3.UP
	# body
	var i := b.add(Vector3(0.0, 0.0, 0.25), n, col)
	b.add(Vector3(0.08, 0.0, -0.2), n, col)
	b.add(Vector3(-0.08, 0.0, -0.2), n, col)
	b.tri_raw(i, i + 1, i + 2)
	# wings: scalloped, three points along the trailing edge
	for s: float in [-1.0, 1.0]:
		var root_f := b.add(Vector3(s * 0.07, 0.0, 0.12), n, col)
		var root_b := b.add(Vector3(s * 0.07, 0.0, -0.15), n, col)
		var tip := b.add(Vector3(s * 0.75, 0.05, 0.05), n, col)
		var mid := b.add(Vector3(s * 0.42, 0.0, -0.14), n, col)
		var out := b.add(Vector3(s * 0.66, 0.02, -0.12), n, col)
		b.tri_raw(root_f, tip, mid)
		b.tri_raw(root_f, mid, root_b)
		b.tri_raw(mid, tip, out)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = b.commit()
	var flocks := [[Vector3(-27.0, 0.0, -26.0), 26, 58.0], [Vector3(-27.0, 0.0, 4.0), 14, 44.0]]
	var total := 0
	for f: Array in flocks:
		total += int(f[1])
	mm.instance_count = total
	var k := 0
	for f: Array in flocks:
		var c := _w(f[0]) - centre   # relative to the MultiMeshInstance at the centre
		for _j in int(f[1]):
			var r := _rng.randf_range(10.0, 38.0)
			var speed := _rng.randf_range(4.5, 8.0) / r * (-1.0 if _rng.randf() < 0.3 else 1.0)
			var sc := _rng.randf_range(0.9, 1.5)
			mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * sc), c))
			mm.set_instance_custom_data(k, Color(r, speed, float(f[2]) + _rng.randf_range(-8.0, 12.0), _rng.randf() * TAU))
			k += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bat.gdshader")
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = centre
	mi.custom_aabb = AABB(Vector3(-110.0, 0.0, -110.0), Vector3(220.0, 110.0, 220.0))
	parent.add_child(mi)


func _add(parent: Node3D, mesh: Mesh, mat: Material, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _stone() -> Color:
	return STONE.lerp(STONE_DARK, _rng.randf() * 0.6)


# --- primitives (castle frame) ------------------------------------------------

## An axis-aligned box from `lo` to `hi`, flat-shaded.
func _box(b: MeshBuilder, lo: Vector3, hi: Vector3, col: Color, skip_bottom := true) -> void:
	var faces := [
		[Vector3.RIGHT, [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z)]],
		[Vector3.LEFT, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]],
		[Vector3.UP, [Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)]],
		[Vector3.BACK, [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
		[Vector3.FORWARD, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z)]],
	]
	if not skip_bottom:
		faces.append([Vector3.DOWN, [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]])
	for f: Array in faces:
		var n := _wn(f[0])
		var q: Array = f[1]
		var i := b.add(_w(q[0]), n, col)
		b.add(_w(q[1]), n, col)
		b.add(_w(q[2]), n, col)
		b.add(_w(q[3]), n, col)
		b.quad(i, i + 1, i + 2, i + 3)


## A cylinder's side from y0 to y1, flat facets.
func _cyl(b: MeshBuilder, c: Vector3, r: float, y0: float, y1: float, segs: int, col: Color) -> void:
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var am := (a0 + a1) * 0.5
		var n := _wn(Vector3(cos(am), 0.0, sin(am)))
		var p0 := Vector3(c.x + cos(a0) * r, 0.0, c.z + sin(a0) * r)
		var p1 := Vector3(c.x + cos(a1) * r, 0.0, c.z + sin(a1) * r)
		var shade := col.darkened(_rng.randf() * 0.06)
		var i := b.add(_w(Vector3(p0.x, y0, p0.z)), n, shade)
		b.add(_w(Vector3(p1.x, y0, p1.z)), n, shade)
		b.add(_w(Vector3(p1.x, y1, p1.z)), n, shade)
		b.add(_w(Vector3(p0.x, y1, p0.z)), n, shade)
		b.quad(i, i + 1, i + 2, i + 3)


## A disc (top of a tower), facing up.
func _disc(b: MeshBuilder, c: Vector3, r: float, y: float, segs: int, col: Color) -> void:
	var n := _wn(Vector3.UP)
	var m := b.add(_w(Vector3(c.x, y, c.z)), n, col)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var i := b.add(_w(Vector3(c.x + cos(a0) * r, y, c.z + sin(a0) * r)), n, col)
		b.add(_w(Vector3(c.x + cos(a1) * r, y, c.z + sin(a1) * r)), n, col)
		b.tri(m, i, i + 1)


## A steep conical spire with a slight flare at its foot and a finial.
func _spire(b: MeshBuilder, c: Vector3, r: float, y: float, h: float, segs: int) -> void:
	var tip := Vector3(c.x, y + h, c.z)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var e0 := Vector3(c.x + cos(a0) * r * 1.15, y - 0.8, c.z + sin(a0) * r * 1.15)
		var e1 := Vector3(c.x + cos(a1) * r * 1.15, y - 0.8, c.z + sin(a1) * r * 1.15)
		var m0 := Vector3(c.x + cos(a0) * r * 0.92, y + h * 0.12, c.z + sin(a0) * r * 0.92)
		var m1 := Vector3(c.x + cos(a1) * r * 0.92, y + h * 0.12, c.z + sin(a1) * r * 0.92)
		var col := ROOF.lerp(ROOF_DARK, float(k % 2) * 0.5 + _rng.randf() * 0.2)
		var am0 := (a0 + a1) * 0.5
		var n0 := _wn(Vector3(cos(am0), 0.5, sin(am0)))
		var i := b.add(_w(e0), n0, col)
		b.add(_w(e1), n0, col)
		b.add(_w(m1), n0, col)
		b.add(_w(m0), n0, col)
		b.quad(i, i + 1, i + 2, i + 3)
		var am := (a0 + a1) * 0.5
		var n1 := _wn(Vector3(cos(am), r / h * 0.9, sin(am)))
		var j := b.add(_w(m0), n1, col)
		b.add(_w(m1), n1, col)
		b.add(_w(tip), n1, col)
		b.tri(j, j + 1, j + 2)
	_box(b, Vector3(c.x - 0.08, y + h - 0.3, c.z - 0.08), Vector3(c.x + 0.08, y + h + 2.2, c.z + 0.08), IRON)


## Merlons along a straight top edge from a to b (x, z) at height y.
func _merlons(b: MeshBuilder, a: Vector2, e: Vector2, y: float, depth: float) -> void:
	var len := a.distance_to(e)
	var dir := (e - a) / len
	var n := int(len / 2.1)
	for k in n:
		var t := (k + 0.5) / n
		var p := a.lerp(e, t)
		var half := Vector2(absf(dir.x) * 0.55 + absf(dir.y) * depth * 0.5, absf(dir.y) * 0.55 + absf(dir.x) * depth * 0.5)
		_box(b, Vector3(p.x - half.x, y, p.y - half.y), Vector3(p.x + half.x, y + 1.4, p.y + half.y), _stone())


func _merlon_ring(b: MeshBuilder, c: Vector3, r: float, y: float) -> void:
	var n := int(TAU * r / 2.2)
	for k in n:
		var a := TAU * k / n
		var p := Vector3(c.x + cos(a) * (r - 0.35), 0.0, c.z + sin(a) * (r - 0.35))
		_box(b, Vector3(p.x - 0.45, y, p.z - 0.45), Vector3(p.x + 0.45, y + 1.3, p.z + 0.45), _stone())


## A gothic window: a tall slot with a pointed head, on a face with outward normal n
## (castle frame), lit (warm or blood red) or dark.
func _window(g: MeshBuilder, c: Vector3, n: Vector3, w: float, h: float) -> void:
	var r := _rng.randf()
	var col := DARK_WINDOW
	if r < 0.4:
		col = WARM.darkened(_rng.randf() * 0.35)
	elif r < 0.47:
		col = BLOOD
	var side := Vector3(-n.z, 0.0, n.x) * w * 0.5
	var p := c + n * 0.06
	var nn := _wn(n)
	var i := g.add(_w(p - side), nn, col)
	g.add(_w(p + side), nn, col)
	g.add(_w(p + side + Vector3.UP * h), nn, col)
	g.add(_w(p - side + Vector3.UP * h), nn, col)
	g.quad(i, i + 1, i + 2, i + 3)
	var t := g.add(_w(p + Vector3.UP * (h + w * 0.9)), nn, col)
	g.tri(i + 3, i + 2, t)


# --- parts --------------------------------------------------------------------

func _curtain(b: MeshBuilder) -> void:
	var t := WALL_T * 0.5
	# side walls
	_box(b, Vector3(XL - t, -FOOT, ZB), Vector3(XL + t, WALL_H, ZF), _stone())
	_box(b, Vector3(XR - t, -FOOT, ZB), Vector3(XR + t, WALL_H, ZF), _stone())
	_merlons(b, Vector2(XL - t + 0.3, ZB + 5.0), Vector2(XL - t + 0.3, ZF - 5.0), WALL_H, 0.6)
	_merlons(b, Vector2(XR + t - 0.3, ZB + 5.0), Vector2(XR + t - 0.3, ZF - 5.0), WALL_H, 0.6)
	# end walls, either side of the gatehouses
	for z: float in [ZB, ZF]:
		var out := -1.0 if z == ZB else 1.0
		_box(b, Vector3(XL, -FOOT, z - t), Vector3(-11.5, WALL_H, z + t), _stone())
		_box(b, Vector3(11.5, -FOOT, z - t), Vector3(XR, WALL_H, z + t), _stone())
		_merlons(b, Vector2(XL + 5.0, z + out * (t - 0.3)), Vector2(-12.0, z + out * (t - 0.3)), WALL_H, 0.6)
		_merlons(b, Vector2(12.0, z + out * (t - 0.3)), Vector2(XR - 5.0, z + out * (t - 0.3)), WALL_H, 0.6)


## Two square towers either side of the road, a passage over it with a raised
## portcullis, and lit windows looking out.
func _gatehouse(b: MeshBuilder, g: MeshBuilder, z: float) -> void:
	var out := -1.0 if z == ZB else 1.0
	var h := 21.0
	for x0: float in [-11.5, GATE_HALF]:
		var x1 := x0 + 7.0
		_box(b, Vector3(x0, -FOOT, z - 4.0), Vector3(x1, h, z + 4.0), _stone())
		var top := h
		_merlons(b, Vector2(x0 + 0.3, z - 3.7), Vector2(x1 - 0.3, z - 3.7), top, 0.6)
		_merlons(b, Vector2(x0 + 0.3, z + 3.7), Vector2(x1 - 0.3, z + 3.7), top, 0.6)
		_merlons(b, Vector2(x0 + 0.3, z - 3.0), Vector2(x0 + 0.3, z + 3.0), top, 0.6)
		_merlons(b, Vector2(x1 - 0.3, z - 3.0), Vector2(x1 - 0.3, z + 3.0), top, 0.6)
		for y: float in [9.0, 15.0]:
			_window(g, Vector3((x0 + x1) * 0.5, y, z + out * 4.0), Vector3(0, 0, out), 0.9, 1.8)
	# the passage roof over the road, its face and the battlements
	_box(b, Vector3(-GATE_HALF, GATE_H, z - 3.6), Vector3(GATE_HALF, 17.0, z + 3.6), _stone())
	_merlons(b, Vector2(-GATE_HALF, z + out * 3.3), Vector2(GATE_HALF, z + out * 3.3), 17.0, 0.6)
	# arch stones: a darker band round the opening
	_box(b, Vector3(-GATE_HALF - 0.3, GATE_H - 0.1, z + out * 3.6 - 0.2), Vector3(GATE_HALF + 0.3, GATE_H + 1.0, z + out * 3.6 + 0.2), STONE_DARK)
	# the raised portcullis: iron teeth just showing
	var pz := z + out * 2.5
	for k in 9:
		var x := -GATE_HALF + 0.5 + k * (2.0 * GATE_HALF - 1.0) / 8.0
		_box(b, Vector3(x - 0.07, GATE_H - 0.9, pz - 0.07), Vector3(x + 0.07, GATE_H + 0.1, pz + 0.07), IRON)
	_box(b, Vector3(-GATE_HALF, GATE_H - 0.35, pz - 0.06), Vector3(GATE_HALF, GATE_H - 0.2, pz + 0.06), IRON)


func _round_tower(b: MeshBuilder, r_b: MeshBuilder, g: MeshBuilder, c: Vector3, r: float, h: float, roof_h: float, rows: int) -> void:
	_cyl(b, c, r, -FOOT, h, 16, _stone())
	# corbelled parapet a little wider than the shaft, then the spire
	_cyl(b, c, r + 0.5, h - 2.2, h, 16, STONE_DARK)
	_disc(b, c, r + 0.5, h - 2.2, 16, STONE_DARK)
	_spire(r_b, c, r + 0.2, h, roof_h, 16)
	for row in rows:
		var y := 7.0 + row * (h - 11.0) / maxf(rows, 1)
		var k := 3 + _rng.randi() % 2
		var off := _rng.randf() * TAU
		for i in k:
			var a := off + TAU * i / k
			var n := Vector3(cos(a), 0.0, sin(a))
			_window(g, c + n * r, n, 0.8, 1.7)


## The keep: a tall block with a steep gabled roof and four corner turrets.
func _keep(b: MeshBuilder, r_b: MeshBuilder, g: MeshBuilder) -> void:
	var lo := Vector3(-38.0, -FOOT, -14.0)
	var hi := Vector3(-16.0, 26.0, 22.0)
	_box(b, lo, hi, STONE)
	_box(b, Vector3(lo.x - 0.4, hi.y - 1.0, lo.z - 0.4), Vector3(hi.x + 0.4, hi.y, hi.z + 0.4), STONE_DARK)
	_gable(r_b, lo.x - 0.8, hi.x + 0.8, lo.z - 0.8, hi.z + 0.8, hi.y, 13.0)
	for c: Vector2 in [Vector2(lo.x, lo.z), Vector2(lo.x, hi.z), Vector2(hi.x, lo.z), Vector2(hi.x, hi.z)]:
		var tc := Vector3(c.x, 0.0, c.y)
		_cyl(b, tc, 2.3, 18.0, 33.0, 12, _stone())
		_spire(r_b, tc, 2.4, 33.0, 9.0, 12)
		var a := _rng.randf() * TAU
		_window(g, tc + Vector3(cos(a), 0, sin(a)) * 2.3, Vector3(cos(a), 0, sin(a)), 0.6, 1.3)
	# windows on all four faces, three floors
	for y: float in [6.0, 12.5, 19.0]:
		for z in range(-10, 21, 5):
			_window(g, Vector3(hi.x, y, z), Vector3.RIGHT, 1.0, 2.2)
			_window(g, Vector3(lo.x, y, z), Vector3.LEFT, 1.0, 2.2)
		for x in range(-35, -17, 5):
			_window(g, Vector3(x, y, lo.z), Vector3.FORWARD, 1.0, 2.2)
			_window(g, Vector3(x, y, hi.z), Vector3.BACK, 1.0, 2.2)
	# the great door facing the courtyard
	_box(b, Vector3(hi.x, 0.0, 2.0), Vector3(hi.x + 0.25, 4.6, 6.0), WOOD)


## A gabled roof over x0..x1, z0..z1 at height y, ridge along z.
func _gable(b: MeshBuilder, x0: float, x1: float, z0: float, z1: float, y: float, rise: float) -> void:
	var xm := (x0 + x1) * 0.5
	var half := (x1 - x0) * 0.5
	for side: float in [-1.0, 1.0]:
		var xe := x0 if side < 0.0 else x1
		var n := _wn(Vector3(side * rise, half, 0.0))
		var col := ROOF.lerp(ROOF_DARK, 0.3 if side < 0.0 else 0.0)
		var i := b.add(_w(Vector3(xe, y, z0)), n, col)
		b.add(_w(Vector3(xe, y, z1)), n, col)
		b.add(_w(Vector3(xm, y + rise, z1)), n, col)
		b.add(_w(Vector3(xm, y + rise, z0)), n, col)
		b.quad(i, i + 1, i + 2, i + 3)
	for z: float in [z0, z1]:
		var n := _wn(Vector3(0, 0, -1 if z == z0 else 1))
		var i := b.add(_w(Vector3(x0, y, z)), n, STONE_DARK)
		b.add(_w(Vector3(x1, y, z)), n, STONE_DARK)
		b.add(_w(Vector3(xm, y + rise, z)), n, STONE_DARK)
		b.tri(i, i + 1, i + 2)


## A low building along the right-hand wall: stables or a guardhouse.
func _lean_to(b: MeshBuilder, r_b: MeshBuilder, g: MeshBuilder) -> void:
	var x0 := 8.0
	var x1 := XR - WALL_T * 0.5
	var z0 := -34.0
	var z1 := 18.0
	_box(b, Vector3(x0, -2.0, z0), Vector3(x1, 6.5, z1), STONE_DARK)
	var n := _wn(Vector3(-0.5, 1.0, 0.0))
	var i := r_b.add(_w(Vector3(x0 - 1.0, 5.6, z0 - 0.6)), n, ROOF_DARK)
	r_b.add(_w(Vector3(x0 - 1.0, 5.6, z1 + 0.6)), n, ROOF_DARK)
	r_b.add(_w(Vector3(x1, 10.0, z1 + 0.6)), n, ROOF_DARK)
	r_b.add(_w(Vector3(x1, 10.0, z0 - 0.6)), n, ROOF_DARK)
	r_b.quad(i, i + 1, i + 2, i + 3)
	for z in range(-30, 16, 7):
		_window(g, Vector3(x0, 2.2, z), Vector3.LEFT, 0.8, 1.2)
		_box(b, Vector3(x0 - 0.2, 0.0, z + 2.0), Vector3(x0, 3.0, z + 4.0), WOOD)


func _well(b: MeshBuilder, r_b: MeshBuilder, c: Vector3) -> void:
	_cyl(b, c, 1.4, -1.0, 1.0, 12, STONE_DARK)
	_disc(b, c, 1.2, 0.6, 12, Color(0.02, 0.02, 0.03))
	for s: float in [-1.0, 1.0]:
		_box(b, Vector3(c.x + s * 1.3 - 0.1, 0.0, c.z - 0.1), Vector3(c.x + s * 1.3 + 0.1, 3.0, c.z + 0.1), WOOD)
	_gable(r_b, c.x - 1.8, c.x + 1.8, c.z - 1.0, c.z + 1.0, 3.0, 1.2)
