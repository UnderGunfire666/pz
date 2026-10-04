extends Node

## Run with --path . res://tests/streaming_benchmark.tscn (real renderer).
## Captures stationary demo samples, then traverses a larger synthetic map.
var root: Window

func _ready() -> void:
	root = get_tree().root
	call_deferred("_run")


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as MVPGameRoot
	root.add_child(game)
	await get_tree().process_frame
	_freeze(game)
	game.mouse_released = true
	game._sync_mouse_capture()
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	for sample in [
		{"name": "street", "position": Vector2(8.5, 7.5), "facing": Vector2(-1, -0.5).normalized(), "pitch": 0.0},
		{"name": "interior", "position": Vector2(3.5, 3.5), "facing": Vector2.RIGHT, "pitch": 0.15},
		{"name": "dense", "position": Vector2(13.5, 9.5), "facing": Vector2.UP, "pitch": 0.0},
		{"name": "unexplored", "position": Vector2(35.5, 35.5), "facing": Vector2.UP, "pitch": -0.35}]:
		game.player.logical_position = sample["position"]
		game.player.facing_direction = sample["facing"]
		game.world_3d_view.refresh_after_load()
		game.world_3d_view.view_rig.pitch = sample["pitch"]
		game.world_3d_view._process(0.0)
		game.hud.refresh(game)
		game.hud.crosshair.show()
		for frame in range(10): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/streaming-%s.png" % sample["name"])
		await _measure(String(sample["name"]), game.world_3d_view.streamer)
	game.queue_free()
	await get_tree().process_frame
	await _traverse_large_map()
	get_tree().quit()


func _freeze(node: Node) -> void:
	node.set_process(false)
	for child in node.get_children(): _freeze(child)


func _measure(label: String, streamer: WorldChunkStreamer) -> void:
	var frame_ms: Array[float] = []
	var cpu_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	for frame in range(120):
		var started := Time.get_ticks_usec()
		await get_tree().process_frame
		frame_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
		cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	frame_ms.sort()
	cpu_ms.sort()
	gpu_ms.sort()
	print("[StreamingBenchmark] ", label, " wall_ms_p50=", frame_ms[60], " wall_ms_p95=", frame_ms[114],
		" render_cpu_ms_p95=", cpu_ms[114], " gpu_ms_p95=", gpu_ms[114],
		" draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		" objects=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		" memory_bytes=", Performance.get_monitor(Performance.MEMORY_STATIC), " chunks=", streamer.stats())


func _traverse_large_map() -> void:
	# Render-only fixture: deliberately no navigation/AI benchmark claims.
	var map := WorldMap.new()
	map.definition = MapDefinition.new()
	map.width = 512
	map.height = 64
	var ground := FloorData.new(0)
	map.floors[0] = ground
	for y in range(64):
		for x in range(512): ground.tiles[Vector2i(x, y)] = WorldTileData.new("grass", true, 0.0)
	for x in range(0, 512, 4):
		for y in range(8, 64, 8):
			ground.wall_faces.append({"start": Vector2(x, y), "end": Vector2(x + 3, y)})
			var prop := MapDecorationDefinition.new()
			prop.position = Vector2(x + 1, y + 2)
			map.definition.decorations.append(prop)
	var host := Node3D.new()
	root.add_child(host)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	host.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -34, 0)
	host.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.far = PlayerViewRig.VIEW_DISTANCE
	host.add_child(camera)
	camera.position = Vector3(8, 1.62, 4)
	camera.rotation.y = -PI * 0.5
	camera.make_current()
	var builder := WorldChunkBuilder.new()
	builder.setup(map)
	var stream := WorldChunkStreamer.new()
	host.add_child(stream)
	stream.setup(builder, camera)
	var timings: Array[float] = []
	var max_built := 0
	var max_resident := 0
	for frame in range(512):
		camera.position.x += 0.9 # Much faster than normal walking.
		var started := Time.get_ticks_usec()
		stream.advance()
		timings.append(float(Time.get_ticks_usec() - started) / 1000.0)
		max_built = maxi(max_built, stream.last_build_count)
		max_resident = maxi(max_resident, stream.resident.size())
		await get_tree().process_frame
	timings.sort()
	print("[StreamingTraversal] 512x64, 896 walls + 896 trees, tick_ms_p50=", timings[256],
		" tick_ms_p95=", timings[486], " tick_ms_max=", timings.back(),
		" max_built=", max_built, " max_resident=", max_resident, " indexed_chunks=", builder.chunks.size())
	while int(stream.stats()["pending"]) > 0:
		stream.advance()
		await get_tree().process_frame
	await _measure("synthetic_dense", stream)
	host.free()
	map.free()
