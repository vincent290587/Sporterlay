class_name MegaKit
extends RefCounted
## Models from Quaternius' Stylized Nature MegaKit (CC0, assets/megakit, prepared by
## tools/import_megakit.py), turned into plain meshes drawn with our toon_tex shader:
##
##   TREE   leaf surfaces get normals pointing away from the crown's centre (the soft
##          one-volume toon shading of our own trees) and sway; bark keeps its normals
##   PLANT  normals bent mostly upwards (flat, even toon light on small plants), a
##          little sway
##   SOLID  rocks, mushrooms, dead trees: normals as modelled
##
## Materials are shared per texture, cut-out and LOD tier, so the LOD manager can set
## each tier's fade distances.

enum { TREE, PLANT, SOLID }

const DIR := "res://assets/megakit/%s.gltf"
const SHADER := preload("res://shaders/toon_tex.gdshader")

static var _meshes := {}
static var _mats := {}


static func available() -> bool:
	return DirAccess.dir_exists_absolute("res://assets/megakit")


## Forget the materials (a new world registers fresh ones with the LOD manager).
static func reset() -> void:
	_mats.clear()
	_meshes.clear()


## The model `name` as one mesh, its surfaces with our materials for `tier`.
static func mesh(name: String, style: int, tier := 0) -> ArrayMesh:
	var key := "%s:%d:%d" % [name, style, tier]
	if _meshes.has(key):
		return _meshes[key]
	var scene: PackedScene = load(DIR % name)
	var root: Node3D = scene.instantiate()
	var out := ArrayMesh.new()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xf := _to_root(mi, root)
		var m := mi.mesh
		for s in m.get_surface_count():
			var arrays := m.surface_get_arrays(s)
			var src := mi.get_active_material(s)
			var tex: Texture2D = null
			var cut := false
			if src is BaseMaterial3D:
				tex = (src as BaseMaterial3D).albedo_texture
				cut = (src as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in verts.size():
				verts[i] = xf * verts[i]
				normals[i] = (xf.basis * normals[i]).normalized()
			_rework_normals(verts, normals, style, cut)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = null
			arrays[Mesh.ARRAY_COLOR] = null   # their baked darkening; only our instance tint applies
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(out.get_surface_count() - 1, material(tex, cut, style, tier))
	root.free()
	_meshes[key] = out
	return out


static func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _rework_normals(verts: PackedVector3Array, normals: PackedVector3Array, style: int, cut: bool) -> void:
	if style == TREE and cut:
		var center := Vector3.ZERO
		for v in verts:
			center += v
		center /= maxi(verts.size(), 1)
		for i in verts.size():
			var out := verts[i] - center
			if out.length() > 0.01:
				normals[i] = (normals[i] * 0.25 + out.normalized() * 0.75).normalized()
	elif style == PLANT:
		for i in normals.size():
			normals[i] = (normals[i] * 0.3 + Vector3.UP * 0.7).normalized()


## Our material for a texture: one per texture, cut-out, sway style and LOD tier.
static func material(tex: Texture2D, cut: bool, style: int, tier: int) -> ShaderMaterial:
	var key := "%s:%s:%d:%d" % [tex.resource_path if tex else "none", cut, style, tier]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("cutout", 1.0 if cut else 0.0)
	if style == TREE:      # bark and leaves together, so the tree bends as one
		m.set_shader_parameter("sway", TreeGen.SWAY)
		m.set_shader_parameter("sway_height", 10.0)
	elif style == PLANT:
		m.set_shader_parameter("sway", 0.06)
		m.set_shader_parameter("sway_height", 0.6)
	_mats[key] = m
	return m


## All materials made for `tier` (to register their fade distances with Lod).
static func tier_materials(tier: int) -> Array:
	var out := []
	for key: String in _mats:
		if key.ends_with(":%d" % tier):
			out.append(_mats[key])
	return out
