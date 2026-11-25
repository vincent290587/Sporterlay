class_name VillageKit
extends RefCounted
## Buildings assembled from Quaternius' Medieval Village MegaKit modules (assets/
## village, CC0) and dressed with the Fantasy Props MegaKit (assets/props): houses of
## 1-2 storeys in plaster or brick, a church with a bell tower, fences, carts,
## barrels. Every module is a MultiMesh instance, one draw per module type for the
## whole set.
##
## A building is laid out in its own frame (`Transform3D`, origin at its ground
## centre): x across the front, z back from it, the front at -z facing the street.
## The kit's walls are 2 m panels 3.12 m tall whose finished side faces -z; roofs are
## sized by footprint (W x L, ridge along z).

const STOREY := 3.12
const ROOFS := {4: [4, 6, 8], 6: [6, 8, 10], 8: [8, 10, 12]}   # widths -> lengths with a roof
const INTERIOR := Color(0.10, 0.07, 0.06)

var sets := {}                 # module name -> Instancer
var interiors := MeshBuilder.new()
var rng := RandomNumberGenerator.new()


static func available() -> bool:
	return MegaKit.has_pack("village") and MegaKit.has_pack("props")


## Loads every module of the imported packs now (at world load), so building a
## village while riding doesn't stall a frame reading files.
static func preload_all() -> void:
	for pack: String in ["village", "props", "local/raft"]:
		if not MegaKit.has_pack(pack):
			continue
		var ext := ".glb" if pack.begins_with("local/") else ".gltf"
		for f in DirAccess.get_files_at("res://assets/" + pack):
			if f.ends_with(ext):
				MegaKit.mesh(pack + "/" + f.get_basename(), MegaKit.SOLID, MegaKit.PROP)


func put(name: String, xf: Transform3D) -> void:
	if not sets.has(name):
		sets[name] = Instancer.new(64.0)
	(sets[name] as Instancer).put_basis(xf.origin, xf.basis, Color.WHITE)


## A module at `p` (building frame) turned by `yaw` about y.
func _at(frame: Transform3D, name: String, p: Vector3, yaw: float) -> void:
	put(name, frame * Transform3D(Basis(Vector3.UP, yaw), p))


## A wall run along one side: `count` 2 m panels, from `a` along `dir`, facing `out`.
func _wall_run(frame: Transform3D, a: Vector3, dir: Vector3, count: int, yaw: float, y: float, pick: Callable) -> void:
	for k in count:
		_at(frame, pick.call(k, count), a + dir * (k * 2.0 + 1.0) + Vector3.UP * y, yaw)


## A house of `w` x `l` m (w in 4/6/8, l from ROOFS[w]), `floors` storeys, "Plaster"
## or "UnevenBrick", its door in the middle of the front.
func house(frame: Transform3D, w: int, l: int, floors: int, material: String) -> void:
	var hw := w * 0.5
	var hl := l * 0.5
	var wall := "village/Wall_%s_" % material
	var windows := [wall + "Window_Wide_Round", wall + "Window_Thin_Round", wall + "Straight"]
	if material == "Plaster":
		windows.append("village/Wall_Plaster_WoodGrid")
	var pick_window := func(_k: int, _n: int) -> String:
		return windows[rng.randi() % windows.size()]
	for f in floors:
		var y := f * STOREY
		# front (-z): the door on the ground floor's middle panel
		var front := func(k: int, n: int) -> String:
			if f == 0 and k == n / 2:
				return wall + "Door_Round"
			return pick_window.call(k, n)
		_wall_run(frame, Vector3(-hw, 0, -hl), Vector3.RIGHT, w / 2, 0.0, y, front)
		_wall_run(frame, Vector3(hw, 0, hl), Vector3.LEFT, w / 2, PI, y, pick_window)
		_wall_run(frame, Vector3(-hw, 0, hl), Vector3.BACK * -1.0, l / 2, PI * 0.5, y, pick_window)
		_wall_run(frame, Vector3(hw, 0, -hl), Vector3.BACK, l / 2, -PI * 0.5, y, pick_window)
	var corner := "village/Corner_Exterior_%s" % ("Brick" if material == "UnevenBrick" else "Wood")
	for c: Vector2 in [Vector2(-hw, -hl), Vector2(hw, -hl), Vector2(hw, hl), Vector2(-hw, hl)]:
		for f in floors:
			_at(frame, corner, Vector3(c.x, f * STOREY, c.y), atan2(-c.x, -c.y) + PI * 0.25)
	var top := floors * STOREY
	_at(frame, "village/Roof_RoundTiles_%dx%d" % [w, l], Vector3(0, top, 0), 0.0)
	_at(frame, "village/Roof_Front_Brick%d" % w, Vector3(0, top, -hl), 0.0)
	_at(frame, "village/Roof_Front_Brick%d" % w, Vector3(0, top, hl), PI)
	if rng.randf() < 0.75:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		_at(frame, "village/Prop_Chimney" if rng.randf() < 0.5 else "village/Prop_Chimney2",
			Vector3(side * hw * 0.5, top + w * 0.25, rng.randf_range(-hl, hl) * 0.6), 0.0)
	# a lantern by the door
	_at(frame, "props/Lantern_Wall", Vector3(1.3, 1.6, -hl - 0.32), PI)
	_interior(frame, Vector3(-hw + 0.25, 0.05, -hl + 0.25), Vector3(hw - 0.25, top, hl - 0.25))


## A church: a brick nave and, at its front, a square bell tower with a spire.
func church(frame: Transform3D) -> void:
	house(frame, 6, 12, 2, "UnevenBrick")
	var t := frame * Transform3D(Basis(), Vector3(0, 0, -6.0 - 2.0))
	var pick := func(k: int, _n: int) -> String:
		return "village/Wall_UnevenBrick_Window_Thin_Round" if k == 0 else "village/Wall_UnevenBrick_Straight"
	for f in 4:
		var y := f * STOREY
		var front := func(k: int, n: int) -> String:
			return "village/Wall_UnevenBrick_Door_Round" if f == 0 and k == 1 else pick.call(k, n)
		_wall_run(t, Vector3(-2, 0, -2), Vector3.RIGHT, 2, 0.0, y, front)
		_wall_run(t, Vector3(2, 0, 2), Vector3.LEFT, 2, PI, y, pick)
		_wall_run(t, Vector3(-2, 0, 2), Vector3.FORWARD, 2, PI * 0.5, y, pick)
		_wall_run(t, Vector3(2, 0, -2), Vector3.BACK, 2, -PI * 0.5, y, pick)
	_at(t, "village/Roof_Tower_RoundTiles", Vector3(0, 4 * STOREY, 0), 0.0)
	_interior(t, Vector3(-1.75, 0.05, -1.75), Vector3(1.75, 4 * STOREY, 1.75))


## A dark box inside a building, so its windows and doorways look into rooms.
func _interior(frame: Transform3D, lo: Vector3, hi: Vector3) -> void:
	var c := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	for q: Array in [[0, 1, 5, 4], [2, 3, 7, 6], [3, 0, 4, 7], [1, 2, 6, 5], [4, 5, 6, 7]]:
		var a: Vector3 = frame * c[q[0]]
		var b: Vector3 = frame * c[q[1]]
		var d: Vector3 = frame * c[q[2]]
		# facing inwards: seen through the openings from outside
		var n := -((b - a).cross(d - a)).normalized()
		var i := interiors.add(a, n, INTERIOR)
		interiors.add(b, n, INTERIOR)
		interiors.add(d, n, INTERIOR)
		interiors.add(frame * c[q[3]], n, INTERIOR)
		interiors.quad(i, i + 1, i + 2, i + 3)


## A fence of `n` 2 m sections from `a` along `dir` (world space, on the ground).
func fence(a: Vector3, dir: Vector3, n: int, ground: Callable) -> void:
	var yaw := atan2(dir.x, dir.z) - PI * 0.5
	for k in n:
		var p := a + dir * (k * 2.06 + 1.03)
		p.y = ground.call(p.x, p.z)
		put("village/Prop_WoodenFence_Single", Transform3D(Basis(Vector3.UP, yaw), p))


func prop(name: String, p: Vector3, yaw: float) -> void:
	put(name, Transform3D(Basis(Vector3.UP, yaw), p))


## Builds every module set under `parent`; returns the instance count.
func build(parent: Node3D, far: float) -> int:
	var n := 0
	for name: String in sets:
		var mesh := MegaKit.mesh(name, MegaKit.SOLID, MegaKit.PROP)
		n += (sets[name] as Instancer).build(parent, mesh, null, far, true)
	if interiors.verts.size() > 0:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/toon_vcol.gdshader")
		var mi := MeshInstance3D.new()
		mi.mesh = interiors.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	return n
