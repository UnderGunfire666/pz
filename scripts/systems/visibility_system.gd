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
var visible_polygon := PackedVector2Array()
var visible_world_polygon := PackedVector2Array()
var vision_radius := 0.0
var half_fov_radians := 0.0
const SELF_VISION_RADIUS := 1.2
const FOV_REFRESH_INTERVAL_MSEC := 50
const FOV_RAY_COUNT := 256
var revision := 0
var _last_refresh_msec := -FOV_REFRESH_INTERVAL_MSEC


func setup(p_world_map: WorldMap) -> void:
	world_map = p_world_map


func refresh(next_viewer_position: Vector2, next_facing_direction: Vector2, next_aim_mode: bool) -> void:
	if world_map == null:
		return
	var next_facing := next_facing_direction.normalized() if next_facing_direction.length_squared() > 0.001 else Vector2.DOWN
	var now := Time.get_ticks_msec()
	var unchanged := (
		viewer_position.distance_squared_to(next_viewer_position) < 0.0025
		and facing_direction.dot(next_facing) > 0.999
		and aim_mode == next_aim_mode
	)
	if unchanged and now - _last_refresh_msec < FOV_REFRESH_INTERVAL_MSEC:
		return
	viewer_position = next_viewer_position
	facing_direction = next_facing
	aim_mode = next_aim_mode
	_last_refresh_msec = now
	visible_tiles.clear()
	var viewer_cell := Vector2i(int(floor(viewer_position.x)), int(floor(viewer_position.y)))
	visible_tiles[viewer_cell] = true
	seen_tiles[viewer_cell] = true

	vision_radius = 6.6 * lerpf(0.55, 1.0, world_map.ambient_light())
	half_fov_radians = deg_to_rad(68.0)
	for y in range(WorldMap.HEIGHT):
		for x in range(WorldMap.WIDTH):
			var cell := Vector2i(x, y)
			var target := Vector2(cell) + Vector2(0.5, 0.5)
			if can_see_position(target):
				visible_tiles[cell] = true
				seen_tiles[cell] = true
	visible_world_polygon = _build_visibility_polygon()
	visible_polygon = PackedVector2Array([world_map.grid_to_screen(viewer_position)])
	for point in visible_world_polygon:
		visible_polygon.append(world_map.grid_to_screen(point))
	revision += 1


func can_see_position(world_position: Vector2) -> bool:
	if world_map == null:
		return false
	var offset := world_position - viewer_position
	if offset.length() > vision_radius:
		return false
	if offset.length() > SELF_VISION_RADIUS:
		var delta_angle := absf(wrapf(offset.angle() - facing_direction.angle(), -PI, PI))
		if delta_angle > half_fov_radians:
			return false
	return world_map.has_line_of_sight(viewer_position, world_position)


func can_see_wall(wall_position: Vector2) -> bool:
	var directions: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for direction in directions:
		var wall_edge_view := wall_position + direction * 0.51
		if world_map.is_walkable(wall_edge_view) and can_see_position(wall_edge_view):
			return true
	return false


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
	for wall_face in world_map.wall_face_segments:
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


func is_tile_visible(cell: Vector2i) -> bool:
	return visible_tiles.has(cell)


func was_tile_seen(cell: Vector2i) -> bool:
	return seen_tiles.has(cell)
