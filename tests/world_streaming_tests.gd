class_name WorldStreamingTests
extends RefCounted


static func run(game: MVPGameRoot, check: Callable) -> void:
	var view := game.world_3d_view
	check.call(game.get_node_or_null("VisibilitySystem") == null and not QuickSave.snapshot(game).has("seen"),
		"runtime and new saves contain no player FOV or exploration history")
	var npc_position := game.npc.logical_position
	var npc_floor := game.npc.floor_level
	game.npc.logical_position = Vector2(32.5, 24.5)
	game.npc.floor_level = 0
	view._update_actors()
	var visual: Dictionary = view.actor_visuals.get(game.npc.get_instance_id(), {})
	check.call(not visual.is_empty() and (visual["root"] as Node3D).visible,
		"actor beyond the old vision radius is submitted without exploration or facing gates")
	game.npc.logical_position = npc_position
	game.npc.floor_level = npc_floor
	view._update_actors()
	var distant_marker := false
	for marker: Dictionary in view.interaction_markers:
		if game.player.logical_position.distance_to(marker["point"]["position"]) > 7.0 and marker["point"]["kind"] == "container":
			distant_marker = distant_marker or (marker["node"] as Node3D).visible
	check.call(distant_marker, "unexplored distant containers are rendered with normal depth occlusion")
	var builds := view.streamer.total_builds
	var yaw := view.view_rig.yaw
	view.view_rig.yaw += PI
	view._update_camera(0.0)
	view.streamer.advance()
	check.call(view.streamer.total_builds == builds and view.streamer.pending.is_empty(), "turning 180 degrees does not rebuild resident chunks")
	view.view_rig.yaw = yaw
	_test_large_map(game, check)


static func _test_large_map(game: MVPGameRoot, check: Callable) -> void:
	var map := WorldMap.new()
	map.definition = MapDefinition.new()
	map.width = 256
	map.height = 32
	var tree := MapDecorationDefinition.new()
	tree.position = Vector2(2, 2)
	map.definition.decorations.append(tree)
	var ground := FloorData.new(0)
	map.floors[0] = ground
	for y in range(32):
		for x in range(256): ground.tiles[Vector2i(x, y)] = WorldTileData.new("grass", true, 0.0)
	var upper := FloorData.new(1)
	upper.tiles[Vector2i(8, 8)] = WorldTileData.new("floor", true, 0.0)
	map.floors[1] = upper
	ground.wall_faces.append({"start": Vector2(0, 8), "end": Vector2(160, 8)})
	map.buildings["long"] = BuildingData.new("long", "Long roof", Rect2i(0, 0, 160, 16), "residential", 0.0)
	var builder := WorldChunkBuilder.new()
	builder.setup(map)
	var wall_length := 0.0
	var roofs := 0
	for data: Dictionary in builder.chunks.values():
		for wall: Dictionary in data["walls"]: wall_length += (wall["start"] as Vector2).distance_to(wall["end"])
		for box: Dictionary in data["boxes"]:
			if box["material"] == "roof": roofs += 1
	check.call(is_equal_approx(wall_length, 160.0) and roofs > 10,
		"long walls and roofs are split across chunks without midpoint ownership or duplicate wall length")
	check.call(WorldChunkBuilder.clip_segment(Vector2(16, 0), Vector2(16, 16), Rect2(0, 0, 16, 16)).is_empty()
		and not WorldChunkBuilder.clip_segment(Vector2(16, 0), Vector2(16, 16), Rect2(16, 0, 16, 16)).is_empty(),
		"wall on a chunk boundary has exactly one owner")
	var host := Node3D.new()
	game.add_child(host)
	var camera := Camera3D.new()
	camera.far = 16.0
	host.add_child(camera)
	camera.position = Vector3(8, 1.62, 8)
	var stream := WorldChunkStreamer.new()
	host.add_child(stream)
	stream.setup(builder, camera)
	check.call(stream.resident.size() < builder.chunks.size(), "large map loads a bounded neighbourhood rather than all geometry")
	var first_chunk: Node3D = stream.resident[Vector2i.ZERO]["node"]
	var mesh_count := first_chunk.get_child_count()
	check.call(mesh_count <= 6, "hundreds of tiles and walls share a handful of material batches")
	var ground_area := 0.0
	var grass := first_chunk.get_node("grass") as MeshInstance3D
	var arrays := grass.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in range(0, indices.size(), 3):
		var a := vertices[indices[index]]
		var b := vertices[indices[index + 1]]
		var c := vertices[indices[index + 2]]
		if is_zero_approx(a.y) and is_zero_approx(b.y) and is_zero_approx(c.y):
			ground_area += (b - a).cross(c - a).length() * 0.5
	check.call(is_equal_approx(ground_area, 256.0), "batching indexed tree meshes with grass preserves every ground triangle")
	var job := builder.begin_chunk(Vector2i.ZERO)
	var finished := builder.advance_chunk(job, 1)
	check.call(not finished and (job["root"] as Node3D).get_parent() == null,
		"a partial construction job stays outside the rendered scene")
	builder.advance_chunk(job, 0)
	var staged := job["root"] as Node3D
	check.call((staged.get_node("grass") as MeshInstance3D).mesh.surface_get_array_index_len(0) == grass.mesh.surface_get_array_index_len(0),
		"resuming construction preserves all geometry without duplicating batches")
	staged.free()
	var upper_visible := false
	for mesh: MeshInstance3D in first_chunk.get_children():
		if mesh.name == "indoor": upper_visible = mesh.get_aabb().position.y >= map.floor_height
	check.call(upper_visible, "upper floor geometry loads with the horizontal chunk without floor slicing")
	camera.position.x = 80.0
	stream.refresh(true)
	var pending_before := stream.pending.size()
	stream.advance()
	check.call(stream.last_build_count <= WorldChunkStreamer.MAX_BUILDS_PER_FRAME
		and stream.pending.size() >= pending_before - WorldChunkStreamer.MAX_BUILDS_PER_FRAME,
		"travel limits chunk construction work per frame")
	camera.position.x = 240.0
	stream.refresh(true)
	var requests_current := true
	for key: Vector2i in stream.pending: requests_current = requests_current and stream.desired.has(key)
	check.call(requests_current and not stream.resident.has(Vector2i.ZERO), "teleport cancels stale requests and evicts distant geometry")
	stream.flush_pending()
	check.call(stream.resident.size() <= stream.desired.size() + WorldChunkStreamer.MAX_CACHED_CHUNKS,
		"resident cache remains bounded after travel")
	var count := stream.total_builds
	stream.refresh(true)
	stream.flush_pending()
	check.call(stream.total_builds == count, "stationary refresh reuses all resident meshes")
	check.call(map.floors[0] == ground and ground.tiles.size() == 8192,
		"render eviction never unloads simulation terrain or changes map state")
	host.free()
	map.free()
