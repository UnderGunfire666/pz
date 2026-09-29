class_name VisibilitySystem
extends Node

## Fan-shaped player FOV. Actors use this same query so unseen zombies and NPCs
## are hidden rather than merely dimmed.
var world_map: WorldMap
var visible_tiles: Dictionary = {}
var seen_tiles: Dictionary = {}
var viewer_position := Vector2.ZERO
var facing_direction := Vector2.DOWN
var aim_mode := false
var viewer_floor := 0
var visible_world_polygon := PackedVector2Array()
var vision_radius := 0.0
var half_fov_radians := 0.0
const SELF_VISION_RADIUS := 1.2
const FOV_RAY_COUNT := 256
var revision := 0
var _last_world_revision := -1
var _last_light := -1.0


func setup(p_world_map: WorldMap) -> void:
	world_map = p_world_map


func refresh(next_viewer_position: Vector2, next_facing_direction: Vector2, next_aim_mode: bool, next_floor: int = 0) -> void:
	if world_map == null:
		return
	var next_facing := next_facing_direction.normalized() if next_facing_direction.length_squared() > 0.001 else Vector2.DOWN
	var unchanged := (
		viewer_position.distance_squared_to(next_viewer_position) < 0.0025
		and facing_direction.dot(next_facing) > 0.999
		and aim_mode == next_aim_mode
		and viewer_floor == next_floor
		and _room_at(viewer_position, viewer_floor) == _room_at(next_viewer_position, next_floor)
		and _last_world_revision == world_map.revision
		and absf(_last_light - world_map.ambient_light()) < 0.005
	)
	if unchanged:
		return
	viewer_position = next_viewer_position
	facing_direction = next_facing
	aim_mode = next_aim_mode
	viewer_floor = next_floor
	_last_world_revision = world_map.revision
	_last_light = world_map.ambient_light()
	visible_tiles.clear()
	var viewer_cell := Vector2i(int(floor(viewer_position.x)), int(floor(viewer_position.y)))
	var viewer_key := Vector3i(viewer_cell.x, viewer_cell.y, viewer_floor)
	visible_tiles[viewer_key] = true
	seen_tiles[viewer_key] = true

	vision_radius = 6.6 * lerpf(0.55, 1.0, world_map.ambient_light())
	half_fov_radians = deg_to_rad(68.0)
	for y in range(WorldMap.HEIGHT):
		for x in range(WorldMap.WIDTH):
			var cell := Vector2i(x, y)
			var target := Vector2(cell) + Vector2(0.5, 0.5)
			if can_see_position(target, viewer_floor):
				var key := Vector3i(x, y, viewer_floor)
				visible_tiles[key] = true
				seen_tiles[key] = true
	visible_world_polygon = _build_visibility_polygon()
	revision += 1


func can_see_position(world_position: Vector2, floor_level: int = 0) -> bool:
	if world_map == null or floor_level != viewer_floor:
		return false
	if not room_contents_allowed(world_position, floor_level):
		return false
	var offset := world_position - viewer_position
	if offset.length() > vision_radius:
		return false
	if offset.length() > SELF_VISION_RADIUS:
		var delta_angle := absf(wrapf(offset.angle() - facing_direction.angle(), -PI, PI))
		if delta_angle > half_fov_radians:
			return false
	return world_map.has_line_of_sight(viewer_position, world_position, viewer_floor)


func _room_at(position: Vector2, floor_level: int) -> String:
	var tile := world_map.get_tile(position, floor_level)
	return tile.room_id if tile != null else ""


func room_contents_allowed(position: Vector2, floor_level: int) -> bool:
	var room := _room_at(position, floor_level)
	return room.is_empty() or room == _room_at(viewer_position, viewer_floor)


func invalidate() -> void:
	_last_world_revision = -1


func _build_visibility_polygon() -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for ray_index in range(FOV_RAY_COUNT):
		var angle := TAU * float(ray_index) / float(FOV_RAY_COUNT)
		var direction := Vector2.from_angle(angle)
		var angle_from_facing := absf(wrapf(angle - facing_direction.angle(), -PI, PI))
		var ray_radius := vision_radius if angle_from_facing <= half_fov_radians else SELF_VISION_RADIUS
		polygon.append(_ray_endpoint(direction, ray_radius))
	return polygon


func _ray_endpoint(direction: Vector2, max_distance: float) -> Vector2:
	var ray_end := viewer_position + direction * max_distance
	var nearest_distance := max_distance
	for wall_face in world_map.wall_faces(viewer_floor):
		var intersection: Variant = Geometry2D.segment_intersects_segment(
			viewer_position,
			ray_end,
			wall_face["start"],
			wall_face["end"]
		)
		if intersection == null:
			continue
		var hit: Vector2 = intersection
		var hit_distance := viewer_position.distance_to(hit)
		if hit_distance < nearest_distance:
			nearest_distance = hit_distance
	return viewer_position + direction * nearest_distance


func is_tile_visible(cell: Vector2i, floor_level: int = 0) -> bool:
	return visible_tiles.has(Vector3i(cell.x, cell.y, floor_level))


func was_tile_seen(cell: Vector2i, floor_level: int = 0) -> bool:
	return seen_tiles.has(Vector3i(cell.x, cell.y, floor_level))
