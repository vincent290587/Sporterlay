extends Node3D
## Sporterlay World: a stylized valley ride driven by power from Sporterlay.
##
## Command line (after `--` when run from the editor binary):
##   --port=47810   UDP port Sporterlay sends power to
##   --seed=7       which world to generate
##   --power=200    fixed power when Sporterlay isn't sending (testing)
##   --at=1200      start this many metres along the road
##   --shot=path.png [--frames=90]  save a screenshot and quit
## Keys: Esc quit, H hide the text, F11 fullscreen, Up/Down manual power without Sporterlay.

var terrain := Terrain.new()
var route := Route.new()
var link := PowerLink.new()
var rider := Rider.new()
var hud := Label.new()
var manual_power := 0.0
var _shot := ""
var _shot_frames := 90
var _frame := 0


func _ready() -> void:
	var args := _args()
	var seed := int(args.get("seed", "7"))
	manual_power = float(args.get("power", "0"))
	_shot = args.get("shot", "")
	_shot_frames = int(args.get("frames", "90"))

	var t0 := Time.get_ticks_msec()
	terrain.setup(seed)
	route.build(seed, terrain)
	terrain.carve(route)
	_environment()
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	Scenery.build(world, terrain, route, seed)
	print("world %d: road %.2f km, built in %d ms" % [seed, route.length / 1000.0, Time.get_ticks_msec() - t0])

	link.port = int(args.get("port", "47810"))
	add_child(link)
	rider.route = route
	rider.distance = float(args.get("at", "0"))
	add_child(rider)
	rider.advance(0.0, 0.0)

	var layer := CanvasLayer.new()
	add_child(layer)
	var ls := LabelSettings.new()
	ls.font_size = 22
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.55)
	hud.label_settings = ls
	hud.position = Vector2(24, 0)
	hud.anchor_top = 1.0
	hud.anchor_bottom = 1.0
	hud.offset_top = -48
	layer.add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.86)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.80, 0.93)
	env.fog_density = 0.00032
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_blur = 1.5
	add_child(sun)


func _process(delta: float) -> void:
	var watts := link.power if link.connected else manual_power
	rider.advance(watts, delta)
	var src := "Sporterlay" if link.connected else (link.error if link.error != "" else "manual (Up/Down) - waiting for Sporterlay")
	hud.text = "%d W   %.1f km/h   %+.1f %%   %.2f km   [%s]" % [watts, rider.speed * 3.6, rider.grade, rider.odometer / 1000.0, src]

	if _shot != "":
		_frame += 1
		if _frame == _shot_frames:
			get_viewport().get_texture().get_image().save_png(_shot)
			print("saved ", _shot)
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_H:
			hud.visible = not hud.visible
		KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_UP:
			manual_power = minf(manual_power + 10.0, 1500.0)
		KEY_DOWN:
			manual_power = maxf(manual_power - 10.0, 0.0)


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out
