class_name NPCBrain
extends RefCounted

enum Goal { REST, DRINK, EAT, FLEE, SCAVENGE, WANDER }

var current_goal: Goal = Goal.WANDER
var traits := TraitSet.new()
var relationships: Dictionary = {}
var memories: Array[String] = []
var last_noise_position := Vector2.ZERO
var last_noise_floor := 0


func choose_goal(
		survival: SurvivalSystem,
		self_position: Vector2,
		nearest_zombie: ZombieActor,
		_home_position: Vector2,
		_food_position: Vector2
	) -> Goal:
	var danger_distance := 2.4 + traits.value("cautiousness", 0.5) * 2.2
	if nearest_zombie != null and self_position.distance_to(nearest_zombie.logical_position) < danger_distance:
		return Goal.FLEE
	if survival.thirst < 55.0:
		return Goal.DRINK
	if survival.hunger < 65.0:
		return Goal.SCAVENGE
	if survival.fatigue < 65.0:
		return Goal.REST
	if not last_noise_position.is_zero_approx() and self_position.distance_to(last_noise_position) < 2.0:
		return Goal.WANDER
	return Goal.REST


func goal_target(
		home_position: Vector2,
		food_position: Vector2,
		self_position: Vector2,
		nearest_zombie: ZombieActor
	) -> Vector2:
	match current_goal:
		Goal.FLEE:
			if nearest_zombie != null:
				return self_position + (self_position - nearest_zombie.logical_position).normalized() * 3.0
			return home_position
		Goal.SCAVENGE, Goal.DRINK:
			return food_position
		Goal.REST:
			return home_position
		_:
			return self_position + Vector2(0.7, 0.2)


func remember(memory: String) -> void:
	memories.append(memory)
	if memories.size() > 12:
		memories.pop_front()


func goal_name() -> String:
	return Goal.keys()[current_goal].capitalize()


func to_save_data() -> Dictionary:
	return {
		"traits": traits.to_save_data(),
		"relationships": relationships.duplicate(),
		"memories": memories.duplicate(),
		"last_noise_position": last_noise_position,
		"last_noise_floor": last_noise_floor,
		"current_goal": int(current_goal),
	}


func load_save_data(data: Dictionary) -> void:
	traits.load_save_data(data.get("traits", {}))
	relationships = data.get("relationships", {}).duplicate()
	memories = data.get("memories", []).duplicate()
	last_noise_position = data.get("last_noise_position", Vector2.ZERO)
	last_noise_floor = int(data.get("last_noise_floor", 0))
	current_goal = int(data.get("current_goal", Goal.REST)) as Goal
