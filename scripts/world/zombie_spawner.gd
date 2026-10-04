class_name ZombieSpawner
extends Node

## Owns the finite zombie population. Pressure selects initial placement and
## destinations for physical migration; this node never replenishes deaths.
signal player_attacked(world_position: Vector2)

const ACTIVE_SIMULATION_RADIUS := 24.0

var world_map: WorldMap
var actor_layer: Node2D
var player: PlayerController
var player_state: PlayerState
var area_catalog := ZombieAreaCatalog.new()
var active_zombies: Array[ZombieActor] = []
var population_initialized := false
var initial_population_count := 0
var population_preset := "Normal"
var migration_game_seconds := 0.0
var _simulation_refresh_left := 0.0


func setup(p_world_map: WorldMap, p_actor_layer: Node2D, p_player: PlayerController,
		p_player_state: PlayerState) -> void:
	world_map = p_world_map
	actor_layer = p_actor_layer
	player = p_player
	player_state = p_player_state
	population_preset = area_catalog.rules.population_preset


func seed_demo_population() -> void:
	if population_initialized: return
	# Initial population is selected once from the map heatmap. Legacy area
	# points remain available only as migration destinations; they no longer
	# dictate where a fresh world starts its zombies.
	var candidates := world_map.initial_zombie_spawn_candidates()
	var random := RandomNumberGenerator.new()
	random.seed = hash(world_map.definition.id)
	var population_range := area_catalog.rules.population_range(population_preset)
	var cap := mini(random.randi_range(population_range.x, population_range.y), candidates.size())
	var spawned := 0
	while spawned < cap and not candidates.is_empty():
		var total_weight := 0.0
		for candidate: Dictionary in candidates:
			total_weight += float(candidate["weight"])
		if total_weight <= 0.0:
			break
		var pick := random.randf() * total_weight
		var selected_index := candidates.size() - 1
		for index in range(candidates.size()):
			pick -= float((candidates[index] as Dictionary)["weight"])
			if pick <= 0.0:
				selected_index = index
				break
		var selected: Dictionary = candidates[selected_index]
		candidates.remove_at(selected_index)
		if _spawn(selected["position"] as Vector2, int(selected["floor"]), true) != null:
			spawned += 1
	population_initialized = true
	initial_population_count = _living_count()


func _process(delta: float) -> void:
	if world_map == null or GameTime.simulation_scale() <= 0.0 or player_state.is_dead(): return
	_simulation_refresh_left -= delta
	if _simulation_refresh_left <= 0.0:
		_refresh_simulation_range()
		_simulation_refresh_left = 0.2
	var game_seconds := GameTime.last_advanced_game_seconds
	if game_seconds <= 0.0: return
	migration_game_seconds += game_seconds
	var interval := area_catalog.rules.migration_interval_game_minutes * 60.0
	if migration_game_seconds >= interval:
		migration_game_seconds = fmod(migration_game_seconds, interval)
		_request_one_migration()


func _request_one_migration() -> bool:
	var area_counts := population_by_area()
	for zombie in active_zombies:
		if not is_instance_valid(zombie) or zombie.health <= 0 or zombie.awareness != ZombieActor.Awareness.IDLE: continue
		var source := area_catalog.area(world_map.zombie_area_id_at(zombie.logical_position, zombie.floor_level))
		if source == null: continue
		var destinations: Array[Dictionary] = []
		for area_id in source.adjacent_area_ids:
			var area := area_catalog.area(area_id)
			if area == null: continue
			var score := area.migration_weight() / float(int(area_counts.get(area.id, 0)) + 1)
			destinations.append({"area": area, "score": score})
		destinations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
		for destination_data in destinations:
			var destination: ZombieAreaDefinition = destination_data["area"]
			for point in destination.population_points:
				var position := Vector2(point.x, point.y)
				var floor := int(point.z)
				if not _valid_migration_destination(zombie, position, floor): continue
				return zombie.request_migration(position, floor, destination.id)
	return false


func _valid_migration_destination(zombie: ZombieActor, position: Vector2, floor: int) -> bool:
	if not world_map.can_stand(position, floor): return false
	if position.distance_to(player.logical_position) < area_catalog.rules.migration_player_exclusion_radius: return false
	return not world_map.find_path(zombie.logical_position, zombie.floor_level, position, floor).is_empty()


func _spawn(world_position: Vector2, floor: int = 0, initializing: bool = false) -> ZombieActor:
	# Used by initial population and validated save restoration. Runtime systems do
	# not call this to replace deaths; the ceiling also prevents accidental growth.
	if not world_map.can_stand(world_position, floor): return null
	if population_initialized and not initializing and _living_count() >= initial_population_count: return null
	var zombie := ZombieActor.new()
	actor_layer.add_child(zombie)
	zombie.setup(world_map, player, player_state, world_position, floor, area_catalog.rules)
	zombie.spawner = self
	zombie.died.connect(_on_zombie_died)
	zombie.attacked_player.connect(func(position: Vector2) -> void: player_attacked.emit(position))
	active_zombies.append(zombie)
	return zombie


func share_visual_observation(observer: ZombieActor, position: Vector2, floor: int) -> void:
	var joined := 1
	for zombie in active_zombies:
		if joined >= area_catalog.rules.maximum_loose_group_size: break
		if zombie == observer or not is_instance_valid(zombie) or zombie.health <= 0: continue
		if zombie.floor_level != observer.floor_level or zombie.logical_position.distance_to(observer.logical_position) > area_catalog.rules.convergence_radius: continue
		if not ActorPerception.sees_actor(world_map, zombie, observer, area_catalog.rules.convergence_radius): continue
		zombie.observe_group_target(position, floor, GameTime.elapsed_game_seconds, observer.target_stair_id)
		joined += 1


func population_by_area() -> Dictionary:
	var result: Dictionary = {}
	for zombie in active_zombies:
		if not is_instance_valid(zombie) or zombie.health <= 0 or zombie.is_queued_for_deletion(): continue
		var area_id := world_map.zombie_area_id_at(zombie.logical_position, zombie.floor_level)
		result[area_id] = int(result.get(area_id, 0)) + 1
	return result


func _refresh_simulation_range() -> void:
	var active_radius := ACTIVE_SIMULATION_RADIUS
	for zombie: ZombieActor in active_zombies:
		if not is_instance_valid(zombie) or zombie.health <= 0:
			continue
		# Include every storey inside the physical simulation sphere, allowing
		# nearby multi-storey pursuit instead of freezing the third floor.
		var floor_distance: float = world_map.elevation_at(zombie.logical_position, zombie.floor_level, zombie.stair_id) - world_map.elevation_at(player.logical_position, player.floor_level, player.stair_id)
		var limit := active_radius + (2.0 if zombie.is_processing() else 0.0)
		var nearby := zombie.logical_position.distance_squared_to(player.logical_position) + floor_distance * floor_distance <= limit * limit
		zombie.set_simulation_active(nearby)
		# Only distant idle actors use a coarse decision tick. Pursuit, combat and
		# anything in the immediate playable bubble remain frame-rate responsive.
		if nearby:
			var horizontal_distance := zombie.logical_position.distance_to(player.logical_position)
			zombie.set_logic_tick_interval(0.18 if not zombie.has_target and horizontal_distance > 10.0 else 0.0)


func clear_population() -> void:
	for zombie in active_zombies:
		if not is_instance_valid(zombie): continue
		zombie.remove_from_group("zombies")
		zombie.set_simulation_active(false)
		zombie.queue_free()
	active_zombies.clear()


func _on_zombie_died(zombie: ZombieActor) -> void:
	active_zombies.erase(zombie)


func _living_count() -> int:
	active_zombies = active_zombies.filter(func(zombie: ZombieActor) -> bool:
		return is_instance_valid(zombie) and not zombie.is_queued_for_deletion() and zombie.health > 0)
	return active_zombies.size()
