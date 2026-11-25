class_name Roads
extends RefCounted
## The road surface: a ribbon along the route with lighter wheel tracks and centre.

const EDGE := Color(0.66, 0.56, 0.40)
const TRACK := Color(0.74, 0.64, 0.47)
const CENTRE := Color(0.80, 0.71, 0.53)
const PLANK := Color(0.52, 0.38, 0.25)


## `bridge` (optional, one byte per route point) paints those points as wooden planks.
static func ribbon(route: Route, bridge := PackedByteArray()) -> ArrayMesh:
	var hw := Route.HALF_WIDTH
	var cols := [-hw, -hw * 0.45, 0.0, hw * 0.45, hw]
	var tints := [EDGE, TRACK, CENTRE, TRACK, EDGE]
	var b := MeshBuilder.new()
	var n := route.count()
	for m in n:
		var p := route.points[m]
		var t := route.tangent_index(m)
		var right := Vector3(-t.z, 0.0, t.x)
		var on_bridge := bridge.size() > 0 and bridge[m] != 0
		for c in cols.size():
			var off: float = cols[c]
			var drop := 0.0 if on_bridge else 0.03 * absf(off) / hw
			var col: Color = PLANK.lightened(0.08 * (m % 2)) if on_bridge else tints[c]
			b.add(p + right * off + Vector3(0.0, 0.02 - drop, 0.0), Vector3.UP, col)
	var w := cols.size()
	for m in n:
		var a := m * w
		var z := ((m + 1) % n) * w
		for c in w - 1:
			b.quad(a + c, a + c + 1, z + c + 1, z + c)
	return b.commit()
