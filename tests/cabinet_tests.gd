extends RefCounted

static func run(game: MVPGameRoot, check: Callable) -> void:
	var baseline := QuickSave.snapshot(game)
	var speed := GameTime.speed_mode
	var map := game.world_map
	var actions := game.interactions
	var cabinet: Dictionary = {}
	for point in actions.points:
		if point["id"] == "test_cabinet_0": cabinet = point
		if point.get("furniture", false):
			var tile := map.get_tile(point["position"], point["floor"])
			check.call(tile != null and not tile.room_id.is_empty(), "cabinet placed inside a house: " + point["id"])
			(point["container"] as ContainerData).is_open = false
	var container: ContainerData = cabinet["container"]
	game.player.logical_position = Vector2(3.1, 3.0)
	game.player.floor_level = 0
	game.player.stair_id = ""
	var model := InventoryPresentation.new()
	model.sides[1]["selected"] = "nearby_all"
	check.call(model.sources(game, 1).is_empty(), "closed cabinets contribute no nearby items")
	game.player.facing_direction = Vector2.RIGHT
	game.player.look_pitch = 0
	actions.request_interaction()
	check.call(not container.is_open, "E facing away cannot open nearby cabinet")
	preload("res://tests/first_person_upgrade_tests.gd").aim_at(game, cabinet)
	actions.request_interaction()
	check.call(actions.is_searching() and not container.is_open and model.sources(game, 1).is_empty(), "search keeps cabinet closed and hides contents until complete")
	check.call(container.search_duration_game_seconds != game.inventory.world["wardrobe"].search_duration_game_seconds, "search duration is independently bound to each container")
	actions._update_active_action(0.5)
	var progress := container.search_progress_seconds
	var partial := QuickSave.snapshot(game)
	var invalid := partial.duplicate(true)
	for entry in invalid["points"]:
		if entry["id"] == cabinet["id"]: entry["search_duration"] = -1.0
	check.call(not QuickSave.validate(invalid, game), "invalid per-container search duration is rejected before restore")
	actions.interrupt_action("Test")
	check.call(progress > 0 and not container.searched and not container.is_open, "interrupted search retains progress without opening")
	container.search_progress_seconds = 0
	var configured_duration := container.search_duration_game_seconds
	container.search_duration_game_seconds = 240
	QuickSave.restore(game, partial)
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	check.call(is_equal_approx(container.search_progress_seconds, progress), "save restores partial container search progress")
	check.call(is_equal_approx(container.search_duration_game_seconds, configured_duration), "save restores independently configured container duration")
	preload("res://tests/first_person_upgrade_tests.gd").aim_at(game, cabinet)
	actions.request_interaction()
	check.call(is_equal_approx(actions.active_action["remaining"], container.search_duration_game_seconds - progress), "E resumes remaining per-container search time")
	actions._update_active_action(20)
	check.call(container.is_open and not game.inventory.world["test_cabinet_1"].is_open, "aim and E opens only selected cabinet")
	check.call(model.sources(game, 1) == ["test_cabinet_0"], "only opened nearby cabinet contributes items")
	game.world_3d_view._update_interaction_markers()
	for marker in game.world_3d_view.interaction_markers:
		if marker["point"]["id"] == cabinet["id"]:
			var mesh: MeshInstance3D = marker["node"].get_node("Cabinet")
			check.call(mesh.material_override.albedo_color == ContainerData.OPEN_COLOR, "open cabinet uses green material")
	model.sides[1]["selected"] = cabinet["id"]
	actions.request_interaction()
	check.call(not container.is_open and not actions.can_access(cabinet["id"]) and model.sources(game, 1).is_empty(), "closing removes access even from previously selected tab")
	actions.request_interaction()
	check.call(container.is_open and not actions.is_searching(), "searched cabinet reopens immediately")
	actions.request_interaction()
	var ground := actions._ground_container()
	check.call(actions.can_access(ground), "ground pile at feet remains accessible")
	game.player.logical_position += Vector2(0.7, 0)
	check.call(not actions.can_access(ground), "ground pile beyond foot radius is excluded")
	game.player.logical_position = Vector2(3.1, 3.0)
	check.call(not map.can_stand(cabinet["position"], 0), "cabinet volume prevents standing inside")
	var moved := map.move_with_wall_slide(Vector2(3.2, 2.7), Vector2(-1, 0), WorldMap.ACTOR_RADIUS, 0)
	check.call(moved.x >= 2.86, "shared actor movement stops before cabinet face")
	check.call(not map._segment_walkable(Vector2(2.8, 2.2), Vector2(2.8, 4.0), 0), "navigation edges respect cabinet clearance")
	check.call(map.can_stand(map.furniture_approach(cabinet["position"], 0, game.player.logical_position), 0), "NPC approach target lies outside cabinet collision")
	check.call(not map.has_spatial_line_of_sight(Vector3(3.2, 0.5, 2.7), Vector3(2.3, 0.5, 2.7)), "cabinet blocks low spatial rays")
	check.call(map.has_spatial_line_of_sight(Vector3(3.2, 1.5, 2.7), Vector3(2.3, 1.5, 2.7)), "spatial rays can pass above cabinet")
	container.is_open = true
	var saved := QuickSave.snapshot(game)
	check.call(QuickSave.validate(saved, game), "cabinet state snapshot validates")
	container.is_open = false
	QuickSave.restore(game, saved)
	check.call(container.is_open, "cabinet open state survives save restore")
	var legacy := saved.duplicate(true)
	legacy.erase("cabinet_layout")
	legacy["player"]["position"] = cabinet["position"]
	for entry in legacy["points"]:
		entry.erase("open")
		entry.erase("search_duration")
	check.call(QuickSave.validate(legacy, game), "old layout migrates actor overlapping new cabinet")
	QuickSave.restore(game, legacy)
	check.call(map.can_stand(game.player.logical_position, 0) and not container.is_open, "legacy actor moved clear and cabinet defaults closed")
	check.call(legacy["player"]["position"] == cabinet["position"] and not legacy.has("cabinet_layout"), "legacy migration does not mutate source snapshot")
	QuickSave.restore(game, baseline)
	GameTime.set_speed(speed)
	game.hud.close_panels()
