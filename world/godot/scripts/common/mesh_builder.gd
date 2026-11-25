class_name MeshBuilder
extends RefCounted
## Collects vertices and triangles for an ArrayMesh. Triangles are wound from their
## vertices' normals, so callers never have to think about Godot's winding order.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()
var custom := PackedFloat32Array()   # optional CUSTOM0 (RGBA float), 4 per vertex


func add(p: Vector3, n: Vector3, c: Color, uv := Vector2.ZERO) -> int:
	verts.append(p)
	normals.append(n)
	colors.append(c)
	uvs.append(uv)
	return verts.size() - 1


## A triangle whose front faces the way its vertices' normals point.
func tri(a: int, b: int, c: int) -> void:
	# Godot's front faces are clockwise, so their cross product points inwards.
	var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if face.dot(normals[a] + normals[b] + normals[c]) > 0.0:
		indices.append(a)
		indices.append(c)
		indices.append(b)
	else:
		indices.append(a)
		indices.append(b)
		indices.append(c)


## A triangle drawn from both sides (grass): winding doesn't matter.
func tri_raw(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)


func quad(a: int, b: int, c: int, d: int) -> void:
	tri(a, b, c)
	tri(a, c, d)


## The same triangles with unshared vertices and face normals (faceted look).
func faceted() -> MeshBuilder:
	var out := MeshBuilder.new()
	for t in range(0, indices.size(), 3):
		var a := indices[t]
		var b := indices[t + 1]
		var c := indices[t + 2]
		var n := -(verts[b] - verts[a]).cross(verts[c] - verts[a]).normalized()
		var col := colors[a].lerp(colors[b], 0.5).lerp(colors[c], 0.33)
		out.tri_raw(out.add(verts[a], n, col), out.add(verts[b], n, col), out.add(verts[c], n, col))
	return out


func commit() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var flags := 0
	if custom.size() == verts.size() * 4:
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh
