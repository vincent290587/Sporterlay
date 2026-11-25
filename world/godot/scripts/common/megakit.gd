class_name MegaKit
extends RefCounted
## Models from imported packs (tools/import_assets.py): Quaternius' Stylized Nature
## MegaKit (CC0, assets/megakit), the Medieval Village and Fantasy Props MegaKits
## (assets/village, assets/props) and local-only ones (assets/local), turned into plain
## meshes drawn with our toon_tex shader:
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
const PROP := 9     # "tier" for small props: own materials, never faded per instance
const PROP_FAR := 10 # small props simplified for distance (own materials too)

const DIR := "res://assets/megakit/%s.gltf"
const SHADER := preload("res://shaders/toon_tex.gdshader")

static var _meshes := {}
static var _mats := {}


static func available() -> bool:
	return DirAccess.dir_exists_absolute("res://assets/megakit")


## Whether a pack was imported (tools/import_assets.py): "village", "props", or a
## local-only one such as "local/raft".
static func has_pack(pack: String) -> bool:
	return DirAccess.dir_exists_absolute("res://assets/" + pack)


## Models are named by pack: "Rock_Medium_1" (the nature kit), "village/Wall_Arch",
## "local/raft/EA04_Bld_Tower_Main_01a" (glb).
static func _path(name: String) -> String:
	if name.begins_with("local/"):
		return "res://assets/%s.glb" % name
	if "/" in name:
		return "res://assets/%s.gltf" % name
	return DIR % name


## Forget the materials (a new world registers fresh ones with the LOD manager).
static func reset() -> void:
	_mats.clear()
	_meshes.clear()


## Share of the triangles kept at each LOD tier (Godot's mesh simplifier picks them).
const TIER_SHARE := [1.0, 0.3, 0.08]


## The model `name` as one mesh, its surfaces with our materials for `tier`; tiers 1 and
## 2 are simplified to TIER_SHARE of the triangles.
static func mesh(name: String, style: int, tier := 0) -> ArrayMesh:
	var key := "%s:%d:%d" % [name, style, tier]
	if _meshes.has(key):
		return _meshes[key]
	var scene: PackedScene = load(_path(name))
	var fallback: Texture2D = null   # packs whose models come without their texture (one shared atlas)
	var atlas := _path(name).get_base_dir().path_join("texture.png")
	if ResourceLoader.exists(atlas):
		fallback = load(atlas)
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
			if tex == null:
				tex = fallback
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
			if tier > 0 and tier < TIER_SHARE.size():
				arrays[Mesh.ARRAY_INDEX] = _simplified(arrays, TIER_SHARE[tier])
			elif tier == PROP_FAR:
				arrays[Mesh.ARRAY_INDEX] = _simplified(arrays, 0.25)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(out.get_surface_count() - 1, material(tex, cut, style, tier))
	root.free()
	_meshes[key] = out
	return out


## Index list of the simplest Godot-generated LOD that keeps at least `share` of the
## triangles (the vertices stay; unreferenced ones cost nothing to draw).
static func _simplified(arrays: Array, share: float) -> PackedInt32Array:
	var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(25.0, 60.0, [])
	var best := full
	for l in im.get_surface_lod_count(0):
		var idx := im.get_surface_lod_indices(0, l)
		if idx.size() >= full.size() * share and idx.size() < best.size():
			best = idx
	if best == full and im.get_surface_lod_count(0) > 0:
		best = im.get_surface_lod_indices(0, im.get_surface_lod_count(0) - 1)   # can't go that low: simplest there is
	return best


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


## The materials of a mesh's surfaces (to register their fade distances with Lod).
static func materials_of(mesh: Mesh) -> Array:
	var out := []
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m != null and not out.has(m):
			out.append(m)
	return out


## Triangles in a mesh, for reports.
static func triangles(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


## Instancers for a list of models, one picked at random per instance: [mesh, material
## or null] pairs.
class Mix:
	var meshes := []
	var mats := []
	var sets: Array[Instancer] = []

	func _init(chunk: float, list: Array) -> void:
		for m: Array in list:
			meshes.append(m[0])
			mats.append(m[1])
			sets.append(Instancer.new(chunk))

	func pick(rng: RandomNumberGenerator) -> Instancer:
		return sets[rng.randi() % sets.size()]

	func build(parent: Node3D, far: float, shadows: bool, lod: String) -> int:
		var n := 0
		for i in sets.size():
			if sets[i].count() > 0:
				n += sets[i].build(parent, meshes[i], mats[i], far, shadows, 0.0, lod)
		return n

	## Full meshes up to `switch` m, `far_meshes` (same order) beyond, to `far` m.
	func build_lod(parent: Node3D, far_meshes: Array, switch: float, far: float, shadows: bool, lod: String) -> int:
		var n := 0
		for i in sets.size():
			if sets[i].count() > 0:
				n += sets[i].build(parent, meshes[i], mats[i], switch, shadows, 0.0, lod)
				sets[i].build(parent, far_meshes[i], mats[i], far, false, switch, lod)
		return n


## A Mix of MegaKit models (props tier, their own materials).
static func mix(chunk: float, names: Array, style: int) -> Mix:
	var list := []
	for n: String in names:
		list.append([mesh(n, style, PROP), null])
	return Mix.new(chunk, list)
