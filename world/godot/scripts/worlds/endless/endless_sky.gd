class_name EndlessSky
extends Node3D
## The endless world's sky, sun (or moon), ambient light and fog, blended every frame
## from the biomes' looks by where the rider is on the road (EndlessBiomes.weights).

## Per biome: sky top/horizon/ground, light colour/energy/pitch/yaw, sun-in-sky
## colour, cloud shade, ambient colour/energy, fog colour/density, saturation, night.
const LOOKS := [
	{"top": Color(0.36, 0.60, 0.90), "horizon": Color(0.80, 0.89, 0.96), "ground": Color(0.62, 0.72, 0.80),
	 "light": Color(1.0, 0.96, 0.88), "energy": 1.15, "pitch": -38.0, "yaw": -35.0, "sun_sky": Color(1.0, 0.95, 0.82),
	 "cloud": Color(0.74, 0.80, 0.90), "ambient": Color(0.62, 0.70, 0.86), "ambient_energy": 0.55,
	 "fog": Color(0.70, 0.80, 0.93), "fog_density": 0.00032, "saturation": 1.08, "night": 0.0},
	{"top": Color(0.40, 0.58, 0.86), "horizon": Color(0.93, 0.87, 0.78), "ground": Color(0.75, 0.70, 0.66),
	 "light": Color(1.0, 0.90, 0.74), "energy": 1.2, "pitch": -28.0, "yaw": -55.0, "sun_sky": Color(1.0, 0.86, 0.62),
	 "cloud": Color(0.80, 0.74, 0.76), "ambient": Color(0.66, 0.66, 0.80), "ambient_energy": 0.55,
	 "fog": Color(0.88, 0.82, 0.76), "fog_density": 0.00036, "saturation": 1.1, "night": 0.0},
	{"top": Color(0.012, 0.016, 0.045), "horizon": Color(0.07, 0.07, 0.13), "ground": Color(0.03, 0.03, 0.05),
	 "light": Color(0.58, 0.66, 0.92), "energy": 0.5, "pitch": -21.0, "yaw": 95.0, "sun_sky": Color(0.95, 0.93, 0.85),
	 "cloud": Color(0.10, 0.10, 0.14), "ambient": Color(0.16, 0.18, 0.32), "ambient_energy": 0.45,
	 "fog": Color(0.045, 0.05, 0.09), "fog_density": 0.0015, "saturation": 0.85, "night": 1.0},
	{"top": Color(0.33, 0.50, 0.78), "horizon": Color(0.99, 0.80, 0.56), "ground": Color(0.80, 0.62, 0.46),
	 "light": Color(1.0, 0.74, 0.46), "energy": 1.45, "pitch": -24.0, "yaw": 70.0, "sun_sky": Color(1.0, 0.70, 0.38),
	 "cloud": Color(0.92, 0.62, 0.50), "ambient": Color(0.52, 0.52, 0.70), "ambient_energy": 0.5,
	 "fog": Color(0.96, 0.76, 0.56), "fog_density": 0.00032, "saturation": 1.12, "night": 0.0},
]

var biomes: EndlessBiomes
var rider: Rider
var env := Environment.new()
var sun := DirectionalLight3D.new()
var sky_mat := ShaderMaterial.new()


func _ready() -> void:
	sky_mat.shader = load("res://shaders/journey_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 350.0
	sun.shadow_blur = 1.5
	add_child(sun)
	update(0.0)


func _process(_delta: float) -> void:
	if rider != null:
		update(rider.distance)


func _dir(pitch: float, yaw: float) -> Vector3:
	return Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)) * Vector3.FORWARD


func update(s: float) -> void:
	var w := biomes.weights(s)
	var v := {}
	var dir := Vector3.ZERO
	for b in EndlessBiomes.COUNT:
		if w[b] <= 0.0:
			continue
		var look: Dictionary = LOOKS[b]
		for key: String in look:
			if key == "pitch" or key == "yaw":
				continue
			v[key] = look[key] * w[b] + v.get(key, look[key] * 0.0)
		dir += _dir(look.pitch, look.yaw) * w[b]
	dir = dir.normalized()
	sun.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3.ZERO)
	sun.light_color = v.light
	sun.light_energy = v.energy
	sky_mat.set_shader_parameter("top_color", v.top)
	sky_mat.set_shader_parameter("horizon_color", v.horizon)
	sky_mat.set_shader_parameter("ground_color", v.ground)
	sky_mat.set_shader_parameter("sun_color", v.sun_sky)
	sky_mat.set_shader_parameter("moon_color", v.sun_sky)
	sky_mat.set_shader_parameter("cloud_shade", v.cloud)
	sky_mat.set_shader_parameter("night", v.night)
	sky_mat.set_shader_parameter("glow_dir", Vector3(-dir.z, 0.0, dir.x))
	env.ambient_light_color = v.ambient
	env.ambient_light_energy = v.ambient_energy
	env.fog_light_color = v.fog
	env.fog_density = v.fog_density
	env.adjustment_saturation = v.saturation
	env.glow_intensity = lerpf(0.4, 0.8, v.night)
