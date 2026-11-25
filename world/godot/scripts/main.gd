extends Node3D
## Sporterlay World: stylized rides driven by power from Sporterlay.
##
## Command line (after `--` when run from the editor binary):
##   --port=47810   UDP port Sporterlay sends power to
##   --world=valley which world: valley, riverlands
##   --seed=7       which variant of it to generate
##   --power=200    fixed power when Sporterlay isn't sending (testing)
##   --at=1200      start this many metres along the road
##   --shot=path.png [--frames=90]  save a screenshot and quit
##   --map=path.png  save a top-down biome map (worlds that have one)
##   --bench=60     ride for that many seconds with vsync off, print the frame rate, quit
##   --size=1920x1080  open in a window of that size
## Keys: Esc quit, H hide the text, F3 frame rate, F11 fullscreen, F2 next world,
## Up/Down manual power without Sporterlay.

var worlds := {"valley": ValleyWorld, "riverlands": RiverWorld}

var world_name := "valley"
var seed := 7
var world_node: Node3D
var link := PowerLink.new()
var rider := Rider.new()
var hud := Label.new()
var manual_power := 0.0
var args := {}
var show_fps := false
var _bench := 0.0
var _bench_frames := PackedFloat32Array()
var _bench_skip := 2.0   # seconds to settle (shader compiles) before measuring
var _shot := ""
var _shot_frames := 90
var _frame := 0


func _ready() -> void:
	args = _args()
	seed = int(args.get("seed", "7"))
	world_name = args.get("world", "valley")
	if not worlds.has(world_name):
		push_warning("unknown world %s" % world_name)
		world_name = "valley"
	manual_power = float(args.get("power", "0"))
	_shot = args.get("shot", "")
	_shot_frames = int(args.get("frames", "90"))
	if args.has("size"):
		var wh: PackedStringArray = str(args.size).split("x")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	_bench = float(args.get("bench", "0"))
	if _bench > 0.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		if manual_power <= 0.0:
			manual_power = 220.0

	link.port = int(args.get("port", "47810"))
	add_child(link)
	add_child(rider)
	_load_world(float(args.get("at", "0")))

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


## Builds the chosen world under a fresh node (the old one, if any, is freed).
func _load_world(at: float) -> void:
	if world_node:
		world_node.free()
	world_node = Node3D.new()
	world_node.name = "World"
	add_child(world_node)
	var t0 := Time.get_ticks_msec()
	var world: Variant = worlds[world_name].new()
	world.build(world_node, seed)
	if args.has("map") and world.has_method("save_map"):
		world.save_map(args.map)
	var route: Route = world.route
	print("%s %d: road %.2f km, built in %d ms" % [world_name, seed, route.length / 1000.0, Time.get_ticks_msec() - t0])
	rider.route = route
	rider.distance = at
	rider.speed = 0.0
	rider.reset()
	rider.advance(0.0, 0.0)


func _process(delta: float) -> void:
	var watts := link.power if link.connected else manual_power
	rider.advance(watts, delta)
	var src := "Sporterlay" if link.connected else (link.error if link.error != "" else "manual (Up/Down) - waiting for Sporterlay")
	var fps := "   %d fps" % Engine.get_frames_per_second() if show_fps else ""
	hud.text = "%s   %d W   %.1f km/h   %+.1f %%   %.2f km   [%s]" % [world_name.capitalize(), watts, rider.speed * 3.6, rider.grade, rider.odometer / 1000.0, src] + fps

	if _bench > 0.0:
		if _bench_skip > 0.0:
			_bench_skip -= delta
		else:
			_bench_frames.append(delta)
			_bench -= delta
			if _bench <= 0.0:
				_report_bench()

	if _shot != "":
		_frame += 1
		if _frame == _shot_frames:
			get_viewport().get_texture().get_image().save_png(_shot)
			print("saved ", _shot)
			get_tree().quit()


func _report_bench() -> void:
	var f := _bench_frames.duplicate()
	f.sort()
	var total := 0.0
	for d in f:
		total += d
	var n := f.size()
	var worst_1pc := f.slice(int(n * 0.99))
	var low := 0.0
	for d in worst_1pc:
		low += d
	low /= maxi(worst_1pc.size(), 1)
	var size := DisplayServer.window_get_size()
	print("bench %s: %dx%d, %d frames over %.0f s: average %.0f fps, 1%% low %.0f fps, worst frame %.1f ms, %.2f km ridden" % [
		world_name, size.x, size.y, n, total, n / total, 1.0 / low, f[n - 1] * 1000.0, rider.odometer / 1000.0])
	print("  video memory %.0f MB (textures %.0f, buffers %.0f), RAM %.0f MB, %d draw calls, %.1f M primitives in the last frame" % [
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6])
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
		KEY_F3:
			show_fps = not show_fps
		KEY_F2:
			var names := worlds.keys()
			world_name = names[(names.find(world_name) + 1) % names.size()]
			_load_world(0.0)
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
