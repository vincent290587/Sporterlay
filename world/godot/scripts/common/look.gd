class_name Look
extends RefCounted
## Sky, ambient light, fog and sun. Each world passes the values it wants to change.

const DEFAULTS := {
	"sky_top": Color(0.36, 0.60, 0.90),
	"sky_horizon": Color(0.80, 0.89, 0.96),
	"sky_ground": Color(0.62, 0.72, 0.80),
	"sun_color": Color(1.0, 0.96, 0.88),
	"sun_sky_color": Color(1.0, 0.95, 0.82),
	"cloud_shade": Color(0.74, 0.80, 0.90),
	"sun_pitch": -38.0,
	"sun_yaw": -35.0,
	"sun_energy": 1.15,
	"ambient": Color(0.62, 0.70, 0.86),
	"ambient_energy": 0.55,
	"fog": Color(0.70, 0.80, 0.93),
	"fog_density": 0.00032,
	"saturation": 1.08,
}


static func apply(parent: Node3D, overrides := {}) -> DirectionalLight3D:
	var o := DEFAULTS.duplicate()
	o.merge(overrides, true)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("top_color", o.sky_top)
	sky_mat.set_shader_parameter("horizon_color", o.sky_horizon)
	sky_mat.set_shader_parameter("ground_color", o.sky_ground)
	sky_mat.set_shader_parameter("sun_color", o.sun_sky_color)
	sky_mat.set_shader_parameter("cloud_shade", o.cloud_shade)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = o.ambient
	env.ambient_light_energy = o.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = o.fog
	env.fog_density = o.fog_density
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = o.saturation
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(o.sun_pitch, o.sun_yaw, 0.0)
	sun.light_color = o.sun_color
	sun.light_energy = o.sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_blur = 1.5
	parent.add_child(sun)
	return sun
