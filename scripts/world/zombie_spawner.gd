class_name ZombieSpawner
extends Node

## Location pressure is data-driven: rural/residential cells seed few zombies;
## commercial cells seed more. No special variants are part of this MVP.
signal player_attacked(world_position: Vector2)

var world_map: WorldMap
var actor_layer: Node2D
var player: PlayerController
var player_state: PlayerState
var visibility_system: VisibilitySystem
var active_zombies: Array[ZombieActor] = []
var respawn_game_seconds := 0.0
const POPULATION_LIMIT := 7


func setup(
		p_world_map: WorldMap,
		p_actor_layer: Node2D,
		p_player: PlayerController,
		p_player_state: PlayerState
	) -> void:
	world_map = p_world_map
	actor_layer = p_actor_layer
	player = p_player
	player_state = p_player_state


func seed_demo_population() -> void:
	# Fixed seed locations make the playable loop repeatable while preserving the
	# pressure logic in data. The rural road has one; the grocery has a cluster.
	for seed in [
		{"position": Vector2(8.4, 9.6), "floor": 0},
		{"position": Vector2(12.1, 6.6), "floor": 0},
		{"position": Vector2(14.7, 5.4), "floor": 0},
		{"position": Vector2(15.3, 6.7), "floor": 0},
		{"position": Vector2(12.2, 3.6), "floor": 0},
		{"position": Vector2(14.5, 5.5), "floor": 1},
		{"position": Vector2(14.5, 4.5), "floor": 2},
	]:
		var seed_position: Vector2 = seed["position"]
		_spawn(seed_position, int(seed["floor"]))


func _process(delta: float) -> void:
	if world_map == null or GameTime.simulation_scale() <= 0.0 or player_state.is_dead():
		return
	respawn_game_seconds += delta * GameTime.GAME_SECONDS_PER_REAL_SECOND * GameTime.simulation_scale()
	# A very conservative pressure refresh: one distant commercial replacement at
	# most every 90 in-game minutes, never a constant horde generator.
	if respawn_game_seconds >= 90.0 * 60.0:
		respawn_game_seconds = 0.0
		if _living_count() >= POPULATION_LIMIT:
			return
		for candidate in [Vector2(15.4, 4.4), Vector2(14.7, 2.6), Vector2(16.1, 7.3)]:
			if _can_respawn_at(candidate, 0):
				_spawn(candidate, 0)
				break


func _spawn(world_position: Vector2, floor: int = 0) -> ZombieActor:
	if not world_map.can_stand(world_position, floor):
		return null
	var zombie := ZombieActor.new()
	actor_layer.add_child(zombie)
	zombie.setup(world_map, player, player_state, world_position, floor)
	zombie.died.connect(_on_zombie_died)
	zombie.attacked_player.connect(func(world_position: Vector2) -> void: player_attacked.emit(world_position))
	active_zombies.append(zombie)
	return zombie


func clear_population() -> void:
	for zombie in active_zombies:
		if not is_instance_valid(zombie):
			continue
		zombie.remove_from_group("zombies")
		zombie.set_process(false)
		zombie.queue_free()
	active_zombies.clear()


func _can_respawn_at(world_position: Vector2, floor: int) -> bool:
	if not world_map.can_stand(world_position, floor):
		return false
	# Avoid spawning below the player too: stacked rooms should stay predictable.
	if world_position.distance_to(player.logical_position) < 6.0:
		return false
	if floor == player.floor_level and visibility_system != null and visibility_system.can_see_position(world_position, floor):
		return false
	for zombie in active_zombies:
		if is_instance_valid(zombie) and zombie.floor_level == floor and zombie.logical_position.distance_to(world_position) < 1.0:
			return false
	return true


func _on_zombie_died(zombie: ZombieActor) -> void:
	active_zombies.erase(zombie)


func _living_count() -> int:
	active_zombies = active_zombies.filter(func(zombie: ZombieActor) -> bool: return is_instance_valid(zombie) and not zombie.is_queued_for_deletion() and zombie.health > 0)
	return active_zombies.size()
