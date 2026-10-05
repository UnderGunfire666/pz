extends Node


func _ready() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate() as MVPGameRoot
	add_child(game)
	await get_tree().process_frame
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	game.player.logical_position = Vector2(4.5, 7.0)
	game.player.facing_direction = Vector2.UP
	game.player.look_pitch = -0.1
	for id: String in ["test_cabinet_0", "wardrobe"]:
		for stack: ItemStack in game.inventory.world[id].contents.duplicate():
			if stack.definition.id == "cabinet_hammer": game.inventory.move_unit(stack.units[0]["uid"], "right_hand")
			if stack.definition.id == "jacket": game.inventory.move_unit(stack.units[0]["uid"], "outer_top")
	game.world_3d_view.sync_view_to_player()
	game.world_3d_view.refresh_after_load()
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/first-person-idle.png")
	game.player._attack_flash_left = 0.09
	game.world_3d_view.first_person_hands.advance(0, game.player)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/first-person-strike.png")
	game.player._attack_flash_left = 0.0
	game.player.logical_position = Vector2(3.2, 2.7)
	for point: Dictionary in game.interactions.points:
		if point["id"] == "test_cabinet_0":
			preload("res://tests/first_person_upgrade_tests.gd").aim_at(game, point)
	game.world_3d_view.refresh_after_load()
	game.hud.refresh(game)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/first-person-focus.png")
	game.interactions.request_interaction()
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	game.interactions.request_interaction()
	game.interactions._update_active_action(20)
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	game.hud.close_panels()
	game.world_3d_view._update_interaction_markers()
	game.hud.refresh(game)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/cabinet-open.png")
	print("First-person visual captures saved.")
	_measure_target_queries(game)
	get_tree().quit()


func _measure_target_queries(game: MVPGameRoot) -> void:
	# CPU targeting sample only: these points do not create meshes or AI actors.
	var original := game.interactions.points
	var samples: Array[float] = []
	game.interactions.points = []
	for floor_index in 4:
		for x in 16:
			for z in 16:
				game.interactions.points.append({"id": "%s:%s:%s" % [floor_index, x, z], "kind": "bed",
					"position": Vector2(x + 0.5, z + 0.5), "floor": floor_index, "radius": 0.9, "furniture": true})
	for sample in 120:
		var start := Time.get_ticks_usec()
		PlayerTargeting.interaction_target(game.interactions)
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	print("Target query CPU (1024 points, existing map walls): median %.3f ms, p95 %.3f ms" % [samples[60], samples[114]])
	game.interactions.points = original
