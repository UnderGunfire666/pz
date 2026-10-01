@tool
extends RefCounted

## All methods operate on an isolated proposal. The dock commits it only after
## replacement confirmation, using one EditorUndoRedoManager action.
const GRASS = preload("res://resources/maps/terrain/grass.tres")
const INDOOR = preload("res://resources/maps/terrain/indoor_floor.tres")
const ASPHALT = preload("res://resources/maps/terrain/asphalt.tres")

static func uid(prefix: String) -> String:
	return "%s_%s" % [prefix, Resource.generate_scene_unique_id()]

static func snapshot(source: MapDefinition) -> MapDefinition:
	var result := source.duplicate(true) as MapDefinition
	for house in result.buildings:
		if house.template != null: house.template = house.template.duplicate(true)
	return result

static func copy_state(target: MapDefinition, source: MapDefinition) -> void:
	for property in source.get_property_list():
		var key: String = property.name
		if int(property.usage) & PROPERTY_USAGE_STORAGE and key != "script" and not key.begins_with("resource_"):
			target.set(key, source.get(key))
	target.emit_changed()

static func bounds(map: MapDefinition) -> Rect2i:
	var size := Vector2i.ZERO
	for cell in map.cells:
		size = size.max(cell.cell_coordinate * cell.size + cell.size)
	return Rect2i(Vector2i.ZERO, size)

static func create_map(size: Vector2i) -> MapDefinition:
	var map := MapDefinition.new()
	map.id = uid("map")
	map.display_name = "New map"
	map.cell_size = size
	var cell := MapCellDefinition.new()
	cell.id = uid("cell")
	cell.size = size
	var level := MapLevelDefinition.new()
	level.level = 0
	var paint := MapTerrainPaint.new()
	paint.id = uid("grass")
	paint.rect = Rect2i(Vector2i.ZERO, size)
	paint.terrain = GRASS
	level.terrain_paints.append(paint)
	cell.levels.append(level)
	map.cells.append(cell)
	map.player_spawn = Vector2(0.5, 0.5)
	map.npc_spawn = Vector2(0.5, 0.5)
	return map

static func adapter(map: MapDefinition) -> WorldMap:
	var world := WorldMap.new()
	world.load_definition(map, false)
	return world

static func cells(rect: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x): result.append(Vector2i(x, y))
	return result

static func house_at(map: MapDefinition, cell: Vector2i) -> MapBuildingInstanceDefinition:
	for house in map.buildings:
		if house.effective_bounds().has_point(cell): return house
	return null

static func normalize_house(map: MapDefinition, house: MapBuildingInstanceDefinition) -> void:
	if house.template != null and house.template.explicit_layout: return
	var world := adapter(map)
	var footprint := house.effective_bounds()
	var template := MapBuildingTemplate.new()
	template.id = uid("layout")
	template.display_name = house.effective_display_name()
	template.footprint = footprint.size
	template.floor_count = house.effective_floor_count()
	template.explicit_layout = true
	for level in range(template.floor_count):
		for cell in cells(footprint):
			var tile := world.get_tile_at(cell, level)
			if tile == null or tile.building_id != house.id: continue
			var floor := MapIndoorFloorDefinition.new()
			floor.id = uid("floor")
			floor.level = level
			floor.rect = Rect2i(cell - footprint.position, Vector2i.ONE)
			floor.terrain = INDOOR
			floor.zombie_pressure = tile.zombie_pressure
			template.indoor_floors.append(floor)
		for face: Dictionary in world.wall_faces(level):
			if face.get("building_id", "") != house.id: continue
			var edge := MapWallEdgeDefinition.new()
			edge.id = uid("wall")
			edge.level = level
			edge.start = face.start - Vector2(footprint.position)
			edge.end = face.end - Vector2(footprint.position)
			template.wall_edges.append(edge)
	for stair in map.stairs.duplicate():
		if stair.building_id != house.id: continue
		var local := stair.duplicate(true) as MapStairDefinition
		local.building_id = ""
		local.start -= Vector2(footprint.position)
		local.end -= Vector2(footprint.position)
		for index in range(local.opening_cells.size()): local.opening_cells[index] -= footprint.position
		template.stairs.append(local)
		map.stairs.erase(stair)
	world.free()
	house.origin = footprint.position
	house.template = template
	house.local_footprint_override = Vector2i.ZERO
	house.local_floor_count_override = -1
	map.wall_edges = map.wall_edges.filter(func(edge: MapWallEdgeDefinition) -> bool: return edge.building_id != house.id)

static func occupancy(map: MapDefinition, cell: Vector2i, level: int, all_floors: bool = false) -> Array[String]:
	var result: Array[String] = []
	for house in map.buildings:
		if house.effective_bounds().has_point(cell): result.append(house.id)
	for surface in map.indoor_floors:
		if (all_floors or surface.level == level) and surface.rect.has_point(cell): result.append(surface.id)
	for prop in map.decorations:
		if (all_floors or prop.level == level) and Vector2i(prop.position.floor()) == cell: result.append(prop.id)
	for road in map.roads:
		if (all_floors or road.level == level) and road_cells(road).has(cell): result.append(road.id)
	for edge in map.wall_edges:
		if all_floors or edge.level == level:
			if Rect2(Vector2(cell), Vector2.ONE).grow(0.001).has_point((edge.start + edge.end) * 0.5):
				result.append(edge.id)
	return result

static func road_cells(road: MapRoadDefinition) -> Array[Vector2i]:
	if not road.grid_cells.is_empty(): return road.grid_cells.duplicate()
	var result: Array[Vector2i] = []
	for index in range(road.centerline.size() - 1):
		var a := road.centerline[index]
		var b := road.centerline[index + 1]
		var box := Rect2(a, Vector2.ZERO).expand(b).grow(road.width * 0.5)
		for y in range(floori(box.position.y), ceili(box.end.y)):
			for x in range(floori(box.position.x), ceili(box.end.x)):
				var cell := Vector2i(x, y)
				if (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(cell) + Vector2(0.5, 0.5), a, b)) <= road.width * 0.5 and not result.has(cell):
					result.append(cell)
	return result

static func reset_heat(map: MapDefinition, rect: Rect2i) -> void:
	for cell in map.cells:
		for level in cell.levels:
			var paint := MapHeatPaint.new()
			paint.id = uid("reset")
			paint.rect = rect.intersection(Rect2i(cell.cell_coordinate * cell.size, cell.size))
			if not paint.rect.has_area(): continue
			paint.rect.position -= cell.cell_coordinate * cell.size
			paint.pressure = 0.1
			level.heat_paints.append(paint)

static func remove_house(map: MapDefinition, house: MapBuildingInstanceDefinition) -> void:
	reset_heat(map, house.effective_bounds())
	map.stairs = map.stairs.filter(func(item: MapStairDefinition) -> bool: return item.building_id != house.id)
	map.wall_edges = map.wall_edges.filter(func(item: MapWallEdgeDefinition) -> bool: return item.building_id != house.id)
	map.indoor_floors = map.indoor_floors.filter(func(item: MapIndoorFloorDefinition) -> bool: return item.building_id != house.id)
	map.buildings.erase(house)

static func clear_cells(map: MapDefinition, positions: Array[Vector2i], level: int, exempt_house: String = "") -> Array[String]:
	var conflicts: Array[String] = []
	for house in map.buildings.duplicate():
		if house.id == exempt_house: continue
		for point in positions:
			if house.effective_bounds().has_point(point):
				conflicts.append("Entire house: " + house.effective_display_name())
				remove_house(map, house)
				break
	for road in map.roads.duplicate():
		if road.level != level: continue
		var remaining := road_cells(road)
		var count := remaining.size()
		for point in positions: remaining.erase(point)
		if remaining.size() == count: continue
		conflicts.append("Road cells: %d" % (count - remaining.size()))
		if remaining.is_empty(): map.roads.erase(road)
		else: road.grid_cells = remaining
	for prop in map.decorations.duplicate():
		if prop.level == level and positions.has(Vector2i(prop.position.floor())):
			conflicts.append("Object: " + prop.id)
			map.decorations.erase(prop)
	for surface in map.indoor_floors.duplicate():
		if surface.level != level: continue
		var remaining := cells(surface.rect)
		var count := remaining.size()
		for point in positions: remaining.erase(point)
		if remaining.size() == count: continue
		conflicts.append("Indoor floor: " + surface.id)
		map.indoor_floors.erase(surface)
		for point in remaining:
			var split := surface.duplicate(true) as MapIndoorFloorDefinition
			split.id = uid("floor")
			split.rect = Rect2i(point, Vector2i.ONE)
			map.indoor_floors.append(split)
	return conflicts

static func paint_terrain(map: MapDefinition, rect: Rect2i, terrain: MapTerrainDefinition) -> Dictionary:
	if not bounds(map).encloses(rect): return {"error": "Selection exceeds map bounds."}
	if terrain.category == "water":
		for point in cells(rect):
			if not occupancy(map, point, 0, true).is_empty():
				return {"error": "Water cannot replace occupied ground, including upper-floor buildings."}
	var world := adapter(map)
	for cell in map.cells:
		var part := rect.intersection(Rect2i(cell.cell_coordinate * cell.size, cell.size))
		if not part.has_area(): continue
		var level := ensure_level(cell, 0)
		var paint := MapTerrainPaint.new()
		paint.id = uid("terrain")
		paint.rect = Rect2i(part.position - cell.cell_coordinate * cell.size, part.size)
		paint.terrain = terrain
		level.terrain_paints.append(paint)
		for point in cells(part):
			var previous := world.get_tile_at(point, 0)
			if terrain.category == "water" or (previous != null and previous.is_water()):
				erase_heat_at(level, point - cell.cell_coordinate * cell.size)
	world.free()
	return {}

static func ensure_level(cell: MapCellDefinition, floor_index: int) -> MapLevelDefinition:
	for level in cell.levels:
		if level.level == floor_index: return level
	var level := MapLevelDefinition.new()
	level.level = floor_index
	cell.levels.append(level)
	return level

static func erase_heat_at(level: MapLevelDefinition, point: Vector2i) -> void:
	var remaining: Array[MapHeatPaint] = []
	for heat in level.heat_paints:
		if not heat.rect.has_point(point):
			remaining.append(heat)
			continue
		for rect in subtract_rect(heat.rect, Rect2i(point, Vector2i.ONE)):
			var split := heat.duplicate(true) as MapHeatPaint
			split.id = uid("heat")
			split.rect = rect
			remaining.append(split)
	level.heat_paints = remaining

static func subtract_rect(source: Rect2i, cut: Rect2i) -> Array[Rect2i]:
	var hit := source.intersection(cut)
	if not hit.has_area(): return [source]
	var result: Array[Rect2i] = []
	for part: Rect2i in [
		Rect2i(source.position, Vector2i(source.size.x, hit.position.y - source.position.y)),
		Rect2i(Vector2i(source.position.x, hit.end.y), Vector2i(source.size.x, source.end.y - hit.end.y)),
		Rect2i(Vector2i(source.position.x, hit.position.y), Vector2i(hit.position.x - source.position.x, hit.size.y)),
		Rect2i(Vector2i(hit.end.x, hit.position.y), Vector2i(source.end.x - hit.end.x, hit.size.y))]:
		if part.has_area(): result.append(part)
	return result

static func paint_heat(map: MapDefinition, rect: Rect2i, level: int, value: float) -> Dictionary:
	var world := adapter(map)
	for house in map.buildings:
		if house.effective_bounds().intersects(rect): normalize_house(map, house)
	for point in cells(rect):
		var tile := world.get_tile_at(point, level)
		if tile == null or not tile.walkable or tile.is_water() or not world.can_stand(Vector2(point) + Vector2(0.5, 0.5), level): continue
		var house := house_at(map, point)
		if house != null:
			split_heat_surfaces(house.template.indoor_floors, Rect2i(point - house.origin, Vector2i.ONE), level, value)
		elif tile.overlay_kind == "floor":
			split_heat_surfaces(map.indoor_floors, Rect2i(point, Vector2i.ONE), level, value)
		else:
			for cell in map.cells:
				var local := point - cell.cell_coordinate * cell.size
				if not Rect2i(Vector2i.ZERO, cell.size).has_point(local): continue
				var authored := ensure_level(cell, level)
				erase_heat_at(authored, local)
				var heat := MapHeatPaint.new()
				heat.id = uid("heat")
				heat.rect = Rect2i(local, Vector2i.ONE)
				heat.pressure = clampf(value, 0.0, 1.0)
				authored.heat_paints.append(heat)
	world.free()
	return {}

static func split_heat_surfaces(surfaces: Array[MapIndoorFloorDefinition], rect: Rect2i, level: int, value: float) -> void:
	for surface in surfaces.duplicate():
		if surface.level != level or not surface.rect.intersects(rect): continue
		surfaces.erase(surface)
		for part in subtract_rect(surface.rect, rect):
			var split := surface.duplicate(true) as MapIndoorFloorDefinition
			split.id = uid("floor")
			split.rect = part
			surfaces.append(split)
		var painted := surface.duplicate(true) as MapIndoorFloorDefinition
		painted.id = uid("floor")
		painted.rect = surface.rect.intersection(rect)
		painted.zombie_pressure = value
		surfaces.append(painted)

static func paint_floor(map: MapDefinition, rect: Rect2i, level: int, house_id: String) -> Dictionary:
	if not bounds(map).encloses(rect): return {"error": "Floor exceeds map bounds."}
	var world := adapter(map)
	for point in cells(rect):
		var ground := world.get_tile_at(point, 0)
		if ground == null or ground.is_water():
			world.free()
			return {"error": "A building requires dry ground beneath every floor."}
	world.free()
	var house: MapBuildingInstanceDefinition
	for item in map.buildings:
		if item.id == house_id: house = item
	if house != null and not house.effective_bounds().encloses(rect):
		return {"error": "Selected floor must stay within the selected house footprint."}
	var conflicts := clear_cells(map, cells(rect), level, house_id)
	if house == null:
		house = MapBuildingInstanceDefinition.new()
		house.id = uid("house")
		house.display_name = "House"
		house.origin = rect.position
		house.template = MapBuildingTemplate.new()
		house.template.id = uid("layout")
		house.template.explicit_layout = true
		house.template.footprint = rect.size
		map.buildings.append(house)
	else: normalize_house(map, house)
	house.template.floor_count = maxi(house.template.floor_count, level + 1)
	var local := Rect2i(rect.position - house.origin, rect.size)
	for existing in house.template.indoor_floors.duplicate():
		if existing.level != level or not existing.rect.intersects(local): continue
		house.template.indoor_floors.erase(existing)
		for part in subtract_rect(existing.rect, local):
			var split := existing.duplicate(true) as MapIndoorFloorDefinition
			split.id = uid("floor")
			split.rect = part
			house.template.indoor_floors.append(split)
	var floor := MapIndoorFloorDefinition.new()
	floor.id = uid("floor")
	floor.level = level
	floor.rect = local
	floor.terrain = INDOOR
	house.template.indoor_floors.append(floor)
	return {"conflicts": conflicts, "house_id": house.id}

static func wall(map: MapDefinition, a: Vector2, b: Vector2, level: int, kind: String, house_id: String) -> Dictionary:
	if a == b or (a.x != b.x and a.y != b.y): return {"error": "Draw an axis-aligned wall along grid edges."}
	var house: MapBuildingInstanceDefinition
	for item in map.buildings:
		if item.id == house_id: house = item
	if house == null: return {"error": "Select a house first, or create its indoor floor."}
	var box := Rect2(Vector2(house.effective_bounds().position), Vector2(house.effective_bounds().size)).grow(0.001)
	if not box.has_point(a) or not box.has_point(b): return {"error": "Wall must stay within the selected house."}
	normalize_house(map, house)
	a -= Vector2(house.origin)
	b -= Vector2(house.origin)
	var direction := (b - a).normalized()
	var edges := house.template.wall_edges
	var conflicts: Array[String] = []
	for index in range(roundi(a.distance_to(b))):
		var start := a + direction * index
		var end := start + direction
		for existing in edges.duplicate():
			if existing.level != level: continue
			var middle := (start + end) * 0.5
			if middle.distance_to(Geometry2D.get_closest_point_to_segment(middle, existing.start, existing.end)) > 0.01: continue
			conflicts.append("Wall segment")
			edges.erase(existing)
			var old_dir: Vector2 = (existing.end - existing.start).normalized()
			for old_index in range(roundi(existing.start.distance_to(existing.end))):
				var old_start: Vector2 = existing.start + old_dir * old_index
				var old_end: Vector2 = old_start + old_dir
				if (old_start + old_end).distance_to(start + end) < 0.01: continue
				var remnant := existing.duplicate(true) as MapWallEdgeDefinition
				remnant.id = uid("edge")
				remnant.start = old_start
				remnant.end = old_end
				edges.append(remnant)
		if kind == "erase": continue
		var edge := MapWallEdgeDefinition.new()
		edge.id = uid("edge")
		edge.start = start
		edge.end = end
		edge.level = level
		edge.kind = kind
		edges.append(edge)
	return {"conflicts": conflicts}

static func place_stair(map: MapDefinition, start: Vector2, direction: Vector2, level: int, house_id: String) -> Dictionary:
	var house: MapBuildingInstanceDefinition
	for item in map.buildings:
		if item.id == house_id: house = item
	if house == null: return {"error": "Select the house that owns this stair."}
	normalize_house(map, house)
	var end := start + direction * 3.0
	if not house.effective_bounds().has_point(Vector2i(start.floor())) or not house.effective_bounds().has_point(Vector2i(end.floor())):
		return {"error": "Both stair landings must belong to the selected house."}
	var world := adapter(map)
	if not world.can_stand(start, level) or not world.can_stand(end, level + 1):
		world.free()
		return {"error": "The stair needs a supported lower landing and an upper landing on the next floor."}
	for floor_index in [level, level + 1]:
		for face in world.query_walls(floor_index, Rect2(start, Vector2.ZERO).expand(end).grow(0.4)):
			if Geometry2D.segment_intersects_segment(start, end, face.start, face.end) != null:
				world.free()
				return {"error": "Remove walls crossing the stair path before placing stairs."}
	for link: StairLink in world.stairs.values():
		if link.from_floor == level and (link.contains(start, 0.5) or link.contains(end, 0.5)):
			world.free()
			return {"error": "Stair overlaps another stair."}
	var stair := MapStairDefinition.new()
	stair.id = uid("stair")
	stair.start = start - Vector2(house.origin)
	stair.end = end - Vector2(house.origin)
	stair.from_floor = level
	stair.to_floor = level + 1
	for step in [1, 2]:
		var point := Vector2i((start + direction * step).floor())
		if not house.effective_bounds().has_point(point):
			world.free()
			return {"error": "Stair must stay inside the house footprint."}
		stair.opening_cells.append(point - house.origin)
	world.free()
	house.template.stairs.append(stair)
	return {}

static func capture(map: MapDefinition, selection: Rect2i) -> MapBuildingTemplate:
	var result := MapBuildingTemplate.new()
	result.id = uid("template")
	result.display_name = "House template"
	result.explicit_layout = true
	result.footprint = selection.size
	for house in map.buildings:
		if not selection.encloses(house.effective_bounds()): continue
		normalize_house(map, house)
		var offset := house.origin - selection.position
		result.floor_count = maxi(result.floor_count, house.template.floor_count)
		result.has_roof = house.template.has_roof
		for surface in house.template.indoor_floors:
			var copy := surface.duplicate(true) as MapIndoorFloorDefinition
			copy.id = uid("floor")
			copy.rect.position += offset
			result.indoor_floors.append(copy)
		for edge in house.template.wall_edges:
			var copy := edge.duplicate(true) as MapWallEdgeDefinition
			copy.id = uid("edge")
			copy.start += Vector2(offset)
			copy.end += Vector2(offset)
			result.wall_edges.append(copy)
		for stair in house.template.stairs:
			var copy := stair.duplicate(true) as MapStairDefinition
			copy.id = uid("stair")
			copy.start += Vector2(offset)
			copy.end += Vector2(offset)
			for index in range(copy.opening_cells.size()): copy.opening_cells[index] += offset
			result.stairs.append(copy)
	for floor in map.indoor_floors:
		if selection.encloses(floor.rect):
			var copy := floor.duplicate(true) as MapIndoorFloorDefinition
			copy.rect.position -= selection.position
			copy.building_id = ""
			copy.room_id = ""
			result.indoor_floors.append(copy)
			result.floor_count = maxi(result.floor_count, copy.level + 1)
	for edge in map.wall_edges:
		var box := Rect2(Vector2(selection.position), Vector2(selection.size)).grow(0.001)
		if box.has_point(edge.start) and box.has_point(edge.end):
			var copy := edge.duplicate(true) as MapWallEdgeDefinition
			copy.start -= Vector2(selection.position)
			copy.end -= Vector2(selection.position)
			copy.building_id = ""
			result.wall_edges.append(copy)
	return result

static func transform_point(point: Vector2, size: Vector2i, turns: int, mirror: bool) -> Vector2:
	if mirror: point.x = size.x - point.x
	for index in range(posmod(turns, 4)):
		point = Vector2(size.y - point.y, point.x)
		size = Vector2i(size.y, size.x)
	return point

static func transformed(source: MapBuildingTemplate, turns: int, mirror: bool) -> MapBuildingTemplate:
	if not source.explicit_layout:
		var temporary := create_map(source.footprint)
		var house := MapBuildingInstanceDefinition.new()
		house.id = uid("legacy")
		house.template = source.duplicate(true)
		temporary.buildings.append(house)
		normalize_house(temporary, house)
		source = house.template
	var result := source.duplicate(true) as MapBuildingTemplate
	var size := source.footprint
	if posmod(turns, 2) == 1: result.footprint = Vector2i(size.y, size.x)
	result.rooms.clear()
	var surfaces: Array[MapIndoorFloorDefinition] = []
	for floor in source.indoor_floors:
		for cell in cells(floor.rect):
			var copy := floor.duplicate(true) as MapIndoorFloorDefinition
			copy.id = uid("floor")
			copy.rect = Rect2i(Vector2i(transform_point(Vector2(cell) + Vector2(0.5, 0.5), size, turns, mirror).floor()), Vector2i.ONE)
			surfaces.append(copy)
	result.indoor_floors = surfaces
	for edge in result.wall_edges:
		edge.start = transform_point(edge.start, size, turns, mirror)
		edge.end = transform_point(edge.end, size, turns, mirror)
	for stair in result.stairs:
		stair.start = transform_point(stair.start, size, turns, mirror)
		stair.end = transform_point(stair.end, size, turns, mirror)
		for index in range(stair.opening_cells.size()):
			stair.opening_cells[index] = Vector2i(transform_point(Vector2(stair.opening_cells[index]) + Vector2(0.5, 0.5), size, turns, mirror).floor())
	return result

static func stamp(map: MapDefinition, template: MapBuildingTemplate, origin: Vector2i) -> Dictionary:
	var rect := Rect2i(origin, template.footprint)
	if not bounds(map).encloses(rect): return {"error": "Template exceeds map bounds."}
	var world := adapter(map)
	for point in cells(rect):
		var tile := world.get_tile_at(point, 0)
		if tile == null or tile.is_water():
			world.free()
			return {"error": "Template footprint overlaps water or unsupported ground."}
	world.free()
	var conflicts: Array[String] = []
	for level in range(template.floor_count):
		conflicts.append_array(clear_cells(map, cells(rect), level))
	var house := MapBuildingInstanceDefinition.new()
	house.id = uid("house")
	house.origin = origin
	house.template = template.duplicate(true)
	house.template.id = uid("layout")
	house.display_name = template.display_name
	map.buildings.append(house)
	return {"conflicts": conflicts, "house_id": house.id}

static func brush(map: MapDefinition, points: Array[Vector2i], width: int) -> Dictionary:
	var world := adapter(map)
	var covered: Array[Vector2i] = []
	var offset := -floori((width - 1) * 0.5)
	for point in points:
		var tile := world.get_tile_at(point, 0)
		if tile == null or tile.is_water(): break
		for y in range(width):
			for x in range(width):
				var position := point + Vector2i(x + offset, y + offset)
				var ground := world.get_tile_at(position, 0)
				if ground != null and not ground.is_water() and not covered.has(position):
					covered.append(position)
	world.free()
	if covered.is_empty(): return {"error": "Road starts on water or outside the map."}
	var conflicts := clear_cells(map, covered, 0)
	var road := MapRoadDefinition.new()
	road.id = uid("road")
	road.width = width
	road.terrain = ASPHALT
	road.grid_cells = covered
	map.roads.append(road)
	return {"conflicts": conflicts}

static func resize(map: MapDefinition, size: Vector2i) -> Dictionary:
	if size.x < 1 or size.y < 1: return {"error": "Map dimensions must be positive."}
	var target := Rect2i(Vector2i.ZERO, size)
	var old := bounds(map)
	var conflicts: Array[String] = []
	for house in map.buildings.duplicate():
		if not target.encloses(house.effective_bounds()):
			conflicts.append("Entire house: " + house.effective_display_name())
			remove_house(map, house)
	for prop in map.decorations.duplicate():
		if not target.has_point(Vector2i(prop.position.floor())):
			conflicts.append("Object: " + prop.id)
			map.decorations.erase(prop)
	for road in map.roads.duplicate():
		var original := road_cells(road)
		road.grid_cells = original.filter(func(point: Vector2i) -> bool: return target.has_point(point))
		if road.grid_cells.size() != original.size(): conflicts.append("Road: " + road.id)
		if road.grid_cells.is_empty(): map.roads.erase(road)
	for surface in map.indoor_floors.duplicate():
		surface.rect = surface.rect.intersection(target)
		if not surface.rect.has_area(): map.indoor_floors.erase(surface)
	for edge in map.wall_edges.duplicate():
		var box := Rect2(Vector2.ZERO, Vector2(size)).grow(0.001)
		if not box.has_point(edge.start) or not box.has_point(edge.end):
			conflicts.append("Wall: " + edge.id)
			map.wall_edges.erase(edge)
	for stair in map.stairs.duplicate():
		if not target.has_point(Vector2i(stair.start.floor())) or not target.has_point(Vector2i(stair.end.floor())):
			conflicts.append("Stair: " + stair.id)
			map.stairs.erase(stair)
	for zone in map.zones.duplicate():
		zone.rect = zone.rect.intersection(target)
		if not zone.rect.has_area(): map.zones.erase(zone)
	var new_cell := MapCellDefinition.new()
	new_cell.id = uid("cell")
	new_cell.size = size
	for cell in map.cells:
		for level in cell.levels:
			var destination := ensure_level(new_cell, level.level)
			for paint in level.terrain_paints:
				var copy := paint.duplicate(true) as MapTerrainPaint
				copy.rect.position += cell.cell_coordinate * cell.size
				copy.rect = copy.rect.intersection(target)
				if copy.rect.has_area(): destination.terrain_paints.append(copy)
			for heat in level.heat_paints:
				var copy := heat.duplicate(true) as MapHeatPaint
				copy.rect.position += cell.cell_coordinate * cell.size
				copy.rect = copy.rect.intersection(target)
				if copy.rect.has_area(): destination.heat_paints.append(copy)
	var ground := ensure_level(new_cell, 0)
	for rect in subtract_rect(target, old):
		var paint := MapTerrainPaint.new()
		paint.id = uid("grass")
		paint.rect = rect
		paint.terrain = GRASS
		ground.terrain_paints.append(paint)
	map.cells.assign([new_cell])
	map.cell_size = size
	map.player_spawn = map.player_spawn.clamp(Vector2(0.5, 0.5), Vector2(size) - Vector2(0.5, 0.5))
	map.npc_spawn = map.npc_spawn.clamp(Vector2(0.5, 0.5), Vector2(size) - Vector2(0.5, 0.5))
	return {"conflicts": conflicts, "shrink": not target.encloses(old)}
