class_name EndlessBiomes
extends RefCounted
## Which landscape the road is in: stretches of 6-10 km, one biome each, blending into
## the next over BLEND m. The order comes from the seed (never the same biome twice
## in a row); the ride always starts in the valley. Each biome has its own relief and
## ground colours (here) and its own sky and light (EndlessSky).
##
## Thread-safe after setup(): tiles call weights() and the height/colour functions
## from worker threads.

enum { VALLEY, AUTUMN, DUSK, CANYON }
const COUNT := 4
const NAMES := ["valley", "autumn", "dusk forest", "canyon"]
const BLEND := 1200.0
const REACH := 2.0e6            # segments are laid out this far ahead at setup

var starts := PackedFloat32Array()   # segment k starts at starts[k]...
var kinds := PackedInt32Array()      # ...and is biome kinds[k]

var hills := FastNoiseLite.new()
var peaks := FastNoiseLite.new()
var jagged := FastNoiseLite.new()
var mesas := FastNoiseLite.new()
var dunes := FastNoiseLite.new()
var tint := FastNoiseLite.new()


func setup(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 77
	var s := 0.0
	var prev := VALLEY
	starts.append(-1e9)
	kinds.append(VALLEY)
	s = rng.randf_range(5000.0, 8000.0)
	while s < REACH:
		var k := rng.randi() % COUNT
		while k == prev:
			k = rng.randi() % COUNT
		starts.append(s)
		kinds.append(k)
		prev = k
		s += rng.randf_range(6000.0, 10000.0)
	hills.seed = seed + 1
	hills.frequency = 0.0028
	hills.fractal_octaves = 3
	peaks.seed = seed + 2
	peaks.frequency = 0.0007
	peaks.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	peaks.fractal_octaves = 5
	jagged.seed = seed + 5
	jagged.frequency = 0.0011
	jagged.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	jagged.fractal_octaves = 5
	mesas.seed = seed + 6
	mesas.frequency = 0.0024
	mesas.fractal_octaves = 4
	dunes.seed = seed + 7
	dunes.frequency = 0.012
	dunes.fractal_octaves = 2
	tint.seed = seed + 4
	tint.frequency = 0.004
	tint.fractal_octaves = 3


func _segment(s: float) -> int:
	var lo := 0
	var hi := starts.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if starts[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


## How much of each biome there is at road distance `s` (sums to 1).
func weights(s: float) -> PackedFloat32Array:
	var w := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var k := _segment(s)
	var t := 1.0
	# blend with the previous segment just after a boundary, the next just before one
	if k > 0 and s - starts[k] < BLEND * 0.5:
		t = smoothstep(-BLEND * 0.5, BLEND * 0.5, s - starts[k])
		w[kinds[k - 1]] += 1.0 - t
	elif k + 1 < starts.size() and starts[k + 1] - s < BLEND * 0.5:
		var t2 := smoothstep(-BLEND * 0.5, BLEND * 0.5, s - starts[k + 1])
		w[kinds[k + 1]] += t2
		t = 1.0 - t2
	w[kinds[k]] += t
	return w


func name_at(s: float) -> String:
	return NAMES[kinds[_segment(s)]]


static func _terrace(t: float) -> float:
	return smoothstep(0.0, 0.05, t) * 0.55 + smoothstep(0.30, 0.35, t) * 0.28 + smoothstep(0.66, 0.70, t) * 0.17


## Relief added to the base height by biome `b`, `d` m from the road.
func relief(b: int, x: float, z: float, d: float) -> float:
	match b:
		VALLEY:
			return hills.get_noise_2d(x, z) * 22.0 * smoothstep(30.0, 220.0, d) \
				+ (120.0 + 520.0 * (peaks.get_noise_2d(x, z) * 0.5 + 0.5)) * smoothstep(350.0, 1300.0, d)
		AUTUMN:
			return hills.get_noise_2d(x, z) * 34.0 * smoothstep(25.0, 180.0, d) \
				+ (40.0 + 220.0 * (peaks.get_noise_2d(x * 1.3, z * 1.3) * 0.5 + 0.5)) * smoothstep(300.0, 1100.0, d)
		DUSK:
			return hills.get_noise_2d(x, z) * 30.0 * smoothstep(25.0, 200.0, d) \
				+ (160.0 + 900.0 * pow(jagged.get_noise_2d(x, z) * 0.5 + 0.5, 1.5)) * smoothstep(400.0, 1400.0, d)
		_:
			var m := mesas.get_noise_2d(x, z) * 0.5 + 0.5
			var mt := clampf((m - 0.52) / 0.22, 0.0, 1.0) * smoothstep(40.0, 150.0, d)
			return dunes.get_noise_2d(x, z) * 2.0 + 140.0 * _terrace(mt) \
				+ 260.0 * _terrace(clampf(peaks.get_noise_2d(x, z) * 0.9 + 0.5, 0.0, 1.0)) * smoothstep(900.0, 1800.0, d)


## Ground colour of biome `b` (sRGB); the alpha says how much canyon rock and sand
## detail the ground shader paints.
func color(b: int, x: float, z: float, h: float, ny: float) -> Color:
	var t := tint.get_noise_2d(x, z) * 0.5 + 0.5
	var t2 := tint.get_noise_2d(x * 3.1 + 500.0, z * 3.1)
	var steep := 1.0 - smoothstep(0.62, 0.8, ny)
	var c: Color
	match b:
		VALLEY:
			c = Color(0.30, 0.47, 0.20).lerp(Color(0.42, 0.58, 0.24), smoothstep(0.3, 0.72, t))
			c = c.lerp(Color(0.70, 0.66, 0.40), smoothstep(0.62, 0.82, t2) * 0.5)
			c = c.lerp(Color(0.52, 0.50, 0.46), steep)
			c = c.lerp(Color(0.93, 0.94, 0.97), smoothstep(300.0, 360.0, h + 60.0 * t) * smoothstep(0.55, 0.72, ny))
		AUTUMN:
			c = Color(0.55, 0.50, 0.26).lerp(Color(0.66, 0.58, 0.30), smoothstep(0.3, 0.72, t))
			c = c.lerp(Color(0.52, 0.30, 0.16), smoothstep(0.55, 0.8, t2) * 0.7)   # rust bracken
			c = c.lerp(Color(0.34, 0.40, 0.22), smoothstep(0.25, 0.0, t) * 0.6)
			c = c.lerp(Color(0.55, 0.50, 0.46), steep)
		DUSK:
			c = Color(0.15, 0.19, 0.12).lerp(Color(0.24, 0.30, 0.17), smoothstep(0.3, 0.75, t))
			c = c.lerp(Color(0.26, 0.21, 0.15), smoothstep(0.55, 0.8, t2) * 0.7)
			c = c.lerp(Color(0.30, 0.29, 0.33), steep)
			c = c.lerp(Color(0.52, 0.55, 0.64), smoothstep(560.0, 660.0, h + 120.0 * t) * smoothstep(0.45, 0.65, ny))
		_:
			c = Color(0.86, 0.66, 0.45).lerp(Color(0.92, 0.78, 0.58), smoothstep(0.35, 0.8, t))
			var band := fposmod(h * 0.11 + tint.get_noise_2d(x * 0.5, z * 0.5) * 1.5, 4.0)
			var rock := Color(0.70, 0.34, 0.20)
			if band >= 1.4 and band < 2.3:
				rock = Color(0.82, 0.48, 0.28)
			elif band >= 2.3 and band < 3.1:
				rock = Color(0.90, 0.76, 0.58)
			elif band >= 3.1:
				rock = Color(0.56, 0.38, 0.34)
			c = c.lerp(rock, 1.0 - smoothstep(0.5, 0.8, ny))
			c.a = 1.0
			return c
	c.a = 0.0
	return c
