class_name WorldChunkStreamer
extends Node3D

## Render residency only. Collision, navigation and AI retain their own owners.
const CHUNK_SIZE := 16
const PRELOAD_MARGIN := 16.0
const RETAIN_MARGIN := 32.0
const MAX_CACHED_CHUNKS := 12
const MAX_BUILDS_PER_FRAME := 2
const BUILD_BUDGET_USEC := 2000
var builder: WorldChunkBuilder
var camera: Camera3D
var resident: Dictionary = {}
var desired: Dictionary = {}
var pending: Array[Vector2i] = []
var revision := 0
var last_build_count := 0
var last_build_usec := 0
var total_builds := 0
var _last_position := Vector2(INF, INF)
var _last_extent := -1.0
var _clock := 0
var _job: Dictionary = {}
var _job_key := Vector2i.ZERO


static func cell_at(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / CHUNK_SIZE), floori(position.y / CHUNK_SIZE))


static func bounds_at(key: Vector2i) -> Rect2:
	return Rect2(Vector2(key * CHUNK_SIZE), Vector2.ONE * CHUNK_SIZE)


static func distance_squared_to_chunk(position: Vector2, key: Vector2i) -> float:
	var bounds := bounds_at(key)
	return position.distance_squared_to(position.clamp(bounds.position, bounds.end))


func render_extent() -> float:
	# Far clip is a plane, not a sphere. Include its corners at wide aspect ratios
	# and every yaw/pitch, so turning around never requires a new load request.
	var size := camera.get_viewport().get_visible_rect().size
	var tangent := tan(deg_to_rad(camera.fov) * 0.5)
	var aspect := size.x / maxf(1.0, size.y)
	return camera.far * sqrt(1.0 + tangent * tangent * (1.0 + aspect * aspect))


func setup(p_builder: WorldChunkBuilder, p_camera: Camera3D) -> void:
	builder = p_builder
	camera = p_camera
	refresh(true)
	# Initial load / explicit load screens may build synchronously. Traversal
	# uses the bounded queue below and preloads before reaching the far plane.
	flush_pending()


func refresh(force: bool = false) -> void:
	var position := Vector2(camera.global_position.x, camera.global_position.z)
	var extent := render_extent()
	if not force and position.distance_squared_to(_last_position) < 16.0 and is_equal_approx(extent, _last_extent):
		return
	_last_position = position
	_last_extent = extent
	_clock += 1
	desired.clear()
	pending.clear() # Cancel obsolete requests after travel or teleport.
	var radius := extent + PRELOAD_MARGIN
	var first := cell_at(position - Vector2.ONE * radius)
	var last := cell_at(position + Vector2.ONE * radius)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var key := Vector2i(x, y)
			if not builder.chunks.has(key) or distance_squared_to_chunk(position, key) > radius * radius:
				continue
			desired[key] = true
			if resident.has(key):
				resident[key]["node"].show()
				resident[key]["used"] = _clock
			else:
				if _job.is_empty() or key != _job_key: pending.append(key)
	if not _job.is_empty() and not desired.has(_job_key):
		(_job["root"] as Node3D).free()
		_job.clear()
	pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return distance_squared_to_chunk(position, a) < distance_squared_to_chunk(position, b))
	var cached: Array[Vector2i] = []
	for key: Vector2i in resident:
		if not desired.has(key):
			resident[key]["node"].hide()
			cached.append(key)
	cached.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return resident[a]["used"] > resident[b]["used"])
	for index in cached.size():
		var key := cached[index]
		if index >= MAX_CACHED_CHUNKS or distance_squared_to_chunk(position, key) > pow(extent + RETAIN_MARGIN, 2):
			(resident[key]["node"] as Node3D).queue_free()
			resident.erase(key)
	revision += 1


func advance() -> void:
	var started := Time.get_ticks_usec()
	refresh()
	last_build_count = 0
	while (not pending.is_empty() or not _job.is_empty()) and last_build_count < MAX_BUILDS_PER_FRAME:
		var remaining := BUILD_BUDGET_USEC - (Time.get_ticks_usec() - started)
		if remaining <= 0: break
		if _job.is_empty():
			_job_key = pending.pop_front()
			_job = builder.begin_chunk(_job_key)
		if not builder.advance_chunk(_job, remaining): break
		_publish(_job_key, _job["root"])
		_job.clear()
		last_build_count += 1
	last_build_usec = Time.get_ticks_usec() - started


func flush_pending() -> void:
	if not _job.is_empty():
		builder.advance_chunk(_job, 0)
		_publish(_job_key, _job["root"])
		_job.clear()
	while not pending.is_empty(): _build_next()


func _build_next() -> void:
	var key: Vector2i = pending.pop_front()
	if resident.has(key) or not desired.has(key): return
	var chunk := builder.build_chunk(key)
	_publish(key, chunk)


func _publish(key: Vector2i, chunk: Node3D) -> void:
	# A door may have changed during the multi-frame job; publish current state.
	var barriers: Dictionary = chunk.get_meta("barriers", {})
	for id: String in barriers:
		for mesh: Node3D in barriers[id]: mesh.visible = not builder.world_map.is_barrier_open(id)
	add_child(chunk)
	resident[key] = {"node": chunk, "used": _clock}
	total_builds += 1
	revision += 1


func barrier_changed(id: String, open: bool) -> void:
	# Dynamic door/window meshes stay separate from static batches. Changing one
	# never rebuilds floors, neighbouring walls, or an entire building.
	for key: Vector2i in builder.barrier_chunks.get(id, []):
		if not resident.has(key): continue
		var chunk: Node3D = resident[key]["node"]
		for mesh: Node3D in chunk.get_meta("barriers", {}).get(id, []):
			mesh.visible = not open


func stats() -> Dictionary:
	return {"resident": resident.size(), "desired": desired.size(), "pending": pending.size() + int(not _job.is_empty()),
		"built_this_frame": last_build_count, "build_usec": last_build_usec, "total_builds": total_builds}


func _exit_tree() -> void:
	if not _job.is_empty():
		(_job["root"] as Node3D).free()
		_job.clear()
