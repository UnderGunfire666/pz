extends Node

var failures: Array[String] = []
var checks := 0
var game: MVPGameRoot


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	_disable_simulation(game)
	GameTime.set_process(false)
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	_test_world_and_stairs()
	_test_structure_occlusion()
	_test_exterior_and_props()
	_test_room_privacy_and_visible_contents()
	_test_visibility_and_combat()
	_test_actions_and_inventory()
	_test_npc_and_paths()
	_test_save_and_pause()
	game.world_3d_view._process(0.0)
	game.hud.refresh(game)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		_place_player(Vector2(4.45, 6.65), 0)
		game.visibility.refresh(game.player.logical_position, Vector2.UP, false, 0)
		game.world_3d_view._process(0.0)
		game.hud.refresh(game)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/mvp-ground.png")
		_place_player(Vector2(14.5, 6.5), 2)
		game.visibility.refresh(game.player.logical_position, Vector2.LEFT, false, 2)
		game.world_3d_view._process(0.0)
		game.hud.refresh(game)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/mvp-upper.png")
		for sample in [
			{"position": Vector2(8.5, 3.5), "name": "exterior-cutaway"},
			{"position": Vector2(11.5, 3.0), "name": "rear-walls"},
			{"position": Vector2(6.3, 6.0), "name": "prop-dither"},
		]:
			_place_player(sample["position"], 0)
			game.visibility.refresh(game.player.logical_position, Vector2.UP, false, 0)
			game.world_3d_view._process(0.0)
			game.hud.refresh(game)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://.godot/mvp-%s.png" % sample["name"])
	await get_tree().process_frame
	if failures.is_empty():
		print("MVP regression passed: %d checks." % checks)
	else:
		for failure in failures:
			push_error(failure)
		print("MVP regression failed: %d / %d checks." % [failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func _disable_simulation(node: Node) -> void:
	node.set_process(false)
	for child in node.get_children():
		_disable_simulation(child)


func _test_structure_occlusion() -> void:
	var view := game.world_3d_view
	_place_player(Vector2(17.5, 13.5), 0)
	view._update_structure_visibility()
	_expect(_all_building_parts_visible(), "outside shows complete buildings")
	_place_player(Vector2(14.5, 6.5), 0)
	view._update_structure_visibility()
	var controller: BuildingVisibilityController = view.building_controllers[view._active_building_id]
	_expect(controller.state == BuildingVisibilityController.State.INTERIOR, "entry activates local interior cutaway")
	_expect(not (controller.roofs[0]["node"] as Node3D).visible, "entry hides roof")
	_expect((controller.floors[0] as BuildingFloor).visible
		and not (controller.floors[1] as BuildingFloor).visible
		and not (controller.floors[2] as BuildingFloor).visible, "current floor visible and all upper floors sliced")
	var front_hidden := false
	var back_visible := false
	for wall: OccludableWall in (controller.floors[0] as BuildingFloor).walls:
		front_hidden = front_hidden or not wall.mesh.visible
		back_visible = back_visible or wall.mesh.visible
	_expect(front_hidden and back_visible, "front wall cutaway preserves back walls")
	# Near a corner, diagonal depth used to incorrectly hide distant rear segments.
	_place_player(Vector2(11.5, 3.0), 0)
	view._update_structure_visibility()
	var rear_intact := true
	var front_cut := true
	for wall: OccludableWall in (controller.floors[0] as BuildingFloor).walls:
		if is_equal_approx(wall.center.y, 2.18) or is_equal_approx(wall.center.x, 10.18):
			rear_intact = rear_intact and wall.mesh.visible
		if is_equal_approx(wall.center.y, 8.82) or is_equal_approx(wall.center.x, 16.82):
			front_cut = front_cut and not wall.mesh.visible
	_expect(rear_intact and front_cut, "all rear wall segments survive near building corner")
	view.camera_yaw += PI
	view._update_structure_visibility()
	var reversed := true
	for wall: OccludableWall in (controller.floors[0] as BuildingFloor).walls:
		if is_equal_approx(wall.center.y, 8.82) or is_equal_approx(wall.center.x, 16.82):
			reversed = reversed and wall.mesh.visible
	_expect(reversed, "camera orbit restores newly rear-facing walls")
	view.camera_yaw -= PI
	view._update_structure_visibility()
	var previous_npc_position := game.npc.logical_position
	game.npc.logical_position = Vector2(5.5, 3.5)
	view._update_structure_visibility()
	_expect(controller.state == BuildingVisibilityController.State.INTERIOR and controller.active_floor == 0,
		"NPC movement cannot change local building visibility")
	game.npc.logical_position = previous_npc_position
	_place_player(Vector2(14.5, 6.5), 1)
	view._update_structure_visibility()
	_expect((controller.floors[1] as BuildingFloor).visible and not (controller.floors[2] as BuildingFloor).visible,
		"floor change updates slice")
	var link: StairLink = game.world_map.stairs["grocery_1_2"]
	_place_player(link.start.lerp(link.end, 0.49), 1)
	game.player.stair_id = link.id
	view._update_structure_visibility()
	_expect(not (controller.floors[2] as BuildingFloor).visible, "stair entry preserves lower slice")
	game.player.logical_position = link.start.lerp(link.end, 0.51)
	view._update_structure_visibility()
	_expect((controller.floors[2] as BuildingFloor).visible, "stair midpoint reveals upper slice")
	for index in range(8):
		_place_player(Vector2(14.5, 6.5), index % 3)
		view._update_structure_visibility()
		_place_player(Vector2(17.5, 13.5), 0)
		view._update_structure_visibility()
	_expect(_all_building_parts_visible(), "rapid entry and exit restores every building part")
	_expect(controller.state == BuildingVisibilityController.State.EXTERIOR_FULL, "exit restores full exterior state")


func _test_exterior_and_props() -> void:
	var view := game.world_3d_view
	var store: BuildingVisibilityController = view.building_controllers["corner_store"]
	_place_player(Vector2(8.5, 3.5), 0)
	view._process(0.0)
	_expect(store.state == BuildingVisibilityController.State.EXTERIOR_CUTAWAY,
		"street player activates tall building exterior cutaway")
	_expect(not (store.floors[1] as BuildingFloor).visible and not (store.roofs[0]["node"] as Node3D).visible,
		"exterior cutaway slices upper floors and roof")
	var visible_walls := 0
	var hidden_walls := 0
	for wall: OccludableWall in (store.floors[0] as BuildingFloor).walls:
		if wall.mesh.visible:
			visible_walls += 1
		else:
			hidden_walls += 1
	_expect(visible_walls > 0 and hidden_walls > 0, "exterior keeps architecture outside player view corridor")
	view.camera_yaw += PI
	game.player.facing_direction = Vector2.LEFT
	view._process(0.0)
	_expect(store.state == BuildingVisibilityController.State.EXTERIOR_FULL, "rotating away restores exterior")
	view.camera_yaw -= PI
	_place_player(Vector2(11.5, 3.0), 0)
	view._process(0.0)
	_expect(store.state == BuildingVisibilityController.State.INTERIOR, "exterior to interior transition keeps correct state")
	_place_player(Vector2(6.3, 6.0), 0)
	view._process(0.0)
	var sign: SmallOccluder = view.small_occluders[0]
	_expect(sign.occluded, "small sign detects partial body occlusion")
	var entry: Dictionary = sign.meshes[1]
	_expect((entry["node"] as MeshInstance3D).material_override == entry["fade"], "small prop uses dedicated dither shader")
	var reveal: Vector4 = (entry["fade"] as ShaderMaterial).get_shader_parameter("reveal_rect")
	_expect(reveal.z > 0.0 and reveal.w > 0.0 and reveal.z < 0.5,
		"dither reveal is localized to projected player body")
	_place_player(Vector2(17.5, 13.5), 0)
	view._process(0.0)
	_expect(not sign.occluded and (entry["node"] as MeshInstance3D).material_override == entry["original"],
		"small prop restores original material after obstruction ends")
	game.player.facing_direction = Vector2.DOWN
	view._process(0.0)
	_expect(_all_building_parts_visible(), "all exterior cuts restored after leaving corridor")
	var index := BuildingOcclusionSystem.new()
	var distant := SmallOccluder.new()
	add_child(distant)
	index.register_zone(OcclusionZone.new(AABB(Vector3(1000, 0, 1000), Vector3.ONE), distant))
	index.update_view("", 0, Vector3.ZERO, Vector3(1, 1, 1).normalized(), 20.0, Vector4.ZERO)
	_expect(index.last_candidate_count == 0, "spatial index skips remote city blocks")
	distant.queue_free()


func _test_room_privacy_and_visible_contents() -> void:
	var view := game.world_3d_view
	game.zombie_spawner.clear_population()
	_place_player(Vector2(13.5, 9.1), 0)
	game.player.facing_direction = Vector2.UP
	view._process(0.0)
	_expect(game.world_map.has_line_of_sight(game.player.logical_position, Vector2(13.5, 8.3), 0),
		"privacy regression uses an open doorway with unobstructed simulation LOS")
	_expect(not game.visibility.can_see_position(Vector2(13.5, 8.3), 0), "outside cannot reveal interior through open doorway")
	var zombie := game.zombie_spawner._spawn(Vector2(13.5, 8.3), 0)
	view._update_actors()
	_expect(zombie != null and not (view.actor_visuals[zombie.get_instance_id()]["root"] as Node3D).visible,
		"indoor zombie concealed even when building is cut away")
	var store: BuildingVisibilityController = view.building_controllers["corner_store"]
	var floor_node: BuildingFloor = store.floors[0]
	var stairs_hidden := true
	for part in floor_node.parts:
		if part["kind"] == "stairs":
			stairs_hidden = stairs_hidden and not (part["node"] as Node3D).visible
	_expect(stairs_hidden, "static interior stair contents concealed outside")
	_place_player(Vector2(13.5, 8.9), 0)
	view._process(0.0)
	_expect((view.actor_visuals[zombie.get_instance_id()]["root"] as Node3D).visible,
		"entering same room reveals visible indoor actor")
	var other_tile := game.world_map.get_tile(Vector2(13.5, 7.5), 0)
	var saved_room := other_tile.room_id
	other_tile.room_id = "separate_test_room"
	_expect(not game.visibility.can_see_position(Vector2(13.5, 7.5), 0), "different room on same floor remains private")
	other_tile.room_id = saved_room
	_place_player(Vector2(13.5, 9.1), 0)
	view._process(0.0)
	_expect(not (view.actor_visuals[zombie.get_instance_id()]["root"] as Node3D).visible,
		"leaving room conceals previously seen contents again")
	game.zombie_spawner.clear_population()
	# A wall misses the player's body but covers contents to the right in the FOV.
	var test_building := BuildingVisibilityController.new()
	view.add_child(test_building)
	test_building.building_id = "visible_contents_test"
	var wall := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 2.7, 0.12)
	wall.mesh = mesh
	wall.position = Vector3(5, 1.35, 4)
	view.add_child(wall)
	test_building.register_part({"node": wall, "floor": 0, "kind": "wall"})
	var index := BuildingOcclusionSystem.new()
	index.register_zone(OcclusionZone.new(OcclusionZone.node_bounds(test_building), test_building))
	var direction := Vector3(0, 1, 1).normalized()
	index.update_view("", 0, Vector3.ZERO, direction, 12, Vector4.ZERO)
	_expect(wall.visible, "off-body wall is retained without visible contents behind it")
	var regions: Array[AABB] = [AABB(Vector3(4.6, 0.03, 1.6), Vector3(0.8, 1.85, 0.8))]
	index.update_view("", 0, Vector3.ZERO, direction, 12, Vector4.ZERO, regions)
	_expect(not wall.visible, "wall hiding FOV contents cuts away even when it misses player body")
	index.update_view("", 0, Vector3.ZERO, direction, 12, Vector4.ZERO)
	_expect(wall.visible, "wall restores when contents leave visible range")
	test_building.queue_free()


func _all_building_parts_visible() -> bool:
	for part in game.world_3d_view.structure_parts:
		if part["kind"] == "stairs":
			continue # Room contents remain concealed outside even when the shell is restored.
		if not (part["node"] as Node3D).is_visible_in_tree():
			return false
	return true


func _test_world_and_stairs() -> void:
	var map := game.world_map
	_expect(map.floor_levels() == [0, 1, 2], "three independent logical floors")
	_expect(map.get_tile(Vector2(1.5, 1.5), 1) == null, "upper outdoor void has no support")
	_expect(map.get_tile(Vector2(14.5, 6.5), 1) != map.get_tile(Vector2(14.5, 6.5), 0), "stacked tile data is independent")
	_expect(map.has_line_of_sight(Vector2(14.5, 4.2), Vector2(14.5, 5.0), 0)
		and not map.has_line_of_sight(Vector2(14.5, 4.2), Vector2(14.5, 5.0), 1), "upper partition does not block ground floor")
	var blocked := map.move_with_wall_slide(Vector2(14.5, 4.1), Vector2(0, 1), 0.22, 1)
	_expect(blocked.y < 4.4, "upper partition blocks physical traversal")
	var outdoor := map.move_with_wall_slide(Vector2(5.5, 3.5), Vector2(3, 0), 0.22, 1)
	_expect(outdoor.x < 6.82, "upper exterior edge cannot be walked through")
	for link: StairLink in map.stairs.values():
		var below_mid := link.start.lerp(link.end, 0.49)
		var above_mid := link.start.lerp(link.end, 0.51)
		_expect(map.display_floor_at(below_mid, link.from_floor, link.id) == link.from_floor
			and map.display_floor_at(above_mid, link.from_floor, link.id) == link.to_floor,
			"%s shows upper floor only after stair midpoint" % link.id)
		_expect(map.display_floor_at(above_mid, link.to_floor, link.id) == link.to_floor
			and map.display_floor_at(below_mid, link.to_floor, link.id) == link.from_floor,
			"%s shows lower floor only after descending past midpoint" % link.id)
		var state := {"position": link.start, "floor": link.from_floor, "stair_id": ""}
		for step in range(160):
			state = map.move_actor(state["position"], state["floor"], link.direction() * 0.04, state["stair_id"])
			if state["floor"] == link.to_floor and state["stair_id"] == "":
				break
		_expect(state["floor"] == link.to_floor and state["position"].distance_to(link.end) < 0.1, "%s reaches upper landing" % link.id)
		for step in range(160):
			state = map.move_actor(state["position"], state["floor"], -link.direction() * 0.04, state["stair_id"])
			if state["floor"] == link.from_floor and state["stair_id"] == "":
				break
		_expect(state["floor"] == link.from_floor and state["position"].distance_to(link.start) < 0.1, "%s descends to lower landing" % link.id)
		state = map.move_actor(link.start, link.from_floor, link.direction() * 0.8)
		var height := map.elevation_at(state["position"], state["floor"], state["stair_id"])
		_expect(height > link.from_floor * 3.0 and height < link.to_floor * 3.0, "%s has continuous elevation" % link.id)
		var perpendicular := Vector2(-link.direction().y, link.direction().x)
		var side := map.move_actor(state["position"], state["floor"], perpendicular * 1.0, state["stair_id"])
		_expect(side["position"].distance_to(state["position"]) < 0.01, "%s prevents sideways departure" % link.id)
		var mid := (link.start + link.end) * 0.5
		var entered := map.move_actor(mid + perpendicular * 0.9, link.from_floor, -perpendicular * 0.9)
		_expect(entered["stair_id"] == "" and entered["floor"] == link.from_floor, "%s rejects side entry" % link.id)
		state = map.move_actor(state["position"], state["floor"], -link.direction() * 1.0, state["stair_id"])
		_expect(state["floor"] == link.from_floor and state["stair_id"] == "", "%s reverses mid-flight" % link.id)
	_expect(map.find_path(Vector2(13.5, 9.5), 0, Vector2(14.5, 6.5), 2).size() > 2, "navigation connects street to third floor")
	_expect(map.find_path(Vector2(13.5, 9.5), 0, Vector2(1.5, 1.5), 2).is_empty(), "navigation rejects unsupported destination")
	_expect(is_finite(map.sound_cost(Vector2(11.25, 7.25), 0, Vector2(11.25, 3.75), 1)), "sound travels through connected stair")
	_expect(map.sound_cost(Vector2(14.5, 6.5), 0, Vector2(14.5, 6.5), 1) > 0.0, "stacked sound has attenuation")


func _test_visibility_and_combat() -> void:
	_place_player(Vector2(14.5, 6.5), 1)
	game.visibility.seen_tiles.clear()
	game.visibility.refresh(game.player.logical_position, Vector2.DOWN, false, 1)
	_expect(game.visibility.can_see_position(Vector2(14.5, 6.9), 1), "FOV sees current floor")
	_expect(not game.visibility.can_see_position(Vector2(14.5, 6.9), 0), "FOV blocks same XY on other floor")
	_expect(not game.visibility.was_tile_seen(Vector2i(14, 6), 0), "exploration memory does not leak between floors")
	game.zombie_spawner.clear_population()
	var zombie := game.zombie_spawner._spawn(Vector2(14.5, 6.9), 1)
	_expect(zombie != null, "zombie can spawn upstairs")
	game.world_3d_view._update_actors()
	var visual: Dictionary = game.world_3d_view.actor_visuals[zombie.get_instance_id()]
	_expect((visual["root"] as Node3D).visible and (visual["health_bar"] as Node3D).visible, "visible upstairs zombie and health bar agree")
	_place_player(Vector2(14.5, 6.5), 0)
	game.visibility.refresh(game.player.logical_position, Vector2.DOWN, false, 0)
	game.world_3d_view._update_actors()
	_expect(not (visual["root"] as Node3D).visible and not (visual["health_bar"] as Node3D).visible, "floor hiding removes both zombie and health bar")
	var health := game.player_state.health
	zombie._process(0.05)
	_expect(is_equal_approx(health, game.player_state.health), "zombie cannot attack through slab")
	game._on_player_attack(game.player.logical_position, Vector2.DOWN)
	_expect(zombie.health == ZombieActor.MAX_HEALTH, "player cannot attack through slab")
	_place_player(Vector2(14.5, 6.5), 1)
	game.visibility.refresh(game.player.logical_position, Vector2.DOWN, false, 1)
	game._on_player_attack(game.player.logical_position, Vector2.DOWN)
	_expect(zombie.health == ZombieActor.MAX_HEALTH - 1, "directional melee damages same-floor target")
	zombie.attack_cooldown = 0.0
	zombie._process(0.01)
	_expect(game.player_state.health < health, "zombie claw causes actual player damage")
	zombie.logical_position = Vector2(14.5, 4.95)
	game.player.logical_position = Vector2(14.5, 4.25)
	zombie.attack_cooldown = 0.0
	health = game.player_state.health
	zombie._process(0.0)
	_expect(is_equal_approx(health, game.player_state.health), "nearby wall blocks zombie melee")
	zombie.take_damage(10)
	_expect(not (visual["health_bar"] as Node3D).visible, "death immediately hides health bar")
	game.zombie_spawner.clear_population()


func _test_actions_and_inventory() -> void:
	_place_player(Vector2(14.5, 6.5), 1)
	var point := game.interactions.nearest_point()
	_expect(point.get("id") == "grocery_upstairs", "upper floor has its own reachable container")
	var container: ContainerData = point["container"]
	game.interactions.request_interaction()
	game.interactions._update_active_action(2.0)
	var progress := container.search_progress_seconds
	_expect(progress > 0.0, "search progress is recorded during action")
	var move := InputEventKey.new()
	move.keycode = KEY_W
	move.pressed = true
	game._unhandled_input(move)
	_expect(game.interactions.active_action.is_empty() and not game.player.interaction_locked, "movement intent cancels search immediately")
	game.interactions.request_interaction()
	_expect(is_equal_approx(game.interactions.active_action["remaining"], 360.0 - progress), "search resumes saved progress")
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	game.interactions._update_active_action(5)
	_expect(is_equal_approx(progress, container.search_progress_seconds), "pause freezes search")
	GameTime.set_speed(GameTime.SpeedMode.FAST)
	game.interactions._update_active_action(1)
	_expect(is_equal_approx(container.search_progress_seconds, progress + 72.0), "3x search advances at correct game-time rate")
	game.interactions._update_active_action(5)
	_expect(container.searched and not game.inventory.placements.is_empty(), "upper loot search completes and transfers supplies")
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	var stack: ItemStack = game.inventory.placements[0]["stack"]
	var quantity := stack.quantity
	game.inventory.take_first_with_tag("food")
	_expect(stack.quantity == quantity - 1, "consume removes one unit, not entire stack")
	_place_player(Vector2(8.5, 7.5), 1)
	var wounds := game.player_state.wounds.size()
	game.interactions._check_hazards()
	_expect(game.player_state.wounds.size() == wounds, "ground hazard cannot injure upstairs")
	_place_player(Vector2(8.5, 7.5), 0)
	game.interactions._check_hazards()
	_expect(game.player_state.wounds.size() == wounds + 1, "ground hazard applies one wound")
	_place_player(Vector2(5.5, 3.5), 1)
	game.interactions.request_interaction()
	_expect(game.interactions.is_resting(), "upstairs bed supports rest")
	game.interactions.interrupt_action("Test injury")
	_expect(not game.player.interaction_locked, "rest can be interrupted")
	game.interactions.request_interaction()
	game.interactions._update_active_action(40)
	game.interactions.request_interaction()
	_expect(game.interactions.is_resting(), "rest can be repeated")
	game.interactions.interrupt_action()
	# Known contents must remain collectible after an initially full inventory.
	var known: ContainerData = game.interactions.points[1]["container"]
	known.searched = true
	game.inventory.placements.clear()
	_place_player(Vector2(12.7, 6.5), 0)
	game.interactions.request_interaction()
	_expect(known.contents.is_empty() and game.inventory.current_weight() > 0, "known container leftovers can be collected")
	var before := game.inventory.current_weight()
	game.inventory.sort_items()
	_expect(is_equal_approx(before, game.inventory.current_weight()), "sorting preserves all item weight")
	game.inventory.placements.clear()
	_place_player(Vector2(4.5, 7.0), 0)
	var test_point := game.interactions.nearest_point()
	_expect(test_point.get("id") == "test_supply_cache", "test supply cache is reachable at spawn")
	game.interactions.request_interaction()
	game.interactions._update_active_action(30.0)
	var test_container: ContainerData = test_point["container"]
	_expect(test_container.searched and test_container.contents.is_empty(), "test cache loot transfers to backpack")
	_expect(game.inventory.placements.size() == 3 and game.inventory.current_weight() > 0.0,
		"test items exercise distinct inventory sizes and weights")


func _test_npc_and_paths() -> void:
	game.npc.logical_position = Vector2(3.5, 10.5)
	game.npc.floor_level = 0
	game.npc.stair_id = ""
	game.npc.survival.hunger = 20
	game.npc.survival.thirst = 80
	game.npc._choose_goal()
	var pantry: ContainerData = game.interactions.points.back()["container"]
	var stock: ItemStack = pantry.contents[0]
	var count := stock.quantity
	for step in range(10):
		game.npc._process(0.5)
	_expect(game.npc.survival.hunger > 30 and stock.quantity < count, "NPC consumes finite shared food to satisfy hunger")
	game.npc.target_position = game.npc.home_position
	game.npc.target_floor = 1
	game.npc.reset_navigation()
	for step in range(600):
		game.npc._move_toward_target(0.08)
		if game.npc.floor_level == 1 and game.npc.logical_position.distance_to(game.npc.home_position) < 0.2:
			break
	_expect(game.npc.floor_level == 1 and game.npc.logical_position.distance_to(game.npc.home_position) < 0.2, "NPC follows stairs to upstairs home (at %s F%d stair=%s)" % [game.npc.logical_position, game.npc.floor_level, game.npc.stair_id])
	game.npc.survival.hunger = 90
	game.npc.survival.thirst = 90
	game.npc.survival.fatigue = 70
	game.npc._choose_goal()
	var fatigue := game.npc.survival.fatigue
	game.npc._process(1.0)
	_expect(game.npc.survival.fatigue < fatigue, "NPC actually recovers fatigue at upstairs home")
	var zombie := game.zombie_spawner._spawn(Vector2(13.5, 9.5), 0)
	zombie.target_position = Vector2(14.5, 6.5)
	zombie.target_floor = 2
	zombie.has_target = true
	for step in range(1800):
		zombie._move_toward_target(0.08)
		if zombie.floor_level == 2 and zombie.logical_position.distance_to(zombie.target_position) < 0.2:
			break
	_expect(zombie.floor_level == 2 and zombie.logical_position.distance_to(zombie.target_position) < 0.2,
		"zombie navigation traverses both stair flights to third floor (at %s F%d stair=%s)" % [zombie.logical_position, zombie.floor_level, zombie.stair_id])
	zombie.target_position = Vector2(13.5, 9.5)
	zombie.target_floor = 0
	zombie.reset_navigation()
	for step in range(1800):
		zombie._move_toward_target(0.08)
		if zombie.floor_level == 0 and zombie.logical_position.distance_to(zombie.target_position) < 0.2:
			break
	_expect(zombie.floor_level == 0 and zombie.logical_position.distance_to(zombie.target_position) < 0.2, "zombie descends two flights and exits building")
	game.zombie_spawner.clear_population()
	var link: StairLink = game.world_map.stairs["grocery_0_1"]
	_place_player(link.start + link.direction() * 0.4, 0)
	game.player.stair_id = link.id
	zombie = game.zombie_spawner._spawn(link.start, 0)
	zombie._process(0.01)
	_expect(zombie.has_target and zombie.target_floor == 1, "seeing player enter stairs creates upstairs pursuit goal")
	zombie.logical_position = link.start + link.direction() * 0.25
	zombie.stair_id = link.id
	zombie.attack_cooldown = 0.0
	var health := game.player_state.health
	zombie._process(0.0)
	_expect(game.player_state.health < health, "zombie can attack player on same stair, no stair invulnerability")
	game.zombie_spawner.clear_population()


func _test_save_and_pause() -> void:
	var link: StairLink = game.world_map.stairs["safehouse_0_1"]
	_place_player(link.start + link.direction() * 0.8, 0)
	game.player.stair_id = link.id
	game.npc.cancel_current_task()
	var zombie := game.zombie_spawner._spawn(link.start, 0)
	zombie.logical_position = link.start + link.direction() * 0.4
	zombie.stair_id = link.id
	zombie.target_position = Vector2(5.5, 3.5)
	zombie.target_floor = 1
	zombie.has_target = true
	var data := QuickSave.snapshot(game)
	_expect(QuickSave.validate(data, game), "snapshot schema accepts a real stair traversal state")
	var invalid := data.duplicate(true)
	invalid["player"]["floor"] = 99
	_expect(not QuickSave.validate(invalid, game), "invalid floor save is rejected before mutation")
	var saved_position := game.player.logical_position
	var path := "/tmp/pz-mvp-check-%d.save" % Time.get_ticks_usec()
	_expect(QuickSave.save_game(game, path), "save writes complete versioned snapshot")
	_expect(QuickSave.save_game(game, path), "saving existing slot atomically replaces previous snapshot")
	_place_player(Vector2(4.45, 6.65), 0)
	_expect(QuickSave.load_game(game, path), "save reload succeeds")
	_expect(game.player.logical_position.is_equal_approx(saved_position) and game.player.stair_id == link.id, "load restores mid-stair position and connector")
	_expect(game.zombie_spawner.active_zombies.size() == 1 and game.zombie_spawner.active_zombies[0].stair_id == link.id, "load restores zombie in stair opening rather than dropping it")
	zombie = game.zombie_spawner.active_zombies[0]
	for step in range(500):
		zombie._move_toward_target(0.08)
		if zombie.floor_level == 1 and zombie.logical_position.distance_to(zombie.target_position) < 0.2:
			break
	_expect(zombie.floor_level == 1 and zombie.stair_id.is_empty(), "restored AI rebuilds path and leaves staircase")
	_expect(GameTime.simulation_scale() == 0.0, "load is paused for safe continuation")
	var old_cooldown := game.player._attack_cooldown_left
	game.player._process(1.0)
	_expect(is_equal_approx(old_cooldown, game.player._attack_cooldown_left), "pause freezes player attack cooldown")
	DirAccess.remove_absolute(path)
	game.zombie_spawner.clear_population()
	game.player.stair_id = ""
	_place_player(Vector2(4.45, 6.65), 0)
	game.player_state.add_wound("Scratch", "arm", 1.0, true)
	_expect(game.player_state.is_dead(), "repeated damage has terminal player consequence")
	_expect(not "virus" in game.player_state.visible_wound_summary(), "wound UI does not disclose zombie-virus state")
	game.player_state.health = PlayerState.MAX_HEALTH
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)


func _place_player(pos: Vector2, level: int) -> void:
	game.player.logical_position = pos
	game.player.floor_level = level
	game.player.stair_id = ""


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		failures.append("FAIL: %s" % description)
