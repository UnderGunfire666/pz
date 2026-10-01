class_name World3DView
extends Node3D

## The world owns floors, wall faces and stair traversal. This node only draws them.
const WALL_HEIGHT := 2.7
const WALL_THICKNESS := 0.12
const CAMERA_PITCH := deg_to_rad(55.0)
const CAMERA_DISTANCE_MIN := 9.0
const CAMERA_DISTANCE_MAX := 32.0
# Exploration is persistent and benefits from a crisp mask. The transient FOV
# mask is filtered by the shader, so it can be smaller without reintroducing
# tile-shaped vision edges. This cuts the per-refresh clear/upload cost to 25%.
const FOG_PIXELS_PER_TILE := 12
const FOG_VISIBILITY_PIXELS_PER_TILE := 6
const ENABLE_DYNAMIC_SHADOWS := false
const STREAM_CHUNK_SIZE := 8
const STREAM_CHUNK_RADIUS := 2
const MAX_CACHED_STREAM_CHUNKS := 48
const EXPLORATION_FOG_SHADER = preload("res://shaders/exploration_fog.gdshader")

var world_map: WorldMap
var player: PlayerController
var actor_layer: Node2D
var visibility: VisibilitySystem
var interactions: InteractionSystem
var camera: Camera3D
var camera_yaw := PI * 0.25
var camera_distance := 19.0
var structure_parts: Array[Dictionary] = []
signal player_building_changed(previous_id: String, current_id: String)
signal player_display_floor_changed(floor_index: int)

var building_controllers: Dictionary = {}
var occlusion_system := BuildingOcclusionSystem.new()
var small_occluders: Array[SmallOccluder] = []
var _active_building_id := ""
var _display_floor := -1
var _last_visibility_context: Array = []
var _region_revision := -1
var _visible_content_regions: Array[AABB] = []
var interaction_markers: Array[Dictionary] = []
var _last_marker_visibility_revision := -1
var actor_visuals: Dictionary = {}
var _actor_visibility_cache: Dictionary = {}
var fog_overlays: Dictionary = {}
var fog_masks: Dictionary = {}
var _floor_openings: Dictionary = {}
var _last_fog_revision := -1
var _pending_exploration: Dictionary = {}
var _reset_exploration := true
var _environment: Environment
var _sun: DirectionalLight3D
var _last_lighting_daylight := -1.0
var _camera_height := 0.0
var _streamed_floor_chunks: Dictionary = {}
var _empty_stream_chunks: Dictionary = {}
var _stream_chunk_clock := 0
var _stream_center := Vector2i(999999, 999999)
var _stream_radius := -1
var _stream_floor := -999
var _building_controllers_ready := false
var _floor_material := _material(Color("393a34"))
var _wall_material := _material(Color("686057"))
var _grass_material := _material(Color("49694b"))
var _soil_material := _material(Color("785f46"))
var _water_material := _material(Color("315b78"))
var _road_material := _material(Color("55595b"))
var _indoor_material := _material(Color("89775e"))
var _stair_material := _material(Color("a58b65"))
var _roof_material := _material(Color("414c52"))
var _door_material := _material(Color("936d43"))
var _player_material := _material(Color("d8e7f3"))
var _player_accent_material := _material(Color("416a92"))
var _zombie_material := _material(Color("a54646"))
var _zombie_flash_material := _material(Color("f06a58"))
var _npc_material := _material(Color("76a878"))
var _health_back_material := _material(Color("261c1a"))
var _health_fill_material := _material(Color("ed655c"))
var _swing_material := _material(Color(1.0, 0.86, 0.53, 0.72), true)


func setup(
		p_world_map: WorldMap,
		p_player: PlayerController,
		p_actor_layer: Node2D,
		p_visibility: VisibilitySystem,
		p_interactions: InteractionSystem
	) -> void:
	world_map = p_world_map
	player = p_player
	actor_layer = p_actor_layer
	visibility = p_visibility
	visibility.tile_explored.connect(func(key: Vector3i) -> void: _pending_exploration[key] = true)
	visibility.exploration_restored.connect(func() -> void:
		_reset_exploration = true
		_last_fog_revision = -1)
	interactions = p_interactions
	_build_environment()
	_build_map()
	_build_interaction_markers()
	interactions.points_changed.connect(_refresh_interaction_markers)
	_build_camera()
	_build_visibility_controllers()
	_build_authored_occluders()
	for controller: BuildingVisibilityController in building_controllers.values():
		occlusion_system.register_zone(OcclusionZone.new(OcclusionZone.node_bounds(controller), controller))
	for prop in small_occluders:
		occlusion_system.register_zone(OcclusionZone.new(OcclusionZone.node_bounds(prop), prop))
	_update_structure_visibility()
	player.world_view = self


func _process(delta: float) -> void:
	if player == null:
		return
	_update_camera(delta)
	_refresh_streamed_floor_chunks()
	# Normal gameplay has already refreshed FOV from MVPGameRoot. A zero-delta
	# direct call is used by deterministic preview/tests and must remain a fully
	# self-contained presentation update.
	_update_structure_visibility(delta <= 0.0)
	_update_wall_fades(delta)
	_update_lighting()
	_update_fog()
	_update_interaction_markers()
	_update_actors()


func _update_wall_fades(delta: float) -> void:
	for controller: BuildingVisibilityController in building_controllers.values():
		for floor_node: BuildingFloor in controller.floors.values():
			for wall: OccludableWall in floor_node.walls:
				wall.advance_fade(delta)


func orbit_camera(mouse_delta: Vector2) -> void:
	camera_yaw = wrapf(camera_yaw - mouse_delta.x * 0.006, -PI, PI)
	_last_visibility_context = []


func input_to_logical(screen_input: Vector2) -> Vector2:
	var camera_right := Vector2(cos(camera_yaw), -sin(camera_yaw))
	var screen_down := Vector2(sin(camera_yaw), cos(camera_yaw))
	return camera_right * screen_input.x + screen_down * screen_input.y


func mouse_to_logical(mouse_position: Vector2, floor_level: int = 0) -> Vector2:
	if camera == null:
		return player.logical_position + player.facing_direction
	var elevation := float(floor_level) * world_map.floor_height
	if floor_level == player.floor_level:
		elevation = world_map.elevation_at(player.logical_position, floor_level, player.stair_id)
	var hit: Variant = Plane(Vector3.UP, elevation).intersects_ray(
		camera.project_ray_origin(mouse_position), camera.project_ray_normal(mouse_position)
	)
	if hit == null:
		return player.logical_position + player.facing_direction
	var point: Vector3 = hit
	return Vector2(point.x, point.z)


func set_zoom_factor(factor: float) -> void:
	if factor > 0.0:
		camera_distance = clampf(camera_distance / factor, CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX)


func _build_environment() -> void:
	var environment_node := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("a5b7c7")
	environment_node.environment = _environment
	add_child(environment_node)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	# The orthographic MVP already communicates depth through elevation, fog and
	# cutaways. A full directional shadow map costs a render pass over every
	# visible wall/prop each frame, so keep it opt-in for a later visual-polish
	# profile rather than taxing the default gameplay renderer.
	_sun.shadow_enabled = ENABLE_DYNAMIC_SHADOWS
	add_child(_sun)
	_update_lighting()


func _update_lighting() -> void:
	var daylight := world_map.ambient_light()
	if absf(daylight - _last_lighting_daylight) < 0.001:
		return
	_last_lighting_daylight = daylight
	_environment.ambient_light_energy = lerpf(0.12, 0.65, daylight)
	_environment.background_color = Color("101a28").lerp(Color("424e59"), daylight)
	_sun.light_energy = lerpf(0.08, 1.1, daylight)
	_sun.light_color = Color("8cadd5").lerp(Color("ffe4b8"), daylight)


func _build_map() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "GroundBackdrop"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(world_map.width + 12.0, world_map.height + 12.0)
	ground.mesh = ground_mesh
	ground.position = Vector3(world_map.width * 0.5, -0.22, world_map.height * 0.5)
	ground.material_override = _floor_material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	for stair in world_map.stairs.values():
		var direction: Vector2 = (stair.end - stair.start).normalized()
		var side := Vector2(-direction.y, direction.x) * float(stair.width) * 0.5
		var low: Vector2 = stair.start + direction * 0.15
		var high: Vector2 = stair.end - direction * 0.28
		var openings: Array = _floor_openings.get(stair.to_floor, [])
		openings.append(PackedVector2Array([low - side, high - side, high + side, low + side]))
		_floor_openings[stair.to_floor] = openings
	for floor_level in world_map.floor_levels():
		_create_fog_overlay(floor_level)
	_refresh_streamed_floor_chunks(true)


func _tile_polygons(cell: Vector2i, floor_level: int) -> Array[PackedVector2Array]:
	var corner := Vector2(cell)
	var polygons: Array[PackedVector2Array] = [PackedVector2Array([
		corner, corner + Vector2.RIGHT, corner + Vector2.ONE, corner + Vector2.DOWN,
	])]
	for opening: PackedVector2Array in _floor_openings.get(floor_level, []):
		var remaining: Array[PackedVector2Array] = []
		for polygon in polygons:
			remaining.append_array(Geometry2D.clip_polygons(polygon, opening))
		polygons = remaining
	return polygons


func _add_polygon(surface: SurfaceTool, polygon: PackedVector2Array, height: float, color: Color = Color.WHITE) -> void:
	for index in Geometry2D.triangulate_polygon(polygon):
		var point := polygon[index]
		surface.set_normal(Vector3.UP)
		surface.set_color(color)
		surface.add_vertex(Vector3(point.x, height, point.y))


func _add_fog_polygon(surface: SurfaceTool, polygon: PackedVector2Array, height: float) -> void:
	var map_size := Vector2(float(world_map.width), float(world_map.height))
	for index in Geometry2D.triangulate_polygon(polygon):
		var point := polygon[index]
		surface.set_normal(Vector3.UP)
		surface.set_uv(point / map_size)
		surface.add_vertex(Vector3(point.x, height, point.y))


func _add_building_floor_batches(floor_level: int) -> void:
	# Kept as a focused construction helper for editor/tests. Runtime floor
	# creation goes through _load_streamed_floor_chunk() so the same room batches
	# can be cached and evicted with outdoor terrain.
	var batches: Dictionary = {}
	for y in range(world_map.height):
		for x in range(world_map.width):
			var cell := Vector2i(x, y)
			var tile := world_map.get_tile_at(cell, floor_level)
			if tile == null or tile.building_id.is_empty():
				continue
			var material_kind := _floor_material_kind(tile.kind)
			var batch_key := "%s|%s|%s" % [tile.building_id, tile.room_id, material_kind]
			if not batches.has(batch_key):
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				batches[batch_key] = {"surface": surface, "building": tile.building_id,
					"room": tile.room_id, "material_kind": material_kind}
			for polygon in _tile_polygons(cell, floor_level):
				_add_polygon((batches[batch_key] as Dictionary)["surface"] as SurfaceTool, polygon,
					float(floor_level) * world_map.floor_height)
	for batch_key in batches:
		var batch: Dictionary = batches[batch_key]
		var instance := MeshInstance3D.new()
		instance.name = "Floor_%s" % String(batch_key).replace("|", "_")
		instance.mesh = (batch["surface"] as SurfaceTool).commit()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.material_override = _floor_material_for_kind(String(batch["material_kind"]))
		add_child(instance)
		structure_parts.append({"node": instance, "floor": floor_level,
			"building": String(batch["building"]), "kind": "floor", "room": String(batch["room"])})


func _refresh_streamed_floor_chunks(force: bool = false) -> void:
	if world_map == null or player == null:
		return
	var center := Vector2i(floor(player.logical_position.x / STREAM_CHUNK_SIZE),
		floor(player.logical_position.y / STREAM_CHUNK_SIZE))
	var radius := STREAM_CHUNK_RADIUS
	var display_floor := world_map.display_floor_at(player.logical_position, player.floor_level, player.stair_id)
	if camera != null:
		var viewport_size := get_viewport().get_visible_rect().size
		var half_height := camera.size * 0.5
		var half_width := half_height * viewport_size.x / maxf(1.0, viewport_size.y)
		var extent := Vector2(half_width, half_height / sin(CAMERA_PITCH)).length()
		extent += absf(_camera_height + 0.6) / tan(CAMERA_PITCH)
		radius = maxi(radius, int(ceil(extent / float(STREAM_CHUNK_SIZE))))
	if not force and center == _stream_center and radius == _stream_radius and display_floor == _stream_floor:
		return
	_stream_center = center
	_stream_radius = radius
	_stream_floor = display_floor
	_stream_chunk_clock += 1
	var desired: Dictionary = {}
	for floor_level in world_map.floor_levels():
		if floor_level > display_floor:
			continue
		for chunk_y in range(center.y - radius, center.y + radius + 1):
			for chunk_x in range(center.x - radius, center.x + radius + 1):
				if chunk_x < 0 or chunk_y < 0:
					continue
				if chunk_x * STREAM_CHUNK_SIZE >= world_map.width or chunk_y * STREAM_CHUNK_SIZE >= world_map.height:
					continue
				var key := Vector3i(floor_level, chunk_x, chunk_y)
				if _empty_stream_chunks.has(key):
					continue
				if not _streamed_floor_chunks.has(key):
					_load_streamed_floor_chunk(key)
				if not _streamed_floor_chunks.has(key):
					continue
				desired[key] = true
				var entry: Dictionary = _streamed_floor_chunks[key]
				entry["last_used"] = _stream_chunk_clock
				for node: Node3D in entry["nodes"]:
					node.visible = true
	# Streaming restores residency first; architectural cutaways own final
	# visibility. In particular a cached ground chunk must not resurrect a roof.
	if _building_controllers_ready:
		for controller: BuildingVisibilityController in building_controllers.values():
			controller.streamed_floor_limit = display_floor
			controller.refresh_visibility()
		_last_visibility_context = []
	for key in _streamed_floor_chunks:
		if desired.has(key):
			continue
		var entry: Dictionary = _streamed_floor_chunks[key]
		for node: Node3D in entry["nodes"]:
			node.visible = false
	_evict_distant_stream_chunks(desired)


func _load_streamed_floor_chunk(key: Vector3i) -> void:
	var floor_level := key.x
	var start := Vector2i(key.y * STREAM_CHUNK_SIZE, key.z * STREAM_CHUNK_SIZE)
	var end := Vector2i(mini(start.x + STREAM_CHUNK_SIZE, world_map.width),
		mini(start.y + STREAM_CHUNK_SIZE, world_map.height))
	var batches: Dictionary = {}
	for y in range(start.y, end.y):
		for x in range(start.x, end.x):
			var tile := world_map.get_tile_at(Vector2i(x, y), floor_level)
			if tile == null:
				continue
			var material_kind := _floor_material_kind(tile.kind)
			# Keep every room in its own batch. Its node is independently owned by
			# BuildingFloor, so floor slicing and concealed-room materials continue
			# to work after the chunk is unloaded and later rebuilt.
			var building_id := String(tile.building_id)
			var room_id := String(tile.room_id)
			var batch_key := material_kind if building_id.is_empty() else "%s|%s|%s" % [building_id, room_id, material_kind]
			if not batches.has(batch_key):
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				batches[batch_key] = {"surface": surface, "building": building_id,
					"room": room_id, "material_kind": material_kind}
			for polygon in _tile_polygons(Vector2i(x, y), floor_level):
				_add_polygon((batches[batch_key] as Dictionary)["surface"] as SurfaceTool, polygon,
					float(floor_level) * world_map.floor_height)
	var nodes: Array[Node3D] = []
	var parts: Array[Dictionary] = []
	if batches.is_empty():
		_empty_stream_chunks[key] = true
		return
	for batch_key in batches:
		var batch: Dictionary = batches[batch_key]
		var instance := MeshInstance3D.new()
		instance.name = "StreamedFloor_%d_%d_%d_%s" % [floor_level, key.y, key.z, String(batch_key).replace("|", "_")]
		instance.mesh = (batch["surface"] as SurfaceTool).commit()
		instance.material_override = _floor_material_for_kind(String(batch["material_kind"]))
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		nodes.append(instance)
		if not String(batch["building"]).is_empty():
			var part := {"node": instance, "floor": floor_level,
				"building": String(batch["building"]), "kind": "floor", "room": String(batch["room"])}
			parts.append(part)
			structure_parts.append(part)
			if _building_controllers_ready:
				_register_structure_part(part)
	# Walls are assigned by their midpoint, so one face belongs to exactly one
	# cache entry even where a room lies on a chunk boundary.
	var chunk_rect := Rect2(Vector2(start), Vector2(end - start))
	for face: Dictionary in world_map.query_walls(floor_level, chunk_rect):
		var midpoint: Vector2 = (face["start"] + face["end"]) * 0.5
		if Vector2i(floor(midpoint.x / STREAM_CHUNK_SIZE), floor(midpoint.y / STREAM_CHUNK_SIZE)) != Vector2i(key.y, key.z):
			continue
		_add_wall_face(face, floor_level, nodes, parts)
	for face: Dictionary in (world_map.floors[floor_level] as FloorData).visual_edges:
		if chunk_rect.has_point((face["start"] + face["end"]) * 0.5):
			_add_wall_face(face, floor_level, nodes, parts)
	# Roof ownership is tied to its building's ground-floor chunk. This keeps a
	# single roof instance while ground-floor streaming remains present whenever
	# a player occupies any higher level of that building.
	if floor_level == 0:
		for building_value in world_map.buildings.values():
			var building := building_value as BuildingData
			var building_center := building.bounds.get_center()
			if Vector2i(floor(building_center.x / STREAM_CHUNK_SIZE), floor(building_center.y / STREAM_CHUNK_SIZE)) != Vector2i(key.y, key.z):
				continue
			_add_roof(building, nodes, parts)
	for stair_value in world_map.stairs.values():
		var stair: RefCounted = stair_value
		if int(stair.from_floor) != floor_level:
			continue
		var stair_chunk := Vector2i(floor(stair.start.x / STREAM_CHUNK_SIZE), floor(stair.start.y / STREAM_CHUNK_SIZE))
		if stair_chunk != Vector2i(key.y, key.z):
			continue
		_add_stair_mesh(stair, nodes, parts)
	_streamed_floor_chunks[key] = {"nodes": nodes, "parts": parts, "last_used": _stream_chunk_clock}


func _evict_distant_stream_chunks(desired: Dictionary) -> void:
	# Visible chunks are mandatory; the cache budget may grow with the viewport.
	while _streamed_floor_chunks.size() > maxi(MAX_CACHED_STREAM_CHUNKS, desired.size()):
		var candidate: Variant = null
		var oldest := INF
		for key in _streamed_floor_chunks:
			if desired.has(key):
				continue
			var last_used := int((_streamed_floor_chunks[key] as Dictionary)["last_used"])
			if last_used < oldest:
				oldest = last_used
				candidate = key
		if candidate == null:
			return
		var entry: Dictionary = _streamed_floor_chunks[candidate]
		for part: Dictionary in entry.get("parts", []):
			_unregister_structure_part(part)
			structure_parts.erase(part)
		for node: Node3D in entry["nodes"]:
			node.queue_free()
		_streamed_floor_chunks.erase(candidate)


func _floor_material_kind(kind: String) -> String:
	match kind:
		"road", "asphalt", "concrete": return "road"
		"floor", "wall", "stairs", "indoor_floor": return "indoor"
		"door": return "door"
		"soil", "dirt": return "soil"
		"water": return "water"
		_: return "grass"


func _floor_material_for_kind(kind: String) -> Material:
	match kind:
		"road": return _road_material
		"indoor": return _indoor_material
		"door": return _door_material
		"soil": return _soil_material
		"water": return _water_material
		_: return _grass_material


func _add_wall_face(face: Dictionary, floor_level: int, nodes: Array[Node3D] = [],
		parts: Array[Dictionary] = []) -> void:
	var start: Vector2 = face["start"]
	var end: Vector2 = face["end"]
	var midpoint := (start + end) * 0.5
	var direction := end - start
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(direction.length(), WALL_HEIGHT, WALL_THICKNESS)
	instance.mesh = mesh
	instance.position = Vector3(midpoint.x, float(floor_level) * world_map.floor_height + WALL_HEIGHT * 0.5, midpoint.y)
	instance.rotation.y = -direction.angle()
	instance.material_override = _wall_material
	if face.get("kind", "wall") == "door":
		instance.material_override = _door_material
	elif face.get("kind", "wall") == "window":
		mesh.size.y = WALL_HEIGHT * 0.5
		instance.material_override = _water_material
	add_child(instance)
	nodes.append(instance)
	var part := {"node": instance, "floor": floor_level, "building": String(face["building_id"]), "kind": "wall"}
	parts.append(part)
	structure_parts.append(part)
	if _building_controllers_ready:
		_register_structure_part(part)


func _add_roof(building: BuildingData, nodes: Array[Node3D] = [], parts: Array[Dictionary] = []) -> void:
	if not building.has_roof: return
	var instance := MeshInstance3D.new()
	instance.name = "%s_Roof" % building.id
	var mesh := BoxMesh.new()
	mesh.size = Vector3(building.bounds.size.x + 0.12, 0.16, building.bounds.size.y + 0.12)
	instance.mesh = mesh
	instance.position = Vector3(
		building.bounds.position.x + building.bounds.size.x * 0.5,
		building.floor_count * world_map.floor_height + 0.04,
		building.bounds.position.y + building.bounds.size.y * 0.5
	)
	instance.material_override = _roof_material
	add_child(instance)
	nodes.append(instance)
	var part := {"node": instance, "floor": building.floor_count, "building": building.id, "kind": "roof"}
	parts.append(part)
	structure_parts.append(part)
	if _building_controllers_ready:
		_register_structure_part(part)


func _add_stair_mesh(stair: RefCounted, nodes: Array[Node3D] = [], parts: Array[Dictionary] = []) -> void:
	var root := Node3D.new()
	root.name = "%s_Stair" % stair.id
	add_child(root)
	var direction: Vector2 = (stair.end - stair.start).normalized()
	var length: float = stair.start.distance_to(stair.end)
	var base: float = float(stair.from_floor) * world_map.floor_height
	var rise: float = float(stair.to_floor - stair.from_floor) * world_map.floor_height
	var steps := maxi(8, int(ceil(rise / 0.22)))
	for step in range(steps):
		var progress := (float(step) + 0.5) / float(steps)
		var point: Vector2 = stair.start.lerp(stair.end, progress)
		var tread := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(length / float(steps) + 0.02, 0.09, float(stair.width))
		tread.mesh = mesh
		tread.position = Vector3(point.x, base + rise * progress - 0.045, point.y)
		tread.rotation.y = -direction.angle()
		tread.material_override = _stair_material
		root.add_child(tread)
	var side := Vector2(-direction.y, direction.x) * float(stair.width) * 0.5
	for side_sign in [-1.0, 1.0]:
		var rail_start: Vector2 = stair.start + side * side_sign
		var rail_end: Vector2 = stair.end + side * side_sign
		_add_beam(root, Vector3(rail_start.x, base + 0.65, rail_start.y), Vector3(rail_end.x, base + rise + 0.65, rail_end.y))
		for progress in [0.0, 0.5, 1.0]:
			var point: Vector2 = rail_start.lerp(rail_end, progress)
			_add_beam(root, Vector3(point.x, base + rise * progress, point.y), Vector3(point.x, base + rise * progress + 0.65, point.y))
	var stair_tile := world_map.get_tile(stair.start, int(stair.from_floor))
	nodes.append(root)
	var part := {"node": root, "floor": int(stair.from_floor), "building": String(stair.building_id),
		"kind": "stairs", "room": stair_tile.room_id if stair_tile != null else "", "stair": stair.id}
	parts.append(part)
	structure_parts.append(part)
	if _building_controllers_ready:
		_register_structure_part(part)


func _add_beam(parent: Node3D, start: Vector3, end: Vector3) -> void:
	var beam := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = start.distance_to(end)
	beam.mesh = mesh
	beam.position = (start + end) * 0.5
	beam.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	beam.material_override = _door_material
	parent.add_child(beam)


func _build_interaction_markers() -> void:
	for point in interactions.points:
		var root := Node3D.new()
		var mesh := TorusMesh.new()
		if point.get("furniture", false):
			var cabinet := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.5, 1.0, 0.5)
			cabinet.mesh = box
			cabinet.position.y = 0.5
			cabinet.material_override = _material(Color("d9d9d2"))
			root.add_child(cabinet)
		mesh.inner_radius = 0.27
		mesh.outer_radius = 0.34
		var ring := MeshInstance3D.new()
		ring.mesh = mesh
		ring.position.y = 0.045
		root.add_child(ring)
		var beacon := MeshInstance3D.new()
		var beacon_mesh := CylinderMesh.new()
		beacon_mesh.top_radius = 0.045
		beacon_mesh.bottom_radius = 0.08
		beacon_mesh.height = 0.42
		beacon.mesh = beacon_mesh
		beacon.position.y = 0.24
		root.add_child(beacon)
		var color := Color("6dcae8")
		match String(point["kind"]):
			"bed":
				color = Color("baa7ea")
			"hazard":
				color = Color("e37a52")
		var material := _material(color)
		material.emission_enabled = true
		material.emission = color * 0.16
		ring.material_override = material
		beacon.material_override = material
		var logical_position: Vector2 = point["position"]
		var floor_level := int(point.get("floor", 0))
		root.position = Vector3(logical_position.x, float(floor_level) * world_map.floor_height, logical_position.y)
		add_child(root)
		interaction_markers.append({"node": root, "point": point})


func _refresh_interaction_markers() -> void:
	for marker in interaction_markers:
		(marker["node"] as Node3D).queue_free()
	interaction_markers.clear()
	_last_marker_visibility_revision = -1
	_build_interaction_markers()


func _update_interaction_markers() -> void:
	if _last_marker_visibility_revision == visibility.revision:
		return
	_last_marker_visibility_revision = visibility.revision
	for marker in interaction_markers:
		var point: Dictionary = marker["point"]
		(marker["node"] as Node3D).visible = (
			visibility.can_see_position(point["position"], int(point.get("floor", 0)))
			and not (String(point["kind"]) == "hazard" and bool(point.get("triggered", false)))
		)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "OrbitCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 120.0
	add_child(camera)
	camera.make_current()
	_camera_height = world_map.elevation_at(player.logical_position, player.floor_level, player.stair_id)
	_update_camera(0.0)


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	camera.size = camera_distance * 0.84
	var target_height := world_map.elevation_at(player.logical_position, player.floor_level, player.stair_id)
	_camera_height = lerpf(_camera_height, target_height, 1.0 - exp(-12.0 * delta)) if delta > 0.0 else target_height
	var focus := Vector3(player.logical_position.x, _camera_height + 0.6, player.logical_position.y)
	var horizontal_distance := camera_distance * cos(CAMERA_PITCH)
	camera.global_position = focus + Vector3(
		sin(camera_yaw) * horizontal_distance,
		camera_distance * sin(CAMERA_PITCH),
		cos(camera_yaw) * horizontal_distance
	)
	camera.look_at(focus, Vector3.UP)


func _build_visibility_controllers() -> void:
	for part in structure_parts:
		_register_structure_part(part)
	# Streamed upper floors may not yet have mesh nodes. Keep their presentation
	# state objects alive so floor slicing remains deterministic before the player
	# enters their chunks.
	for building_value in world_map.buildings.values():
		var building := building_value as BuildingData
		var controller := building_controllers.get(building.id) as BuildingVisibilityController
		if controller == null:
			continue
		for floor_index in range(building.floor_count):
			controller.ensure_floor(floor_index)
	_building_controllers_ready = true
	for controller: BuildingVisibilityController in building_controllers.values():
		controller.refresh_visibility()


func _register_structure_part(part: Dictionary) -> void:
	var id := String(part["building"])
	if id.is_empty():
		return
	if not building_controllers.has(id):
		var controller := BuildingVisibilityController.new()
		controller.name = id + "_Visibility"
		controller.building_id = id
		add_child(controller)
		building_controllers[id] = controller
	var controller := building_controllers[id] as BuildingVisibilityController
	controller.streamed_floor_limit = _stream_floor
	controller.register_part(part)


func _unregister_structure_part(part: Dictionary) -> void:
	var id := String(part.get("building", ""))
	if id.is_empty() or not building_controllers.has(id):
		return
	(building_controllers[id] as BuildingVisibilityController).unregister_part(part["node"] as Node3D)


func _update_structure_visibility(ensure_visibility: bool = true) -> void:
	# The game root owns runtime FOV cadence. Direct callers (editor previews and
	# tests) can retain the former self-contained behaviour by using the default.
	if ensure_visibility:
		visibility.refresh(player.logical_position, player.facing_direction, player.aim_mode, player.floor_level,
			player.state.perception_multiplier())
	# Presentation follows the FOV revision, while camera yaw/zoom and viewport
	# changes still update cutaways immediately.
	# Camera transform itself is deliberately absent: following the player changes
	# it every frame even when the view direction and range are unchanged.
	var context := [player.floor_level, player.stair_id, camera_yaw, visibility.revision,
		camera_distance, get_viewport().get_visible_rect().size]
	if context == _last_visibility_context:
		return
	_last_visibility_context = context
	_update_visible_content_regions()
	var tile := world_map.get_tile_at(Vector2i(player.logical_position.floor()), player.floor_level)
	var player_building := tile.building_id if tile != null else ""
	var highest_visible_floor := world_map.display_floor_at(player.logical_position, player.floor_level, player.stair_id)
	if not player.stair_id.is_empty() and world_map.stairs.has(player.stair_id):
		var stair: RefCounted = world_map.stairs[player.stair_id]
		player_building = stair.building_id
	var direction := Vector3(sin(camera_yaw) * cos(CAMERA_PITCH), sin(CAMERA_PITCH), cos(camera_yaw) * cos(CAMERA_PITCH))
	var feet := Vector3(player.logical_position.x,
		world_map.elevation_at(player.logical_position, player.floor_level, player.stair_id), player.logical_position.y)
	var content_tile := world_map.get_tile(player.logical_position, highest_visible_floor)
	var current_room := content_tile.room_id if content_tile != null else ""
	if player_building != _active_building_id:
		var previous := _active_building_id
		if building_controllers.has(previous):
			(building_controllers[previous] as BuildingVisibilityController).configure_content("", "", [], direction, camera_distance + 1.0)
			(building_controllers[previous] as BuildingVisibilityController).set_cutaway(false)
		_active_building_id = player_building
		player_building_changed.emit(previous, player_building)
	if building_controllers.has(player_building):
		(building_controllers[player_building] as BuildingVisibilityController).configure_content(
			current_room, player.stair_id, _visible_content_regions, direction, camera_distance + 1.0)
		(building_controllers[player_building] as BuildingVisibilityController).update_local_view(
			highest_visible_floor, player.logical_position, Vector2(sin(camera_yaw), cos(camera_yaw)), feet)
	occlusion_system.update_view(player_building, highest_visible_floor, feet, direction,
		camera_distance + 1.0, _player_reveal_rect(feet), _visible_content_regions)
	if _display_floor != highest_visible_floor:
		_display_floor = highest_visible_floor
		for floor_level in fog_overlays:
			(fog_overlays[floor_level] as MeshInstance3D).visible = int(floor_level) <= highest_visible_floor
		_last_fog_revision = -1
		player_display_floor_changed.emit(highest_visible_floor)


func _update_visible_content_regions() -> void:
	if _region_revision == visibility.revision:
		return
	_region_revision = visibility.revision
	_visible_content_regions.clear()
	var polygon := visibility.visible_world_polygon
	if polygon.size() < 3:
		return
	var floor_index := visibility.viewer_floor
	# Intersect all existing floor tiles in the small FOV bounds with the
	# continuous contour.  visible_tiles is intentionally not used here: it is
	# persistent grid exploration data and has no authority over a partial cell
	# currently visible through a doorway.
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	var min_x := maxi(0, floori(bounds.position.x))
	var max_x := mini(world_map.width - 1, ceili(bounds.end.x))
	var min_y := maxi(0, floori(bounds.position.y))
	var max_y := mini(world_map.height - 1, ceili(bounds.end.y))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if world_map.get_tile_at(cell, floor_index) == null:
				continue
			for tile_polygon in _tile_polygons(cell, floor_index):
				for fragment in Geometry2D.intersect_polygons(tile_polygon, polygon):
					if fragment.size() < 3:
						continue
					var rect := Rect2(fragment[0], Vector2.ZERO)
					for point in fragment:
						rect = rect.expand(point)
					# Insets avoid treating contact at a rear wall as occlusion.
					if rect.size.x <= 0.04 or rect.size.y <= 0.04:
						continue
					rect = rect.grow(-0.02)
					_visible_content_regions.append(AABB(Vector3(rect.position.x,
						floor_index * world_map.floor_height + 0.03, rect.position.y), Vector3(rect.size.x, 1.85, rect.size.y)))


func _player_reveal_rect(feet: Vector3) -> Vector4:
	var body := AABB(feet - Vector3(0.35, 0, 0.35), Vector3(0.7, 1.9, 0.7))
	var rect := Rect2(camera.unproject_position(body.position), Vector2.ZERO)
	for index in range(8):
		rect = rect.expand(camera.unproject_position(body.get_endpoint(index)))
	var viewport_size := get_viewport().get_visible_rect().size
	var center := rect.get_center() / viewport_size
	var size := rect.size / viewport_size
	return Vector4(center.x, center.y, size.x, size.y)


func _build_authored_occluders() -> void:
	for decoration: MapDecorationDefinition in world_map.definition.decorations:
		if decoration.kind == "road_sign":
			_add_road_sign(decoration)
		elif decoration.kind == "tree":
			_add_tree(decoration)


func _add_road_sign(decoration: MapDecorationDefinition) -> void:
	var sign := SmallOccluder.new()
	sign.name = decoration.id
	add_child(sign)
	sign.position = world_map.definition.logical_to_world(decoration.position, decoration.level)
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.05
	post_mesh.bottom_radius = 0.05
	post_mesh.height = 2.6
	post.mesh = post_mesh
	post.position.y = 1.3
	post.material_override = _wall_material
	sign.add_child(post)
	sign.register_mesh(post)
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(1.1, 0.75, 0.08)
	board.mesh = board_mesh
	board.position.y = 2.3
	board.material_override = _material(Color("526e8a"))
	sign.add_child(board)
	sign.register_mesh(board)
	small_occluders.append(sign)


func _add_tree(decoration: MapDecorationDefinition) -> void:
	var tree := SmallOccluder.new()
	tree.name = decoration.id
	add_child(tree)
	tree.position = world_map.definition.logical_to_world(decoration.position, decoration.level)
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.18
	trunk_mesh.height = 2.8
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.4
	trunk.material_override = _stair_material
	tree.add_child(trunk)
	tree.register_mesh(trunk)
	var crown := MeshInstance3D.new()
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.9
	crown_mesh.height = 1.8
	crown.mesh = crown_mesh
	crown.position.y = 3.0
	crown.material_override = _grass_material
	tree.add_child(crown)
	tree.register_mesh(crown)
	small_occluders.append(tree)


func _create_fog_overlay(floor_level: int) -> void:
	var fog := MeshInstance3D.new()
	fog.name = "Floor_%d_VisionFog" % floor_level
	var image := Image.create(world_map.width * FOG_PIXELS_PER_TILE,
		world_map.height * FOG_PIXELS_PER_TILE, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	var texture := ImageTexture.create_from_image(image)
	var visibility_image := Image.create(world_map.width * FOG_VISIBILITY_PIXELS_PER_TILE,
		world_map.height * FOG_VISIBILITY_PIXELS_PER_TILE, false, Image.FORMAT_RGBA8)
	visibility_image.fill(Color.BLACK)
	var visibility_texture := ImageTexture.create_from_image(visibility_image)
	var material := ShaderMaterial.new()
	material.shader = EXPLORATION_FOG_SHADER
	material.set_shader_parameter("exploration_mask", texture)
	material.set_shader_parameter("visibility_mask", visibility_texture)
	var image_size := image.get_size()
	material.set_shader_parameter("texel_size", Vector2(1.0 / float(image_size.x), 1.0 / float(image_size.y)))
	material.render_priority = 2
	fog.material_override = material
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Geometry is static.  The two masks contain the changing exploration/FOV
	# state, avoiding a full SurfaceTool rebuild every visibility refresh.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(world_map.height):
		for x in range(world_map.width):
			var cell := Vector2i(x, y)
			if world_map.get_tile_at(cell, floor_level) == null:
				continue
			for polygon in _tile_polygons(cell, floor_level):
				_add_fog_polygon(surface, polygon, float(floor_level) * world_map.floor_height + 0.018)
	fog.mesh = surface.commit()
	add_child(fog)
	fog_overlays[floor_level] = fog
	fog_masks[floor_level] = {
		"image": image,
		"texture": texture,
		"visibility_image": visibility_image,
		"visibility_texture": visibility_texture,
		"seen_tiles": {},
		"had_visibility": false,
	}


func _update_fog() -> void:
	if visibility.revision == _last_fog_revision:
		return
	_last_fog_revision = visibility.revision
	if _reset_exploration:
		_pending_exploration = visibility.seen_tiles.duplicate()
	for floor_level in world_map.floor_levels():
		_update_fog_mask(floor_level)
	_pending_exploration.clear()
	_reset_exploration = false


func _update_fog_mask(floor_level: int) -> void:
	var entry: Dictionary = fog_masks[floor_level]
	var image := entry["image"] as Image
	var visible_image := entry["visibility_image"] as Image
	var seen_tiles: Dictionary = entry["seen_tiles"] as Dictionary
	var exploration_changed := _reset_exploration
	if _reset_exploration:
		image.fill(Color.BLACK)
		seen_tiles.clear()
	for key_value in _pending_exploration:
		var key: Vector3i = key_value
		if key.z != floor_level:
			continue
		image.fill_rect(Rect2i(key.x * FOG_PIXELS_PER_TILE, key.y * FOG_PIXELS_PER_TILE,
			FOG_PIXELS_PER_TILE, FOG_PIXELS_PER_TILE), Color.WHITE)
		seen_tiles[key] = true
		exploration_changed = true
	if floor_level == visibility.viewer_floor:
		visible_image.fill(Color.BLACK)
		_rasterize_visibility(visible_image, floor_level, FOG_VISIBILITY_PIXELS_PER_TILE)
		entry["had_visibility"] = true
		(entry["visibility_texture"] as ImageTexture).update(visible_image)
	elif bool(entry["had_visibility"]):
		visible_image.fill(Color.BLACK)
		entry["had_visibility"] = false
		(entry["visibility_texture"] as ImageTexture).update(visible_image)
	if exploration_changed:
		(entry["texture"] as ImageTexture).update(image)


func _rasterize_visibility(image: Image, floor_level: int, pixels_per_tile: int) -> void:
	# Scan-convert the wall-clipped contour at sub-tile resolution. Do not gate
	# pixels by a grid-cell visibility flag: that would hide a partly exposed
	# doorway or body simply because the cell centre is behind a wall.
	var polygon := visibility.visible_world_polygon
	if polygon.size() < 3:
		return
	var scale_factor := float(pixels_per_tile)
	var min_y := image.get_height()
	var max_y := 0
	for point in polygon:
		min_y = mini(min_y, int(floor(point.y * scale_factor)))
		max_y = maxi(max_y, int(ceil(point.y * scale_factor)))
	for row in range(maxi(0, min_y), mini(image.get_height(), max_y)):
		var y := (float(row) + 0.5) / scale_factor
		var crossings: Array[float] = []
		var previous := polygon[polygon.size() - 1]
		for point in polygon:
			if (point.y > y) != (previous.y > y):
				crossings.append((point.x + (y - point.y) * (previous.x - point.x) / (previous.y - point.y)) * scale_factor)
			previous = point
		crossings.sort()
		for index in range(0, crossings.size() - 1, 2):
			var start := maxi(0, int(ceil(crossings[index] - 0.5)))
			var end := mini(image.get_width(), int(ceil(crossings[index + 1] - 0.5)))
			image.fill_rect(Rect2i(start, row, end - start, 1), Color.WHITE)


static func fog_color_for_seen(seen: bool) -> Color:
	# Exploration memory remains readable when it leaves the current FOV. Only
	# never-observed space is fully black; current visibility is cut out above.
	return Color(0.055, 0.08, 0.12, 0.22) if seen else Color(0.0, 0.0, 0.0, 1.0)


func _update_actors() -> void:
	var alive_ids: Dictionary = {}
	for actor in actor_layer.get_children():
		if not actor is PlayerController and not actor is ZombieActor and not actor is SurvivorNPC:
			continue
		var node := actor as Node2D
		var actor_id := node.get_instance_id()
		if node.is_queued_for_deletion():
			continue
		alive_ids[actor_id] = true
		var logical_position: Vector2 = node.get("logical_position")
		var actor_floor := int(node.get("floor_level"))
		var stair_id := String(node.get("stair_id"))
		var visible := _actor_is_visible(node, actor_id, logical_position, actor_floor, stair_id)
		var visual: Dictionary = actor_visuals.get(actor_id, {})
		if not visible:
			if not visual.is_empty():
				(visual["root"] as Node3D).visible = false
				if bool(visual["has_health"]):
					(visual["health_bar"] as Node3D).visible = false
			continue
		if visual.is_empty():
			visual = _create_actor_visual(node)
			actor_visuals[actor_id] = visual
		var model: Node3D = visual["root"]
		model.visible = true
		if bool(visual["has_health"]):
			(visual["health_bar"] as Node3D).visible = true
		model.position = Vector3(logical_position.x, world_map.elevation_at(logical_position, actor_floor, stair_id), logical_position.y)
		if node == player:
			model.rotation.y = atan2(-player.facing_direction.x, -player.facing_direction.y)
			(visual["equipment_visual"] as PlayerEquipmentVisual).refresh()
			var swing: Node3D = visual["swing"]
			swing.visible = player._attack_flash_left > 0.0
			swing.rotation.y = lerpf(-0.9, 0.9, 1.0 - clampf(player._attack_flash_left / 0.18, 0.0, 1.0))
		elif node is ZombieActor:
			var zombie := node as ZombieActor
			var direction := zombie.target_position - zombie.logical_position
			if direction.length_squared() > 0.001:
				model.rotation.y = atan2(-direction.x, -direction.y)
			_update_health_bar(visual, zombie.health, ZombieActor.MAX_HEALTH)
			var flash := _zombie_flash_material if zombie._damage_flash_left > 0.0 else _zombie_material
			(visual["body"] as MeshInstance3D).material_override = flash
			(visual["head"] as MeshInstance3D).material_override = flash
		if bool(visual["has_health"]):
			var bar: Node3D = visual["health_bar"]
			bar.global_position = model.global_position + Vector3(0.0, 2.05, 0.0)
			bar.look_at(camera.global_position, Vector3.UP)
	for actor_id in actor_visuals.keys():
		if not alive_ids.has(actor_id):
			_remove_actor_visual(actor_id, actor_visuals[actor_id])
	for actor_id in _actor_visibility_cache.keys():
		if not alive_ids.has(actor_id):
			_actor_visibility_cache.erase(actor_id)


func _actor_is_visible(node: Node2D, actor_id: int, logical_position: Vector2,
		actor_floor: int, stair_id: String) -> bool:
	if node == player:
		return true
	# LOS is much more expensive than updating a visible model transform. Reuse
	# the result until either end of the query changes. Moving actors still get a
	# fresh answer immediately, while dormant off-screen populations become cheap.
	var cached: Dictionary = _actor_visibility_cache.get(actor_id, {})
	if (not cached.is_empty()
		and int(cached["revision"]) == visibility.revision
		and cached["position"] == logical_position
		and int(cached["floor"]) == actor_floor
		and String(cached["stair"]) == stair_id
		and String(cached["player_stair"]) == player.stair_id):
		return bool(cached["visible"])
	var result := visibility.can_see_actor(logical_position, actor_floor)
	if not stair_id.is_empty() or not player.stair_id.is_empty():
		result = (not stair_id.is_empty() and stair_id == player.stair_id
			and visibility.can_see_actor(logical_position, player.floor_level))
	_actor_visibility_cache[actor_id] = {
		"revision": visibility.revision,
		"position": logical_position,
		"floor": actor_floor,
		"stair": stair_id,
		"player_stair": player.stair_id,
		"visible": result,
	}
	return result


func _create_actor_visual(actor: Node2D) -> Dictionary:
	var root := Node3D.new()
	root.name = "PlayerVisual" if actor == player else "ActorVisual"
	add_child(root)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var lower_body: MeshInstance3D = null
	if actor == player:
		var torso_mesh := CylinderMesh.new()
		torso_mesh.top_radius = 0.22
		torso_mesh.bottom_radius = 0.25
		torso_mesh.height = 0.72
		torso_mesh.radial_segments = 8
		body.mesh = torso_mesh
		body.position.y = 1.06
		lower_body = MeshInstance3D.new()
		lower_body.name = "LowerBody"
		var lower_mesh := CylinderMesh.new()
		lower_mesh.top_radius = 0.22
		lower_mesh.bottom_radius = 0.17
		lower_mesh.height = 0.7
		lower_mesh.radial_segments = 8
		lower_body.mesh = lower_mesh
		lower_body.position.y = 0.35
		root.add_child(lower_body)
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.26
		capsule.height = 1.42
		body.mesh = capsule
		body.position.y = 0.76
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.23
	head_mesh.height = 0.46
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.62, -0.04)
	root.add_child(head)
	var has_health := actor is ZombieActor
	var material := _zombie_material if has_health else (_npc_material if actor is SurvivorNPC else _player_material)
	body.material_override = material
	if lower_body != null: lower_body.material_override = material
	head.material_override = _player_accent_material if actor == player else material
	if has_health:
		head.position.z = -0.2
	var direction_marker := MeshInstance3D.new()
	direction_marker.name = "DirectionMarker"
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.07, 0.07, 0.42)
	direction_marker.mesh = marker_mesh
	direction_marker.position = Vector3(0.0, 0.85, -0.42)
	direction_marker.material_override = _door_material
	root.add_child(direction_marker)
	var visual := {"root": root, "body": body, "head": head, "lower_body": lower_body, "has_health": has_health}
	if actor == player:
		var equipment_visual := PlayerEquipmentVisual.new()
		root.add_child(equipment_visual)
		equipment_visual.setup(player.state.inventory)
		visual["equipment_visual"] = equipment_visual
		visual["swing"] = _create_swing_visual(root)
	if has_health:
		visual["health_bar"] = _create_health_bar()
		var actor_id := actor.get_instance_id()
		(actor as ZombieActor).died.connect(
			func(_zombie: ZombieActor) -> void: _remove_actor_visual(actor_id, visual),
			CONNECT_ONE_SHOT
		)
	return visual


func _create_swing_visual(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "AttackSwing"
	parent.add_child(root)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(12):
		var a := lerpf(-0.45, 0.45, float(index) / 12.0)
		var b := lerpf(-0.45, 0.45, float(index + 1) / 12.0)
		for point in [Vector2(sin(a), -cos(a)) * 0.72, Vector2(sin(a), -cos(a)) * 1.22, Vector2(sin(b), -cos(b)) * 1.22,
			Vector2(sin(a), -cos(a)) * 0.72, Vector2(sin(b), -cos(b)) * 1.22, Vector2(sin(b), -cos(b)) * 0.72]:
			surface.add_vertex(Vector3(point.x, 0.85, point.y))
	var arc := MeshInstance3D.new()
	arc.mesh = surface.commit()
	arc.material_override = _swing_material
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(arc)
	root.visible = false
	return root


func _remove_actor_visual(actor_id: int, visual: Dictionary) -> void:
	for key in ["root", "health_bar"]:
		var node := visual.get(key) as Node3D
		if is_instance_valid(node):
			node.visible = false
			node.queue_free()
	actor_visuals.erase(actor_id)
	_actor_visibility_cache.erase(actor_id)


func _create_health_bar() -> Node3D:
	var bar := Node3D.new()
	add_child(bar)
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(0.8, 0.1, 0.04)
	back.mesh = back_mesh
	back.material_override = _health_back_material
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(back)
	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.72, 0.055, 0.06)
	fill.mesh = fill_mesh
	fill.position.z = -0.035
	fill.material_override = _health_fill_material
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(fill)
	bar.visible = false
	return bar


func _update_health_bar(visual: Dictionary, health: int, max_health: int) -> void:
	var bar: Node3D = visual["health_bar"]
	var fill := bar.get_child(1) as MeshInstance3D
	var ratio := clampf(float(health) / float(maxi(1, max_health)), 0.0, 1.0)
	fill.scale.x = maxf(0.001, ratio)
	fill.position.x = -0.36 * (1.0 - ratio)


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
