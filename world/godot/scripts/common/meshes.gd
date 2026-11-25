class_name Meshes
extends RefCounted
## Procedural low-poly props: grass clumps, round trees, conifers, rocks. Sizes in m.

const TRUNK := Color(0.44, 0.32, 0.22)
const LEAF_DARK := Color(0.20, 0.38, 0.17)
const LEAF_LIGHT := Color(0.42, 0.62, 0.24)
const NEEDLE_DARK := Color(0.14, 0.30, 0.20)
const NEEDLE_LIGHT := Color(0.26, 0.48, 0.28)


enum { GRASS_SHORT, GRASS_AVERAGE, GRASS_TALL, GRASS_FLOWERING }

## Grass types: blades per clump, clump radius, blade width and height ranges (m),
## segments per blade, random lean, sway strength (UV2.x, read by the grass shader)
## and a vertex tint (multiplied with the instance's ground colour).
const GRASS_TYPES := {
	GRASS_SHORT: {"blades": 14, "radius": 0.3, "width": Vector2(0.06, 0.1), "height": Vector2(0.15, 0.35),
		"segments": 2, "lean": 0.12, "sway": 0.45, "tint": Color(0.8, 0.9, 0.78)},
	GRASS_AVERAGE: {"blades": 9, "radius": 0.35, "width": Vector2(0.04, 0.07), "height": Vector2(0.35, 0.8),
		"segments": 2, "lean": 0.25, "sway": 1.0, "tint": Color(1.0, 1.0, 1.0)},
	GRASS_TALL: {"blades": 9, "radius": 0.4, "width": Vector2(0.018, 0.03), "height": Vector2(1.0, 1.6),
		"segments": 4, "lean": 0.28, "sway": 1.6, "tint": Color(1.0, 0.96, 0.78)},
	GRASS_FLOWERING: {"blades": 9, "radius": 0.4, "width": Vector2(0.018, 0.03), "height": Vector2(0.9, 1.4),
		"segments": 4, "lean": 0.22, "sway": 1.5, "tint": Color(1.0, 0.98, 0.84)},
}

## Flower heads on GRASS_FLOWERING: share of blades with a head, and head size. The
## colour isn't in the mesh: the grass shader paints head vertices (UV2.y > 0) with its
## `head_color`, so one model serves every colour (one material each).
const HEADS := {
	"plume": {"share": 0.85, "length": Vector2(0.16, 0.26), "width": Vector2(0.04, 0.065)},  # fluffy seed heads
	"haze": {"share": 1.0, "length": Vector2(0.24, 0.38), "width": Vector2(0.022, 0.035)},  # fine, airy plumes en masse
	"star": {"share": 0.6, "radius": Vector2(0.07, 0.11)},                                   # five-petal flowers
}


## The average clump, as before (nine blades, two segments each).
static func grass_clump(rng: RandomNumberGenerator, lean_all := Vector3.ZERO) -> ArrayMesh:
	return grass(rng, GRASS_AVERAGE, lean_all)


## A clump of grass of one of GRASS_TYPES. UV.y is 0 at the root and 1 at the tip (the
## grass shader bends by it); colour comes from the instance times the type's tint.
## `lean_all` tips every blade the same way (local +x), for grass combed by the wind or
## leaning to water; tall blades curve over more as they go up.
static func grass(rng: RandomNumberGenerator, kind: int, lean_all := Vector3.ZERO, head := "") -> ArrayMesh:
	var t: Dictionary = GRASS_TYPES[kind]
	var b := MeshBuilder.new()
	var segs: int = t.segments
	var width: Vector2 = t.width
	var height: Vector2 = t.height
	var tint: Color = t.tint
	var sway := Vector2(t.sway, 0.0)
	for _k in int(t.blades):
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * float(t.radius)
		var base := Vector3(cos(a) * r, -0.05, sin(a) * r)
		var facing := rng.randf() * TAU
		var side := Vector3(cos(facing), 0.0, sin(facing)) * rng.randf_range(width.x, width.y)
		var lean := Vector3(cos(facing + 1.57), 0.0, sin(facing + 1.57)) * rng.randf_range(-t.lean, t.lean) \
			+ lean_all * minf(height.y / 0.8, 1.3)
		var h := rng.randf_range(height.x, height.y)
		var prev_l := -1
		var prev_r := -1
		for sgi in segs + 1:
			var f := float(sgi) / segs
			# bends over more towards the tip: lean grows with the square of the height
			var p := base + lean * f * f + Vector3(0.0, h * f * (1.0 - 0.15 * f * f * lean.length()), 0.0)
			var uv := Vector2(0.5, f)
			if sgi == segs:
				var tip := b.add(p, Vector3.UP, tint, uv)
				b.uv2s.append(sway)
				b.tri_raw(prev_l, prev_r, tip)
				if head != "" and rng.randf() < float(HEADS[head].share):
					var below := base + lean * 0.5625 + Vector3(0.0, h * 0.75, 0.0)
					_head(b, rng, head, p, (p - below).normalized(), t.sway)
			else:
				var w := 1.0 - f * 0.65
				var l := b.add(p - side * w, Vector3.UP, tint, Vector2(0.0, f))
				var rr := b.add(p + side * w, Vector3.UP, tint, Vector2(1.0, f))
				b.uv2s.append(sway)
				b.uv2s.append(sway)
				if prev_l >= 0:
					b.tri_raw(prev_l, prev_r, rr)
					b.tri_raw(prev_l, rr, l)
				prev_l = l
				prev_r = rr
	return b.commit()


## A flower head at a blade's tip, going on along `dir`. Head vertices carry UV2.y = 1
## (2 for a star's centre); the shader colours them. UV.y stays near 1, so they sway.
static func _head(b: MeshBuilder, rng: RandomNumberGenerator, head: String, tip: Vector3, dir: Vector3, sway: float) -> void:
	var h: Dictionary = HEADS[head]
	var white := Color.WHITE
	if head == "star":
		var r := rng.randf_range(h.radius.x, h.radius.y)
		# faces mostly sideways (seen from eye height), a random way, tilted up a little
		var a0 := rng.randf() * TAU
		var up := (Vector3(cos(a0), 0.0, sin(a0)) + Vector3.UP * 0.6).normalized()
		var side := up.cross(Vector3.UP).normalized()
		var side2 := up.cross(side)
		var c := b.add(tip, Vector3.UP, white, Vector2(0.5, 1.0))
		b.uv2s.append(Vector2(sway, 2.0))
		var ring := PackedInt32Array()
		for k in 10:
			var a := TAU * k / 10
			var rr := r if k % 2 == 0 else r * 0.45   # five petals
			ring.append(b.add(tip + (side * cos(a) + side2 * sin(a)) * rr, Vector3.UP, white, Vector2(0.5, 1.0)))
			b.uv2s.append(Vector2(sway, 1.0))
		for k in 10:
			b.tri_raw(c, ring[k], ring[(k + 1) % 10])
		return
	# plume / haze: two crossed cards continuing the blade, widest in the middle
	var length := rng.randf_range(h.length.x, h.length.y)
	var width := rng.randf_range(h.width.x, h.width.y)
	var spin := rng.randf() * TAU
	for k in 2:
		var a := spin + PI * 0.5 * k
		var side := dir.cross(Vector3(cos(a), 0.0, sin(a))).normalized() * width
		var bend := Vector3(cos(spin), 0.0, sin(spin)) * length * 0.15   # plumes nod a little
		var pts := [tip, tip + dir * length * 0.45 + bend * 0.3, tip + dir * length + bend]
		var ws := [0.25, 1.0, 0.0]
		var row := []
		for q in 3:
			var pq: Vector3 = pts[q]
			var w: float = ws[q]
			var l := b.add(pq - side * w, Vector3.UP, white, Vector2(0.0, 1.0))
			var rr := b.add(pq + side * w, Vector3.UP, white, Vector2(1.0, 1.0))
			b.uv2s.append(Vector2(sway, 1.0))
			b.uv2s.append(Vector2(sway, 1.0))
			row.append([l, rr])
		for q in 2:
			b.tri_raw(row[q][0], row[q][1], row[q + 1][1])
			b.tri_raw(row[q][0], row[q + 1][1], row[q + 1][0])


## An ellipsoid with a jittered surface, shaded dark underneath and light on top.
static func blob(b: MeshBuilder, center: Vector3, radius: Vector3, rings: int, segs: int,
		rng: RandomNumberGenerator, jitter: float, bottom_col: Color, top_col: Color) -> void:
	var bottom := b.add(center - Vector3(0.0, radius.y, 0.0), Vector3.DOWN, bottom_col)
	for r in range(1, rings):
		var lat := PI * r / rings - PI / 2.0
		for s in segs:
			var lon := TAU * s / segs
			var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var p := center + dir * radius * (1.0 + rng.randf_range(-jitter, jitter))
			b.add(p, dir, bottom_col.lerp(top_col, smoothstep(-0.6, 0.7, dir.y)))
	var top := b.add(center + Vector3(0.0, radius.y, 0.0), Vector3.UP, top_col)
	var first := bottom + 1
	for s in segs:
		var s2 := (s + 1) % segs
		b.tri(bottom, first + s, first + s2)
		for r in rings - 2:
			var a := first + r * segs
			b.quad(a + s, a + s2, a + segs + s2, a + segs + s)
		var last := first + (rings - 2) * segs
		b.tri(top, last + s, last + s2)


static func trunk(b: MeshBuilder, height: float, r0: float, r1: float, segs: int) -> void:
	var start := b.verts.size()
	for s in segs:
		var a := TAU * s / segs
		var d := Vector3(cos(a), 0.0, sin(a))
		b.add(d * r0 + Vector3(0.0, -0.6, 0.0), d, TRUNK.darkened(0.15))
		b.add(d * r1 + Vector3(0.0, height, 0.0), d, TRUNK)
	for s in segs:
		var s2 := (s + 1) % segs
		b.quad(start + s * 2, start + s2 * 2, start + s2 * 2 + 1, start + s * 2 + 1)


## A round broadleaf tree about 10 m tall.
static func broadleaf(rng: RandomNumberGenerator, dark := LEAF_DARK, light := LEAF_LIGHT) -> ArrayMesh:
	var b := MeshBuilder.new()
	trunk(b, 5.5, 0.32, 0.2, 7)
	blob(b, Vector3(0.0, 6.4, 0.0), Vector3(3.2, 2.6, 3.2), 6, 10, rng, 0.08, dark, light)
	for _k in 3:
		var a := rng.randf() * TAU
		var c := Vector3(cos(a) * 1.8, rng.randf_range(7.0, 8.6), sin(a) * 1.8)
		var r := rng.randf_range(1.7, 2.3)
		blob(b, c, Vector3(r, r * 0.85, r), 5, 8, rng, 0.08, dark, light)
	return b.commit()


## Broadleaf for far away: one canopy blob, a tenth of the triangles.
static func broadleaf_far(rng: RandomNumberGenerator, dark := LEAF_DARK, light := LEAF_LIGHT) -> ArrayMesh:
	var b := MeshBuilder.new()
	trunk(b, 5.5, 0.32, 0.2, 4)
	blob(b, Vector3(0.0, 7.0, 0.0), Vector3(3.6, 3.2, 3.6), 4, 6, rng, 0.0, dark, light)
	return b.commit()


const PINE_LAYERS := [[2.2, 3.4, 7.0], [5.0, 2.7, 9.6], [7.6, 1.9, 12.6]]
const SPRUCE_LAYERS := [[1.5, 2.6, 6.0], [4.0, 2.2, 8.6], [6.6, 1.8, 11.2], [9.2, 1.3, 13.6], [11.6, 0.8, 16.0]]


## A conifer about 13 m tall: stacked cones (`layers`: [base y, radius, tip y]).
static func conifer(rng: RandomNumberGenerator, layers := PINE_LAYERS, dark := NEEDLE_DARK, light := NEEDLE_LIGHT) -> ArrayMesh:
	var b := MeshBuilder.new()
	trunk(b, 3.0, 0.3, 0.22, 6)
	for layer in layers:
		var y0: float = layer[0]
		var r: float = layer[1]
		var y1: float = layer[2]
		var segs := 9
		var start := b.verts.size()
		for s in segs:
			var a := TAU * s / segs + rng.randf_range(-0.1, 0.1)
			var d := Vector3(cos(a), 0.0, sin(a))
			var rr := r * rng.randf_range(0.9, 1.1)
			b.add(d * rr + Vector3(0.0, y0, 0.0), (d * (y1 - y0) + Vector3.UP * rr).normalized(), dark)
		var apex := b.add(Vector3(0.0, y1, 0.0), Vector3.UP, light)
		var under := b.add(Vector3(0.0, y0 + 0.4, 0.0), Vector3.DOWN, dark.darkened(0.3))
		for s in segs:
			var s2 := (s + 1) % segs
			b.tri(apex, start + s, start + s2)
		# underside: separate verts facing down
		var ring := PackedInt32Array()
		for s in segs:
			ring.append(b.add(b.verts[start + s], Vector3.DOWN, dark.darkened(0.3)))
		for s in segs:
			b.tri(under, ring[s], ring[(s + 1) % segs])
	return b.commit()


## A faceted boulder about 1 m across.
static func rock(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var grey := Color(0.60, 0.58, 0.54)
	blob(b, Vector3(0.0, 0.15, 0.0), Vector3(0.6, 0.42, 0.5), 5, 7, rng, 0.22, grey.darkened(0.25), grey.lightened(0.1))
	return b.faceted().commit()


## Conifer for far away: one cone per tree.
static func conifer_far(height: float, radius: float, dark := NEEDLE_DARK, light := NEEDLE_LIGHT) -> ArrayMesh:
	var b := MeshBuilder.new()
	trunk(b, 2.0, 0.3, 0.25, 4)
	var segs := 6
	var start := b.verts.size()
	for s in segs:
		var a := TAU * s / segs
		var d := Vector3(cos(a), 0.0, sin(a))
		b.add(d * radius + Vector3(0.0, 1.8, 0.0), (d * height + Vector3.UP * radius).normalized(), dark)
	var apex := b.add(Vector3(0.0, height, 0.0), Vector3.UP, light)
	for s in segs:
		b.tri(apex, start + s, start + (s + 1) % segs)
	return b.commit()


const BIRCH_BARK := Color(0.90, 0.88, 0.82)


## A slim birch about 11 m tall: white trunk, a tall loose crown.
static func birch(rng: RandomNumberGenerator, dark: Color, light: Color) -> ArrayMesh:
	var b := MeshBuilder.new()
	var start := b.verts.size()
	var segs := 6
	for s in segs:
		var a := TAU * s / segs
		var d := Vector3(cos(a), 0.0, sin(a))
		for k in 4:
			var y := -0.5 + k * 3.0
			var r := lerpf(0.2, 0.1, k / 3.0)
			var col := BIRCH_BARK.darkened(0.55) if (k + s) % 3 == 0 else BIRCH_BARK
			b.add(d * r + Vector3(0.0, y, 0.0), d, col)
	for s in segs:
		var s2 := (s + 1) % segs
		for k in 3:
			b.quad(start + s * 4 + k, start + s2 * 4 + k, start + s2 * 4 + k + 1, start + s * 4 + k + 1)
	for k in 4:
		var a := rng.randf() * TAU
		var c := Vector3(cos(a) * 0.9, 5.5 + k * 1.5, sin(a) * 0.9)
		var r := rng.randf_range(1.4, 1.9) * (1.0 - k * 0.12)
		blob(b, c, Vector3(r, r * 1.1, r), 5, 7, rng, 0.1, dark, light)
	return b.commit()


static func birch_far(rng: RandomNumberGenerator, dark: Color, light: Color) -> ArrayMesh:
	var b := MeshBuilder.new()
	trunk(b, 6.0, 0.2, 0.12, 4)
	blob(b, Vector3(0.0, 7.6, 0.0), Vector3(2.2, 3.4, 2.2), 4, 6, rng, 0.0, dark, light)
	return b.commit()


## A low bush about 1.5 m across, grey so the instance colour gives it its hue.
static func bush(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var dark := Color(0.5, 0.5, 0.5)
	var light := Color(1.0, 1.0, 1.0)
	for _k in 3:
		var a := rng.randf() * TAU
		var c := Vector3(cos(a) * 0.4, 0.45, sin(a) * 0.4)
		var r := rng.randf_range(0.5, 0.75)
		blob(b, c, Vector3(r, r * 0.8, r), 4, 7, rng, 0.12, dark, light)
	return b.commit()


## A fallen trunk, 6 m long, lying along x.
static func fallen_log(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var segs := 7
	var start := b.verts.size()
	for s in segs:
		var a := TAU * s / segs
		var d := Vector3(0.0, sin(a), cos(a))
		var r := 0.32 * rng.randf_range(0.9, 1.1)
		b.add(d * r + Vector3(-3.0, 0.25, 0.0), d, TRUNK.darkened(0.1))
		b.add(d * r * 0.85 + Vector3(3.0, 0.22, 0.0), d, TRUNK)
	for s in segs:
		var s2 := (s + 1) % segs
		b.quad(start + s * 2, start + s2 * 2, start + s2 * 2 + 1, start + s * 2 + 1)
	for end in [-1.0, 1.0]:
		var c := b.add(Vector3(3.0 * end, 0.24, 0.0), Vector3(end, 0.0, 0.0), Color(0.78, 0.66, 0.46))
		var ring := PackedInt32Array()
		for s in segs:
			var p := b.verts[start + s * 2 + (1 if end > 0.0 else 0)]
			ring.append(b.add(p, Vector3(end, 0.0, 0.0), Color(0.72, 0.60, 0.42)))
		for s in segs:
			b.tri(c, ring[s], ring[(s + 1) % segs])
	return b.commit()


static func stump(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	trunk(b, 0.6, 0.45, 0.38, 7)
	var c := b.add(Vector3(0.0, 0.6, 0.0), Vector3.UP, Color(0.78, 0.66, 0.46))
	var ring := PackedInt32Array()
	for s in 7:
		var a := TAU * s / 7
		ring.append(b.add(Vector3(cos(a) * 0.38, 0.6 + rng.randf_range(-0.05, 0.08), sin(a) * 0.38), Vector3.UP, Color(0.72, 0.60, 0.42)))
	for s in 7:
		b.tri(c, ring[s], ring[(s + 1) % 7])
	return b.commit()


## A cliff chunk about 1 m across, faceted, with sedimentary bands.
static func cliff(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var base := Color(0.62, 0.58, 0.52)
	blob(b, Vector3(0.0, 0.0, 0.0), Vector3(0.6, 0.5, 0.55), 6, 8, rng, 0.2, base, base)
	for i in b.verts.size():
		var band := sin(b.verts[i].y * 14.0 + 0.7) * 0.5 + 0.5
		b.colors[i] = base.darkened(0.25).lerp(base.lightened(0.12), band)
	return b.faceted().commit()


## Reeds: tall thin blades for the grass shader (colour from the instance).
static func reeds(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	for _k in 10:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.4
		var base := Vector3(cos(a) * r, -0.1, sin(a) * r)
		var facing := rng.randf() * TAU
		var side := Vector3(cos(facing), 0.0, sin(facing)) * 0.035
		var lean := Vector3(cos(facing + 1.57), 0.0, sin(facing + 1.57)) * rng.randf_range(-0.2, 0.2)
		var h := rng.randf_range(1.2, 1.9)
		var w := Color.WHITE
		var i0 := b.add(base - side, Vector3.UP, w, Vector2(0.0, 0.0))
		var i1 := b.add(base + side, Vector3.UP, w, Vector2(1.0, 0.0))
		var i2 := b.add(base + lean + Vector3(0.0, h, 0.0), Vector3.UP, w, Vector2(0.5, 1.0))
		b.tri_raw(i0, i1, i2)
		if rng.randf() < 0.3:   # a cattail head
			var top := base + lean * 0.8 + Vector3(0.0, h * 0.8, 0.0)
			var brown := Color(0.45, 0.30, 0.18)
			var j0 := b.add(top - side * 1.6, Vector3.UP, brown, Vector2(0.0, 0.9))
			var j1 := b.add(top + side * 1.6, Vector3.UP, brown, Vector2(1.0, 0.9))
			var j2 := b.add(top + side * 1.6 + Vector3(0.0, 0.22, 0.0), Vector3.UP, brown, Vector2(1.0, 0.95))
			var j3 := b.add(top - side * 1.6 + Vector3(0.0, 0.22, 0.0), Vector3.UP, brown, Vector2(0.0, 0.95))
			b.tri_raw(j0, j1, j2)
			b.tri_raw(j0, j2, j3)
	return b.commit()


## A few wildflowers for the grass shader: green stems, `petal` heads.
static func flowers(rng: RandomNumberGenerator, petal: Color) -> ArrayMesh:
	var b := MeshBuilder.new()
	var stem := Color(0.35, 0.55, 0.22)
	for _k in 6:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.3
		var base := Vector3(cos(a) * r, -0.05, sin(a) * r)
		var h := rng.randf_range(0.25, 0.5)
		var side := Vector3(0.012, 0.0, 0.0)
		var top := base + Vector3(0.0, h, 0.0)
		b.tri_raw(b.add(base - side, Vector3.UP, stem, Vector2(0.0, 0.0)),
			b.add(base + side, Vector3.UP, stem, Vector2(1.0, 0.0)),
			b.add(top, Vector3.UP, stem, Vector2(0.5, 0.9)))
		var s := rng.randf_range(0.05, 0.08)
		var spin := rng.randf() * TAU
		var c := b.add(top, Vector3.UP, petal.lightened(0.3), Vector2(0.5, 1.0))
		var ring := PackedInt32Array()
		for p in 5:
			var pa := spin + TAU * p / 5
			ring.append(b.add(top + Vector3(cos(pa) * s, 0.01, sin(pa) * s), Vector3.UP, petal, Vector2(0.5, 1.0)))
		for p in 5:
			b.tri_raw(c, ring[p], ring[(p + 1) % 5])
	return b.commit()


## A fern: fronds arching out from the middle, for the grass shader (it sways).
## White, so the instance colour gives it its autumn hue.
static func fern(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var fronds := 8
	for f in fronds:
		var a := TAU * f / fronds + rng.randf_range(-0.2, 0.2)
		var d := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-d.z, 0.0, d.x)
		var reach := rng.randf_range(0.6, 0.9)
		var pts := [Vector3.ZERO, d * reach * 0.35 + Vector3(0, 0.45, 0), d * reach * 0.75 + Vector3(0, 0.42, 0), d * reach + Vector3(0, 0.22, 0)]
		var widths := [0.03, 0.14, 0.1, 0.0]
		var prev_l := -1
		var prev_r := -1
		for k in pts.size():
			var p: Vector3 = pts[k]
			var w: float = widths[k]
			var shade := Color(0.75, 0.75, 0.75).lerp(Color.WHITE, k / 3.0)
			var uv := Vector2(0.5, k / 3.0)
			var l := b.add(p - side * w, Vector3.UP, shade, uv)
			var r := b.add(p + side * w, Vector3.UP, shade, uv)
			if prev_l >= 0:
				b.tri_raw(prev_l, prev_r, r)
				b.tri_raw(prev_l, r, l)
			prev_l = l
			prev_r = r
	return b.commit()


## A tapered limb from `a` to `c`.
static func limb(b: MeshBuilder, a: Vector3, c: Vector3, r0: float, r1: float, segs: int, col: Color) -> void:
	var dir := (c - a).normalized()
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	var start := b.verts.size()
	for s in segs:
		var ang := TAU * s / segs
		var o := side * cos(ang) + up * sin(ang)
		b.add(a + o * r0, o, col.darkened(0.1))
		b.add(c + o * r1, o, col)
	for s in segs:
		var s2 := (s + 1) % segs
		b.quad(start + s * 2, start + s2 * 2, start + s2 * 2 + 1, start + s * 2 + 1)


## A dead tree: a grey trunk with a few bare branches.
static func dead_tree(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var bark := Color(0.56, 0.52, 0.48)
	limb(b, Vector3(0, -0.5, 0), Vector3(0.2, 8.0, 0.1), 0.3, 0.08, 6, bark)
	for k in 5:
		var y := rng.randf_range(3.0, 7.0)
		var a := rng.randf() * TAU
		var base := Vector3(0.2 * y / 8.0, y, 0.1 * y / 8.0)
		var tip := base + Vector3(cos(a) * rng.randf_range(1.2, 2.4), rng.randf_range(0.8, 2.0), sin(a) * rng.randf_range(1.2, 2.4))
		limb(b, base, tip, 0.1, 0.03, 4, bark)
	return b.commit()


## Reeds all tipping towards local +x (towards the water once turned).
static func reeds_leaning(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	for _k in 10:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.4
		var base := Vector3(cos(a) * r, -0.1, sin(a) * r)
		var side := Vector3(0.0, 0.0, 0.035)
		var lean := Vector3(rng.randf_range(0.15, 0.45), 0.0, rng.randf_range(-0.12, 0.12))
		var h := rng.randf_range(1.2, 1.9)
		var w := Color.WHITE
		b.tri_raw(b.add(base - side, Vector3.UP, w, Vector2(0.0, 0.0)),
			b.add(base + side, Vector3.UP, w, Vector2(1.0, 0.0)),
			b.add(base + lean + Vector3(0.0, h, 0.0), Vector3.UP, w, Vector2(0.5, 1.0)))
		if rng.randf() < 0.3:
			var top := base + lean * 0.8 + Vector3(0.0, h * 0.8, 0.0)
			var brown := Color(0.45, 0.30, 0.18)
			var j0 := b.add(top - side * 1.6, Vector3.UP, brown, Vector2(0.0, 0.9))
			var j1 := b.add(top + side * 1.6, Vector3.UP, brown, Vector2(1.0, 0.9))
			var j2 := b.add(top + side * 1.6 + Vector3(0.0, 0.22, 0.0), Vector3.UP, brown, Vector2(1.0, 0.95))
			var j3 := b.add(top - side * 1.6 + Vector3(0.0, 0.22, 0.0), Vector3.UP, brown, Vector2(0.0, 0.95))
			b.tri_raw(j0, j1, j2)
			b.tri_raw(j0, j2, j3)
	return b.commit()


## A low mound of soil for the foot of a tree, 2.4 m across the base and 0.45 m high,
## its rim just under the ground. White: the instance colour is the ground's.
static func mound() -> ArrayMesh:
	var b := MeshBuilder.new()
	var segs := 12
	var top := b.add(Vector3(0.0, 0.45, 0.0), Vector3.UP, Color.WHITE)
	var mid := PackedInt32Array()
	var rim := PackedInt32Array()
	for s in segs:
		var a := TAU * s / segs
		var d := Vector3(cos(a), 0.0, sin(a))
		mid.append(b.add(d * 1.0 + Vector3(0.0, 0.3, 0.0), (d * 0.25 + Vector3.UP).normalized(), Color.WHITE))
		rim.append(b.add(d * 2.4 + Vector3(0.0, -0.1, 0.0), (d * 0.15 + Vector3.UP).normalized(), Color.WHITE))
	for s in segs:
		var s2 := (s + 1) % segs
		b.tri(top, mid[s], mid[s2])
		b.quad(mid[s], rim[s], rim[s2], mid[s2])
	return b.commit()
