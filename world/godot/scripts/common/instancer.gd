class_name Instancer
extends RefCounted
## Collects instances of one prop in square chunks and turns each chunk into a
## MultiMeshInstance3D, so the GPU only draws chunks in view. Each instance is 12 floats
## of transform and 4 of colour (multiplied into the mesh's vertex colours).

class Chunk:
	var origin := Vector3.ZERO
	var data := PackedFloat32Array()

var size := 32.0
var chunks := {}


func _init(chunk_size: float) -> void:
	size = chunk_size


func _chunk(pos: Vector3) -> Chunk:
	var key := Vector2i(floori(pos.x / size), floori(pos.z / size))
	var ch: Chunk = chunks.get(key)
	if ch == null:
		ch = Chunk.new()
		ch.origin = Vector3((key.x + 0.5) * size, 0.0, (key.y + 0.5) * size)
		chunks[key] = ch
	return ch


## Upright instance: turned by `yaw`, scaled `sxz` across and `sy` up.
func put(pos: Vector3, yaw: float, sxz: float, sy: float, col: Color) -> void:
	var ch := _chunk(pos)
	var c := cos(yaw)
	var s := sin(yaw)
	var o := pos - ch.origin
	ch.data.append_array(PackedFloat32Array([
		c * sxz, 0.0, s * sxz, o.x,
		0.0, sy, 0.0, o.y,
		-s * sxz, 0.0, c * sxz, o.z,
		col.r, col.g, col.b, col.a]))


## Instance with any basis (tilted rocks).
func put_basis(pos: Vector3, b: Basis, col: Color) -> void:
	var ch := _chunk(pos)
	var o := pos - ch.origin
	ch.data.append_array(PackedFloat32Array([
		b.x.x, b.y.x, b.z.x, o.x,
		b.x.y, b.y.y, b.z.y, o.y,
		b.x.z, b.y.z, b.z.z, o.z,
		col.r, col.g, col.b, col.a]))


func count() -> int:
	var n := 0
	for key in chunks:
		n += (chunks[key] as Chunk).data.size() / 16
	return n


## Adds one MultiMeshInstance3D per chunk, visible from `near` to `far` m (0 = no limit).
## `mat` null keeps the mesh's own materials (multi-surface meshes like TreeGen's).
func build(parent: Node3D, mesh: Mesh, mat: Material, far: float, shadows: bool, near := 0.0) -> int:
	var total := 0
	for key in chunks:
		var ch: Chunk = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = ch.data.size() / 16
		mm.buffer = ch.data
		total += mm.instance_count
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		if mat != null:
			mi.material_override = mat   # else the mesh's own surface materials
		mi.position = ch.origin
		mi.visibility_range_begin = near
		mi.visibility_range_end = far
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	return total


## Levels of detail: `tiers` is a list of [mesh, material or null, from m, to m, shadows].
## Returns the instance count once.
func build_tiers(parent: Node3D, tiers: Array) -> int:
	var n := 0
	for t: Array in tiers:
		n = build(parent, t[0], t[1], t[3], t[4], t[2])
	return n


## `mesh` up close (with `mat`, or its own materials if null), `far_mesh` from `switch` m
## out to `far` m.
func build_lod(parent: Node3D, mesh: Mesh, mat: Material, far_mesh: Mesh, far_mat: Material, switch: float, far: float) -> int:
	var n := build(parent, mesh, mat, switch, true)
	build(parent, far_mesh, far_mat, far, false, switch)
	return n
