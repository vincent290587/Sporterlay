class_name GiantLand
extends RefCounted
## A flooded giant world: most of the ground is below the water line, leaving
## islands and a ring of mountains. Giant trees (10x normal) stand on the islands.
## The water is a plane at WATER; the road is a wooden boardwalk above it.

const HALF := 3600.0        # height field covers -HALF..HALF
const STEP := 8.0
const N := 901
const FAR := 11500.0        # skirt reaches this radius (camera far is 12 km)
const RING := 3000.0        # mountains start rising here
const SKIRT_LEVELS := 32
const WATER := 2.0          # water surface (m)

const GREEN_DEEP := Color(0.14, 0.34, 0.18)
const GREEN_LIGHT := Color(0.38, 0.60, 0.30)
const SAND := Color(0.74, 0.65, 0.44)
const ROCK := Color(0.48, 0.45, 0.42)
const ROCK_HIGH := Color(0.40, 0.41, 0.45)
const SEABED := Color(0.20, 0.24, 0.20)
const SNOW := Color(0.92, 0.94, 0.98)

var islands := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var ridges := FastNoiseLite.new()
var tint := FastNoiseLite.new()
var grid := PackedFloat32Array()   # heights at the mesh's grid points, filled by build_mesh

func setup(seed: int) -> void:
	islands.seed = seed
	islands.frequency = 0.0032
	islands.fractal_octaves = 4
	detail.seed = seed + 1
	detail.frequency = 0.016
	detail.fractal_octaves = 2
	ridges.seed = seed + 2
	ridges.frequency = 0.0008
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 5
	tint.seed = seed + 3
	tint.frequency = 0.006
	tint.fractal_octaves = 3

## Height before the road is laid over it.
func natural(x: float, z: float) -> float:
	var big := islands.get_noise_2d(x, z) * 0.5 + 0.5
	var small := detail.get_noise_2d(x, z) * 0.5 + 0.5
	var h := -16.0 + 32.0 * big + 4.0 * small
	var r := Vector2(x, z).length()
	var m := smoothstep(RING, RING + 1800.0, r)
	h += m * (170.0 + 560.0 * (ridges.get_noise_2d(x, z) * 0.5 + 0.5))
	return h

## The drawn ground's height at (x, z): the mesh's triangle there, which can sit up to
## ~0.5 m off `natural` between grid points (plants use this so they don't float).
## Exact once `build_mesh` has cached the grid; `natural` before that.
func drawn(x: float, z: float) -> float:
	var fx := (x + HALF) / STEP
	var fz := (z + HALF) / STEP
	var i := floori(fx)
	var j := floori(fz)
	if grid.is_empty() or i < 0 or j < 0 or i >= N - 1 or j >= N - 1:
		return natural(x, z)
	var u := fx - i
	var v := fz - j
	var k := j * N + i
	if u + v <= 1.0:   # triangle k, k+1, k+N
		return grid[k] + (grid[k + 1] - grid[k]) * u + (grid[k + N] - grid[k]) * v
	return grid[k + N + 1] + (grid[k + N] - grid[k + N + 1]) * (1.0 - u) + (grid[k + 1] - grid[k + N + 1]) * (1.0 - v)

func color_at(x: float, z: float, h: float, ny: float) -> Color:
	var t := tint.get_noise_2d(x, z) * 0.5 + 0.5
	var c := GREEN_DEEP.lerp(GREEN_LIGHT, smoothstep(0.25, 0.75, t))
	c = c.lerp(SAND, 1.0 - smoothstep(WATER + 0.2, WATER + 2.2, h))
	c = c.lerp(ROCK, smoothstep(20.0, 55.0, h) * smoothstep(0.62, 0.78, ny))
	c = c.lerp(ROCK_HIGH, smoothstep(140.0, 360.0, h))
	var under := 1.0 - smoothstep(WATER - 1.6, WATER + 0.5, h)
	c = c.lerp(SEABED, under * 0.85)
	c = c.lerp(SNOW, smoothstep(300.0, 380.0, h) * smoothstep(0.55, 0.72, ny))
	return c

func _grid_normal(i: int, j: int) -> Vector3:
	var x := -HALF + i * STEP
	var z := -HALF + j * STEP
	var e := STEP
	return Vector3(natural(x - e, z) - natural(x + e, z), 2.0 * e,
		natural(x, z - e) - natural(x, z + e)).normalized()

func build_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	grid.resize(N * N)
	for j in N:
		var z := -HALF + j * STEP
		for i in N:
			var x := -HALF + i * STEP
			var h := natural(x, z)
			grid[j * N + i] = h
			var n := _grid_normal(i, j)
			b.add(Vector3(x, h, z), n, color_at(x, z, h, n.y))
	for j in N - 1:
		for i in N - 1:
			var k := j * N + i
			b.tri(k, k + 1, k + N)
			b.tri(k + 1, k + N + 1, k + N)

	# skirt: rays from the height field's edge out to FAR, sharing the edge vertices
	var prev := PackedInt32Array()
	for i in N - 1:
		prev.append(i)
	for j in N - 1:
		prev.append(j * N + N - 1)
	for i in range(N - 1, 0, -1):
		prev.append((N - 1) * N + i)
	for j in range(N - 1, 0, -1):
		prev.append(j * N)
	var edge := prev.duplicate()
	var p_count := edge.size()
	for l in range(1, SKIRT_LEVELS + 1):
		var t := pow(float(l) / SKIRT_LEVELS, 2.0)
		var row := PackedInt32Array()
		for a in p_count:
			var inner := b.verts[edge[a]]
			var dir := Vector2(inner.x, inner.z)
			var r0 := dir.length()
			var r := lerpf(r0, FAR, t)
			var x := dir.x / r0 * r
			var z := dir.y / r0 * r
			var h := natural(x, z)
			var e := maxf(STEP, r * 0.004)
			var n := Vector3(natural(x - e, z) - natural(x + e, z), 2.0 * e,
				natural(x, z - e) - natural(x, z + e)).normalized()
			row.append(b.add(Vector3(x, h, z), n, color_at(x, z, h, n.y)))
		for a in p_count:
			var a2 := (a + 1) % p_count
			b.tri(prev[a], prev[a2], row[a])
			b.tri(prev[a2], row[a2], row[a])
		prev = row
	return b.commit()
