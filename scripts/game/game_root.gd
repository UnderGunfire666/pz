class_name MVPGameRoot
extends Node2D

var world_map: WorldMap
var visibility: VisibilitySystem
var actor_layer: Node2D
var player: PlayerController
var camera: Camera3D
var world_3d_view: World3DView
var rotating_camera := false
var player_state := PlayerState.new()
var inventory := InventoryGrid.new(Vector2i(6, 4), 12.0)
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


func _ready() -> void:
	GameTime.elapsed_game_seconds = 8.0 * 3600.0
	GameTime.last_advanced_game_seconds = 0.0
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	world_map = WorldMap.new()
	world_map.name = "WorldMap"
	add_child(world_map)

	actor_layer = Node2D.new()
	actor_layer.name = "Actors"
	actor_layer.visible = false
	add_child(actor_layer)

	visibility = VisibilitySystem.new()
	visibility.name = "VisibilitySystem"
	add_child(visibility)
	visibility.setup(world_map)

	player = PlayerController.new()
	player.name = "Player"
	actor_layer.add_child(player)
	player.setup(world_map, player_state, Vector2(4.45, 6.65))
	player.attack_requested.connect(_on_player_attack)

	interactions = InteractionSystem.new()
	interactions.name = "InteractionSystem"
	interactions.visible = false
	add_child(interactions)
	interactions.setup(world_map, player, player_state, inventory, visibility)
	player.action_intent.connect(func() -> void: interactions.interrupt_action())
	interactions.notification_requested.connect(show_notification)
	interactions.food_found.connect(func() -> void: milestones["food"] = true)
	interactions.light_injury_received.connect(func() -> void: milestones["injury"] = true)
	interactions.rest_completed.connect(_on_rest_completed)

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
	npc.setup(world_map, Vector2(4.4, 10.3))
	npc.setup_interactions(interactions)

	world_3d_view = World3DView.new()
	world_3d_view.name = "World3DScene"
	add_child(world_3d_view)
	world_3d_view.setup(world_map, player, actor_layer, visibility, interactions)
	camera = world_3d_view.camera

	hud = MVPHud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(world_3d_view)

	GameTime.speed_changed.connect(_on_speed_changed)
	player_state.died.connect(_on_player_died)
	show_notification("Prototype ready. First objective: enter the safehouse.")


func _process(delta: float) -> void:
	var game_seconds := GameTime.last_advanced_game_seconds
	if game_seconds > 0.0 and not player_state.is_dead():
		player_state.survival.advance(game_seconds, player.exertion(), interactions.is_resting())
		player_state.advance(game_seconds)

	visibility.refresh(player.logical_position, player.facing_direction, player.aim_mode, player.floor_level)
	_update_milestones()
	notification_seconds_left = maxf(0.0, notification_seconds_left - delta)
	if notification_seconds_left <= 0.0 and not player_state.is_dead():
		notification = ""
	if player_state.is_dead() and GameTime.simulation_scale() > 0.0:
		GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	hud.refresh(self)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		rotating_camera = event.pressed
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and rotating_camera:
		world_3d_view.orbit_camera(event.relative)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			hud.adjust_zoom(1.12)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			hud.adjust_zoom(1.0 / 1.12)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			interactions.interrupt_action()
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
	if event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT]:
		interactions.interrupt_action()
	elif event.keycode == KEY_E:
		if interactions.interrupt_action():
			return
	elif event.keycode in [KEY_F, KEY_V, KEY_R]:
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
		nearest.take_damage(1)
		hit_anything = true
	if hit_anything:
		show_notification("Melee hit. The sound may draw more attention.")
	else:
		show_notification("You swing into open space. The noise still carries.")


func _on_player_attacked(_world_position: Vector2) -> void:
	interactions.interrupt_action("Injured")
	milestones["injury"] = true
	if not player_state.is_dead():
		GameTime.set_speed(GameTime.SpeedMode.NORMAL)
		show_notification("A zombie claws you. Check your wounds and create distance.")


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
	show_notification("You died. Enter: new run · F9: load quick save")


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
	var stack := inventory.take_first_with_tag(tag)
	if stack == null:
		show_notification("No %s item in your inventory." % tag)
		return
	if tag == "food":
		player_state.survival.eat(24.0)
		show_notification("You eat %s." % stack.label())
	else:
		player_state.survival.drink(32.0)
		show_notification("You drink %s." % stack.label())


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
