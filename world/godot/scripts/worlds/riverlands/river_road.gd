class_name RiverRoad
extends RefCounted
## Plans the Riverlands road like a road engineer would: waypoints around the basin,
## joined by A* over the analysis grid. Climbing costs (grade squared), so does crossing
## water (bridges are expensive) and rough, high ground; the road ends up following
## valleys and crossing rivers where it must.

const WAYPOINTS := 7


static func plan(land: RiverLand, seed: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 31
	var na := RiverLand.NA
	var offset := rng.randf() * TAU
	var stops := PackedInt32Array()
	for k in WAYPOINTS:
		var a := offset + TAU * k / WAYPOINTS + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(520.0, 820.0)
		stops.append(_best_cell(land, Vector2(cos(a), sin(a)) * r))
	var cells := PackedInt32Array()
	for k in WAYPOINTS:
		var leg := _astar(land, stops[k], stops[(k + 1) % WAYPOINTS])
		if cells.size() > 0 and leg.size() > 0:
			leg = leg.slice(1)
		cells.append_array(leg)
	cells = _drop_spurs(cells)
	# again from half-way round, for a spur at the start/end waypoint
	var half := cells.size() / 2
	cells = _drop_spurs(cells.slice(half) + cells.slice(0, half))
	var raw := PackedVector2Array()
	for c in cells:
		raw.append(Vector2(-RiverLand.HALF + (c % na) * RiverLand.A_STEP, -RiverLand.HALF + (c / na) * RiverLand.A_STEP))
	for _i in 3:
		raw = Route.smooth_loop2(raw, 3)
	return raw


## Where the path comes back within 25 m of a cell it passed before, within under half
## the loop (out to a waypoint and back the same way, or a hairpin), cut the excursion.
static func _drop_spurs(cells: PackedInt32Array) -> PackedInt32Array:
	var na := RiverLand.NA
	var n := cells.size()
	var longest := int(n * 0.45)
	var out := PackedInt32Array()
	var i := 0
	while i < n:
		out.append(cells[i])
		var ci := cells[i] % na
		var cj := cells[i] / na
		var best := -1
		for j in range(i + 12, mini(i + longest, n)):
			var dx := cells[j] % na - ci
			var dz := cells[j] / na - cj
			if dx * dx + dz * dz <= 6:
				best = j
		i = best if best >= 0 else i + 1
	return out


## The gentlest dry cell near `p`.
static func _best_cell(land: RiverLand, p: Vector2) -> int:
	var na := RiverLand.NA
	var ci := int((p.x + RiverLand.HALF) / RiverLand.A_STEP)
	var cj := int((p.y + RiverLand.HALF) / RiverLand.A_STEP)
	var best := cj * na + ci
	var best_score := 1e30
	for j in range(cj - 6, cj + 7):
		for i in range(ci - 6, ci + 7):
			if i < 1 or j < 1 or i >= na - 1 or j >= na - 1:
				continue
			var c := j * na + i
			var score := land.slope[c] * 10.0 + land.alpine[c] * 5.0 + (20.0 if land.wl[c] != RiverLand.DRY else 0.0)
			score += exp(-land.dw[c] / 20.0) * 2.0
			if score < best_score:
				best_score = score
				best = c
	return best


static func _surface(land: RiverLand, c: int) -> float:
	return land.wl[c] if land.wl[c] != RiverLand.DRY else land.ha[c]


static func _astar(land: RiverLand, from: int, to: int) -> PackedInt32Array:
	var na := RiverLand.NA
	var n := na * na
	var step := RiverLand.A_STEP
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(1e30)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var ti := to % na
	var tj := to / na
	var heap := MinHeap.new()
	g[from] = 0.0
	heap.push(0.0, from)
	while not heap.is_empty():
		var c := heap.pop()
		if c == to:
			break
		if closed[c] != 0:
			continue
		closed[c] = 1
		var ci := c % na
		var cj := c / na
		var hc := _surface(land, c)
		for d in 8:
			var ni: int = ci + RiverLand.DX[d]
			var nj: int = cj + RiverLand.DZ[d]
			if ni < 2 or nj < 2 or ni >= na - 2 or nj >= na - 2:
				continue
			var nb := nj * na + ni
			if closed[nb] != 0:
				continue
			var seg_len := step * (1.4142 if d >= 4 else 1.0)
			var grade := absf(_surface(land, nb) - hc) / seg_len
			var cost := seg_len * (1.0 + 400.0 * grade * grade + 4.0 * land.slope[nb] + 3.0 * land.alpine[nb])
			if land.wl[nb] != RiverLand.DRY:
				cost += seg_len * 14.0
			var ng := g[c] + cost
			if ng < g[nb]:
				g[nb] = ng
				came[nb] = c
				var hx := float(ni - ti)
				var hz := float(nj - tj)
				heap.push(ng + sqrt(hx * hx + hz * hz) * step * 1.3, nb)
	var path := PackedInt32Array()
	var c := to
	while c >= 0:
		path.append(c)
		if c == from:
			break
		c = came[c]
	path.reverse()
	return path
