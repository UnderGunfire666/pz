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
var facing_direction := Vector2.DOWN
var look_pitch := 0.0
var health := 100.0
var attack_cooldown := 0.0
var threat_memory_until := 0.0
var threat_memory_position := Vector2.ZERO
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
var last_hearing: Dictionary = {}
var _footstep_distance := 0.0
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
	if not NoiseBus.noise_emitted.is_connected(hear_noise): NoiseBus.noise_emitted.connect(hear_noise)


func setup_interactions(p_interactions: InteractionSystem) -> void:
	interactions = p_interactions
	for point in interactions.points:
		if String(point.get("kind", "")) != "container":
			continue
		var container: ContainerData = point["container"]
		if container.claimed_by == actor_id and not known_container_ids.has(String(point["id"])):
			known_container_ids.append(String(point["id"]))


func _process(delta: float) -> void:
	if world_map == null or health <= 0:
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
	attack_cooldown = maxf(0.0, attack_cooldown - scaled_delta)
	var defended := _defend(scaled_delta)
	var game_seconds := scaled_delta * GameTime.GAME_SECONDS_PER_REAL_SECOND
	decision_cooldown -= scaled_delta
	if decision_cooldown <= 0.0:
		decision_cooldown = 1.2
		_discover_containers()
		_choose_goal()
	var resting := brain.current_goal == NPCBrain.Goal.REST and _at_target()
	survival.advance(game_seconds, 0.0 if _at_target() else 0.15, resting)
	if defended: return
	if _at_target():
		_perform_goal(game_seconds)
	else:
		_search_progress = 0.0
		_move_toward_target(scaled_delta)


func _choose_goal() -> void:
	var nearest_zombie := _nearest_zombie()
	if nearest_zombie != null:
		threat_memory_position = nearest_zombie.logical_position
		threat_memory_until = GameTime.elapsed_game_seconds + 45.0
	brain.current_goal = brain.choose_goal(survival, logical_position, nearest_zombie, home_position, food_position)
	if nearest_zombie == null and GameTime.elapsed_game_seconds < threat_memory_until:
		brain.current_goal = NPCBrain.Goal.FLEE
	elif nearest_zombie == null and brain.last_noise_danger and brain.last_noise_floor == floor_level \
		and GameTime.elapsed_game_seconds < brain.noise_memory_until:
		brain.current_goal = NPCBrain.Goal.FLEE
		threat_memory_position = brain.last_noise_position
	var next_position := home_position
	var next_floor := home_floor
	var next_resource: Dictionary = {}
	match brain.current_goal:
		NPCBrain.Goal.FLEE:
			if not stair_id.is_empty() and world_map.stairs.has(stair_id):
				var link: StairLink = world_map.stairs[stair_id]
				var go_up := link.end.distance_squared_to(threat_memory_position) > link.start.distance_squared_to(threat_memory_position)
				next_position = link.end if go_up else link.start
				next_floor = link.to_floor if go_up else link.from_floor
			else:
				next_position = _escape_position(threat_memory_position)
				next_floor = floor_level
		NPCBrain.Goal.SCAVENGE, NPCBrain.Goal.DRINK, NPCBrain.Goal.EAT:
			var tag := "water" if brain.current_goal == NPCBrain.Goal.DRINK else "food"
			next_resource = _find_resource(tag, nearest_zombie)
			if not next_resource.is_empty():
				next_position = world_map.furniture_approach(next_resource["position"], int(next_resource.get("floor", 0)), logical_position)
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


func _escape_position(threat: Vector2) -> Vector2:
	# A blocked straight escape must not send the survivor back toward danger.
	var away := threat.direction_to(logical_position)
	if away.is_zero_approx(): away = facing_direction
	var best := logical_position
	var best_score := logical_position.distance_to(threat)
	for angle: float in [0.0, -45.0, 45.0, -90.0, 90.0]:
		var candidate := logical_position + away.rotated(deg_to_rad(angle)) * 3.0
		if not world_map.can_stand(candidate, floor_level): continue
		var path := world_map.find_path(logical_position, floor_level, candidate, floor_level)
		if path.is_empty(): continue
		var length := 0.0
		var previous := logical_position
		var safe := true
		for waypoint: Dictionary in path:
			var point: Vector2 = waypoint["position"]
			if threat.distance_to(Geometry2D.get_closest_point_to_segment(threat, previous, point)) < minf(1.0, logical_position.distance_to(threat)):
				safe = false
			length += previous.distance_to(point)
			previous = point
		var score := candidate.distance_to(threat) - length * 0.2
		if safe and score > best_score:
			best = candidate
			best_score = score
	return best


func _discover_containers() -> void:
	if interactions == null or not stair_id.is_empty():
		return
	for point in interactions.points:
		if String(point.get("kind", "")) != "container" or int(point.get("floor", 0)) != floor_level:
			continue
		var point_position: Vector2 = point["position"]
		var target := ActorPerception.point(world_map, point_position, floor_level, "", 0.65)
		if ActorPerception.sees_point(world_map, self, target, 4.5 * lerpf(0.55, 1.0, world_map.ambient_light())):
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
		point_position = world_map.furniture_approach(point_position, point_floor, logical_position)
		var route := world_map.find_path(logical_position, floor_level, point_position, point_floor)
		if route.is_empty() and (floor_level != point_floor or logical_position.distance_to(point_position) > 0.2):
			continue
		var score := 0.0
		var previous := Vector3(logical_position.x, world_map.elevation_at(logical_position, floor_level, stair_id), logical_position.y)
		for waypoint: Dictionary in route:
			var pos: Vector2 = waypoint["position"]
			var next := Vector3(pos.x, int(waypoint["floor"]) * world_map.floor_height, pos.y)
			score += previous.distance_to(next)
			previous = next
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
	NoiseBus.emit_actor_noise(self, 1.2, "rummaging")


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
	var previous := logical_position
	var previous_point := ActorPerception.point(world_map, logical_position, floor_level, stair_id, 0.12)
	var result := _navigation.advance(world_map, logical_position, floor_level, stair_id,
		target_position, target_floor, MOVE_SPEED, scaled_delta)
	logical_position = result["position"]
	floor_level = int(result["floor"])
	stair_id = String(result["stair_id"])
	if logical_position.distance_squared_to(previous) > 0.000001:
		facing_direction = previous.direction_to(logical_position)
		_footstep_distance += previous_point.distance_to(ActorPerception.point(world_map, logical_position, floor_level, stair_id, 0.12))
		if _footstep_distance >= 0.75:
			_footstep_distance = fmod(_footstep_distance, 0.75)
			NoiseBus.emit_actor_noise(self, 2.2, "footsteps", 1.0, 0.12)


func _nearest_zombie(max_range: float = 4.5) -> ZombieActor:
	var nearest: ZombieActor = null
	var nearest_distance := INF
	for actor in get_tree().get_nodes_in_group("zombies"):
		var zombie := actor as ZombieActor
		if zombie == null or zombie.health <= 0 or zombie.is_queued_for_deletion():
			continue
		if zombie.world_map != world_map: continue
		var distance := ActorPerception.point(world_map, logical_position, floor_level, stair_id, 0.0).distance_to(
			ActorPerception.point(world_map, zombie.logical_position, zombie.floor_level, zombie.stair_id, 0.0))
		var visual_range := 4.5 * lerpf(0.55, 1.0, world_map.ambient_light())
		if distance > max_range: continue
		if distance < nearest_distance and ActorPerception.sees_actor(world_map, self, zombie, visual_range):
			nearest = zombie
			nearest_distance = distance
	return nearest


func hear_noise(stimulus: NoiseStimulus) -> void:
	if world_map == null or health <= 0 or is_queued_for_deletion() or GameTime.simulation_scale() <= 0.0: return
	if stimulus == null or stimulus.world_time < brain.last_noise_time: return
	var now := GameTime.elapsed_game_seconds
	var heard := ActorHearing.sample(world_map, self, stimulus, now)
	if heard.is_empty(): return
	# Danger may interrupt an innocuous clue; repeated weak sounds do not flood
	# the memory log or continuously cancel scavenging/navigation.
	var danger := bool(heard["danger"])
	if not danger and brain.last_noise_danger and now < brain.noise_memory_until: return
	if now < brain.noise_lock_until and (not danger or brain.last_noise_danger):
		if float(heard["strength"]) <= brain.last_noise_strength * 1.25: return
	brain.remember("Heard %s nearby." % stimulus.event_type)
	brain.last_noise_position = heard["position"]
	brain.last_noise_floor = int(heard["floor"])
	brain.last_noise_time = stimulus.world_time
	brain.last_noise_strength = float(heard["strength"])
	brain.last_noise_danger = danger
	brain.noise_memory_until = stimulus.world_time + ActorHearing.MEMORY_SECONDS
	brain.noise_lock_until = now + ActorHearing.SWITCH_LOCK_SECONDS
	last_hearing = heard
	NoiseBus.record_hearing(self, heard)
	# A remembered visible threat takes priority over anonymous sound. Cross-floor
	# danger is remembered but does not invent a planar escape from another room.
	if now < threat_memory_until: return
	if danger and brain.last_noise_floor == floor_level:
		cancel_current_task()
	elif brain.current_goal != NPCBrain.Goal.FLEE:
		var direction := logical_position.direction_to(brain.last_noise_position)
		if not direction.is_zero_approx(): facing_direction = direction


func _defend(delta: float) -> bool:
	var threat := _nearest_zombie(ActorCombat.NPC_REACH + 0.3)
	if threat == null: return false
	var target := ActorPerception.point(world_map, threat.logical_position, threat.floor_level, threat.stair_id, ActorPerception.CHEST_HEIGHT)
	var eye := ActorPerception.point(world_map, logical_position, floor_level, stair_id, ActorPerception.EYE_HEIGHT)
	if eye.distance_to(target) > ActorCombat.NPC_REACH: return false
	ActorCombat.turn_toward(self, target, delta)
	if attack_cooldown > 0.0 or ActorCombat.contact(self, threat, ActorCombat.direction(self), ActorCombat.NPC_REACH).is_empty(): return false
	attack_cooldown = 1.2
	threat.take_damage(1)
	NoiseBus.emit_actor_noise(self, 3.0, "struggle")
	_search_progress = 0.0
	return true


func take_damage(amount: float) -> void:
	health = maxf(0.0, health - maxf(0.0, amount))
	cancel_current_task()
