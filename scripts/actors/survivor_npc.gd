class_name SurvivorNPC
extends Node2D

## One survivor shares the player's world traversal and finite container stock.
const MOVE_SPEED := 0.95
const SEARCH_GAME_SECONDS := 90.0

var actor_id := "neighbour"
var world_map: WorldMap
var player: PlayerController
var interactions: InteractionSystem
var logical_position := Vector2.ZERO
var floor_level := 0
var stair_id := ""
var survival := SurvivalSystem.new()
var brain := NPCBrain.new()
var target_position := Vector2.ZERO
var target_floor := 0
var decision_cooldown := 0.0
var home_position := Vector2(3.8, 10.4)
var home_floor := 1
var food_position := Vector2(3.5, 10.5)
var known_container_ids: Array[String] = []
var _resource_point: Dictionary = {}
var _search_progress := 0.0
var _navigation := LocalNavigation.new()
var _logic_tick_elapsed := 0.0
const DISTANT_LOGIC_TICK := 0.18


func setup(p_world_map: WorldMap, start_position: Vector2, p_player: PlayerController = null) -> void:
	world_map = p_world_map
	player = p_player
	logical_position = start_position
	target_position = start_position
	if world_map.definition.id != "orangeville_prototype":
		home_position = start_position
		home_floor = 0
	brain.traits.set_value("cautiousness", 0.78)
	brain.traits.set_value("resourcefulness", 0.45)
	brain.relationships["player"] = 0.0
	brain.remember("The outbreak began this morning.")
	add_to_group("zombie_targets")
	NoiseBus.noise_emitted.connect(hear_noise)


func setup_interactions(p_interactions: InteractionSystem) -> void:
	interactions = p_interactions
	for point in interactions.points:
		if String(point.get("kind", "")) != "container":
			continue
		var container: ContainerData = point["container"]
		if container.claimed_by == actor_id and not known_container_ids.has(String(point["id"])):
			known_container_ids.append(String(point["id"]))


func _process(delta: float) -> void:
	if world_map == null:
		return
	if player != null and logical_position.distance_squared_to(player.logical_position) > 100.0:
		_logic_tick_elapsed += delta
		if _logic_tick_elapsed < DISTANT_LOGIC_TICK:
			return
		delta = _logic_tick_elapsed
		_logic_tick_elapsed = 0.0
	else:
		_logic_tick_elapsed = 0.0
	var simulation_scale := GameTime.simulation_scale()
	if simulation_scale <= 0.0:
		return
	var scaled_delta := delta * simulation_scale
	var game_seconds := scaled_delta * GameTime.GAME_SECONDS_PER_REAL_SECOND
	decision_cooldown -= scaled_delta
	if decision_cooldown <= 0.0:
		decision_cooldown = 1.2
		_discover_containers()
		_choose_goal()
	var resting := brain.current_goal == NPCBrain.Goal.REST and _at_target()
	survival.advance(game_seconds, 0.0 if _at_target() else 0.15, resting)
	if _at_target():
		_perform_goal(game_seconds)
	else:
		_search_progress = 0.0
		_move_toward_target(scaled_delta)


func _choose_goal() -> void:
	var nearest_zombie := _nearest_zombie()
	brain.current_goal = brain.choose_goal(survival, logical_position, nearest_zombie, home_position, food_position)
	var next_position := home_position
	var next_floor := home_floor
	var next_resource: Dictionary = {}
	match brain.current_goal:
		NPCBrain.Goal.FLEE:
			next_position = brain.goal_target(home_position, food_position, logical_position, nearest_zombie)
			next_floor = floor_level
			if not world_map.is_walkable(next_position, next_floor) or world_map.find_path(logical_position, floor_level, next_position, next_floor).is_empty():
				next_position = home_position
				next_floor = home_floor
		NPCBrain.Goal.SCAVENGE, NPCBrain.Goal.DRINK, NPCBrain.Goal.EAT:
			var tag := "water" if brain.current_goal == NPCBrain.Goal.DRINK else "food"
			next_resource = _find_resource(tag, nearest_zombie)
			if not next_resource.is_empty():
				next_position = next_resource["position"]
				next_floor = int(next_resource.get("floor", 0))
			else:
				brain.current_goal = NPCBrain.Goal.REST
		NPCBrain.Goal.WANDER:
			# A remembered sound does not reveal any actor's current position.
			brain.current_goal = NPCBrain.Goal.REST
	if String(next_resource.get("id", "")) != String(_resource_point.get("id", "")):
		_search_progress = 0.0
	_resource_point = next_resource
	if target_position.distance_squared_to(next_position) > 0.04 or target_floor != next_floor:
		target_position = next_position
		target_floor = next_floor
		if stair_id.is_empty():
			reset_navigation()


func _discover_containers() -> void:
	if interactions == null or not stair_id.is_empty():
		return
	for point in interactions.points:
		if String(point.get("kind", "")) != "container" or int(point.get("floor", 0)) != floor_level:
			continue
		var point_position: Vector2 = point["position"]
		if logical_position.distance_to(point_position) <= 4.5 and world_map.has_line_of_sight(logical_position, point_position, floor_level):
			var point_id := String(point["id"])
			if not known_container_ids.has(point_id):
				known_container_ids.append(point_id)
				brain.remember("Found supplies at %s." % point.get("label", point_id))


func _find_resource(tag: String, visible_threat: ZombieActor) -> Dictionary:
	if interactions == null:
		return {}
	var best: Dictionary = {}
	var best_score := INF
	for point in interactions.points:
		if String(point.get("kind", "")) != "container" or not known_container_ids.has(String(point["id"])):
			continue
		var container: ContainerData = point["container"]
		if not container.claimed_by.is_empty() and container.claimed_by != actor_id:
			continue
		if _supply_index(container, tag) < 0:
			continue
		var point_position: Vector2 = point["position"]
		var point_floor := int(point.get("floor", 0))
		var route := world_map.find_path(logical_position, floor_level, point_position, point_floor)
		if route.is_empty() and (floor_level != point_floor or logical_position.distance_to(point_position) > 0.2):
			continue
		var score := float(route.size())
		if visible_threat != null and visible_threat.floor_level == point_floor:
			score += maxf(0.0, 5.0 - point_position.distance_to(visible_threat.logical_position)) * (1.0 + brain.traits.value("cautiousness")) * 3.0
		if container.claimed_by == actor_id:
			score -= 1.0
		if score < best_score:
			best_score = score
			best = point
	return best


func _perform_goal(game_seconds: float) -> void:
	if _resource_point.is_empty():
		return
	var container: ContainerData = _resource_point["container"]
	if not container.claimed_by.is_empty() and container.claimed_by != actor_id:
		_resource_point = {}
		return
	var tag := "water" if brain.current_goal == NPCBrain.Goal.DRINK else "food"
	var index := _supply_index(container, tag)
	if index < 0:
		_resource_point = {}
		decision_cooldown = 0.0
		return
	_search_progress += game_seconds
	var duration := SEARCH_GAME_SECONDS / (1.0 + maxf(0.0, brain.traits.value("resourcefulness")))
	if _search_progress < duration:
		return
	var stack := container.contents[index]
	stack.quantity -= 1
	if stack.quantity <= 0:
		container.contents.remove_at(index)
	if tag == "water":
		survival.drink(32.0)
	else:
		survival.eat(24.0)
	brain.remember("Used %s from %s." % [stack.definition.display_name, container.display_name])
	_search_progress = 0.0
	decision_cooldown = 0.0
	NoiseBus.emit_noise(logical_position, 1.2, "rummaging", floor_level)


func _supply_index(container: ContainerData, tag: String) -> int:
	for index in range(container.contents.size()):
		var stack := container.contents[index]
		if stack.quantity > 0 and tag in stack.definition.tags:
			return index
	return -1


func _at_target() -> bool:
	return floor_level == target_floor and stair_id.is_empty() and logical_position.distance_to(target_position) < 0.18


func reset_navigation() -> void:
	_navigation.reset()


func cancel_current_task() -> void:
	_resource_point = {}
	_search_progress = 0.0
	decision_cooldown = 0.0
	reset_navigation()


func _move_toward_target(scaled_delta: float) -> void:
	var result := _navigation.advance(world_map, logical_position, floor_level, stair_id,
		target_position, target_floor, MOVE_SPEED, scaled_delta)
	logical_position = result["position"]
	floor_level = int(result["floor"])
	stair_id = String(result["stair_id"])


func _nearest_zombie() -> ZombieActor:
	if not stair_id.is_empty():
		return null
	var nearest: ZombieActor = null
	var nearest_distance := INF
	for actor in get_tree().get_nodes_in_group("zombies"):
		var zombie := actor as ZombieActor
		if zombie == null or zombie.health <= 0 or zombie.is_queued_for_deletion() or zombie.floor_level != floor_level or not zombie.stair_id.is_empty():
			continue
		var distance := logical_position.distance_to(zombie.logical_position)
		var visual_range := 4.5 * lerpf(0.55, 1.0, world_map.ambient_light())
		if distance < nearest_distance and distance <= visual_range and world_map.has_line_of_sight(logical_position, zombie.logical_position, floor_level):
			nearest = zombie
			nearest_distance = distance
	return nearest


func hear_noise(stimulus: NoiseStimulus) -> void:
	if GameTime.simulation_scale() <= 0.0: return
	if world_map.sound_cost(logical_position, floor_level, stimulus.world_position, stimulus.floor_level) <= stimulus.audible_range * stimulus.loudness:
		brain.remember("Heard %s nearby." % stimulus.event_type)
		brain.last_noise_position = stimulus.world_position
		brain.last_noise_floor = stimulus.floor_level
