class_name ZombieSpawner
extends Node

## Owns the finite zombie population. Pressure selects initial placement and
## destinations for physical migration; this node never replenishes deaths.
signal player_attacked(world_position: Vector2)

const POPULATION_LIMIT := 7 # Compatibility alias; authored default lives in world_rules.tres.
const MIN_ACTIVE_SIMULATION_RADIUS := 12.0
const ACTIVE_SIMULATION_RADIUS_MULTIPLIER := 2.0

var world_map: WorldMap
var actor_layer: Node2D
var player: PlayerController
var player_state: PlayerState
var visibility_system: VisibilitySystem
var area_catalog := ZombieAreaCatalog.new()
var active_zombies: Array[ZombieActor] = []
var population_initialized := false
var initial_population_count := 0
var migration_game_seconds := 0.0
var _simulation_refresh_left := 0.0


func setup(p_world_map: WorldMap, p_actor_layer: Node2D, p_player: PlayerController,
		p_player_state: PlayerState) -> void:
	world_map = p_world_map
	actor_layer = p_actor_layer
	player = p_player
	player_state = p_player_state


func seed_demo_population() -> void:
	if population_initialized: return
	var used: Dictionary = {}
	var counts: Dictionary = {}
	var cap := area_catalog.rules.initial_population_cap
	for _slot in range(cap):
		var best: ZombieAreaDefinition = null
		var best_score := -1.0
		for area: ZombieAreaDefinition in area_catalog.areas.values():
			var available := 0
			for point in area.population_points:
				if not used.has(point): available += 1
			if available == 0: continue
			var score := area.pressure / float(int(counts.get(area.id, 0)) + 1)
			if score > best_score or (is_equal_approx(score, best_score) and (best == null or area.id < best.id)):
				best = area
				best_score = score
		if best == null: break
		for point in best.population_points:
			if used.has(point): continue
			used[point] = true
			if _spawn(Vector2(point.x, point.y), int(point.z), true) != null:
				counts[best.id] = int(counts.get(best.id, 0)) + 1
				break
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
			var score := area.pressure / float(int(area_counts.get(area.id, 0)) + 1)
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
	if floor == player.floor_level and visibility_system != null and visibility_system.can_see_position(position, floor): return false
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
		if not world_map.has_line_of_sight(observer.logical_position, zombie.logical_position, observer.floor_level): continue
		zombie.observe_group_target(position, floor, GameTime.elapsed_game_seconds)
		joined += 1


func population_by_area() -> Dictionary:
	var result: Dictionary = {}
	for zombie in active_zombies:
		if not is_instance_valid(zombie) or zombie.health <= 0 or zombie.is_queued_for_deletion(): continue
		var area_id := world_map.zombie_area_id_at(zombie.logical_position, zombie.floor_level)
		result[area_id] = int(result.get(area_id, 0)) + 1
	return result


func _refresh_simulation_range() -> void:
	var vision_radius := visibility_system.vision_radius if visibility_system != null else 0.0
	var active_radius := maxf(MIN_ACTIVE_SIMULATION_RADIUS, vision_radius * ACTIVE_SIMULATION_RADIUS_MULTIPLIER)
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
