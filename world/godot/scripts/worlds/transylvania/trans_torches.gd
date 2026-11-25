class_name TransTorches
extends Node3D
## Fire along the road: torches in pairs up the climb to the castle (closer together
## near the gates), torches on the gatehouses, braziers in the courtyard, and wooden
## wayside crosses (troiță) with a candle lantern all round the loop.
##
## Every flame is drawn (instanced, see flame.gdshader), but only the ones near the
## rider cast light: a fixed pool of OmniLight3Ds follows the nearest fires, fading in
## and out by distance so none pops, the closest few with shadows. The cost stays the
## same however many torches there are.

const TORCH := 0
const BRAZIER := 1
const CANDLE := 2

const POOL := 18             # lights in the pool
const SHADOWED := 4          # the nearest this many cast shadows
const LIGHT_REACH := 85.0    # a fire lights up within this distance of the camera...
const LIGHT_FADE := 25.0     # ...fading over the last this many metres
const FIRE_COLOR := Color(1.0, 0.52, 0.2)
const CANDLE_COLOR := Color(1.0, 0.62, 0.3)
const WOOD := Color(0.22, 0.15, 0.10)
const IRON := Color(0.10, 0.10, 0.11)
const ROOF := Color(0.20, 0.13, 0.09)

var fires: Array[Vector4] = []   # x, y, z of the flame; w = kind
var _lights: Array[OmniLight3D] = []
var _phase := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _time := 0.0


func build(route: Route, castle_s: float, castle: TransCastle, seed: int) -> void:
	_rng.seed = seed + 700
	var torches := Instancer.new(100.0)
	var braziers := Instancer.new(100.0)
	var brackets := Instancer.new(100.0)
	var crosses := Instancer.new(200.0)
	var flames := Instancer.new(100.0)
	var hw := Route.HALF_WIDTH

	# the climb: pairs either side, every ~45 m low down, every ~16 m near the gates
	for dir: float in [-1.0, 1.0]:
		var u := TransLand.PLATEAU + 18.0
		while u < 2500.0:
			var s := castle_s + dir * u
			var p := route.position_at(s)
			var r := route.right_at(s)
			for side: float in [-1.0, 1.0]:
				var base := p + r * side * (hw + 1.1) + Vector3.DOWN * 0.1
				torches.put(base, _rng.randf() * TAU, 1.0, _rng.randf_range(0.95, 1.08), Color.WHITE)
				_flame(flames, base + Vector3.UP * 2.45, 1.0, TORCH)
			u += lerpf(16.0, 46.0, smoothstep(150.0, 2000.0, u))

	# the gatehouses: a torch on the wall either side of each gate, outside and in
	for z: float in [TransCastle.ZB, TransCastle.ZF]:
		for out: float in [-1.0, 1.0]:
			for x: float in [-TransCastle.GATE_HALF - 1.4, TransCastle.GATE_HALF + 1.4]:
				var face := z + out * 4.3
				var wall := castle._w(Vector3(x, 4.2, z + out * 4.0))
				var at := castle._w(Vector3(x, 4.2, face))
				brackets.put(wall, atan2(-out * castle.fwd.x, -out * castle.fwd.z), 1.0, 1.0, Color.WHITE)
				_flame(flames, at + Vector3.UP * 0.25, 1.0, TORCH)
	# braziers down the courtyard
	for z in range(-38, 40, 19):
		for x: float in [-4.6, 4.6]:
			var at := castle._w(Vector3(x, 0.0, z))
			braziers.put(at, _rng.randf() * TAU, 1.0, 1.0, Color.WHITE)
			_flame(flames, at + Vector3.UP * 1.25, 1.9, BRAZIER)

	# wayside crosses all round the loop, a candle lantern at the foot of each
	var s := 140.0
	while s < route.length - 60.0:
		var u := absf(s - castle_s)
		if u > TransLand.PLATEAU + 60.0:
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			var r := route.right_at(s)
			var at := route.position_at(s) + r * side * (hw + 2.4)
			var t := route.tangent_at(s)
			# arms along the road, the lantern on the road side
			crosses.put(at + Vector3.DOWN * 0.2, atan2(t.x, t.z) + (PI if side > 0.0 else 0.0), 1.0, _rng.randf_range(0.95, 1.1), Color(1, 1, 1).darkened(_rng.randf() * 0.2))
			_flame(flames, at + r * side * -0.45 + Vector3.UP * 0.55, 0.45, CANDLE)
		s += _rng.randf_range(380.0, 650.0)

	var toon := ShaderMaterial.new()
	toon.shader = load("res://shaders/toon_vcol.gdshader")
	torches.build(self, _torch_mesh(), toon, 400.0, true)
	braziers.build(self, _brazier_mesh(), toon, 400.0, true)
	brackets.build(self, _bracket_mesh(), toon, 400.0, false)
	crosses.build(self, _cross_mesh(), toon, 500.0, true)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/flame.gdshader")
	flames.build(self, _flame_mesh(), fm, 1600.0, false)

	for i in POOL:
		var l := OmniLight3D.new()
		l.light_color = FIRE_COLOR
		l.omni_range = 14.0
		l.omni_attenuation = 1.3
		l.light_volumetric_fog_energy = 2.0
		l.shadow_enabled = i < SHADOWED
		l.visible = false
		add_child(l)
		_lights.append(l)
	_phase.resize(POOL)
	print("  fires: %d (%d torches, %d braziers, %d crosses)" % [fires.size(), torches.count(), braziers.count(), crosses.count()])


func _flame(flames: Instancer, at: Vector3, size: float, kind: int) -> void:
	flames.put(at, _rng.randf() * TAU, size, size, Color.WHITE)
	fires.append(Vector4(at.x, at.y + 0.3 * size, at.z, kind))


## Every frame: the pool's lights go to the nearest fires (by distance, in order, so
## the nearest keep their shadows), with a flicker per fire.
func _process(delta: float) -> void:
	_time += delta
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var near := []
	var reach2 := LIGHT_REACH * LIGHT_REACH
	for i in fires.size():
		var f := fires[i]
		var d2 := Vector3(f.x, f.y, f.z).distance_squared_to(eye)
		if d2 < reach2:
			near.append(Vector2(d2, i))
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for k in POOL:
		var l := _lights[k]
		if k >= near.size():
			l.visible = false
			continue
		var i := int(near[k].y)
		var f := fires[i]
		var d := sqrt(near[k].x)
		var kind := int(f.w)
		var flick := 0.82 + 0.12 * sin(_time * 9.0 + i * 1.3) * sin(_time * 4.3 + i) + 0.06 * sin(_time * 17.0 + i * 2.1)
		var base := 4.5 if kind == BRAZIER else (1.3 if kind == CANDLE else 3.0)
		l.visible = true
		l.position = Vector3(f.x, f.y, f.z)
		l.light_color = CANDLE_COLOR if kind == CANDLE else FIRE_COLOR
		l.omni_range = 22.0 if kind == BRAZIER else (8.0 if kind == CANDLE else 16.0)
		l.light_energy = base * flick * (1.0 - smoothstep(LIGHT_REACH - LIGHT_FADE, LIGHT_REACH, d))


# --- meshes -------------------------------------------------------------------

static func _box(b: MeshBuilder, lo: Vector3, hi: Vector3, col: Color) -> void:
	var faces := [
		[Vector3.RIGHT, [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z)]],
		[Vector3.LEFT, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]],
		[Vector3.UP, [Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)]],
		[Vector3.DOWN, [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]],
		[Vector3.BACK, [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
		[Vector3.FORWARD, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z)]],
	]
	for f: Array in faces:
		var q: Array = f[1]
		var i := b.add(q[0], f[0], col)
		b.add(q[1], f[0], col)
		b.add(q[2], f[0], col)
		b.add(q[3], f[0], col)
		b.quad(i, i + 1, i + 2, i + 3)


## A wooden pole with an iron cup at the top (the flame sits at 2.45 m).
static func _torch_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	_box(b, Vector3(-0.07, 0.0, -0.07), Vector3(0.07, 2.2, 0.07), WOOD)
	_box(b, Vector3(-0.16, 2.2, -0.16), Vector3(0.16, 2.45, 0.16), IRON)
	_box(b, Vector3(-0.2, 2.42, -0.2), Vector3(0.2, 2.47, 0.2), IRON)
	return b.commit()


## An iron arm out of a wall with a cup on it (the wall at z = 0, the arm along -z;
## the flame sits 0.3 m out at 0.25 m up).
static func _bracket_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	_box(b, Vector3(-0.15, -0.4, -0.05), Vector3(0.15, 0.1, 0.0), IRON)
	_box(b, Vector3(-0.04, -0.3, -0.3), Vector3(0.04, -0.22, 0.0), IRON)
	_box(b, Vector3(-0.13, -0.22, -0.43), Vector3(0.13, 0.0, -0.17), IRON)
	return b.commit()


## An iron bowl on three legs (the flame sits at 1.25 m).
static func _brazier_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	for k in 3:
		var a := TAU * k / 3.0
		var o := Vector3(cos(a), 0.0, sin(a)) * 0.35
		_box(b, o + Vector3(-0.04, 0.0, -0.04), o + Vector3(0.04, 1.0, 0.04), IRON)
	_box(b, Vector3(-0.45, 1.0, -0.45), Vector3(0.45, 1.25, 0.45), IRON)
	_box(b, Vector3(-0.38, 1.22, -0.38), Vector3(0.38, 1.3, 0.38), Color(0.35, 0.12, 0.04))   # embers
	return b.commit()


## A troiță: a tall wooden cross with a little gabled roof over its arms, and a
## lantern box on a stone at its foot (facing the road along -x).
static func _cross_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	_box(b, Vector3(-0.12, 0.0, -0.12), Vector3(0.12, 3.4, 0.12), WOOD)
	_box(b, Vector3(-0.08, 2.3, -0.9), Vector3(0.08, 2.5, 0.9), WOOD)
	# the roof: two slopes along z over the arms, from z -1.1 to 1.1
	for side: float in [-1.0, 1.0]:
		var n := Vector3(side * 0.8, 1.0, 0.0).normalized()
		var i := b.add(Vector3(side * 0.55, 2.85, -1.1), n, ROOF)
		b.add(Vector3(side * 0.55, 2.85, 1.1), n, ROOF)
		b.add(Vector3(0.0, 3.35, 1.1), n, ROOF)
		b.add(Vector3(0.0, 3.35, -1.1), n, ROOF)
		b.quad(i, i + 1, i + 2, i + 3)
	_box(b, Vector3(-0.75, 0.0, -0.3), Vector3(-0.15, 0.35, 0.3), Color(0.38, 0.37, 0.39))
	_box(b, Vector3(-0.6, 0.35, -0.15), Vector3(-0.3, 0.42, 0.15), IRON)
	_box(b, Vector3(-0.6, 0.78, -0.15), Vector3(-0.3, 0.84, 0.15), IRON)
	return b.commit()


## Three crossed quads, 0.36 m wide and 0.75 m tall, UV y from the base up.
static func _flame_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	for k in 3:
		var a := PI * k / 3.0
		var d := Vector3(cos(a), 0.0, sin(a)) * 0.18
		var n := Vector3(-d.z, 0.0, d.x).normalized()
		var i := b.add(-d, n, Color.WHITE, Vector2(0.0, 0.0))
		b.add(d, n, Color.WHITE, Vector2(1.0, 0.0))
		b.add(d + Vector3.UP * 0.75, n, Color.WHITE, Vector2(1.0, 1.0))
		b.add(-d + Vector3.UP * 0.75, n, Color.WHITE, Vector2(0.0, 1.0))
		b.tri_raw(i, i + 1, i + 2)
		b.tri_raw(i, i + 2, i + 3)
	return b.commit()
