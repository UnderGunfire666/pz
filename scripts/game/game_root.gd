class_name MVPGameRoot
extends Node2D

var world_map: WorldMap
var visibility: VisibilitySystem
var actor_layer: Node2D
var player: PlayerController
var camera: Camera3D
var world_3d_view: World3DView
var rotating_camera := false
var character_catalog := CharacterCatalog.new()
var player_state := PlayerState.new()
var inventory := InventoryGrid.new(false)
var zombie_spawner: ZombieSpawner
var npc: SurvivorNPC
var interactions: InteractionSystem
var hud: MVPHud

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
# FOV changes drive fog uploads, interior-content clipping and cutaways. They
# need to feel immediate, but do not need to execute once per rendered frame.
# Thirty updates per second leaves the delay below a frame pair while avoiding
# repeated CPU/image work during continuous movement.
const VISIBILITY_REFRESH_INTERVAL := 1.0 / 30.0
var _visibility_refresh_left := 0.0
var _last_visibility_floor := -999
var _last_visibility_stair := "__unset__"


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

	visibility = VisibilitySystem.new()
	visibility.name = "VisibilitySystem"
	add_child(visibility)
	visibility.setup(world_map)

	player = PlayerController.new()
	player_state.setup_character(character_catalog)
	player_state.setup_inventory(inventory)
	player.name = "Player"
	actor_layer.add_child(player)
	player.setup(world_map, player_state, world_map.definition.player_spawn)
	player.attack_requested.connect(_on_player_attack)
	_refresh_player_visibility(true)
	_startup_mark("Player + character data")

	interactions = InteractionSystem.new()
	interactions.name = "InteractionSystem"
	interactions.visible = false
	add_child(interactions)
	interactions.setup(world_map, player, player_state, inventory, visibility)
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
	zombie_spawner.visibility_system = visibility
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
	world_3d_view.setup(world_map, player, actor_layer, visibility, interactions)
	camera = world_3d_view.camera
	_startup_mark("3D world + visibility")

	hud = MVPHud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(world_3d_view)

	GameTime.speed_changed.connect(_on_speed_changed)
	player_state.died.connect(_on_player_died)
	show_notification("Prototype ready. First objective: enter the safehouse.")
	_startup_mark("HUD + final setup")


func _process(delta: float) -> void:
	var game_seconds := GameTime.last_advanced_game_seconds
	if game_seconds > 0.0 and not player_state.is_dead():
		var nearby_counts := local_zombie_counts()
		if interactions.is_resting() and int(nearby_counts["danger"]) > 0:
			interactions.interrupt_action("Danger woke you")
		player_state.advance(game_seconds, player.exertion(), interactions.is_resting(),
			int(nearby_counts["nearby"]), player.exertion() > 0.0)

	_refresh_player_visibility(false, delta)
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


func _refresh_player_visibility(force: bool = false, delta: float = 0.0) -> void:
	_visibility_refresh_left = maxf(0.0, _visibility_refresh_left - delta)
	var state_changed := (
		player.floor_level != _last_visibility_floor
		or player.stair_id != _last_visibility_stair
	)
	if not force and not state_changed and _visibility_refresh_left > 0.0:
		return
	visibility.refresh(player.logical_position, player.facing_direction, player.aim_mode, player.floor_level,
		player_state.perception_multiplier())
	_visibility_refresh_left = VISIBILITY_REFRESH_INTERVAL
	_last_visibility_floor = player.floor_level
	_last_visibility_stair = player.stair_id


func _input(event: InputEvent) -> void:
	if hud != null and hud.character_creation_panel != null and hud.character_creation_panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		hud.toggle_inventory()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		hud.toggle_character_panel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		rotating_camera = event.pressed
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and rotating_camera:
		world_3d_view.orbit_camera(event.relative)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if hud != null and hud.character_creation_panel != null and hud.character_creation_panel.visible:
		return
	if event is InputEventMouseButton:
		if not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if not hud.pointer_over_page(event.position): hud.adjust_zoom(1.12)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not hud.pointer_over_page(event.position): hud.adjust_zoom(1.0 / 1.12)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
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


func _on_player_attack(attack_position: Vector2, direction: Vector2) -> void:
	if player_state.is_dead() or GameTime.simulation_scale() <= 0.0:
		return
	var hit_anything := false
	var nearest: ZombieActor = null
	var nearest_distance := INF
	for zombie: ZombieActor in zombie_spawner.active_zombies.duplicate():
		if not is_instance_valid(zombie) or zombie.health <= 0 or zombie.is_queued_for_deletion():
			continue
		if not melee_contact(zombie, 1.25):
			continue
		var offset := zombie.logical_position - attack_position
		var angle := absf(wrapf(offset.angle() - direction.angle(), -PI, PI))
		if angle <= deg_to_rad(54.0) and offset.length() < nearest_distance:
			nearest = zombie
			nearest_distance = offset.length()
	if nearest != null:
		nearest.take_damage(inventory.attack_damage())
		if inventory.held_weapon() == null and nearest.health > 0:
			var shoved := world_map.move_actor(nearest.logical_position, nearest.floor_level, direction.normalized() * 0.3, nearest.stair_id)
			nearest.logical_position = shoved["position"]
			nearest.floor_level = shoved["floor"]
			nearest.stair_id = shoved["stair_id"]
		hit_anything = true
	if hit_anything:
		show_notification("%s hit." % inventory.attack_type().capitalize())
	else:
		show_notification("You swing into open space. The noise still carries.")


func _on_player_attacked(_world_position: Vector2) -> void:
	interactions.interrupt_action("Injured")
	milestones["injury"] = true
	if not player_state.is_dead():
		GameTime.set_speed(GameTime.SpeedMode.NORMAL)
		show_notification("A zombie claws you. Check your wounds and create distance.")


func _spawn_destroyed_clothing_rags(count: int) -> void:
	if count > 0:
		interactions.spawn_ground_stack(ItemStack.new(ClothingSystem.rag_definition(), count))


func melee_contact(zombie: ZombieActor, attack_range: float) -> bool:
	var height_difference := world_map.elevation_at(player.logical_position, player.floor_level, player.stair_id) - world_map.elevation_at(zombie.logical_position, zombie.floor_level, zombie.stair_id)
	if Vector2(player.logical_position.distance_to(zombie.logical_position), height_difference).length() > attack_range:
		return false
	if not player.stair_id.is_empty() or not zombie.stair_id.is_empty():
		return player.stair_id == zombie.stair_id
	return (player.floor_level == zombie.floor_level
		and world_map.has_line_of_sight(player.logical_position, zombie.logical_position, player.floor_level))


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
		if visibility.can_see_position(zombie.logical_position, zombie.floor_level):
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
		return "2/5  Find food: [E] at a blue container; more supplies are upstairs."
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
		if is_instance_valid(zombie) and zombie.floor_level == player.floor_level and visibility.can_see_position(zombie.logical_position, zombie.floor_level) and player.logical_position.distance_to(zombie.logical_position) <= radius:
			count += 1
	return count


func local_zombie_counts() -> Dictionary:
	var result := {"danger": 0, "nearby": 0}
	for zombie: ZombieActor in zombie_spawner.active_zombies:
		if not is_instance_valid(zombie) or zombie.floor_level != player.floor_level:
			continue
		var distance := player.logical_position.distance_to(zombie.logical_position)
		if distance > 6.0 or not visibility.can_see_position(zombie.logical_position, zombie.floor_level):
			continue
		result["nearby"] = int(result["nearby"]) + 1
		if distance <= 4.0:
			result["danger"] = int(result["danger"]) + 1
	return result
