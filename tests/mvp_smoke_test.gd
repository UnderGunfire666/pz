extends Node

const MAP_MOD_REGISTRY = preload("res://scripts/systems/map_mod_registry.gd")
const MAP_VALIDATOR = preload("res://scripts/systems/map_validator.gd")
const SPATIAL_QUERY_TESTS = preload("res://tests/spatial_query_tests.gd")
const MAP_AUTHORING_TESTS = preload("res://tests/map_authoring_tests.gd")

var failures: Array[String] = []
var checks := 0
var game: MVPGameRoot


func _test_simulation_activation() -> void:
	var spawner := ZombieSpawner.new()
	spawner.setup(game.world_map, game.actor_layer, game.player, game.player_state)
	var zombie := ZombieActor.new()
	zombie.floor_level = game.player.floor_level
	zombie.logical_position = game.player.logical_position
	zombie.set_process(false)
	spawner.active_zombies.append(zombie)
	spawner._refresh_simulation_range()
	_expect(zombie.is_processing(), "nearby zombie wakes without player movement")
	zombie.logical_position += Vector2(100, 100)
	spawner._refresh_simulation_range()
	_expect(not zombie.is_processing(), "zombie leaving simulation radius sleeps while player stays still")
	zombie.free()
	spawner.free()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_map_packages()
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	_expect(not game.hud.character_creation_panel.visible, "startup keeps unfinished character creation hidden")
	await get_tree().process_frame
	game.player_state.character.select_build(game.character_catalog.rules.default_occupation_id, [])
	game.hud.character_creation_panel.hide()
	_disable_simulation(game)
	GameTime.set_process(false)
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	_test_priority_fixes()
	MAP_AUTHORING_TESTS.run(_expect)
	SPATIAL_QUERY_TESTS.run(game, _expect)
	preload("res://tests/hearing_tests.gd").run(game, _expect)
	_test_world_and_stairs()
	ZombiePressureTests.run(game, _expect)
	FirstPersonTests.run(game, _expect)
	WorldStreamingTests.run(game, _expect)
	_test_barrier_rendering()
	_test_visibility_and_combat()
	_test_actions_and_inventory()
	_test_npc_and_paths()
	BackpackTests.run(game, _expect)
	InventoryUpgradeTests.run(game, _expect)
	ClothingTests.run(game, _expect)
	PlayerStatusTests.run(game, _expect)
	CharacterProgressionTests.run(game, _expect)
	_test_save_and_pause()
	_test_simulation_activation()
	game.world_3d_view._process(0.0)
	game.hud.refresh(game)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		if game.inventory.contents("outer_top").is_empty():
			for stack: ItemStack in game.inventory.world["wardrobe"].contents:
				if stack.definition.id == "jacket":
					game.inventory.move_unit(stack.units[0]["uid"], "outer_top")
					break
		_place_player(Vector2(17.5, 13.5), 0)
		game.world_3d_view.sync_view_to_player()
		game.player._attack_flash_left = 0.1
		game.world_3d_view._update_camera(0.0)
		game.world_3d_view._process(0.0)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/mvp-clothing.png")
		game.player._attack_flash_left = 0.0
		_place_player(Vector2(4.45, 6.65), 0)
		game.world_3d_view._process(0.0)
		game.hud.refresh(game)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/mvp-ground.png")
		_place_player(Vector2(14.5, 6.5), 2)
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
			game.world_3d_view._process(0.0)
			game.hud.refresh(game)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://.godot/mvp-%s.png" % sample["name"])
		_place_player(Vector2(5.7, 7.0), 0)
		game.world_3d_view._process(0.0)
		game.hud.details.visible = true
		game.hud.pack_panel.presentation.sides[0]["selected"] = "all_carried"
		game.hud.pack_panel.presentation.sides[1]["selected"] = "test_cabinet_0"
		game.hud.pack_panel.last_signature = ""
		game.hud.refresh(game)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/mvp-backpack.png")
		game.hud.details.hide()
		game.hud.character_panel.show()
		game.hud.character_panel.refresh(game)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/mvp-character.png")
	await get_tree().process_frame
	if failures.is_empty():
		print("MVP regression passed: %d checks." % checks)
	else:
		for failure in failures:
			push_error(failure)
		print("MVP regression failed: %d / %d checks." % [failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_priority_fixes() -> void:
	var state := PlayerStatusTests.fresh_state()
	var garment := ClothingTests.garment("fractional_shirt", "inner_top", ["Torso"],
		{"Torso": 100}, {"Torso": 0.5})
	state.inventory.contents("inner_top").append(garment)
	state.receive_hit("Scratch", "Torso", 1.0, false, 0.0)
	_expect(is_equal_approx(state.body_health["Torso"], 99.5), "half-point damage after clothing stays half a point")
	state.advance(1.0)
	_expect(is_equal_approx(state.wounds[0]["severity"], 0.5), "wound normalization does not magnify fractional severity")
	var restored := PlayerStatusTests.fresh_state()
	restored.load_save_data(state.to_save_data())
	_expect(is_equal_approx(restored.wounds[0]["severity"], 0.5), "fractional wounds survive status save and restore")
	var local_map := WorldMap.new()
	local_map.width = 2
	local_map.height = 2
	var floor_data := FloorData.new(0)
	local_map.floors[0] = floor_data
	for y in range(2):
		for x in range(2):
			floor_data.tiles[Vector2i(x, y)] = WorldTileData.new("floor", true, 0.0, "test", "left" if x == 0 else "right")
	var start := Vector2(0.25, 0.25)
	var end := Vector2(0.75, 0.75)
	_expect(local_map._nav_neighbours_connect(start, end, 0), "navigation accepts clear supported body corridor")
	floor_data.wall_faces.append({"start": Vector2(0.5, 0.7), "end": Vector2(0.5, 1.2)})
	local_map.rebuild_spatial_index()
	_expect(local_map.can_stand(start, 0) and local_map.can_stand(end, 0)
		and local_map.has_line_of_sight(start, end, 0) and not local_map._nav_neighbours_connect(start, end, 0),
		"navigation rejects wall endpoint clearance even with valid endpoints and clear LOS")
	floor_data.wall_faces.clear()
	local_map.rebuild_spatial_index()
	floor_data.tiles.erase(Vector2i(1, 0))
	_expect(not local_map._nav_neighbours_connect(Vector2(0.75, 0.75), Vector2(1.25, 1.25), 0),
		"navigation rejects diagonal unsupported corner")
	var builder := WorldChunkBuilder.new()
	local_map.definition = MapDefinition.new()
	builder.setup(local_map)
	var chunk := builder.build_chunk(Vector2i.ZERO)
	_expect(chunk.get_child_count() == 1, "same-material room floors merge into one static render batch")
	chunk.free()
	local_map.free()
	var zombie := ZombieActor.new()
	zombie.setup(game.world_map, game.player, game.player_state, game.player.logical_position, game.player.floor_level)
	zombie.set_simulation_active(false)
	var noise := NoiseStimulus.new(zombie.logical_position, 10.0, "sleep test", zombie.floor_level, 1.0, GameTime.elapsed_game_seconds)
	zombie.hear_noise(noise)
	_expect(not NoiseBus.noise_emitted.is_connected(zombie.hear_noise) and zombie.awareness == ZombieActor.Awareness.IDLE,
		"dormant zombies unsubscribe from noise and ignore direct hearing calls")
	zombie.set_simulation_active(true)
	zombie.hear_noise(noise)
	_expect(NoiseBus.noise_emitted.is_connected(zombie.hear_noise) and zombie.awareness == ZombieActor.Awareness.SOUND,
		"proximity activation reconnects zombie hearing")
	zombie.free()


func _test_map_packages() -> void:
	var manifest: Resource = load("res://resources/maps/mods/orangeville_base_mod.tres")
	var resolution: Dictionary = MAP_MOD_REGISTRY.resolve_load_order([manifest])
	_expect((resolution["issues"] as Array).is_empty(), "base map package manifest validates")
	var order: Array = resolution["order"]
	_expect(order.size() == 1 and str((order[0] as Resource).get("id")) == "orangeville_base",
		"base map package resolves deterministically")


func _disable_simulation(node: Node) -> void:
	node.set_process(false)
	for child in node.get_children():
		_disable_simulation(child)


func _test_barrier_rendering() -> void:
	var map := game.world_map
	var view := game.world_3d_view
	var id := "safehouse:legacy_door_0"
	var barrier: Dictionary = map.barriers[id]
	var original := map.is_barrier_open(id)
	var midpoint: Vector2 = (barrier["start"] + barrier["end"]) * 0.5
	var edge: Vector2 = (barrier["end"] - barrier["start"]).normalized()
	var inward := Vector2(edge.y, -edge.x)
	map.set_barrier_open(id, true)
	_place_player(midpoint, 0)
	game.player.facing_direction = inward
	game.interactions.request_interaction()
	_expect(not map.is_barrier_open(id) and map.can_stand(game.player.logical_position, 0)
		and game.player.logical_position.distance_to(midpoint) >= WorldMap.ACTOR_RADIUS,
		"closing a door under the player resolves collision overlap")
	_expect(not map.has_line_of_sight(game.player.logical_position, midpoint + inward * 0.55, 0),
		"closed door still blocks gameplay LOS after removing player FOV")
	var count := 0
	var opaque := true
	for key: Vector2i in view.chunk_builder.barrier_chunks[id]:
		var root: Node3D = view.streamer.resident[key]["node"]
		for mesh: MeshInstance3D in root.get_meta("barriers")[id]:
			count += 1
			opaque = opaque and mesh.visible and (mesh.material_override as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	_expect(count == 1 and opaque, "closed door retains exactly one opaque mesh")
	var builds := view.streamer.total_builds
	map.set_barrier_open(id, true)
	_expect(view.streamer.total_builds == builds, "opening a barrier never rebuilds static chunks")
	map.set_barrier_open(id, original)

func _test_world_and_stairs() -> void:
	var map := game.world_map
	_expect(map.definition.id == "orangeville_prototype" and map.width == 64 and map.height == 64,
		"runtime loads the authored 64 by 64 Orangeville map resource")
	_expect(game.world_3d_view.streamer.resident.size() <= 25, "demo map uses bounded horizontal chunks for all floors")
	_expect(MAP_VALIDATOR.validate(map.definition).is_empty(), "authored Orangeville map validates before play")
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
	game.zombie_spawner.clear_population()
	var zombie := game.zombie_spawner._spawn(Vector2(14.5, 6.9), 1)
	_expect(zombie != null, "zombie can spawn upstairs")
	game.world_3d_view._update_actors()
	var visual: Dictionary = game.world_3d_view.actor_visuals[zombie.get_instance_id()]
	_expect((visual["root"] as Node3D).visible and (visual["health_bar"] as Node3D).visible, "visible upstairs zombie and health bar agree")
	_place_player(Vector2(14.5, 6.5), 0)
	game.world_3d_view._update_actors()
	_expect((visual["root"] as Node3D).visible and (visual["health_bar"] as Node3D).visible, "upper-floor actors remain rendered and are naturally occluded by the slab")
	var health := game.player_state.health
	zombie._process(0.05)
	_expect(is_equal_approx(health, game.player_state.health), "zombie cannot attack through slab")
	game._on_player_attack(game.player.logical_position, Vector2.DOWN)
	_expect(zombie.health == ZombieActor.MAX_HEALTH, "player cannot attack through slab")
	_place_player(Vector2(14.5, 6.5), 1)
	game._on_player_attack(game.player.logical_position, Vector2.DOWN)
	_expect(zombie.health == ZombieActor.MAX_HEALTH - 1, "directional melee damages same-floor target")
	zombie.attack_cooldown = 0.0
	var arm_health := float(game.player_state.body_health["Right Arm"])
	zombie._process(0.01)
	_expect(game.player_state.body_health["Right Arm"] < arm_health and is_equal_approx(game.player_state.health, health),
		"zombie claw damages its body region without double-charging overall health")
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
	_expect(game.interactions.active_action.is_empty() and game.interactions.can_access(point["id"]), "viewing a reachable cabinet is immediate and needs no search")
	game.interactions._start_container_search(point)
	game.interactions._update_active_action(2.0)
	var progress := container.search_progress_seconds
	_expect(progress > 0.0, "search progress is recorded during action")
	game.hud.close_panels()
	game.mouse_released = false
	game._sync_mouse_capture()
	var move := InputEventKey.new()
	move.keycode = KEY_W
	move.pressed = true
	game._unhandled_input(move)
	_expect(game.interactions.active_action.is_empty() and not game.player.interaction_locked, "movement intent cancels search immediately")
	game.interactions._start_container_search(point)
	_expect(is_equal_approx(game.interactions.active_action["remaining"], 360.0 - progress), "legacy search resumes saved progress")
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	game.interactions._update_active_action(5)
	_expect(is_equal_approx(progress, container.search_progress_seconds), "pause freezes search")
	GameTime.set_speed(GameTime.SpeedMode.FAST)
	game.interactions._update_active_action(1)
	_expect(is_equal_approx(container.search_progress_seconds, progress + 72.0), "3x search advances at correct game-time rate")
	game.interactions._update_active_action(5)
	_expect(container.searched and not game.inventory.contents(game.inventory.default_destination()).is_empty(), "upper loot search completes and transfers supplies")
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	var stack: ItemStack = game.inventory.contents(game.inventory.default_destination())[0]
	var quantity := stack.quantity
	game.player_state.survival.hunger = 20
	game.interactions.request_use(game.inventory.first_with_tag("food"))
	game.interactions._update_active_action(10.0)
	_expect(stack.quantity == quantity - 1, "consume removes one unit, not entire stack")
	_place_player(Vector2(8.5, 7.5), 1)
	var wounds := game.player_state.wounds.size()
	game.interactions._check_hazards()
	_expect(game.player_state.wounds.size() == wounds, "ground hazard cannot injure upstairs")
	_place_player(Vector2(8.5, 7.5), 0)
	game.interactions._check_hazards()
	_expect(game.player_state.wounds.size() == wounds + 1, "ground hazard applies one wound")
	_place_player(Vector2(5.5, 3.5), 1)
	game.player_state.survival.fatigue = 60.0
	game.interactions.request_interaction()
	_expect(game.interactions.is_resting() and GameTime.speed_mode == GameTime.SpeedMode.SLEEP, "upstairs bed starts unified-time sleep fast-forward")
	game.interactions.interrupt_action("Test injury")
	_expect(not game.player.interaction_locked, "rest can be interrupted")
	game.interactions.request_interaction()
	game.interactions._update_active_action(40)
	game.interactions.request_interaction()
	_expect(game.interactions.is_resting(), "sleep can be repeated while still tired")
	game.interactions.interrupt_action()
	# Known contents must remain collectible after an initially full inventory.
	var known: ContainerData = game.interactions.points[1]["container"]
	known.searched = true
	game.inventory.contents(game.inventory.default_destination()).clear()
	_place_player(Vector2(12.7, 6.5), 0)
	game.interactions.request_batch(known.id, game.inventory.default_destination())
	game.interactions._update_active_action(30.0)
	_expect(known.contents.is_empty() and game.inventory.current_weight() > 0, "known container leftovers can be collected")
	var before := game.inventory.current_weight()
	game.inventory.sort_items()
	_expect(is_equal_approx(before, game.inventory.current_weight()), "sorting preserves all item weight")
	game.inventory.contents(game.inventory.default_destination()).clear()
	_place_player(Vector2(4.5, 7.0), 0)
	var test_point := game.interactions.nearest_point()
	_expect(test_point.get("id") == "test_supply_cache", "test supply cache is reachable at spawn")
	game.interactions.request_batch(test_point["id"], game.inventory.default_destination())
	game.interactions._update_active_action(30.0)
	var test_container: ContainerData = test_point["container"]
	_expect(test_container.contents.is_empty(), "test cache loot transfers without a search prerequisite")
	_expect(game.inventory.contents(game.inventory.default_destination()).size() == 11 and game.inventory.current_weight() > 0.0,
		"test cache provides food, tools, and six medical treatment types")


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
	game.npc.survival.fatigue = 50
	game.npc._choose_goal()
	var fatigue := game.npc.survival.fatigue
	game.npc._process(1.0)
	_expect(game.npc.survival.fatigue > fatigue, "NPC actually recovers fatigue reserve at upstairs home")
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
	_expect(zombie.has_target and zombie.target_stair_id == link.id
		and zombie.target_position.is_equal_approx(game.player.logical_position), "seeing player enter stairs tracks the observed position on that stair")
	zombie.logical_position = link.start + link.direction() * 0.25
	zombie.stair_id = link.id
	zombie.attack_cooldown = 0.0
	var arm_health := float(game.player_state.body_health["Right Arm"])
	zombie._process(0.0)
	_expect(game.player_state.body_health["Right Arm"] < arm_health, "zombie can injure player on same stair, no stair invulnerability")
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
	zombie.awareness = ZombieActor.Awareness.SOUND
	zombie.sound_memory_expires_at = GameTime.elapsed_game_seconds + 42.0
	zombie.last_stimulus_time = GameTime.elapsed_game_seconds
	var data := QuickSave.snapshot(game)
	_expect(QuickSave.validate(data, game), "snapshot schema accepts a real stair traversal state")
	var barrier_id := ""
	for id: String in game.world_map.barriers:
		if game.world_map.barriers[id]["kind"] == "door": barrier_id = id; break
	var saved_barrier_open := game.world_map.is_barrier_open(barrier_id)
	_expect(not barrier_id.is_empty() and game.world_map.set_barrier_open(barrier_id, not saved_barrier_open),
		"barrier state is captured before a door is changed")
	QuickSave.restore(game, data)
	_expect(game.world_map.is_barrier_open(barrier_id) == saved_barrier_open,
		"save/load restores the door state")
	var wrong_map := data.duplicate(true)
	wrong_map["map_identity"]["id"] = "another_map"
	_expect(not QuickSave.validate(wrong_map, game), "save from another map is rejected")
	wrong_map = data.duplicate(true)
	wrong_map["map_identity"]["format_version"] += 1
	_expect(not QuickSave.validate(wrong_map, game), "save map format mismatch is rejected")
	wrong_map = data.duplicate(true)
	wrong_map["map_identity"]["content_hash"] = "changed"
	_expect(not QuickSave.validate(wrong_map, game), "save with changed static map content is rejected")
	var before_restore := game.player.logical_position
	wrong_map["player"]["position"] = Vector2(4.45, 6.65)
	QuickSave.restore(game, wrong_map)
	_expect(game.player.logical_position == before_restore, "map mismatch restore leaves live player untouched")
	var legacy_v9 := data.duplicate(true)
	legacy_v9["version"] = 9
	legacy_v9["seen"] = {Vector3i(1, 1, 0): true}
	var migrated_v9 := QuickSave._migrate_v9(legacy_v9)
	_expect(QuickSave.validate(migrated_v9, game) and not migrated_v9.has("seen") and legacy_v9.has("seen"),
		"v9 exploration is dropped on a copy while the original save remains intact")
	var legacy_path := OS.get_temp_dir().path_join("pz-v9-migration-%d.save" % Time.get_ticks_usec())
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_var(legacy_v9, false)
	legacy_file.close()
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy_path)
	_expect(QuickSave.load_game(game, legacy_path) and FileAccess.get_file_as_bytes(legacy_path) == legacy_bytes
		and not QuickSave.snapshot(game).has("seen"), "loading a real v9 file migrates without modifying its bytes")
	DirAccess.remove_absolute(legacy_path)
	var legacy := data.duplicate(true)
	legacy["version"] = 7
	legacy.erase("map_identity")
	_expect(QuickSave.validate(legacy, game), "version-seven bundled-map save migrates to map-bound schema")
	var definition := MapDefinition.new()
	definition.id = "hash_test"
	var instance := MapBuildingInstanceDefinition.new()
	instance.template = MapBuildingTemplate.new()
	definition.buildings.append(instance)
	var identity := QuickSave.map_identity(definition)
	_expect(identity == QuickSave.map_identity(definition.duplicate(true)), "map fingerprint does not depend on resource instance IDs")
	instance.template.floor_count += 1
	_expect(identity != QuickSave.map_identity(definition), "map fingerprint includes nested building template content")
	var invalid := data.duplicate(true)
	invalid["player"]["floor"] = 99
	_expect(not QuickSave.validate(invalid, game), "invalid floor save is rejected before mutation")
	var saved_position := game.player.logical_position
	var path := OS.get_temp_dir().path_join("pz-mvp-check-%d.save" % Time.get_ticks_usec())
	_expect(QuickSave.save_game(game, path), "save writes complete versioned snapshot")
	_expect(QuickSave.save_game(game, path), "saving existing slot atomically replaces previous snapshot")
	_place_player(Vector2(4.45, 6.65), 0)
	_expect(QuickSave.load_game(game, path), "save reload succeeds")
	_expect(game.player.logical_position.is_equal_approx(saved_position) and game.player.stair_id == link.id, "load restores mid-stair position and connector")
	_expect(game.zombie_spawner.active_zombies.size() == 1 and game.zombie_spawner.active_zombies[0].stair_id == link.id, "load restores zombie in stair opening rather than dropping it")
	zombie = game.zombie_spawner.active_zombies[0]
	_expect(zombie.awareness == ZombieActor.Awareness.SOUND
		and is_equal_approx(zombie.sound_memory_expires_at, GameTime.elapsed_game_seconds + 42.0)
		and game.zombie_spawner.initial_population_count == data["population"]["initial_count"],
		"save/load preserves zombie stimulus memory and finite population ledger without duplication")
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
	game.player_state.add_wound("Bite", "Torso", 100.0, true, 0.0)
	_expect(game.player_state.is_dead(), "torso region reaching zero has a terminal consequence")
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
