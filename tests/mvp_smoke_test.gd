extends Node

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	_expect(packed_scene != null, "main scene loads")
	if packed_scene == null:
		get_tree().quit(1)
		return

	var game := packed_scene.instantiate() as MVPGameRoot
	get_tree().root.add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var world_view: World3DView = game.get("world_3d_view")
	_expect(game.world_map != null, "world map initializes")
	_expect(game.world_map is WorldMap, "logical map stays available to simulation systems")
	_expect(world_view != null, "3D world renderer initializes")
	_expect(game.camera is Camera3D, "game uses a true 3D orbit camera")
	_expect(
		game.camera.get_viewport() == game.get_viewport(),
		"3D camera renders directly into the main game viewport"
	)
	_expect(not game.world_map.visible and not game.actor_layer.visible, "legacy 2D visuals are replaced by 3D rendering")
	_expect(not game.interactions.visible, "legacy 2D red and blue interaction dots are disabled")
	_expect(
		world_view.interaction_markers.size() == game.interactions.points.size(),
		"interaction locations are represented by 3D world markers"
	)
	var horizontal_grid_direction: Vector2 = world_view.input_to_logical(Vector2.RIGHT)
	_expect(
		horizontal_grid_direction.length_squared() > 0.99,
		"camera-relative movement uses a normalized world direction"
	)
	var initial_yaw: float = world_view.camera_yaw
	var middle_press := InputEventMouseButton.new()
	middle_press.button_index = MOUSE_BUTTON_MIDDLE
	middle_press.pressed = true
	game._input(middle_press)
	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(24.0, -12.0)
	game._input(mouse_motion)
	var middle_release := InputEventMouseButton.new()
	middle_release.button_index = MOUSE_BUTTON_MIDDLE
	middle_release.pressed = false
	game._input(middle_release)
	_expect(world_view.camera_yaw != initial_yaw, "middle mouse drag rotates the 3D camera")
	var initial_pitch: float = world_view.camera_pitch
	world_view.orbit_camera(Vector2(0.0, 180.0))
	_expect(
		is_equal_approx(world_view.camera_pitch, initial_pitch),
		"vertical middle-drag motion does not tilt the camera"
	)
	_expect(game.camera != null and game.camera.current, "3D camera is active")
	var ground := world_view.get_node("GroundBackdrop") as MeshInstance3D
	var ground_tile := world_view.get_node("Tile_0_0") as MeshInstance3D
	_expect(
		ground.position.y < ground_tile.position.y - 0.04,
		"ground backdrop is separated from tile meshes to prevent depth flicker"
	)
	_expect(game.hud.normal_button != null and game.hud.fast_button != null, "HUD exposes time-speed controls")
	var initial_zoom: float = world_view.camera_distance
	game.hud.adjust_zoom(1.12)
	_expect(world_view.camera_distance < initial_zoom, "camera zoom control changes 3D camera distance")
	var upper_floor_count := 0
	for segment in world_view.wall_segments:
		if int(segment["floor"]) == 1:
			upper_floor_count += 1
			_expect(not (segment["node"] as Node3D).visible, "upper wall floors are hidden from ground level")
			break
	_expect(upper_floor_count > 0, "buildings have explicit upper-floor wall geometry")
	var safehouse := game.world_map.buildings["safehouse"] as BuildingData
	game.player.logical_position = safehouse.ramp_start
	game.player.floor_level = 0
	var ramp_direction := (safehouse.ramp_end - safehouse.ramp_start).normalized()
	for _step in range(30):
		game.player.logical_position = game.world_map.move_with_wall_slide(
			game.player.logical_position,
			ramp_direction * 0.1
		)
		game.player.floor_level = world_view.floor_level_at(
			game.player.logical_position,
			game.player.floor_level
		)
	_expect(
		game.player.floor_level == 1
			and game.player.logical_position.distance_to(safehouse.ramp_end) < 0.2,
		"walking up the building ramp physically moves the player to the upper floor"
	)
	world_view._update_wall_visibility()
	_expect(
		game.interactions.nearest_point().is_empty(),
		"ground-floor interactions are not offered from the upper floor"
	)
	var active_floor_wall: Dictionary = {}
	var visible_upper_walls := 0
	for segment in world_view.wall_segments:
		if int(segment["floor"]) == 1 and (segment["node"] as Node3D).visible:
			visible_upper_walls += 1
		if bool(segment["wall"]) and int(segment["floor"]) == 1:
			active_floor_wall = segment
	_expect(visible_upper_walls > 0, "selected floor geometry is shown")
	world_view.camera_yaw += PI
	world_view._update_wall_visibility()
	_expect(
		not active_floor_wall.is_empty() and (active_floor_wall["node"] as Node3D).visible,
		"camera angle no longer hides walls"
	)
	world_view.camera_yaw -= PI
	for _step in range(30):
		game.player.logical_position = game.world_map.move_with_wall_slide(
			game.player.logical_position,
			-ramp_direction * 0.1
		)
		game.player.floor_level = world_view.floor_level_at(
			game.player.logical_position,
			game.player.floor_level
		)
	_expect(game.player.floor_level == 0, "walking down the ramp returns the player to the ground floor")
	game.player.logical_position = Vector2(4.45, 6.65)
	var wall_cell_position := Vector2(4.5, 2.5)
	_expect(game.world_map.is_walkable(wall_cell_position), "wall tile floor remains walkable")
	var slid_position := game.world_map.move_with_wall_slide(
		Vector2(4.5, 3.5),
		Vector2(0.4, -1.3)
	)
	_expect(
		slid_position.y > 2.2 and slid_position.y < 3.0 and slid_position.x > 4.5,
		"wall face blocks crossing while allowing entry into its tile and sliding along it"
	)
	_expect(game.world_map.is_safehouse(Vector2(4.3, 3.5)), "safehouse metadata is queryable")
	_expect(
		game.world_map.pressure_at(Vector2(12.5, 6.5)) > game.world_map.pressure_at(Vector2(1.5, 1.5)),
		"commercial pressure exceeds rural pressure"
	)
	_expect(game.zombie_spawner.active_zombies.size() >= 3, "pressure model seeds a commercial zombie cluster")

	game.visibility.refresh(Vector2(4.5, 7.4), Vector2.UP, false)
	var normal_vision_radius := game.visibility.vision_radius
	var normal_half_fov := game.visibility.half_fov_radians
	_expect(game.visibility.can_see_position(Vector2(4.5, 6.5)), "fan FOV sees tiles in front of the player")
	_expect(not game.world_map.has_line_of_sight(Vector2(1.5, 3.5), Vector2(5.5, 3.5)), "walls block line of sight")
	var smooth_fov_origin := Vector2(8.5, 11.5)
	game.visibility.refresh(smooth_fov_origin, Vector2.UP, true)
	var fov_revision := game.visibility.revision
	game.visibility.refresh(smooth_fov_origin, Vector2.UP, true)
	_expect(
		game.visibility.revision == fov_revision,
		"unchanged vision state reuses its cached polygon instead of recalculating every frame"
	)
	_expect(
		is_equal_approx(game.visibility.vision_radius, normal_vision_radius)
			and is_equal_approx(game.visibility.half_fov_radians, normal_half_fov),
		"holding aim does not change vision distance or field of view"
	)
	var off_center_target := smooth_fov_origin + Vector2.from_angle(deg_to_rad(-22.5)) * 2.8
	var target_cell := Vector2i(int(floor(off_center_target.x)), int(floor(off_center_target.y)))
	_expect(game.visibility.can_see_position(off_center_target), "FOV accepts visible positions continuously")
	_expect(
		not game.visibility.is_tile_visible(target_cell),
		"continuous actor visibility is not snapped to the target tile center"
	)
	_expect(game.visibility.visible_polygon.size() > 100, "world FOV mask is rendered as a dense continuous polygon")
	world_view._update_fog()
	_expect(
		world_view.fog_overlay.mesh != null
			and (world_view.fog_overlay.mesh as ArrayMesh).get_surface_count() > 0,
		"vision fog is rendered as a continuous clipped polygon instead of per-tile squares"
	)
	_expect(
		world_view._fog_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
			and world_view._fog_material.cull_mode == BaseMaterial3D.CULL_DISABLED
			and world_view._fog_material.albedo_color.r > 0.9
			and world_view._fog_material.albedo_color.g > 0.9
			and world_view._fog_material.albedo_color.b > 0.9,
		"vision fog uses a consistently white, unshaded, double-sided material"
	)
	var fog_mesh := world_view.fog_overlay.mesh as ArrayMesh
	var fog_normals := fog_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var normals_face_up := not fog_normals.is_empty()
	for normal in fog_normals:
		if normal.dot(Vector3.UP) < 0.99:
			normals_face_up = false
			break
	_expect(normals_face_up, "vision-fog triangles have uniform upward normals")
	var behind_player_nearby := smooth_fov_origin + Vector2.DOWN * 0.8
	var behind_player_far := smooth_fov_origin + Vector2.DOWN * 1.6
	_expect(
		game.visibility.can_see_position(behind_player_nearby),
		"player has an omnidirectional close-range vision radius"
	)
	_expect(
		not game.visibility.can_see_position(behind_player_far),
		"close-range vision preserves directional FOV outside its radius"
	)
	var close_wall_position := Vector2(2.5, 3.5)
	game.visibility.refresh(Vector2(3.2, 3.5), Vector2.LEFT, false)
	_expect(game.visibility.can_see_wall(close_wall_position), "wall face remains visible when standing close to it")

	game.player_state.add_wound("Test cut", "hand", 0.1, false)
	_expect("Test cut" in game.player_state.visible_wound_summary(), "wound display uses observable wound data")
	_expect(not "zombie-virus" in game.player_state.visible_wound_summary(), "hidden zombie-virus state is excluded from wound display")

	var ration := ItemDefinition.new("test_ration", "Test ration", Vector2i(1, 1), 0.2, ["food"])
	_expect(game.inventory.add_item(ItemStack.new(ration)), "grid inventory accepts a fitting weighted item")
	_expect(game.inventory.take_first_with_tag("food") != null, "inventory retrieves an item by gameplay tag")
	game.player_state.traits.set_value("cautiousness", 0.25)
	_expect(is_equal_approx(game.player_state.traits.value("cautiousness"), 0.25), "player uses the shared trait framework")
	_expect(game.npc.brain.to_save_data().has("memories"), "NPC brain exposes persistence-ready memory data")

	game.player.logical_position = Vector2(12.7, 6.5)
	game.interactions.request_interaction()
	_expect(not game.interactions.active_action.is_empty(), "grocery interaction starts a time-costed search")
	game.interactions._update_active_action(0.5)
	_expect(game.interactions.interrupt_search(), "search can be interrupted without losing its progress")
	var grocery_container: ContainerData = game.interactions.points[1]["container"]
	_expect(grocery_container.search_progress_seconds > 0.0, "interrupted search stores completed progress")
	game.interactions.request_interaction()
	_expect(
		float(game.interactions.active_action["remaining"]) < float(game.interactions.active_action["duration"]),
		"restarted search resumes from saved progress"
	)
	game.interactions.active_action["remaining"] = 0.0
	game.interactions._update_active_action(0.0)
	_expect(game.milestones["food"], "completed grocery search advances the food milestone")
	_expect(game.inventory.take_first_with_tag("food") != null, "grocery search transfers food to inventory")

	var test_zombie: ZombieActor = game.zombie_spawner.active_zombies[0]
	game.player.logical_position = Vector2(4.45, 6.65)
	test_zombie.logical_position = game.player.logical_position + Vector2.UP * 0.5
	game.visibility.refresh(game.player.logical_position, Vector2.UP, false)
	game._on_player_attack(game.player.logical_position, Vector2.UP)
	_expect(test_zombie.health == ZombieActor.MAX_HEALTH - 1, "directional player attack damages a visible zombie")
	var zombie_visual := world_view._create_actor_visual(test_zombie)
	_expect(
		bool(zombie_visual["has_health"]) and zombie_visual.has("health_bar"),
		"3D zombie actor has a health bar"
	)
	test_zombie.attack_cooldown = 0.0
	test_zombie._process(0.016)
	_expect(
		"Scratch" in game.player_state.visible_wound_summary(),
		"nearby zombie attacks apply a visible wound"
	)
	world_view.actor_visuals[test_zombie.get_instance_id()] = zombie_visual
	var zombie_health_bar := zombie_visual["health_bar"] as Node3D
	test_zombie.take_damage(ZombieActor.MAX_HEALTH)
	_expect(not zombie_health_bar.visible, "zombie health bar hides immediately when its owner dies")

	game.player.logical_position = Vector2(8.5, 7.5)
	game.interactions._check_hazards()
	_expect(game.milestones["injury"], "broken glass applies the demonstrable light injury")

	game.player.logical_position = Vector2(4.3, 3.6)
	game.interactions.request_interaction()
	_expect(game.interactions.is_resting(), "safehouse bed starts a time-costed rest")
	var rest_action: Dictionary = game.interactions.active_action.duplicate()
	game.interactions.active_action = {}
	game.player.interaction_locked = false
	game.interactions._complete_action(rest_action)
	_expect(game.milestones["rest"], "completed bed interaction advances the rest milestone")

	if failures.is_empty():
		print("MVP smoke test passed.")
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures.append("FAIL: %s" % description)
