class_name WorldMap
extends Node

## Simulation authority: sparse floor support, wall faces, stairs and navigation.
const WIDTH := 18
const HEIGHT := 14
const FLOOR_HEIGHT := 3.0
const ACTOR_RADIUS := 0.22
var floors: Dictionary = {}
var buildings: Dictionary = {}
var stairs: Dictionary = {}
var revision := 0
var _navigation := AStar3D.new()
var _nav_points: Dictionary = {}
var _floor_node_ids: Dictionary = {}
var _stair_node_pairs: Array[Vector2i] = []
var _zombie_areas := ZombieAreaCatalog.new()


func _ready() -> void:
	_build_demo_map()


func _build_demo_map() -> void:
	floors.clear()
	buildings.clear()
	stairs.clear()
	floors[0] = FloorData.new(0)
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var road := y == 7 or x == 8
			floors[0].tiles[Vector2i(x, y)] = WorldTileData.new("road" if road else "grass", true,
				_area_pressure("roads" if road else "outskirts"))
	_make_building("safehouse", "Miller House", Rect2i(2, 2, 5, 4), Vector2i(4, 5), 2, _area_pressure("safehouse"), true)
	_make_building("corner_store", "Corner Grocery", Rect2i(10, 2, 7, 7), Vector2i(13, 8), 3, _area_pressure("corner_store"))
	_make_building("neighbour_house", "Neighbour House", Rect2i(2, 9, 4, 3), Vector2i(3, 11), 2, _area_pressure("neighbour_house"))
	_add_stair("safehouse_0_1", "safehouse", Vector2(3.25, 4.5), Vector2(5.75, 4.5), 0, 1, 0.72)
	_add_stair("neighbour_0_1", "neighbour_house", Vector2(2.7, 9.7), Vector2(5.3, 9.7), 0, 1, 0.72)
	_add_stair("grocery_0_1", "corner_store", Vector2(11.25, 7.25), Vector2(11.25, 3.75), 0, 1)
	_add_stair("grocery_1_2", "corner_store", Vector2(12.25, 3.75), Vector2(12.25, 7.25), 1, 2)
	# Different upper layouts prove that collision/LOS do not reuse ground walls.
	_add_wall(Vector2(13.4, 4.6), Vector2(16.82, 4.6), "corner_store", 1)
	_add_wall(Vector2(14.0, 2.18), Vector2(14.0, 4.0), "corner_store", 2)
	_build_navigation()
	revision += 1


func _area_pressure(id: String) -> float:
	var definition := _zombie_areas.area(id)
	return definition.pressure if definition != null else 0.0


func _make_building(id: String, title: String, bounds: Rect2i, door: Vector2i,
		count: int, pressure: float, safehouse: bool = false) -> void:
	var building := BuildingData.new(id, title, bounds, "commercial" if id == "corner_store" else "residential", pressure, safehouse)
	buildings[id] = building
	for level in range(count):
		if not floors.has(level):
			floors[level] = FloorData.new(level)
		var floor_data: FloorData = floors[level]
		var room := RoomData.new("%s_%d" % [id, level], "%s / %d" % [title, level + 1], bounds, ["interior"], level)
		building.add_room(room)
		floor_data.rooms.append(room)
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				var cell := Vector2i(x, y)
				var edge := x == bounds.position.x or x == bounds.end.x - 1 or y == bounds.position.y or y == bounds.end.y - 1
				var is_door := level == 0 and cell == door
				var kind := "door" if is_door else ("wall" if edge else "floor")
				floor_data.tiles[cell] = WorldTileData.new(kind, true, pressure, id, room.id, safehouse, level)
				if not edge or is_door:
					continue
				if y == bounds.position.y:
					_add_wall(Vector2(x, y + 0.18), Vector2(x + 1, y + 0.18), id, level)
				if y == bounds.end.y - 1:
					_add_wall(Vector2(x, y + 0.82), Vector2(x + 1, y + 0.82), id, level)
				if x == bounds.position.x:
					_add_wall(Vector2(x + 0.18, y), Vector2(x + 0.18, y + 1), id, level)
				if x == bounds.end.x - 1:
					_add_wall(Vector2(x + 0.82, y), Vector2(x + 0.82, y + 1), id, level)


func _add_wall(start: Vector2, end: Vector2, building: String, level: int) -> void:
	floors[level].wall_faces.append({"start": start, "end": end, "building_id": building})


func _add_stair(id: String, building: String, start: Vector2, end: Vector2,
		from_floor: int, to_floor: int, width: float = 0.8) -> void:
	stairs[id] = StairLink.new(id, building, start, end, from_floor, to_floor, width)
	buildings[building].stair_ids.append(id)


func floor_levels() -> Array:
	var result := floors.keys()
	result.sort()
	return result


func wall_faces(level: int) -> Array[Dictionary]:
	var data: FloorData = floors.get(level)
	return data.wall_faces if data != null else []


func get_tile(pos: Vector2, level: int = 0) -> WorldTileData:
	return get_tile_at(Vector2i(pos.floor()), level)


func get_tile_at(cell: Vector2i, level: int = 0) -> WorldTileData:
	var data: FloorData = floors.get(level)
	return data.tile_at(cell) if data != null else null


func is_walkable(pos: Vector2, level: int = 0) -> bool:
	var tile := get_tile(pos, level)
	return tile != null and tile.walkable and not _inside_stair_body(pos, level)


func can_stand(pos: Vector2, level: int = 0) -> bool:
	return _valid_position(pos, level)


func _inside_stair_body(pos: Vector2, level: int, margin: float = 0.0) -> bool:
	for link: StairLink in stairs.values():
		if level != link.from_floor and level != link.to_floor:
			continue
		var offset := pos - link.start
		var along := offset.dot(link.direction())
		if along > StairLink.LANDING_LENGTH and along < link.length() - StairLink.LANDING_LENGTH and absf(offset.cross(link.direction())) < link.width * 0.5 + margin:
			return true
	return false


func _valid_position(pos: Vector2, level: int, radius: float = ACTOR_RADIUS) -> bool:
	if not is_walkable(pos, level) or _inside_stair_body(pos, level, radius):
		return false
	for offset in [Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
		var tile := get_tile(pos + offset, level)
		if tile == null or not tile.walkable:
			return false
	for face in wall_faces(level):
		if pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, face["start"], face["end"])) < radius:
			return false
	return true


func move_with_wall_slide(pos: Vector2, motion: Vector2, radius: float = ACTOR_RADIUS, level: int = 0) -> Vector2:
	var steps := maxi(1, int(ceil(motion.length() / 0.07)))
	var step := motion / float(steps)
	for _index in range(steps):
		if _valid_position(pos + step, level, radius):
			pos += step
			continue
		var x_step := Vector2(step.x, 0)
		if _valid_position(pos + x_step, level, radius):
			pos += x_step
		var y_step := Vector2(0, step.y)
		if _valid_position(pos + y_step, level, radius):
			pos += y_step
	return pos


func move_actor(pos: Vector2, level: int, motion: Vector2, stair_id: String = "", radius: float = ACTOR_RADIUS) -> Dictionary:
	var state := {"position": pos, "floor": level, "stair_id": stair_id}
	var steps := maxi(1, int(ceil(motion.length() / 0.07)))
	for _index in range(steps):
		state = _move_step(state, motion / float(steps), radius)
	return state


func _move_step(state: Dictionary, motion: Vector2, radius: float) -> Dictionary:
	var pos: Vector2 = state["position"]
	var level := int(state["floor"])
	var id := String(state["stair_id"])
	if not id.is_empty() and stairs.has(id):
		var link: StairLink = stairs[id]
		var along := (pos - link.start).dot(link.direction()) + motion.dot(link.direction())
		if along <= 0.0:
			return {"position": link.start, "floor": link.from_floor, "stair_id": ""}
		if along >= link.length():
			return {"position": link.end, "floor": link.to_floor, "stair_id": ""}
		return {"position": link.start + link.direction() * along, "floor": level, "stair_id": id}
	for link: StairLink in stairs.values():
		var alignment := motion.normalized().dot(link.direction())
		var entering_up := level == link.from_floor and pos.distance_to(link.start) <= 0.28 and alignment > 0.85
		var entering_down := level == link.to_floor and pos.distance_to(link.end) <= 0.28 and alignment < -0.85
		if entering_up or entering_down:
			var along := clampf((pos - link.start).dot(link.direction()), 0.0, link.length())
			return _move_step({"position": link.start + link.direction() * along, "floor": level, "stair_id": link.id}, motion, radius)
	return {"position": move_with_wall_slide(pos, motion, radius, level), "floor": level, "stair_id": ""}


func elevation_at(pos: Vector2, level: int, stair_id: String = "") -> float:
	if not stair_id.is_empty() and stairs.has(stair_id):
		var link: StairLink = stairs[stair_id]
		return lerpf(link.from_floor * FLOOR_HEIGHT, link.to_floor * FLOOR_HEIGHT, link.progress_at(pos))
	return float(level) * FLOOR_HEIGHT


func display_floor_at(pos: Vector2, level: int, stair_id: String = "") -> int:
	if not stair_id.is_empty() and stairs.has(stair_id):
		var link: StairLink = stairs[stair_id]
		return link.to_floor if link.progress_at(pos) >= 0.5 else link.from_floor
	return level


func has_line_of_sight(from: Vector2, to: Vector2, level: int = 0, to_floor: int = -1) -> bool:
	if to_floor >= 0 and level != to_floor:
		return false
	if get_tile(from, level) == null or get_tile(to, level) == null:
		return false
	for face in wall_faces(level):
		if Geometry2D.segment_intersects_segment(from, to, face["start"], face["end"]) != null:
			return false
	return true


func pressure_at(pos: Vector2, level: int = 0) -> float:
	var tile := get_tile(pos, level)
	return tile.zombie_pressure if tile != null else 0.0


func zombie_area_id_at(pos: Vector2, level: int = 0) -> String:
	var tile := get_tile(pos, level)
	if tile == null: return ""
	if not tile.building_id.is_empty(): return tile.building_id
	return "roads" if tile.kind == "road" else "outskirts"


func stress_at(pos: Vector2, nearby_zombies: int = 0, level: int = 0) -> float:
	return clampf(pressure_at(pos, level) * 55.0 + nearby_zombies * 13.0 + (1.0 - ambient_light()) * 16.0, 0.0, 100.0)


func is_safehouse(pos: Vector2, level: int = 0) -> bool:
	var tile := get_tile(pos, level)
	return tile != null and tile.is_safehouse


func ambient_light() -> float:
	var hour := fmod(GameTime.elapsed_game_seconds, 86400.0) / 3600.0
	return clampf(0.22 + maxf(0.0, sin((hour - 6.0) * PI / 12.0)) * 0.78, 0.22, 1.0)


func _segment_walkable(from: Vector2, to: Vector2, level: int) -> bool:
	var count := maxi(1, int(ceil(from.distance_to(to) / 0.1)))
	for index in range(count + 1):
		if not _valid_position(from.lerp(to, float(index) / float(count)), level):
			return false
	return has_line_of_sight(from, to, level)


func _add_nav_point(pos: Vector2, level: int) -> int:
	var id := _navigation.get_point_count()
	_navigation.add_point(id, Vector3(pos.x, level * FLOOR_HEIGHT, pos.y))
	_nav_points[id] = {"position": pos, "floor": level}
	var ids: Array = _floor_node_ids.get(level, [])
	ids.append(id)
	_floor_node_ids[level] = ids
	return id


func _build_navigation() -> void:
	_navigation.clear()
	_nav_points.clear()
	_floor_node_ids.clear()
	_stair_node_pairs.clear()
	for level: int in floor_levels():
		for y in range(HEIGHT * 2):
			for x in range(WIDTH * 2):
				var pos := Vector2(x * 0.5 + 0.25, y * 0.5 + 0.25)
				if _valid_position(pos, level):
					_add_nav_point(pos, level)
	for link: StairLink in stairs.values():
		var low := _add_nav_point(link.start, link.from_floor)
		var high := _add_nav_point(link.end, link.to_floor)
		_stair_node_pairs.append(Vector2i(low, high))
	for level in _floor_node_ids:
		var ids: Array = _floor_node_ids[level]
		for index in range(ids.size()):
			var from: Vector2 = _nav_points[ids[index]]["position"]
			for next_index in range(index + 1, ids.size()):
				var to: Vector2 = _nav_points[ids[next_index]]["position"]
				if from.distance_squared_to(to) <= 0.81 and _segment_walkable(from, to, level):
					_navigation.connect_points(ids[index], ids[next_index])
	for pair in _stair_node_pairs:
		_navigation.connect_points(pair.x, pair.y)


func _nearest_nav(pos: Vector2, level: int) -> int:
	var nearest := -1
	var distance := INF
	for id: int in _floor_node_ids.get(level, []):
		var target: Vector2 = _nav_points[id]["position"]
		var squared := target.distance_squared_to(pos)
		if squared < distance and squared < 2.26 and _segment_walkable(pos, target, level):
			nearest = id
			distance = squared
	return nearest


func find_path(from: Vector2, from_floor: int, to: Vector2, to_floor: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _valid_position(from, from_floor) or not _valid_position(to, to_floor):
		return result
	if from_floor == to_floor and _segment_walkable(from, to, from_floor):
		return [{"position": to, "floor": to_floor}]
	var start := _nearest_nav(from, from_floor)
	var finish := _nearest_nav(to, to_floor)
	if start < 0 or finish < 0:
		return result
	var path := _navigation.get_id_path(start, finish)
	if path.is_empty():
		return result
	for id in path:
		result.append(_nav_points[id].duplicate())
	result.append({"position": to, "floor": to_floor})
	return result


func sound_cost(from: Vector2, from_floor: int, to: Vector2, to_floor: int) -> float:
	if get_tile(from, from_floor) == null or get_tile(to, to_floor) == null:
		return INF
	if from_floor == to_floor:
		var cost := from.distance_to(to)
		for face in wall_faces(from_floor):
			if Geometry2D.segment_intersects_segment(from, to, face["start"], face["end"]) != null:
				cost += 2.5
		return cost
	# Stair mouths carry sound vertically. No broadcast to disconnected buildings.
	var best := INF
	for link: StairLink in stairs.values():
		if from_floor != link.from_floor and from_floor != link.to_floor:
			continue
		var next_floor := link.to_floor if from_floor == link.from_floor else link.from_floor
		if absi(next_floor - to_floor) >= absi(from_floor - to_floor):
			continue
		var entry := link.start if from_floor == link.from_floor else link.end
		var exit := link.end if from_floor == link.from_floor else link.start
		var access := from.distance_to(entry) + (0.0 if has_line_of_sight(from, entry, from_floor) else 2.5)
		best = minf(best, access + 2.0 + link.length() * 0.35 + sound_cost(exit, next_floor, to, to_floor))
	return best
