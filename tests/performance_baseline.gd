extends Node

## P0 repeatable baseline. Run headless for CPU/startup figures, then with a
## real renderer for GPU, draw-call and video-memory figures.
const STARTUP_SAMPLES := 3
const PATH_SAMPLES := 128
const HEARING_LISTENERS := 128
const UI_SAMPLES := 12
const SAVE_SAMPLES := 3

var report := {
	"schema": 1,
	"engine": Engine.get_version_info(),
	"display_driver": DisplayServer.get_name(),
	"renderer_requested": ProjectSettings.get_setting("rendering/renderer/rendering_method", "default"),
	"samples": {},
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var startup_samples: Array[float] = []
	var navigation_samples: Array[float] = []
	var navigation_stages := {"nodes": [], "edges": [], "stairs": [], "total": []}
	for sample in STARTUP_SAMPLES:
		var game := await _create_game()
		startup_samples.append(float(game.startup_timings_ms.get("Game initialization total", 0.0)))
		navigation_samples.append(float(game.startup_timings_ms.get("Map + navigation", 0.0)))
		for stage: String in navigation_stages:
			(navigation_stages[stage] as Array).append(float(game.world_map.navigation_timings_ms.get(stage, 0.0)))
		await _free_game(game)
	report["samples"]["startup_total_ms"] = _summary(startup_samples)
	report["samples"]["map_navigation_ms"] = _summary(navigation_samples)
	var stage_summary := {}
	for stage: String in navigation_stages:
		stage_summary[stage] = _summary(navigation_stages[stage])
	report["samples"]["navigation_stages_ms"] = stage_summary

	var game := await _create_game()
	game.mouse_released = true
	game._sync_mouse_capture()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	report["samples"]["save_load_ms"] = await _save_load_sample(game)
	report["samples"]["path_query_ms"] = _path_sample(game)
	report["samples"]["hearing_fanout_ms"] = _hearing_sample(game)
	report["samples"]["inventory_rebuild_ms"] = _inventory_sample(game)
	await _render_sample(game)
	report["memory_static_bytes"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	report["video_memory_bytes"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	_print_report()
	await _free_game(game)
	get_tree().quit()


func _create_game() -> MVPGameRoot:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as MVPGameRoot
	add_child(game)
	# _ready constructs the world synchronously; two frames include the first
	# gameplay update and the initial render/streaming queue handoff.
	await get_tree().process_frame
	await get_tree().process_frame
	return game


func _free_game(game: MVPGameRoot) -> void:
	game.queue_free()
	await get_tree().process_frame


func _save_load_sample(game: MVPGameRoot) -> Dictionary:
	var path := OS.get_temp_dir().path_join("afterlight-p0-%d.save" % Time.get_ticks_usec())
	var values: Array[float] = []
	if not QuickSave.save_game(game, path):
		return {"error": "temporary save could not be written"}
	for sample in SAVE_SAMPLES:
		var started := Time.get_ticks_usec()
		var loaded := QuickSave.load_game(game, path)
		values.append(float(Time.get_ticks_usec() - started) / 1000.0)
		if not loaded:
			DirAccess.remove_absolute(path)
			return {"error": "temporary save could not be loaded"}
	DirAccess.remove_absolute(path)
	return _summary(values)


func _path_sample(game: MVPGameRoot) -> Dictionary:
	var routes := [
		{"from": game.world_map.definition.player_spawn, "from_floor": 0, "to": Vector2(14.5, 6.5), "to_floor": 2},
		{"from": Vector2(3.5, 3.5), "from_floor": 0, "to": Vector2(14.5, 3.5), "to_floor": 0},
		{"from": Vector2(14.5, 6.5), "from_floor": 2, "to": Vector2(14.5, 9.5), "to_floor": 0},
	]
	var values: Array[float] = []
	var paths_found := 0
	# Clear first so the first route records uncached work; subsequent calls still
	# report how the real local-navigation cache affects repeated requests.
	game.world_map._path_cache.clear()
	for index in PATH_SAMPLES:
		var route: Dictionary = routes[index % routes.size()]
		var started := Time.get_ticks_usec()
		var path: Array[Dictionary] = game.world_map.find_path(route["from"], route["from_floor"], route["to"], route["to_floor"])
		values.append(float(Time.get_ticks_usec() - started) / 1000.0)
		if not path.is_empty(): paths_found += 1
	var summary := _summary(values)
	summary["requests"] = PATH_SAMPLES
	summary["paths_found"] = paths_found
	summary["cache_hits"] = game.world_map.path_cache_hits
	return summary


func _hearing_sample(game: MVPGameRoot) -> Dictionary:
	var listeners: Array[ZombieActor] = []
	for index in HEARING_LISTENERS:
		var listener := ZombieActor.new()
		listener.world_map = game.world_map
		listener.logical_position = Vector2(2.5 + float(index % 16), 2.5 + float(index / 16))
		listener.floor_level = index % 3
		listeners.append(listener)
	var stimulus := NoiseStimulus.new(Vector2(12.5, 8.5), 28.0, "p0_baseline", 0, 1.0, GameTime.elapsed_game_seconds)
	var values: Array[float] = []
	var heard := 0
	for repeat in 20:
		var started := Time.get_ticks_usec()
		for listener in listeners:
			if not ActorHearing.sample(game.world_map, listener, stimulus, GameTime.elapsed_game_seconds).is_empty(): heard += 1
		values.append(float(Time.get_ticks_usec() - started) / 1000.0)
	for listener in listeners: listener.free()
	var summary := _summary(values)
	summary["listeners"] = HEARING_LISTENERS
	summary["events"] = values.size()
	summary["heard_total"] = heard
	return summary


func _inventory_sample(game: MVPGameRoot) -> Dictionary:
	var definition := ItemDefinition.new("p0_measurement_item", "P0 measurement item", Vector3(2, 2, 2), 0.01, [])
	for index in 256:
		game.inventory.loose.append(ItemStack.new(definition))
	game.inventory.revision += 1
	game.hud.details.show()
	game.hud.pack_panel.presentation.sides[0]["selected"] = "all_carried"
	game.hud.pack_panel.presentation.sides[1]["selected"] = "test_cabinet_0"
	var values: Array[float] = []
	for sample in UI_SAMPLES:
		game.inventory.revision += 1
		game.hud.pack_panel.last_signature = ""
		var started := Time.get_ticks_usec()
		game.hud.refresh(game)
		values.append(float(Time.get_ticks_usec() - started) / 1000.0)
	game.hud.details.hide()
	var summary := _summary(values)
	summary["items"] = 256
	summary["rebuilds"] = UI_SAMPLES
	return summary


func _render_sample(game: MVPGameRoot) -> void:
	var wall_ms: Array[float] = []
	var cpu_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	for frame in 120:
		var started := Time.get_ticks_usec()
		await get_tree().process_frame
		wall_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
		cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	var summary := _summary(wall_ms)
	summary["render_cpu_ms"] = _summary(cpu_ms)
	summary["render_gpu_ms"] = _summary(gpu_ms)
	summary["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	summary["objects"] = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	summary["visible_zombies"] = game.zombie_spawner.active_zombies.size()
	report["samples"]["idle_frame_ms"] = summary


func _summary(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var ordered := values.duplicate()
	ordered.sort()
	var p95_index := mini(ordered.size() - 1, int(ceil(ordered.size() * 0.95)) - 1)
	var total := 0.0
	for value in ordered: total += float(value)
	return {"count": ordered.size(), "p50": ordered[ordered.size() / 2], "p95": ordered[p95_index], "max": ordered.back(), "mean": total / ordered.size()}


func _print_report() -> void:
	print("[PerformanceBaseline] ", JSON.stringify(report))
