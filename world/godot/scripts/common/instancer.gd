class_name Instancer
extends RefCounted
## Collects instances of one prop in square chunks and turns each chunk into a
## MultiMeshInstance3D, so the GPU only draws chunks in view. Each instance is 12 floats
## of transform and 4 of colour (multiplied into the mesh's vertex colours).

class Chunk:
	var origin := Vector3.ZERO
	var data := PackedFloat32Array()

var size := 32.0
var data := PackedFloat32Array()   # every instance, origin in world space


func _init(chunk_size: float) -> void:
	size = chunk_size


func _record(b: Basis, pos: Vector3, col: Color) -> void:
	data.append_array(PackedFloat32Array([
		b.x.x, b.y.x, b.z.x, pos.x,
		b.x.y, b.y.y, b.z.y, pos.y,
		b.x.z, b.y.z, b.z.z, pos.z,
		col.r, col.g, col.b, col.a]))


## Upright instance: turned by `yaw`, scaled `sxz` across and `sy` up.
func put(pos: Vector3, yaw: float, sxz: float, sy: float, col: Color) -> void:
	var c := cos(yaw)
	var s := sin(yaw)
	_record(Basis(Vector3(c * sxz, 0.0, -s * sxz), Vector3(0.0, sy, 0.0), Vector3(s * sxz, 0.0, c * sxz)), pos, col)


## Instance with any basis (tilted rocks).
func put_basis(pos: Vector3, b: Basis, col: Color) -> void:
	_record(b, pos, col)


## The instances grouped into square chunks of `chunk` m, positions relative to each
## chunk's centre.
func _chunks(chunk: float) -> Dictionary:
	var out := {}
	for i in range(0, data.size(), 16):
		var key := Vector2i(floori(data[i + 3] / chunk), floori(data[i + 11] / chunk))
		var ch: Chunk = out.get(key)
		if ch == null:
			ch = Chunk.new()
			ch.origin = Vector3((key.x + 0.5) * chunk, 0.0, (key.y + 0.5) * chunk)
			out[key] = ch
		var rec := data.slice(i, i + 16)
		rec[3] -= ch.origin.x
		rec[11] -= ch.origin.z
		ch.data.append_array(rec)
	return out


func count() -> int:
	return data.size() / 16


## Adds one MultiMeshInstance3D per chunk, visible from `near` to `far` m (0 = no limit).
## `mat` null keeps the mesh's own materials (multi-surface meshes like TreeGen's).
func build(parent: Node3D, mesh: Mesh, mat: Material, far: float, shadows: bool, near := 0.0, lod := "",
		pad := 0.0, chunk := 0.0) -> int:
	var total := 0
	var chunks := _chunks(chunk if chunk > 0.0 else size)
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
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		if lod != "":
			Lod.add(lod, mi, near, far, pad)   # the LOD manager owns its distances
		else:
			mi.visibility_range_begin = near
			mi.visibility_range_end = far
	return total


## Levels of detail: `tiers` is a list of [mesh, material or null, from m, to m, shadows,
## materials to dissolve, chunk size], all in LOD category `lod`. With dissolve
## materials (their shader includes lod_fade.gdshaderinc) each instance picks its own
## tier and fades between them; the chunks' ranges are widened by the chunk's
## half-diagonal so every instance that needs drawing is in a drawn chunk. Small chunks
## for heavy near tiers (little wasted vertex work), big ones far away (few draw calls).
## Returns the instance count once.
func build_tiers(parent: Node3D, tiers: Array, lod := "") -> int:
	var n := 0
	for t: Array in tiers:
		var fades: Array = t[5] if t.size() > 5 else []
		var chunk: float = t[6] if t.size() > 6 else size
		for m: ShaderMaterial in fades:
			Lod.add_fade(lod, m, t[2], t[3])
		n = build(parent, t[0], t[1], t[3], t[4], t[2], lod, chunk * 0.7072 if not fades.is_empty() else 0.0, chunk)
	return n


## `mesh` up close (with `mat`, or its own materials if null), `far_mesh` from `switch` m
## out to `far` m.
func build_lod(parent: Node3D, mesh: Mesh, mat: Material, far_mesh: Mesh, far_mat: Material, switch: float, far: float) -> int:
	var n := build(parent, mesh, mat, switch, true)
	build(parent, far_mesh, far_mat, far, false, switch)
	return n
