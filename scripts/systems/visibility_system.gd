class_name VisibilitySystem
extends Node

## Fan-shaped player FOV. Actors use this same query so unseen zombies and NPCs
## are hidden rather than merely dimmed.
var world_map: WorldMap
var visible_tiles: Dictionary = {}
var seen_tiles: Dictionary = {}
signal tile_explored(key: Vector3i)
signal exploration_restored
var viewer_position := Vector2.ZERO
var facing_direction := Vector2.DOWN
var aim_mode := false
var viewer_floor := 0
var visible_world_polygon := PackedVector2Array()
var vision_radius := 0.0
var half_fov_radians := 0.0
var perception_multiplier := 1.0
const SELF_VISION_RADIUS := 1.2
# 128 rays produce a 2.8-degree contour, which remains smooth once rasterized
# into the filtered FOV mask while halving the wall-intersection work done on
# each meaningful player/FOV update.
const FOV_RAY_COUNT := 128
var revision := 0
var _last_world_revision := -1
var _last_light := -1.0


func setup(p_world_map: WorldMap) -> void:
	world_map = p_world_map


func refresh(next_viewer_position: Vector2, next_facing_direction: Vector2, next_aim_mode: bool,
		next_floor: int = 0, next_perception_multiplier: float = 1.0) -> void:
	if world_map == null:
		return
	var next_facing := next_facing_direction.normalized() if next_facing_direction.length_squared() > 0.001 else Vector2.DOWN
	var unchanged := (
		viewer_position.distance_squared_to(next_viewer_position) < 0.0025
		and facing_direction.dot(next_facing) > 0.999
		and aim_mode == next_aim_mode
		and viewer_floor == next_floor
		and is_equal_approx(perception_multiplier, next_perception_multiplier)
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
	perception_multiplier = clampf(next_perception_multiplier, 0.25, 1.0)
	_last_world_revision = world_map.revision
	_last_light = world_map.ambient_light()
	visible_tiles.clear()
	var viewer_cell := Vector2i(int(floor(viewer_position.x)), int(floor(viewer_position.y)))
	var viewer_key := Vector3i(viewer_cell.x, viewer_cell.y, viewer_floor)
	visible_tiles[viewer_key] = true
	_mark_seen(viewer_key)

	vision_radius = 6.6 * lerpf(0.55, 1.0, world_map.ambient_light()) * perception_multiplier
	half_fov_radians = deg_to_rad(68.0)
	# FOV is bounded by vision_radius.  Do not re-test an entire city whenever
	# the player takes a step; only cells which can possibly fall inside the
	# sight circle need a LOS query.
	var min_x := maxi(0, int(floor(viewer_position.x - vision_radius)))
	var max_x := mini(world_map.width - 1, int(floor(viewer_position.x + vision_radius)))
	var min_y := maxi(0, int(floor(viewer_position.y - vision_radius)))
	var max_y := mini(world_map.height - 1, int(floor(viewer_position.y + vision_radius)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			var target := Vector2(cell) + Vector2(0.5, 0.5)
			if can_see_position(target, viewer_floor):
				var key := Vector3i(x, y, viewer_floor)
				visible_tiles[key] = true
				_mark_seen(key)
	visible_world_polygon = _build_visibility_polygon()
	revision += 1


func can_see_position(world_position: Vector2, floor_level: int = 0) -> bool:
	if world_map == null or floor_level != viewer_floor:
		return false
	var offset := world_position - viewer_position
	if offset.length() > vision_radius:
		return false
	if offset.length() > SELF_VISION_RADIUS:
		var delta_angle := absf(wrapf(offset.angle() - facing_direction.angle(), -PI, PI))
		if delta_angle > half_fov_radians:
			return false
	return room_contents_allowed(world_position, floor_level)


func _mark_seen(key: Vector3i) -> void:
	if seen_tiles.has(key):
		return
	seen_tiles[key] = true
	tile_explored.emit(key)


func restore_exploration(tiles: Dictionary) -> void:
	seen_tiles = tiles.duplicate()
	invalidate()
	exploration_restored.emit()


func _room_at(position: Vector2, floor_level: int) -> String:
	var tile := world_map.get_tile(position, floor_level)
	return tile.room_id if tile != null else ""


func room_contents_allowed(position: Vector2, floor_level: int) -> bool:
	# Rooms are not opaque privacy volumes. Doorways and future open windows reveal
	# whatever the ordinary floor-aware LOS can actually reach; solid wall faces
	# still block the query regardless of rendering cutaways.
	return (world_map != null and floor_level == viewer_floor
		and world_map.has_line_of_sight(viewer_position, position, viewer_floor, floor_level))


func invalidate() -> void:
	_last_world_revision = -1


func _build_visibility_polygon() -> PackedVector2Array:
	var polygon := PackedVector2Array()
	var radius := maxf(vision_radius, SELF_VISION_RADIUS)
	var walls := world_map.query_walls(viewer_floor, Rect2(viewer_position, Vector2.ZERO).grow(radius))
	for ray_index in range(FOV_RAY_COUNT):
		var angle := TAU * float(ray_index) / float(FOV_RAY_COUNT)
		var direction := Vector2.from_angle(angle)
		var angle_from_facing := absf(wrapf(angle - facing_direction.angle(), -PI, PI))
		var ray_radius := vision_radius if angle_from_facing <= half_fov_radians else SELF_VISION_RADIUS
		polygon.append(_ray_endpoint(direction, ray_radius, walls))
	return polygon


func _ray_endpoint(direction: Vector2, max_distance: float, candidates: Array) -> Vector2:
	var ray_end := viewer_position + direction * max_distance
	var nearest_distance := max_distance
	for wall_face in candidates:
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
