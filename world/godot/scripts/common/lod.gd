class_name Lod
extends Node
## Level-of-detail manager. Every drawn thing belongs to a category (trees, grass,
## cliffs, ...). Each registered node has base distances (where it shows, from-to,
## for a 1080p screen at the camera's field of view); the manager scales them by:
##
##   resolution  distances grow with the screen's focal length in pixels, so a bigger
##               or narrower view keeps the same on-screen sizes;
##   quality     --quality=low|medium|high|ultra sets every category's starting scale;
##   budget      while riding, frame cost is measured (CPU and GPU render time, so it
##               works with vsync on). Over budget, the category with the highest
##               estimated cost per unit of importance gives up range first; with room
##               to spare, the most important category relative to its current scale
##               gets range back. Steps are small and spaced out, so nothing breathes.
##
## Cost estimate per category: the triangles of every registered node currently within
## its range (instances x triangles per instance), so cuts go where the triangles are.
## Tiered props whose shaders include lod_fade.gdshaderinc (trees) pick their tier per
## instance and dissolve between tiers with a dither (no pop, and no whole chunk
## switching at once); other props switch per chunk.

const REF_HEIGHT := 1080.0
const STEP_DOWN := 0.85
const STEP_UP := 1.08
const SCALE_MIN := 0.35
const SCALE_MAX := 1.6
const QUALITY := {"low": 0.6, "medium": 0.8, "high": 1.0, "ultra": 1.3}
const UPDATE_S := 0.5
const COOLDOWN_S := 1.5
const ROOM_S := 4.0          # time under the low mark before giving detail back
const FADE := 0.1            # cross-fade margin, as a share of the boundary distance

class Entry:
	var node: GeometryInstance3D
	var base_from := 0.0
	var base_to := 0.0
	var pad := 0.0           # extra range (chunk half-diagonal) when instances fade themselves
	var tris := 0            # triangles per instance x instances

class Category:
	var name := ""
	var importance := 1.0
	var scale := 1.0
	var entries: Array[Entry] = []
	var materials := []      # [material, parameter, base value] scaled with the category
	var fades := []          # [material, from, to]: tier materials with the per-instance dissolve
	var cost := 0.0          # triangles in range at the last update

static var _self: Lod

var categories := {}
var quality := "high"
var auto := true
var target_fps := 60.0
var camera: Camera3D
var _times := PackedFloat32Array()
var _clock := 0.0
var _cooldown := 0.0
var _room := 0.0
var _focal_ratio := 1.0
var last_p95_ms := 0.0
var fade := true
var _pending: Array[Category] = []   # categories whose nodes still need their new ranges
var _apply_at := 0
var _scan_cat := 0           # cursor over categories and their entries
var _scan_at := 0
var _scan_sum := {}
var last_change := ""


func _ready() -> void:
	_self = self
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


static func get_manager() -> Lod:
	return _self


## Declares a category; `importance` weighs how much it's worth keeping (0..1).
static func category(name: String, importance: float) -> void:
	var m := _self
	if m == null or m.categories.has(name):
		return
	var c := Category.new()
	c.name = name
	c.importance = importance
	c.scale = QUALITY.get(m.quality, 1.0)
	m.categories[name] = c


## Registers a node drawn from `from` to `to` m (base, 1080p). 0 for `to` = no limit.
## `pad` widens its range when its instances dissolve per instance (add_fade).
static func add(name: String, node: GeometryInstance3D, from: float, to: float, pad := 0.0) -> void:
	var m := _self
	if m == null:
		node.visibility_range_begin = from
		node.visibility_range_end = to
		return
	if not m.categories.has(name):
		category(name, 0.5)
	var e := Entry.new()
	e.node = node
	e.base_from = from
	e.base_to = to
	e.pad = pad
	e.tris = _triangles(node)
	(m.categories[name] as Category).entries.append(e)
	m._apply_entry(e, m.categories[name])


## A tier material whose instances dissolve in and out at `from` and `to` m (base).
static func add_fade(name: String, material: ShaderMaterial, from: float, to: float) -> void:
	var m := _self
	if m == null:
		return
	if not m.categories.has(name):
		category(name, 0.5)
	var c: Category = m.categories[name]
	for f: Array in c.fades:
		if f[0] == material:
			return
	c.fades.append([material, from, to])
	m._apply_fade(c, c.fades[c.fades.size() - 1])


func _apply_fade(c: Category, f: Array) -> void:
	var k := c.scale * _focal_ratio
	var band := FADE if fade else 0.0
	var from: float = f[1] * k
	var to: float = f[2] * k
	var v := Vector4(from * (1.0 - band), from * (1.0 + band), to * (1.0 - band), to * (1.0 + band))
	if from <= 0.0:
		v.x = -2.0
		v.y = -1.0
	(f[0] as ShaderMaterial).set_shader_parameter("lod_fade", v)


## A shader parameter that scales with the category (grass fade distances).
static func add_param(name: String, material: ShaderMaterial, param: String, base: float) -> void:
	var m := _self
	if m == null:
		return
	if not m.categories.has(name):
		category(name, 0.5)
	var c: Category = m.categories[name]
	c.materials.append([material, param, base])
	material.set_shader_parameter(param, base * c.scale * m._focal_ratio)


static var _mesh_tris := {}


static func _triangles(node: GeometryInstance3D) -> int:
	var mesh: Mesh
	var count := 1
	if node is MultiMeshInstance3D:
		var mm := (node as MultiMeshInstance3D).multimesh
		mesh = mm.mesh
		count = mm.instance_count
	elif node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	if mesh == null:
		return 0
	if _mesh_tris.has(mesh):
		return int(_mesh_tris[mesh]) * count
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		tris += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_mesh_tris[mesh] = tris
	return tris * count


## Forget everything (a new world is being built).
func clear() -> void:
	categories.clear()
	_pending.clear()
	_apply_at = 0
	_scan_sum.clear()
	_scan_cat = 0
	_scan_at = 0
	_mesh_tris.clear()
	_times.clear()


func _apply_entry(e: Entry, c: Category) -> void:
	var k := c.scale * _focal_ratio
	var node := e.node
	if e.pad > 0.0:
		# the instances choose their tier in the shader; the chunk just has to be drawn
		node.visibility_range_begin = maxf(e.base_from * k * (1.0 - FADE) - e.pad, 0.0)
		node.visibility_range_end = e.base_to * k * (1.0 + FADE) + e.pad if e.base_to > 0.0 else 0.0
	else:
		node.visibility_range_begin = e.base_from * k
		node.visibility_range_end = e.base_to * k
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## Applies a category's scale: materials at once, nodes a slice per frame (see
## _apply_step), so a change never stalls a frame.
func _apply(c: Category) -> void:
	if not _pending.has(c):
		_pending.append(c)
	for m: Array in c.materials:
		(m[0] as ShaderMaterial).set_shader_parameter(m[1], float(m[2]) * c.scale * _focal_ratio)
	for f: Array in c.fades:
		_apply_fade(c, f)


const APPLY_PER_FRAME := 400


func _apply_step() -> void:
	var budget := APPLY_PER_FRAME
	while budget > 0 and not _pending.is_empty():
		var c: Category = _pending[0]
		var stop := mini(_apply_at + budget, c.entries.size())
		for i in range(_apply_at, stop):
			if is_instance_valid(c.entries[i].node):
				_apply_entry(c.entries[i], c)
		budget -= stop - _apply_at
		_apply_at = stop
		if _apply_at >= c.entries.size():
			_pending.pop_front()
			_apply_at = 0


func _apply_all() -> void:
	for name in categories:
		_apply(categories[name])


## Frame cost in ms: the larger of CPU and GPU render time (not the time between
## frames, which vsync pads to the refresh rate).
func _frame_ms() -> float:
	var rid := get_viewport().get_viewport_rid()
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return maxf(cpu, gpu)


func _process(delta: float) -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
		if camera == null:
			return
	# distances follow the focal length in pixels (resolution and field of view)
	var h := float(get_viewport().get_visible_rect().size.y)
	var win_h := float(DisplayServer.window_get_size().y)
	var focal := win_h / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	var ref := REF_HEIGHT / (2.0 * tan(deg_to_rad(72.0) * 0.5))
	var ratio := clampf(focal / ref, 0.5, 3.0)
	if absf(ratio - _focal_ratio) > 0.02:
		_focal_ratio = ratio
		_apply_all()
	_times.append(_frame_ms())
	_apply_step()
	_scan_step()
	_clock += delta
	_cooldown -= delta
	if _clock < UPDATE_S:
		return
	_clock = 0.0
	var sorted := _times.duplicate()
	sorted.sort()
	last_p95_ms = sorted[int(sorted.size() * 0.95)] if sorted.size() > 0 else 0.0
	_times.clear()
	if not auto or _cooldown > 0.0:
		return
	var budget := 1000.0 / target_fps
	if last_p95_ms > budget * 0.85:
		_room = 0.0
		_shed()
	elif last_p95_ms < budget * 0.6:
		_room += UPDATE_S
		if _room >= ROOM_S:
			_room = 0.0
			_restore()
	else:
		_room = 0.0


## Triangles each category has within range (frustum ignored), counted a slice of
## SCAN_PER_FRAME nodes per frame so the count never causes a hitch.
const SCAN_PER_FRAME := 300


func _scan_step() -> void:
	var names := categories.keys()
	if names.is_empty():
		return
	var cam := camera.global_position
	var budget := SCAN_PER_FRAME
	while budget > 0:
		if _scan_cat >= names.size():
			# a full pass is done: publish and start over
			for name in _scan_sum:
				if categories.has(name):
					(categories[name] as Category).cost = _scan_sum[name]
			_scan_sum.clear()
			_scan_cat = 0
			_scan_at = 0
			return
		var name: String = names[_scan_cat]
		var entries: Array[Entry] = (categories[name] as Category).entries
		var stop := mini(_scan_at + budget, entries.size())
		var sum: float = _scan_sum.get(name, 0.0)
		for i in range(_scan_at, stop):
			var e := entries[i]
			if not is_instance_valid(e.node) or not e.node.visible:
				continue
			var d := cam.distance_to(e.node.global_position)
			if d >= e.node.visibility_range_begin and (e.node.visibility_range_end <= 0.0 or d <= e.node.visibility_range_end):
				sum += e.tris
		_scan_sum[name] = sum
		budget -= stop - _scan_at
		_scan_at = stop
		if _scan_at >= entries.size():
			_scan_cat += 1
			_scan_at = 0


## Over budget: the category with the most triangles per unit of importance gives up
## range. Importance counts cubed, so roadside trees and grass hold on while ferns and
## mounds go, unless they're nearly the whole cost.
func _shed() -> void:
	var worst: Category = null
	var worst_ratio := -1.0
	for name in categories:
		var c: Category = categories[name]
		if c.scale <= SCALE_MIN:
			continue
		var r := c.cost / pow(maxf(c.importance, 0.05), 3.0)
		if r > worst_ratio:
			worst_ratio = r
			worst = c
	if worst == null:
		return
	worst.scale = maxf(worst.scale * STEP_DOWN, SCALE_MIN)
	_apply(worst)
	_cooldown = COOLDOWN_S
	last_change = "%s down to %.2f" % [worst.name, worst.scale]


## Room to spare: the most important category relative to its scale gets range back.
func _restore() -> void:
	var best: Category = null
	var best_ratio := -1.0
	for name in categories:
		var c: Category = categories[name]
		if c.scale >= SCALE_MAX:
			continue
		var r := c.importance / c.scale
		if r > best_ratio:
			best_ratio = r
			best = c
	if best == null:
		return
	best.scale = minf(best.scale * STEP_UP, SCALE_MAX)
	_apply(best)
	_cooldown = COOLDOWN_S
	last_change = "%s up to %.2f" % [best.name, best.scale]


## One line for the status text: frame cost and each category's scale.
func summary() -> String:
	var parts := []
	for name in categories:
		var c: Category = categories[name]
		parts.append("%s %.2f" % [name, c.scale])
	return "%.1f ms p95 (budget %.1f)  %s" % [last_p95_ms, 1000.0 / target_fps, "  ".join(parts)]
