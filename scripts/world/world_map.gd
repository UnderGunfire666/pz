class_name WorldMap
extends Node

## Simulation authority: sparse floor support, wall faces, stairs and navigation.
const WIDTH := 64 # Legacy compatibility; use width for authored maps.
const HEIGHT := 64 # Legacy compatibility; use height for authored maps.
const FLOOR_HEIGHT := 3.0
const ACTOR_RADIUS := 0.22
const NAV_GRID_STEP := 0.5
const NAV_NEAREST_RADIUS_CELLS := 4
# Grid neighbours are at most 0.71 units apart.  During graph construction we
# only need to prove terrain support between already-valid endpoints; sampling
# that short segment every 0.07 units made navigation initialization dominate
# startup on even the small Orangeville map.  Wall clearance remains exact.
const NAV_NEIGHBOUR_SUPPORT_STEP := 0.20
const BASELINE_ZOMBIE_PRESSURE := 0.1
const SPATIAL_QUERY_INDEX = preload("res://scripts/world/spatial_query_index.gd")
const DEFAULT_MAP: MapDefinition = preload("res://resources/maps/orangeville_prototype.tres")
@export var definition: MapDefinition = DEFAULT_MAP
var width := 64
var height := 64
var floor_height := FLOOR_HEIGHT
var floors: Dictionary = {}
var buildings: Dictionary = {}
var stairs: Dictionary = {}
var revision := 0
var _navigation := AStar3D.new()
var _nav_points: Dictionary = {}
var _floor_node_ids: Dictionary = {}
var _nav_grid_ids: Dictionary = {}
var _stair_nav_ids: Dictionary = {}
var _stair_node_pairs: Array[Vector2i] = []
var _last_navigation_grid_entries_scanned := 0
var _last_nearest_nav_candidates := 0
var _zombie_areas := ZombieAreaCatalog.new()
var _wall_index := SPATIAL_QUERY_INDEX.new()
var _stair_index := SPATIAL_QUERY_INDEX.new()
var _spatial_index_ready := false


func _ready() -> void:
	load_definition(definition)


func load_definition(value: MapDefinition, build_navigation: bool = true) -> void:
	var started_usec := Time.get_ticks_usec()
	definition = value if value != null else DEFAULT_MAP
	width = 0
	height = 0
	floor_height = definition.default_floor_spacing
	floors.clear()
	buildings.clear()
	stairs.clear()
	_spatial_index_ready = false
	for cell: MapCellDefinition in definition.cells:
		width = max(width, cell.cell_coordinate.x * cell.size.x + cell.size.x)
		height = max(height, cell.cell_coordinate.y * cell.size.y + cell.size.y)
		for authored_level: MapLevelDefinition in cell.levels:
			if not floors.has(authored_level.level):
				floors[authored_level.level] = FloorData.new(authored_level.level)
			for paint: MapTerrainPaint in authored_level.terrain_paints:
				if not paint.is_override:
					_apply_terrain_paint(cell, authored_level.level, paint)
	# Explicit cell paints deliberately run last: they are local overrides over
	# deterministic macro output such as roads.
	for cell: MapCellDefinition in definition.cells:
		for authored_level: MapLevelDefinition in cell.levels:
			for paint: MapTerrainPaint in authored_level.terrain_paints:
				if paint.is_override:
					_apply_terrain_paint(cell, authored_level.level, paint)
	for road: MapRoadDefinition in definition.roads:
		_apply_road(road)
	_apply_heat_paints()
	if definition.format_version < 2:
		_apply_zones()
	for indoor_floor: MapIndoorFloorDefinition in definition.indoor_floors:
		_apply_indoor_floor(indoor_floor)
	for building: MapBuildingInstanceDefinition in definition.buildings:
		_make_building(building)
	for edge: MapWallEdgeDefinition in definition.wall_edges:
		if edge.kind != "wall":
			if not floors.has(edge.level): floors[edge.level] = FloorData.new(edge.level)
			floors[edge.level].visual_edges.append({"start": edge.start, "end": edge.end, "building_id": edge.building_id, "kind": edge.kind})
		if edge.kind == "wall" and not edge.initially_open and edge.initially_intact:
			if not floors.has(edge.level): floors[edge.level] = FloorData.new(edge.level)
			_add_wall(edge.start, edge.end, edge.building_id, edge.level)
	for stair: MapStairDefinition in definition.stairs:
		_add_stair(stair)
	for decoration: MapDecorationDefinition in definition.decorations:
		var tile := get_tile(decoration.position, decoration.level)
		if tile != null:
			tile.occupancy_kind = "decoration"
			tile.occupancy_id = decoration.id
	# Version-one maps used rectangular zones as their only authored heat data.
	# Retain this read-only migration path so old map resources remain playable;
	# new maps author heat directly on MapLevelDefinition instead.
	rebuild_spatial_index()
	var navigation_started_usec := Time.get_ticks_usec()
	if build_navigation:
		_build_navigation()
	print("[Startup/Map] Geometry + spatial index: %.2f ms; navigation: %.2f ms" % [
		float(navigation_started_usec - started_usec) / 1000.0,
		float(Time.get_ticks_usec() - navigation_started_usec) / 1000.0])
	revision += 1


func _apply_terrain_paint(cell: MapCellDefinition, level: int, paint: MapTerrainPaint) -> void:
	if paint.terrain == null:
		return
	var offset := cell.cell_coordinate * cell.size + paint.rect.position
	var rect := Rect2i(offset, paint.rect.size)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x < 0 or y < 0 or x >= width or y >= height:
				continue
			var terrain := paint.terrain
			var existing := (floors[level] as FloorData).tile_at(Vector2i(x, y))
			# Terrain remains the base layer. A late override must not erase an
			# independent road or indoor surface placed over it.
			if existing != null and existing.is_occupied():
				if terrain.category != "water":
					existing.base_kind = terrain.category
					existing.base_walkable = terrain.passable
				continue
			var pressure := 0.0 if terrain.category == "water" else BASELINE_ZOMBIE_PRESSURE
			(floors[level] as FloorData).tiles[Vector2i(x, y)] = WorldTileData.new(
				terrain.visual_recipe, terrain.passable, pressure, "", "", false, level,
				terrain.category, terrain.passable)


func _apply_road(road: MapRoadDefinition) -> void:
	if road.terrain == null:
		return
	if not floors.has(road.level):
		floors[road.level] = FloorData.new(road.level)
	if not road.grid_cells.is_empty():
		for cell: Vector2i in road.grid_cells:
			var tile := get_tile_at(cell, road.level)
			if tile != null and not tile.is_water():
				tile.set_overlay(road.terrain.visual_recipe, road.terrain.passable, "road", road.id)
		return
	if road.centerline.size() < 2: return
	for index in range(road.centerline.size() - 1):
		var start := road.centerline[index]
		var end := _clip_road_segment_to_water(start, road.centerline[index + 1], road.level)
		if end.distance_to(start) < 0.01:
			continue
		var bounds := Rect2(start, Vector2.ZERO).expand(end).grow(road.width * 0.5)
		for y in range(maxi(0, int(floor(bounds.position.y))), mini(height, int(ceil(bounds.end.y)))):
			for x in range(maxi(0, int(floor(bounds.position.x))), mini(width, int(ceil(bounds.end.x)))):
				var center := Vector2(x + 0.5, y + 0.5)
				if center.distance_to(Geometry2D.get_closest_point_to_segment(center, start, end)) > road.width * 0.5:
					continue
				var tile := get_tile_at(Vector2i(x, y), road.level)
				# Roads are overlays.  They cannot cross water, and an independently
				# authored indoor floor/building owns the visible surface instead.
				if tile == null or tile.is_water() or (tile.is_occupied() and tile.occupancy_kind != "road"):
					continue
				var terrain := road.terrain
				tile.set_overlay(terrain.visual_recipe, terrain.passable, "road", road.id)


func _clip_road_segment_to_water(start: Vector2, end: Vector2, level: int) -> Vector2:
	## Source roads are stored as strokes, but water is an absolute boundary. The
	## first water cell ends a stroke instead of allowing it to resume on the
	## far shore when the resource is later rebuilt at runtime.
	var steps := maxi(1, int(ceil(start.distance_to(end) * 4.0)))
	var last_safe := start
	for index in range(steps + 1):
		var sample := start.lerp(end, float(index) / float(steps))
		var tile := get_tile(sample, level)
		if tile == null or tile.is_water():
			return last_safe
		last_safe = sample
	return end


func _apply_indoor_floor(source: MapIndoorFloorDefinition, origin: Vector2i = Vector2i.ZERO,
		fallback_building_id: String = "", fallback_safehouse: bool = false) -> void:
	if source.terrain == null or source.rect.size.x <= 0 or source.rect.size.y <= 0:
		return
	if not floors.has(source.level):
		floors[source.level] = FloorData.new(source.level)
	var floor_data: FloorData = floors[source.level]
	var building_id := source.building_id if not source.building_id.is_empty() else fallback_building_id
	var room_id := source.room_id if not source.room_id.is_empty() else "%s_%d" % [building_id, source.level]
	for y in range(source.rect.position.y, source.rect.end.y):
		for x in range(source.rect.position.x, source.rect.end.x):
			var position := origin + Vector2i(x, y)
			if position.x < 0 or position.y < 0 or position.x >= width or position.y >= height:
				continue
			var base := floor_data.tile_at(position)
			if base != null and base.is_water():
				continue
			var base_kind := base.base_kind if base != null else "grass"
			var base_walkable := base.base_walkable if base != null else true
			floor_data.tiles[position] = WorldTileData.new(source.terrain.visual_recipe,
				source.terrain.passable, source.zombie_pressure, building_id, room_id,
				source.safehouse or fallback_safehouse, source.level, base_kind, base_walkable,
				source.terrain.visual_recipe, "building", building_id)


func _apply_zones() -> void:
	var ordered := definition.zones.duplicate()
	ordered.sort_custom(func(a: MapZoneDefinition, b: MapZoneDefinition) -> bool: return a.priority < b.priority)
	for zone: MapZoneDefinition in ordered:
		if zone.kind != "zombie_pressure" or not floors.has(zone.level):
			continue
		for y in range(zone.rect.position.y, zone.rect.end.y):
			for x in range(zone.rect.position.x, zone.rect.end.x):
				var tile := get_tile_at(Vector2i(x, y), zone.level)
				if tile != null:
					tile.zombie_pressure = zone.pressure


func _apply_heat_paints() -> void:
	for cell: MapCellDefinition in definition.cells:
		for authored_level: MapLevelDefinition in cell.levels:
			for paint: MapHeatPaint in authored_level.heat_paints:
				var offset := cell.cell_coordinate * cell.size + paint.rect.position
				var rect := Rect2i(offset, paint.rect.size)
				for y in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						var tile := get_tile_at(Vector2i(x, y), authored_level.level)
						if tile != null and not tile.is_water():
							tile.zombie_pressure = paint.pressure


func _area_pressure(id: String) -> float:
	var definition := _zombie_areas.area(id)
	return definition.pressure if definition != null else 0.0


func _make_building(source: MapBuildingInstanceDefinition) -> void:
	var bounds := source.effective_bounds()
	var floor_count := source.effective_floor_count()
	var door_cell := source.effective_door_cell()
	var building := BuildingData.new(source.id, source.effective_display_name(), bounds, source.effective_zone_type(),
		source.zombie_pressure, source.safehouse)
	buildings[source.id] = building
	building.has_roof = source.template == null or source.template.has_roof
	for level in range(floor_count):
		if not floors.has(level):
			floors[level] = FloorData.new(level)
		var floor_data: FloorData = floors[level]
		_add_authored_rooms(source, building, floor_data, bounds, level)
		var uses_explicit_surfaces := source.template != null and (source.template.explicit_layout or not source.template.indoor_floors.is_empty())
		if uses_explicit_surfaces:
			for surface: MapIndoorFloorDefinition in source.template.indoor_floors:
				if surface.level == level:
					_apply_indoor_floor(surface, source.origin, source.id, source.safehouse)
		else:
			# Compatibility path for the prototype's pre-layered rectangle buildings.
			for y in range(bounds.position.y, bounds.end.y):
				for x in range(bounds.position.x, bounds.end.x):
					var cell := Vector2i(x, y)
					var edge := x == bounds.position.x or x == bounds.end.x - 1 or y == bounds.position.y or y == bounds.end.y - 1
					var is_door := level == 0 and cell == door_cell
					var room := _room_for_cell(floor_data.rooms, cell, level)
					var existing := floor_data.tile_at(cell)
					if existing != null and existing.is_water():
						continue
					var base_kind := existing.base_kind if existing != null else "grass"
					var base_walkable := existing.base_walkable if existing != null else true
					floor_data.tiles[cell] = WorldTileData.new("floor", true, source.zombie_pressure, source.id,
						room.id if room != null else "%s_%d" % [source.id, level], source.safehouse, level,
						base_kind, base_walkable, "floor", "building", source.id)
					if not edge or is_door:
						continue
					if y == bounds.position.y:
						_add_wall(Vector2(x, y + 0.18), Vector2(x + 1, y + 0.18), source.id, level)
					if y == bounds.end.y - 1:
						_add_wall(Vector2(x, y + 0.82), Vector2(x + 1, y + 0.82), source.id, level)
					if x == bounds.position.x:
						_add_wall(Vector2(x + 0.18, y), Vector2(x + 0.18, y + 1), source.id, level)
					if x == bounds.end.x - 1:
						_add_wall(Vector2(x + 0.82, y), Vector2(x + 0.82, y + 1), source.id, level)
		_add_template_walls(source, level)
	if source.template != null:
		for local_stair: MapStairDefinition in source.template.stairs:
			var authored := local_stair.duplicate(true) as MapStairDefinition
			authored.id = source.id + ":" + local_stair.id
			authored.building_id = source.id
			authored.start += Vector2(source.origin)
			authored.end += Vector2(source.origin)
			for index in range(authored.opening_cells.size()): authored.opening_cells[index] += source.origin
			_add_stair(authored)


func _add_template_walls(source: MapBuildingInstanceDefinition, level: int) -> void:
	if source.template == null:
		return
	for edge: MapWallEdgeDefinition in source.template.wall_edges:
		if edge.level != level or not edge.initially_intact:
			continue
		# Template edges are local-space, so a reusable building remains portable.
		var origin := Vector2(source.origin)
		if edge.kind != "wall":
			floors[level].visual_edges.append({"start": origin + edge.start, "end": origin + edge.end, "building_id": source.id, "kind": edge.kind})
		elif not edge.initially_open:
			_add_wall(origin + edge.start, origin + edge.end, source.id, level)


func _add_authored_rooms(source: MapBuildingInstanceDefinition, building: BuildingData,
		floor_data: FloorData, bounds: Rect2i, level: int) -> void:
	var authored := false
	if source.template != null:
		for definition: MapRoomDefinition in source.template.rooms:
			if definition.floor_level != level:
				continue
			var room_bounds := Rect2i(source.origin + definition.bounds.position, definition.bounds.size)
			var room := RoomData.new("%s_%s" % [source.id, definition.id], definition.display_name,
				room_bounds, [definition.room_type], level)
			building.add_room(room)
			floor_data.rooms.append(room)
			authored = true
	if not authored:
		var fallback := RoomData.new("%s_%d" % [source.id, level], "%s / %d" % [source.effective_display_name(), level + 1], bounds, ["interior"], level)
		building.add_room(fallback)
		floor_data.rooms.append(fallback)


func _room_for_cell(rooms: Array[RoomData], cell: Vector2i, level: int) -> RoomData:
	for room: RoomData in rooms:
		if room.floor_level == level and room.bounds.has_point(cell):
			return room
	return null


func _add_wall(start: Vector2, end: Vector2, building: String, level: int) -> void:
	floors[level].wall_faces.append({"start": start, "end": end, "building_id": building})
	_spatial_index_ready = false


func _add_stair(source: MapStairDefinition) -> void:
	_spatial_index_ready = false
	if floors.has(source.to_floor):
		for cell: Vector2i in source.opening_cells:
			floors[source.to_floor].tiles.erase(cell)
	stairs[source.id] = StairLink.new(source.id, source.building_id, source.start, source.end,
		source.from_floor, source.to_floor, source.width)
	if buildings.has(source.building_id):
		(buildings[source.building_id] as BuildingData).stair_ids.append(source.id)


func floor_levels() -> Array:
	var result := floors.keys()
	result.sort()
	return result


func wall_faces(level: int) -> Array[Dictionary]:
	var data: FloorData = floors.get(level)
	return data.wall_faces if data != null else []


func rebuild_spatial_index() -> void:
	# Call after bulk direct edits to FloorData/stairs. Normal load/add APIs
	# invalidate automatically. This rebuilds queries, not the navigation graph.
	_wall_index.clear()
	_stair_index.clear()
	for level: int in floors:
		for face in wall_faces(level):
			_wall_index.insert(level, Rect2(face["start"], Vector2.ZERO).expand(face["end"]), face)
	for link: StairLink in stairs.values():
		var bounds := Rect2(link.start, Vector2.ZERO).expand(link.end).grow(maxf(link.width * 0.5, 0.28))
		_stair_index.insert(link.from_floor, bounds, link)
		if link.to_floor != link.from_floor:
			_stair_index.insert(link.to_floor, bounds, link)
	_spatial_index_ready = true


func query_walls(level: int, bounds: Rect2) -> Array:
	if not _spatial_index_ready: rebuild_spatial_index()
	return _wall_index.query(level, bounds)


func query_stairs(level: int, bounds: Rect2) -> Array:
	if not _spatial_index_ready: rebuild_spatial_index()
	return _stair_index.query(level, bounds)


func stairs_on_floor(level: int) -> Array:
	if not _spatial_index_ready: rebuild_spatial_index()
	return _stair_index.all_on_floor(level)


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
	for link: StairLink in query_stairs(level, Rect2(pos, Vector2.ZERO).grow(margin)):
		if level != link.from_floor and level != link.to_floor:
			continue
		var offset := pos - link.start
		var along := offset.dot(link.direction())
		if along > StairLink.LANDING_LENGTH and along < link.length() - StairLink.LANDING_LENGTH and absf(offset.cross(link.direction())) < link.width * 0.5 + margin:
			return true
	return false


func _valid_position(pos: Vector2, level: int, radius: float = ACTOR_RADIUS) -> bool:
	if not _supported_position(pos, level, radius):
		return false
	for face in query_walls(level, Rect2(pos, Vector2.ZERO).grow(radius)):
		if pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, face["start"], face["end"])) < radius:
			return false
	return true


func _supported_position(pos: Vector2, level: int, radius: float = ACTOR_RADIUS) -> bool:
	if not is_walkable(pos, level) or _inside_stair_body(pos, level, radius):
		return false
	for offset in [Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
		var tile := get_tile(pos + offset, level)
		if tile == null or not tile.walkable:
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
	for link: StairLink in query_stairs(level, Rect2(pos, Vector2.ZERO).grow(0.28)):
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
		return lerpf(link.from_floor * floor_height, link.to_floor * floor_height, link.progress_at(pos))
	return float(level) * floor_height


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
	for face in query_walls(level, Rect2(from, Vector2.ZERO).expand(to)):
		if Geometry2D.segment_intersects_segment(from, to, face["start"], face["end"]) != null:
			return false
	return true


func pressure_at(pos: Vector2, level: int = 0) -> float:
	var tile := get_tile(pos, level)
	return tile.zombie_pressure if tile != null else 0.0


func initial_zombie_spawn_candidates() -> Array[Dictionary]:
	## Called only during world initialization.  Keeping it here avoids a second
	## map interpretation in ZombieSpawner and includes every authored floor.
	var candidates: Array[Dictionary] = []
	for level: int in floor_levels():
		var data: FloorData = floors[level]
		for cell: Vector2i in data.tiles:
			var tile: WorldTileData = data.tiles[cell]
			if tile.zombie_pressure <= 0.0 or tile.is_water():
				continue
			var position := Vector2(cell) + Vector2(0.5, 0.5)
			if can_stand(position, level):
				candidates.append({"position": position, "floor": level, "weight": tile.zombie_pressure})
	return candidates


func zombie_area_id_at(pos: Vector2, level: int = 0) -> String:
	var tile := get_tile(pos, level)
	if tile == null: return ""
	if not tile.building_id.is_empty(): return tile.building_id
	return "roads" if tile.occupancy_kind == "road" or tile.kind == "road" else "outskirts"


func stress_at(pos: Vector2, nearby_zombies: int = 0, level: int = 0) -> float:
	return clampf(pressure_at(pos, level) * 55.0 + nearby_zombies * 13.0 + (1.0 - ambient_light()) * 16.0, 0.0, 100.0)


func is_safehouse(pos: Vector2, level: int = 0) -> bool:
	var tile := get_tile(pos, level)
	return tile != null and tile.is_safehouse


func ambient_light() -> float:
	var hour := fmod(GameTime.elapsed_game_seconds, 86400.0) / 3600.0
	return clampf(0.22 + maxf(0.0, sin((hour - 6.0) * PI / 12.0)) * 0.78, 0.22, 1.0)


func _segment_has_support(from: Vector2, to: Vector2, level: int,
		sample_step: float, include_endpoints: bool = true) -> bool:
	var count := maxi(1, int(ceil(from.distance_to(to) / sample_step)))
	var first := 0 if include_endpoints else 1
	var last := count if include_endpoints else count - 1
	for index in range(first, last + 1):
		if not _supported_position(from.lerp(to, float(index) / float(count)), level):
			return false
	return true


func _segment_has_wall_clearance(from: Vector2, to: Vector2, level: int) -> bool:
	# Exact segment clearance avoids sampling past a short wall endpoint. Check
	# each candidate wall once, rather than once for every terrain support probe.
	var corridor := Rect2(from, Vector2.ZERO).expand(to).grow(ACTOR_RADIUS)
	for face in query_walls(level, corridor):
		var a: Vector2 = face["start"]
		var b: Vector2 = face["end"]
		if not corridor.intersects(Rect2(a, Vector2.ZERO).expand(b), true):
			continue
		if Geometry2D.segment_intersects_segment(from, to, a, b) != null:
			return false
		if from.distance_to(Geometry2D.get_closest_point_to_segment(from, a, b)) < ACTOR_RADIUS:
			return false
		if to.distance_to(Geometry2D.get_closest_point_to_segment(to, a, b)) < ACTOR_RADIUS:
			return false
		if a.distance_to(Geometry2D.get_closest_point_to_segment(a, from, to)) < ACTOR_RADIUS:
			return false
		if b.distance_to(Geometry2D.get_closest_point_to_segment(b, from, to)) < ACTOR_RADIUS:
			return false
	return true


func _segment_walkable(from: Vector2, to: Vector2, level: int) -> bool:
	return _segment_has_support(from, to, level, 0.07) and _segment_has_wall_clearance(from, to, level)


func _add_nav_point(pos: Vector2, level: int) -> int:
	var id := _navigation.get_point_count()
	_navigation.add_point(id, Vector3(pos.x, level * floor_height, pos.y))
	_nav_points[id] = {"position": pos, "floor": level}
	var ids: Array = _floor_node_ids.get(level, [])
	ids.append(id)
	_floor_node_ids[level] = ids
	return id


func _build_navigation() -> void:
	_navigation.clear()
	_nav_points.clear()
	_floor_node_ids.clear()
	_nav_grid_ids.clear()
	_stair_nav_ids.clear()
	_stair_node_pairs.clear()
	for level: int in floor_levels():
		for y in range(int(ceil(float(height) / NAV_GRID_STEP))):
			for x in range(int(ceil(float(width) / NAV_GRID_STEP))):
				var pos := Vector2((float(x) + 0.5) * NAV_GRID_STEP, (float(y) + 0.5) * NAV_GRID_STEP)
				if _valid_position(pos, level):
					var id := _add_nav_point(pos, level)
					_nav_grid_ids[Vector3i(x, y, level)] = id
	# Each grid key is visited exactly once. Previously every completed floor
	# re-scanned every earlier floor and skipped it after the fact.
	_last_navigation_grid_entries_scanned = _nav_grid_ids.size()
	for key: Vector3i in _nav_grid_ids:
		var from_id := int(_nav_grid_ids[key])
		var from: Vector2 = _nav_points[from_id]["position"]
		for offset in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(1, -1)]:
			var neighbour_key := Vector3i(key.x + offset.x, key.y + offset.y, key.z)
			if not _nav_grid_ids.has(neighbour_key):
				continue
			var to_id := int(_nav_grid_ids[neighbour_key])
			var to: Vector2 = _nav_points[to_id]["position"]
			if _nav_grid_neighbours_connect(from, to, key.z):
				_navigation.connect_points(from_id, to_id)
	for link: StairLink in stairs.values():
		var low := _add_nav_point(link.start, link.from_floor)
		var high := _add_nav_point(link.end, link.to_floor)
		_stair_nav_ids[link.from_floor] = _stair_nav_ids.get(link.from_floor, []) + [low]
		_stair_nav_ids[link.to_floor] = _stair_nav_ids.get(link.to_floor, []) + [high]
		_stair_node_pairs.append(Vector2i(low, high))
		_connect_stair_landing(low, link.start, link.from_floor)
		_connect_stair_landing(high, link.end, link.to_floor)
	for pair in _stair_node_pairs:
		_navigation.connect_points(pair.x, pair.y)


func _connect_stair_landing(stair_node: int, position: Vector2, level: int) -> void:
	var center := Vector2i(floor(position.x / NAV_GRID_STEP), floor(position.y / NAV_GRID_STEP))
	for y in range(center.y - 2, center.y + 3):
		for x in range(center.x - 2, center.x + 3):
			var key := Vector3i(x, y, level)
			if not _nav_grid_ids.has(key):
				continue
			var node := int(_nav_grid_ids[key])
			var target: Vector2 = _nav_points[node]["position"]
			if target.distance_squared_to(position) <= 1.44 and _segment_walkable(position, target, level):
				_navigation.connect_points(stair_node, node)


func _nav_neighbours_connect(from: Vector2, to: Vector2, level: int) -> bool:
	# Public/helper path used by validation. Keep endpoint validation here, while
	# the startup builder can skip it because every graph node was already passed
	# through _valid_position before this method is reached.
	return _supported_position(from, level) and _supported_position(to, level) \
		and _nav_grid_neighbours_connect(from, to, level)


func _nav_grid_neighbours_connect(from: Vector2, to: Vector2, level: int) -> bool:
	# A grid edge is short and both endpoints are known valid. Probe only its
	# interior for void/stair support, at less than the actor radius, then use an
	# analytic wall-capsule check so narrow walls and their endpoints remain
	# impassable without the former dense collision sampling.
	return _segment_has_support(from, to, level, NAV_NEIGHBOUR_SUPPORT_STEP, false) \
		and _segment_has_wall_clearance(from, to, level)


func _nearest_nav(pos: Vector2, level: int) -> int:
	var nearest := -1
	var distance := INF
	var candidates: Dictionary = {}
	var center := Vector2i(floor(pos.x / NAV_GRID_STEP), floor(pos.y / NAV_GRID_STEP))
	for y in range(center.y - NAV_NEAREST_RADIUS_CELLS, center.y + NAV_NEAREST_RADIUS_CELLS + 1):
		for x in range(center.x - NAV_NEAREST_RADIUS_CELLS, center.x + NAV_NEAREST_RADIUS_CELLS + 1):
			var grid_key := Vector3i(x, y, level)
			if _nav_grid_ids.has(grid_key):
				candidates[_nav_grid_ids[grid_key]] = true
	# Stair endpoints are sparse non-grid nodes and remain eligible even when
	# the caller starts exactly on a landing.
	for id: int in _stair_nav_ids.get(level, []):
		candidates[id] = true
	_last_nearest_nav_candidates = candidates.size()
	for id: int in candidates:
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
		for face in query_walls(from_floor, Rect2(from, Vector2.ZERO).expand(to)):
			if Geometry2D.segment_intersects_segment(from, to, face["start"], face["end"]) != null:
				cost += 2.5
		return cost
	# Stair mouths carry sound vertically. No broadcast to disconnected buildings.
	var best := INF
	for link: StairLink in stairs_on_floor(from_floor):
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
