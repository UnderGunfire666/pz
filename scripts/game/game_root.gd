class_name MVPGameRoot
extends Node2D

var world_map: WorldMap
var actor_layer: Node2D
var player: PlayerController
var camera: Camera3D
var world_3d_view: World3DView
var mouse_released := false
var character_catalog := CharacterCatalog.new()
var player_state := PlayerState.new()
var inventory := InventoryGrid.new(false)
var zombie_spawner: ZombieSpawner
var npc: SurvivorNPC
var interactions: InteractionSystem
var hud: MVPHud
var combat_feedback: CombatFeedback

var milestones := {
	"safehouse": false,
	"food": false,
	"injury": false,
	"avoid": false,
	"rest": false,
	"explore": false,
}
var notification := ""
var notification_seconds_left := 0.0
var encounter_origin := Vector2.ZERO
var encountered_zombie := false
var rest_origin := Vector2.ZERO
var rest_floor := 0
var startup_timings_ms: Dictionary = {}
var _startup_started_usec := 0
var _startup_stage_usec := 0
var _startup_report_pending := true


func _startup_mark(stage: String) -> void:
	var now := Time.get_ticks_usec()
	startup_timings_ms[stage] = float(now - _startup_stage_usec) / 1000.0
	_startup_stage_usec = now
	print("[Startup] %s: %.2f ms" % [stage, startup_timings_ms[stage]])


func _ready() -> void:
	_startup_started_usec = Time.get_ticks_usec()
	_startup_stage_usec = _startup_started_usec
	print("[Startup] Engine start to game _ready: %.2f ms" % (float(_startup_started_usec) / 1000.0))
	GameTime.elapsed_game_seconds = 8.0 * 3600.0
	GameTime.last_advanced_game_seconds = 0.0
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	world_map = WorldMap.new()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map="):
			var authored := load(argument.trim_prefix("--map=")) as MapDefinition
			if authored != null: world_map.definition = authored
	world_map.name = "WorldMap"
	add_child(world_map)
	_startup_mark("Map + navigation")

	actor_layer = Node2D.new()
	actor_layer.name = "Actors"
	actor_layer.visible = false
	add_child(actor_layer)

	player = PlayerController.new()
	player_state.setup_character(character_catalog)
	player_state.setup_inventory(inventory)
	inventory.contents("two_hands").append(ItemStack.new(ItemDefinition.baseball_bat()))
	ClothingCatalog.starter_outfit(inventory)
	inventory.revision += 1
	player.name = "Player"
	actor_layer.add_child(player)
	player.setup(world_map, player_state, world_map.definition.player_spawn)
	player.attack_impact_requested.connect(_on_player_attack)
	_startup_mark("Player + character data")

	interactions = InteractionSystem.new()
	interactions.name = "InteractionSystem"
	interactions.visible = false
	add_child(interactions)
	interactions.setup(world_map, player, player_state, inventory)
	player_state.rags_requested.connect(_spawn_destroyed_clothing_rags)
	player.action_intent.connect(func() -> void: interactions.interrupt_action())
	interactions.notification_requested.connect(show_notification)
	interactions.food_found.connect(func() -> void: milestones["food"] = true)
	interactions.light_injury_received.connect(func() -> void: milestones["injury"] = true)
	interactions.rest_completed.connect(_on_rest_completed)
	_startup_mark("Interactions + loot")

	zombie_spawner = ZombieSpawner.new()
	zombie_spawner.name = "ZombieSpawner"
	add_child(zombie_spawner)
	zombie_spawner.setup(world_map, actor_layer, player, player_state)
	zombie_spawner.seed_demo_population()
	zombie_spawner.player_attacked.connect(_on_player_attacked)

	npc = SurvivorNPC.new()
	npc.name = "SurvivorNPC"
	actor_layer.add_child(npc)
	npc.setup(world_map, world_map.definition.npc_spawn, player)
	npc.setup_interactions(interactions)
	_startup_mark("Zombies + NPC")

	world_3d_view = World3DView.new()
	world_3d_view.name = "World3DScene"
	add_child(world_3d_view)
	world_3d_view.setup(world_map, player, actor_layer, interactions)
	camera = world_3d_view.camera
	combat_feedback = CombatFeedback.new()
	combat_feedback.name = "CombatFeedback"
	add_child(combat_feedback)
	_startup_mark("3D chunks + rendering")

	hud = MVPHud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(world_3d_view)
	for panel: Control in [hud.details, hud.character_panel, hud.character_creation_panel, hud.help_panel]:
		panel.visibility_changed.connect(_sync_mouse_capture)
	_sync_mouse_capture()

	GameTime.speed_changed.connect(_on_speed_changed)
	player_state.died.connect(_on_player_died)
	show_notification("Prototype ready. First objective: enter the safehouse.")
	_startup_mark("HUD + final setup")


func _process(delta: float) -> void:
	_sync_mouse_capture()
	var game_seconds := GameTime.last_advanced_game_seconds
	if game_seconds > 0.0 and not player_state.is_dead():
		StatusConfig.AMBIENT_TEMPERATURE = StatusConfig.ambient_temperature_at(GameTime.elapsed_game_seconds)
		var nearby_counts := local_zombie_counts()
		if interactions.is_resting() and int(nearby_counts["danger"]) > 0:
			interactions.interrupt_action("Danger woke you")
		player_state.advance(game_seconds, player.exertion(), interactions.is_resting(),
			int(nearby_counts["nearby"]), player.exertion() > 0.0)
		if interactions.is_resting() and not player_state.effect_active("sleeping_pill") and (player_state.pain >= 60.0 or player_state.anxiety >= 60.0):
			interactions.interrupt_action("Pain or anxiety woke you")
		inventory.advance_item_states(game_seconds)

	_update_milestones()
	notification_seconds_left = maxf(0.0, notification_seconds_left - delta)
	if notification_seconds_left <= 0.0 and not player_state.is_dead():
		notification = ""
	if player_state.is_dead() and GameTime.simulation_scale() > 0.0:
		GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	hud.refresh(self)
	if _startup_report_pending:
		_startup_report_pending = false
		_startup_mark("First gameplay update")
		startup_timings_ms["Game initialization total"] = float(Time.get_ticks_usec() - _startup_started_usec) / 1000.0
		startup_timings_ms["Engine start to first update"] = float(Time.get_ticks_usec()) / 1000.0
		print("[Startup] Game initialization total: %.2f ms; engine start to first update: %.2f ms" % [
			startup_timings_ms["Game initialization total"], startup_timings_ms["Engine start to first update"]])


func _sync_mouse_capture() -> void:
	if hud == null or player == null:
		return
	var blocked := mouse_released or player_state.is_dead() or hud.has_open_panel()
	player.controls_enabled = not blocked
	hud.crosshair.visible = not blocked
	var desired := Input.MOUSE_MODE_VISIBLE if blocked else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != desired:
		Input.mouse_mode = desired


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		mouse_released = true
		_sync_mouse_capture()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		interactions.interrupt_action()
		if hud.has_open_panel():
			hud.close_panels()
		else:
			mouse_released = true
		_sync_mouse_capture()
		get_viewport().set_input_as_handled()
		return
	if hud != null and hud.character_creation_panel != null and hud.character_creation_panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		mouse_released = false
		hud.toggle_inventory()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		mouse_released = false
		hud.toggle_character_panel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and player.controls_enabled:
		world_3d_view.orbit_camera(event.relative)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if hud != null and hud.character_creation_panel != null and hud.character_creation_panel.visible:
		return
	if event is InputEventMouseButton:
		if not event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				# Input events arrive before the next controller tick; clear the visual
				# stance now so releasing RMB never leaves a one-frame layer overlay.
				player.aim_mode = false
			return
		if not player.controls_enabled:
			if event.button_index == MOUSE_BUTTON_LEFT and not hud.has_open_panel() and not player_state.is_dead():
				mouse_released = false
				_sync_mouse_capture()
				get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not player.aim_mode:
				return
			interactions.interrupt_action()
			var switchable := inventory.held_switchable()
			if player.aim_mode and not switchable.is_empty() and inventory.held_weapon() == null:
				inventory.toggle_switchable(switchable["unit"]["uid"])
				show_notification("%s switched %s." % [switchable["stack"].definition.display_name,
					"on" if switchable["unit"].get("switched_on", false) else "off"])
				return
			player.try_attack()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			interactions.interrupt_action()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F9:
		QuickSave.load_game(self)
		return
	if event.keycode == KEY_F10:
		show_notification("Render chunks: %s" % world_3d_view.streamer.stats())
		return
	if player_state.is_dead():
		if event.keycode == KEY_ENTER:
			get_tree().reload_current_scene()
		return
	if event.keycode == KEY_F5:
		QuickSave.save_game(self)
		return
	if event.keycode == KEY_ESCAPE:
		interactions.interrupt_action()
		return
	if not player.controls_enabled:
		return
	if interactions.is_resting() and event.keycode in [KEY_SPACE, KEY_1, KEY_2]:
		return
	if event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT]:
		interactions.interrupt_action()
	elif event.keycode in [KEY_F, KEY_V]:
		interactions.interrupt_action()
	match event.keycode:
		KEY_E:
			interactions.request_interaction()
		KEY_F:
			_consume("food")
		KEY_V:
			_consume("water")
		KEY_R:
			interactions.request_sorting()
		KEY_SPACE:
			GameTime.toggle_pause()
		KEY_1:
			GameTime.set_speed(GameTime.SpeedMode.NORMAL)
		KEY_2:
			GameTime.set_speed(GameTime.SpeedMode.FAST)


func _on_player_attack(_attack_position: Vector2, direction: Vector2) -> void:
	if player_state.is_dead() or GameTime.simulation_scale() <= 0.0:
		return
	var hit_anything := false
	var weapon := inventory.held_weapon()
	var reach := ActorCombat.WEAPON_REACH if weapon != null else ActorCombat.PLAYER_REACH
	var nearest: ZombieActor = null
	var hit: Dictionary = {}
	if weapon != null and weapon.definition.weapon_hitbox_size != Vector3.ZERO:
		var weapon_result := ActorCombat.select_weapon_target(player, zombie_spawner.active_zombies,
			player.look_direction(direction), weapon.definition.weapon_hitbox_size)
		nearest = weapon_result.get("target") as ZombieActor
		hit = weapon_result.get("hit", {})
	else:
		nearest = PlayerTargeting.melee_target(player, zombie_spawner.active_zombies, player.look_direction(direction), reach)
		if nearest != null: hit = ActorCombat.contact(player, nearest, player.look_direction(direction), reach)
	if nearest != null:
		if hit.is_empty(): return
		nearest.receive_hit(inventory.attack_damage(), hit["region"])
		if inventory.held_weapon() == null and nearest.health > 0:
			var shoved := world_map.move_actor(nearest.logical_position, nearest.floor_level, direction.normalized() * 0.3, nearest.stair_id)
			nearest.logical_position = shoved["position"]
			nearest.floor_level = shoved["floor"]
			nearest.stair_id = shoved["stair_id"]
		elif nearest.health > 0:
			ActorCombat.apply_hit_recoil(nearest, direction, 0.22)
		hit_anything = true
	if hit_anything:
		if weapon != null:
			NoiseBus.emit_action_noise(player, "player_melee_hit")
			combat_feedback.play_bat_impact()
			world_3d_view.play_hit_camera_shake()
		show_notification("%s hit: %s." % [inventory.attack_type().capitalize(), nearest.last_hit_region])
	else:
		show_notification("You swing into open space. The noise still carries.")


func _on_player_attacked(_world_position: Vector2) -> void:
	world_3d_view.third_person_equipment.hurt_remaining = 0.3
	interactions.interrupt_action("Injured")
	milestones["injury"] = true
	if not player_state.is_dead():
		GameTime.set_speed(GameTime.SpeedMode.NORMAL)
		show_notification("A zombie claws you. Check your wounds and create distance.")


func _spawn_destroyed_clothing_rags(count: int) -> void:
	if count > 0:
		interactions.spawn_ground_stack(ItemStack.new(ClothingSystem.rag_definition(), count))


func _on_player_died() -> void:
	interactions.interrupt_action("You collapsed")
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	show_notification("You died%s. Enter: new run · F9: load quick save" % (" from the infection" if player_state.should_reanimate() else ""))


func _update_milestones() -> void:
	if world_map.is_safehouse(player.logical_position, player.floor_level):
		milestones["safehouse"] = true
	for zombie in zombie_spawner.active_zombies:
		if not is_instance_valid(zombie):
			continue
		if zombie.floor_level != player.floor_level:
			continue
		if world_map.has_line_of_sight(player.logical_position, zombie.logical_position, player.floor_level, zombie.floor_level):
			encountered_zombie = true
			encounter_origin = player.logical_position
	if encountered_zombie and player.logical_position.distance_to(encounter_origin) > 2.0:
		milestones["avoid"] = true
	if milestones["rest"] and (player.logical_position.distance_to(rest_origin) > 2.0 or player.floor_level != rest_floor):
		milestones["explore"] = true


func _on_rest_completed() -> void:
	milestones["rest"] = true
	rest_origin = player.logical_position
	rest_floor = player.floor_level


func _consume(tag: String) -> void:
	if player_state.is_dead() or GameTime.simulation_scale() <= 0.0:
		return
	var uid := inventory.first_with_tag(tag)
	if uid.is_empty():
		show_notification("No %s item in your inventory." % tag)
		return
	interactions.request_use(uid)


func show_notification(message: String) -> void:
	notification = message
	notification_seconds_left = 4.5


func _on_speed_changed(mode_name: String, _simulation_scale: float) -> void:
	show_notification("Time speed: %s" % mode_name)


func objective_text() -> String:
	if not milestones["safehouse"]:
		return "1/5  Enter the safehouse through its ground-floor doorway."
	if not milestones["food"]:
		return "2/5  Find food: aim at a cabinet and press [E]; more supplies are upstairs."
	if not milestones["avoid"]:
		return "3/5  Spot a zombie, then create distance; they can follow stairs."
	if not milestones["rest"]:
		return "4/5  Return to a safehouse bed and rest with [E]."
	if not milestones["explore"]:
		return "5/5  Leave home and continue exploring."
	return "Loop complete. Keep exploring, managing sound, supplies, and time."


func local_zombie_count(radius: float = 4.0) -> int:
	var count := 0
	for zombie: ZombieActor in zombie_spawner.active_zombies:
		if is_instance_valid(zombie) and zombie.floor_level == player.floor_level and world_map.has_line_of_sight(player.logical_position, zombie.logical_position, player.floor_level, zombie.floor_level) and player.logical_position.distance_to(zombie.logical_position) <= radius:
			count += 1
	return count


func local_zombie_counts() -> Dictionary:
	var result := {"danger": 0, "nearby": 0}
	for zombie: ZombieActor in zombie_spawner.active_zombies:
		if not is_instance_valid(zombie) or zombie.floor_level != player.floor_level:
			continue
		var distance := player.logical_position.distance_to(zombie.logical_position)
		if distance > 6.0 or not world_map.has_line_of_sight(player.logical_position, zombie.logical_position, player.floor_level, zombie.floor_level):
			continue
		result["nearby"] = int(result["nearby"]) + 1
		if distance <= 4.0:
			result["danger"] = int(result["danger"]) + 1
	return result
