class_name EndlessStream
extends Node3D
## Keeps the world built around the rider: generates the road ahead and drops it
## behind, builds ground tiles on worker threads (near tiles along the road, a ring of
## big low-detail tiles out to the horizon), adds them when ready, and frees what's
## been left behind.

const AHEAD := 1800.0           # road and tiles this far ahead...
const BEHIND := 400.0           # ...and behind
const NEAR_RADIUS := 600.0      # near tiles within this of the road
const FAR_RADIUS := 4200.0      # far tiles within this of the rider
const ROAD_CHUNK := 200.0
const MAX_TASKS := 6
const ROAD_KEEP := 6000.0       # road points kept either side: far tiles need to know where it goes

class Inbox:
	var mutex := Mutex.new()
	var done: Array = []

var route: StreamRoute
var land: EndlessLand
var kit: EndlessKit
var landmarks: EndlessLandmarks
var rider: Rider
var ground_mat: Material
var road_mat: Material
var _inbox := Inbox.new()
var _tasks := {}                # key -> task id
var _tiles := {}                # key -> Node3D
var _roads := {}                # chunk index -> MeshInstance3D
var _props: Array = []          # [tile node, kind, Instancer] still to build, a few a frame
var _want_at := -1e9
var _want := {}


func _ready() -> void:
	var toon := ShaderMaterial.new()
	toon.shader = load("res://shaders/toon_vcol.gdshader")
	var ground := ShaderMaterial.new()
	ground.shader = load("res://shaders/canyon_ground.gdshader")   # canyon detail by vertex alpha
	ground_mat = ground
	road_mat = toon


static func _key(k: Vector2i, far: bool) -> Vector3i:
	return Vector3i(k.x, k.y, 1 if far else 0)


## Builds everything around road distance `s` before the first frame (blocking).
func prime(s: float) -> void:
	_update(s)
	while not _tasks.is_empty():
		for key: Vector3i in _tasks.keys():
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
		_tasks.clear()   # waited for: their ids are spent
		_collect(1000)
		_build_props(100000)
		_update(s)


func _process(_delta: float) -> void:
	if rider == null:
		return
	_update(rider.distance)
	_collect(1)
	_build_props(4)


func _exit_tree() -> void:
	for key: Vector3i in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
	_tasks.clear()


func _update(s: float) -> void:
	route.ensure(s + ROAD_KEEP)
	if landmarks != null:
		landmarks.plan_up_to(s + ROAD_KEEP - 200.0)
	route.trim(s - ROAD_KEEP)
	_update_roads(s)
	if absf(s - _want_at) > 40.0:
		_want_at = s
		_want = _wanted(s)
		_unload()
	# start the nearest missing tiles
	if _tasks.size() < MAX_TASKS:
		var eye := route.position_at(s)
		var missing := []
		for key: Vector3i in _want:
			if not _tiles.has(key) and not _tasks.has(key):
				missing.append(key)
		var e2 := Vector2(eye.x, eye.z)
		missing.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			var da := _tile_centre(a).distance_squared_to(e2) * (16.0 if a.z == 1 else 1.0)
			var db := _tile_centre(b).distance_squared_to(e2) * (16.0 if b.z == 1 else 1.0)
			return da < db)
		for key: Vector3i in missing:
			if _tasks.size() >= MAX_TASKS:
				break
			_start(key)


func _tile_centre(key: Vector3i) -> Vector2:
	var size := EndlessLand.FAR_TILE if key.z == 1 else EndlessLand.TILE
	return Vector2((key.x + 0.5) * size, (key.y + 0.5) * size)


## Tiles to have: near ones along the road from BEHIND to AHEAD, far ones round the
## rider.
func _wanted(s: float) -> Dictionary:
	var out := {}
	var t := EndlessLand.TILE
	var r := int(ceil(NEAR_RADIUS / t))
	var a := s - BEHIND
	while a <= s + AHEAD:
		var p := route.position_at(a)
		var ci := int(floor(p.x / t))
		var cj := int(floor(p.z / t))
		for j in range(cj - r, cj + r + 1):
			for i in range(ci - r, ci + r + 1):
				if Vector2((i + 0.5) * t, (j + 0.5) * t).distance_to(Vector2(p.x, p.z)) < NEAR_RADIUS + t * 0.71:
					out[Vector3i(i, j, 0)] = true
		a += 64.0
	var ft := EndlessLand.FAR_TILE
	var eye := route.position_at(s)
	var fr := int(ceil(FAR_RADIUS / ft))
	var fi := int(floor(eye.x / ft))
	var fj := int(floor(eye.z / ft))
	for j in range(fj - fr, fj + fr + 1):
		for i in range(fi - fr, fi + fr + 1):
			if Vector2((i + 0.5) * ft, (j + 0.5) * ft).distance_to(Vector2(eye.x, eye.z)) < FAR_RADIUS:
				out[Vector3i(i, j, 1)] = true
	return out


func _start(key: Vector3i) -> void:
	var far := key.z == 1
	var size := EndlessLand.FAR_TILE if far else EndlessLand.TILE
	var lo := Vector2(key.x * size, key.y * size)
	# every tile needs the road out to where the mountains are allowed to rise, or it
	# would raise them over a road it can't see (and float as a sheet)
	var road := route.points_near(lo, lo + Vector2(size, size), 1400.0)
	if far:
		# far tiles only need a thin sample of the road for their coarse distance
		var p: PackedVector3Array = road[0]
		var sd: PackedFloat32Array = road[1]
		var thin := PackedVector3Array()
		var thin_s := PackedFloat32Array()
		for i in range(0, p.size(), 4):
			thin.append(p[i])
			thin_s.append(sd[i])
		road = [thin, thin_s]
	var inbox := _inbox
	var l := land
	_tasks[key] = WorkerThreadPool.add_task(func() -> void:
		var result := l.build_tile(Vector2i(key.x, key.y), far, road)
		if not far:
			result["props"] = EndlessScatter.scatter(result, road, l, l.seed)
		result["k3"] = key
		inbox.mutex.lock()
		inbox.done.append(result)
		inbox.mutex.unlock())


func _collect(limit: int) -> void:
	_inbox.mutex.lock()
	var ready := _inbox.done.slice(0, limit)
	_inbox.done = _inbox.done.slice(limit)
	_inbox.mutex.unlock()
	for r: Dictionary in ready:
		var key: Vector3i = r["k3"]
		if _tasks.has(key):
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
			_tasks.erase(key)
		if not _want.has(key) or _tiles.has(key):
			continue
		var node := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = r["mesh"]
		mi.material_override = ground_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if key.z == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.add_child(mi)
		add_child(node)
		if r.has("props"):
			var props: Dictionary = r["props"]
			for kind: String in props:
				_props.append([node, kind, props[kind]])
		_tiles[key] = node


func _build_props(limit: int) -> void:
	var n := 0
	while n < limit and not _props.is_empty():
		var p: Array = _props.pop_front()
		var node: Node3D = p[0]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		kit.build_one(node, p[1], p[2])
		n += 1


func _unload() -> void:
	for key: Vector3i in _tiles.keys():
		if not _want.has(key):
			var node: Node3D = _tiles[key]
			var geo := []
			for c in node.find_children("*", "GeometryInstance3D", true, false):
				geo.append(c)
			Lod.forget(geo)
			node.queue_free()
			_tiles.erase(key)


## The road surface in chunks of ROAD_CHUNK m, built and dropped with the window.
func _update_roads(s: float) -> void:
	var c0 := int(floor((s - BEHIND) / ROAD_CHUNK))
	var c1 := int(floor((s + AHEAD) / ROAD_CHUNK))
	for c: int in _roads.keys():
		if c < c0 or c > c1:
			(_roads[c] as Node).queue_free()
			_roads.erase(c)
	for c in range(maxi(c0, 0), c1 + 1):
		if not _roads.has(c):
			var mi := MeshInstance3D.new()
			mi.mesh = _ribbon(c * ROAD_CHUNK, (c + 1) * ROAD_CHUNK)
			mi.material_override = road_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_roads[c] = mi


func _ribbon(s0: float, s1: float) -> ArrayMesh:
	var hw := Route.HALF_WIDTH
	var cols := [-hw, -hw * 0.45, 0.0, hw * 0.45, hw]
	var tints := [Roads.EDGE, Roads.TRACK, Roads.CENTRE, Roads.TRACK, Roads.EDGE]
	var b := MeshBuilder.new()
	var n := int(round((s1 - s0) / route.spacing))
	for m in n + 1:
		var s := s0 + m * route.spacing
		var p := route.position_at(s)
		var right := route.right_at(s)
		for c in cols.size():
			var off: float = cols[c]
			b.add(p + right * off + Vector3(0.0, 0.02 - 0.03 * absf(off) / hw, 0.0), Vector3.UP, tints[c])
	var w := cols.size()
	for m in n:
		for c in w - 1:
			b.quad(m * w + c, m * w + c + 1, (m + 1) * w + c + 1, (m + 1) * w + c)
	return b.commit()
