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
	"sky_shader": "res://shaders/sky.gdshader",
	"sky_params": {},           # extra uniforms for the sky shader
	"fog_height": 0.0,          # with fog_height_density > 0: thicker fog below this height
	"fog_height_density": 0.0,
	"fog_aerial": 0.3,
	"glow_intensity": 0.4,
	"glow_bloom": 0.0,
	"shadow_distance": 400.0,
	"volumetric": {},           # volumetric fog settings (density, albedo, length...), off if empty
}


static func apply(parent: Node3D, overrides := {}) -> DirectionalLight3D:
	var o := DEFAULTS.duplicate()
	o.merge(overrides, true)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load(o.sky_shader)
	sky_mat.set_shader_parameter("top_color", o.sky_top)
	sky_mat.set_shader_parameter("horizon_color", o.sky_horizon)
	sky_mat.set_shader_parameter("ground_color", o.sky_ground)
	sky_mat.set_shader_parameter("sun_color", o.sun_sky_color)
	sky_mat.set_shader_parameter("cloud_shade", o.cloud_shade)
	for k: String in o.sky_params:
		sky_mat.set_shader_parameter(k, o.sky_params[k])
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
	env.fog_aerial_perspective = o.fog_aerial
	env.fog_height = o.fog_height
	env.fog_height_density = o.fog_height_density
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = o.glow_intensity
	env.glow_bloom = o.glow_bloom
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = o.saturation
	var vol: Dictionary = o.volumetric
	if not vol.is_empty():
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = vol.get("density", 0.0)
		env.volumetric_fog_albedo = vol.get("albedo", Color(0.8, 0.8, 0.9))
		env.volumetric_fog_emission = vol.get("emission", Color.BLACK)
		env.volumetric_fog_length = vol.get("length", 96.0)
		env.volumetric_fog_detail_spread = vol.get("spread", 2.0)
		env.volumetric_fog_ambient_inject = vol.get("ambient_inject", 0.0)
		env.volumetric_fog_sky_affect = 0.0
		env.volumetric_fog_temporal_reprojection_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(o.sun_pitch, o.sun_yaw, 0.0)
	sun.light_color = o.sun_color
	sun.light_energy = o.sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = o.shadow_distance
	sun.shadow_blur = 1.5
	parent.add_child(sun)
	return sun
