class_name MapAuthoringTests
extends RefCounted
const OPS = preload("res://addons/native_map_authoring/map_edit_operations.gd")


static func run(check: Callable) -> void:
	var map := MapDefinition.new()
	map.id = "authoring_layer_test"
	map.format_version = 2
	map.cell_size = Vector2i(4, 4)
	var cell := MapCellDefinition.new()
	cell.id = "cell"
	cell.size = Vector2i(4, 4)
	var ground := MapLevelDefinition.new()
	ground.level = 0
	ground.terrain_paints = [_paint("grass", Rect2i(Vector2i.ZERO, Vector2i(4, 4)), _terrain("grass")),
		_paint("water", Rect2i(2, 0, 1, 4), _terrain("water"))]
	var heat := MapHeatPaint.new()
	heat.id = "heat"
	heat.rect = Rect2i(0, 0, 2, 1)
	heat.pressure = 0.7
	ground.heat_paints = [heat]
	cell.levels = [ground]
	map.cells = [cell]
	var road := MapRoadDefinition.new()
	road.id = "road"
	road.level = 0
	road.centerline = PackedVector2Array([Vector2(0.5, 0.5), Vector2(3.5, 0.5)])
	road.width = 1.0
	road.terrain = _terrain("road")
	map.roads = [road]
	var upper := MapIndoorFloorDefinition.new()
	upper.id = "upper"
	upper.level = 1
	upper.rect = Rect2i(0, 0, 1, 1)
	upper.terrain = _terrain("indoor")
	upper.zombie_pressure = 0.6
	map.indoor_floors = [upper]
	var world := WorldMap.new()
	world.load_definition(map, false)
	var road_tile := world.get_tile_at(Vector2i(0, 0), 0)
	var water_tile := world.get_tile_at(Vector2i(2, 0), 0)
	check.call(road_tile.base_kind == "grass" and road_tile.occupancy_kind == "road" and road_tile.kind == "road",
		"road layer preserves its underlying terrain")
	check.call(water_tile.is_water() and not water_tile.walkable and water_tile.occupancy_id.is_empty(),
		"water rejects road overlay and remains impassable")
	check.call(is_equal_approx(world.pressure_at(Vector2(0.5, 0.5), 0), 0.7)
		and is_equal_approx(world.pressure_at(Vector2(2.5, 0.5), 0), 0.0),
		"heat paints affect walkable terrain while water has no heat")
	check.call(world.get_tile_at(Vector2i(0, 0), 1) != null and world.get_tile_at(Vector2i(0, 0), 1).building_id.is_empty()
		and is_equal_approx(world.pressure_at(Vector2(0.5, 0.5), 1), 0.6),
		"indoor floors are independent per floor and provide independent heat candidates")
	check.call(world.initial_zombie_spawn_candidates().any(func(candidate: Dictionary) -> bool:
		return int(candidate["floor"]) == 1) and not world.initial_zombie_spawn_candidates().any(func(candidate: Dictionary) -> bool:
		var position: Vector2 = candidate["position"]
		return position.x >= 2.0 and position.x < 3.0 and int(candidate["floor"]) == 0),
		"spawn candidates include upper indoor floors and exclude water")
	world.free()
	_test_editor_workflow(check)
	_test_brush_and_presets(check)

static func _test_brush_and_presets(check: Callable) -> void:
	var map := OPS.create_map(Vector2i(12, 12))
	OPS.paint_terrain(map, Rect2i(5, 0, 1, 12), load("res://resources/maps/terrain/water.tres"))
	var points: Array[Vector2i] = [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]
	OPS.brush(map, points, 2)
	check.call(map.roads.size() == 1 and map.roads[0].grid_cells.all(func(point: Vector2i) -> bool: return point.x < 5), "integer-width brush stops at shoreline without resuming on the opposite bank")
	check.call(OPS.paint_terrain(map, Rect2i(3, 4, 1, 1), load("res://resources/maps/terrain/water.tres")).has("error"), "road occupancy rejects water painting")
	OPS.paint_terrain(map, Rect2i(3, 4, 1, 1), load("res://resources/maps/terrain/soil.tres"))
	var world := OPS.adapter(map)
	check.call(world.get_tile_at(Vector2i(3, 4), 0).kind == "road" and world.get_tile_at(Vector2i(3, 4), 0).base_kind == "dirt", "editing soil underneath a road preserves its overlay")
	world.free()
	var legacy := load("res://resources/maps/templates/miller_house.tres") as MapBuildingTemplate
	var transformed := OPS.transformed(legacy, 1, true)
	check.call(transformed.explicit_layout and not transformed.indoor_floors.is_empty() and not transformed.wall_edges.is_empty(), "legacy template conversion retains geometry before rotation and mirroring")
	var rules := ZombieWorldRules.new()
	var expected := {"Very Few": Vector2i(1, 3), "Few": Vector2i(4, 6), "Normal": Vector2i(7, 10), "Many": Vector2i(11, 16), "Very Many": Vector2i(17, 24), "Extremely Many": Vector2i(25, 32)}
	for preset: String in expected:
		check.call(rules.population_range(preset) == expected[preset], "population preset range: " + preset)


static func _test_editor_workflow(check: Callable) -> void:
	var map := OPS.create_map(Vector2i(16, 16))
	var house_rect := Rect2i(2, 2, 6, 6)
	var placed := OPS.paint_floor(map, house_rect, 0, "")
	var house_id: String = placed.get("house_id", "")
	check.call(not house_id.is_empty(), "floor painting creates an independently owned house")
	OPS.paint_floor(map, house_rect, 1, house_id)
	OPS.wall(map, Vector2(2, 2), Vector2(8, 2), 0, "wall", house_id)
	var doorway := OPS.wall(map, Vector2(3, 2), Vector2(4, 2), 0, "door", house_id)
	check.call(not doorway.get("conflicts", []).is_empty(), "replacing wall with door reports a confirmation conflict")
	var house: MapBuildingInstanceDefinition = map.buildings[0]
	check.call(house.template.wall_edges.size() == 6, "door replacement preserves all five neighbouring unit wall segments")
	var stair := OPS.place_stair(map, Vector2(3.5, 4.5), Vector2.RIGHT, 0, house_id)
	check.call(not stair.has("error"), "straight stairs accept supported endpoints on adjacent floors")
	var world := OPS.adapter(map)
	check.call(world.get_tile_at(Vector2i(4, 4), 1) == null and world.can_stand(Vector2(6.5, 4.5), 1),
		"stairs open upper slab while preserving supported arrival landing")
	var ascent := world.move_actor(Vector2(3.5, 4.5), 0, Vector2(3.5, 0))
	check.call(ascent.floor == 1 and ascent.position.distance_to(Vector2(7.0, 4.5)) < 0.1,
		"editor-authored stairs support continuous movement onto the upper landing")
	check.call(not world.has_line_of_sight(Vector2(2.5, 1.5), Vector2(2.5, 2.5), 0)
		and world.has_line_of_sight(Vector2(3.5, 1.5), Vector2(3.5, 2.5), 0),
		"static door replaces the blocking wall without removing neighbouring wall occlusion")
	world.free()
	OPS.paint_heat(map, Rect2i(3, 3, 1, 1), 1, 0.8)
	world = OPS.adapter(map)
	check.call(is_equal_approx(world.pressure_at(Vector2(3.5, 3.5), 1), 0.8)
		and is_equal_approx(world.pressure_at(Vector2(3.5, 3.5), 0), 0.1), "heat editing isolates stacked indoor floors")
	world.free()
	var captured := OPS.capture(OPS.snapshot(map), house_rect)
	var rotated := OPS.transformed(captured, 1, true)
	check.call(rotated.stairs.size() == 1 and rotated.indoor_floors.size() > 0, "template capture includes independent floors, heat, and stair openings")
	var proposal := OPS.snapshot(map)
	var replacement := OPS.stamp(proposal, rotated, Vector2i(5, 5))
	check.call(not replacement.has("error") and not replacement.get("conflicts", []).is_empty()
		and proposal.buildings.size() == 1 and proposal.buildings[0].id != house_id, "partial overlap replaces the entire old house in an isolated proposal")
	check.call(map.buildings.size() == 1 and map.buildings[0].id == house_id, "replacement preview does not mutate the live map")
	var history := UndoRedo.new()
	var old := OPS.snapshot(map)
	history.create_action("Replace house")
	history.add_do_method(OPS.copy_state.bind(map, proposal))
	history.add_undo_method(OPS.copy_state.bind(map, old))
	history.commit_action()
	history.undo()
	check.call(map.buildings[0].id == house_id and map.buildings[0].template.stairs.size() == 1, "undo restores entire replaced house and its stair")
	history.redo()
	check.call(map.buildings[0].id != house_id, "redo restores the independently placed replacement")
	history.clear_history()
	history.free()
	OPS.copy_state(map, OPS.snapshot(old))
	var stairs_before := map.buildings[0].template.stairs.duplicate()
	map.buildings[0].template.stairs.clear()
	world = OPS.adapter(map)
	check.call(world.get_tile_at(Vector2i(4, 4), 1) != null, "removing stair reveals its original upper floor")
	world.free()
	map.buildings[0].template.stairs.assign(stairs_before)
	var water = load("res://resources/maps/terrain/water.tres")
	check.call(OPS.paint_terrain(map, Rect2i(4, 4, 1, 1), water).has("error"), "water refuses house occupancy across floors")
	OPS.paint_heat(map, Rect2i(12, 12, 1, 1), 0, 0.9)
	OPS.paint_terrain(map, Rect2i(12, 12, 1, 1), water)
	OPS.paint_terrain(map, Rect2i(12, 12, 1, 1), load("res://resources/maps/terrain/soil.tres"))
	world = OPS.adapter(map)
	check.call(is_equal_approx(world.pressure_at(Vector2(12.5, 12.5), 0), 0.1), "water-to-land transition resets heat instead of reviving old heat")
	world.free()
	var clone := OPS.snapshot(map)
	OPS.resize(clone, Vector2i(20, 18))
	world = OPS.adapter(clone)
	check.call(world.get_tile_at(Vector2i(19, 17), 0).kind == "grass" and clone.buildings.size() == 1,
		"map expansion preserves house and fills new boundary with grass")
	world.free()
	var cropped := OPS.resize(clone, Vector2i(5, 5))
	check.call(cropped.shrink and not cropped.conflicts.is_empty() and clone.buildings.is_empty(), "shrink proposal reports complete houses removed by crop")
	check.call(ResourceSaver.save(map, "user://map_authoring_roundtrip.tres") == OK, "native authored map can be saved")
	var loaded := ResourceLoader.load("user://map_authoring_roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as MapDefinition
	check.call(loaded != null and loaded.buildings[0].template.stairs.size() == 1, "native map reload preserves template stair and floor data")
	world = OPS.adapter(loaded)
	check.call(world.get_tile_at(Vector2i(4, 4), 1) == null, "reloaded stairs preserve their upper-floor opening")
	world.free()
	var detached := OPS.snapshot(map)
	detached.buildings[0].template.indoor_floors[0].zombie_pressure = 0.99
	check.call(not is_equal_approx(map.buildings[0].template.indoor_floors[0].zombie_pressure, 0.99), "editing a copied house does not mutate the source")
	for item in map.buildings.duplicate(): OPS.remove_house(map, item)
	world = OPS.adapter(map)
	check.call(world.get_tile_at(Vector2i(3, 3), 0).building_id.is_empty() and is_equal_approx(world.pressure_at(Vector2(3.5, 3.5), 0), 0.1), "house deletion removes interior heat and restores baseline outdoor ground")
	world.free()


static func _terrain(kind: String) -> MapTerrainDefinition:
	var terrain := MapTerrainDefinition.new()
	terrain.id = kind
	terrain.category = "water" if kind == "water" else ("asphalt" if kind == "road" else ("indoor_floor" if kind == "indoor" else "grass"))
	terrain.visual_recipe = "road" if kind == "road" else ("floor" if kind == "indoor" else kind)
	terrain.passable = kind != "water"
	return terrain


static func _paint(id: String, rect: Rect2i, terrain: MapTerrainDefinition) -> MapTerrainPaint:
	var paint := MapTerrainPaint.new()
	paint.id = id
	paint.rect = rect
	paint.terrain = terrain
	return paint
