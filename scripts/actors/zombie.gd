class_name ZombieActor
extends Node2D

signal died(zombie: ZombieActor)
signal attacked_player(world_position: Vector2)

const MOVE_SPEED := 0.58
const VISUAL_RANGE := 4.8
const MAX_HEALTH := 2

var world_map: WorldMap
var player: PlayerController
var player_state: PlayerState
var logical_position := Vector2.ZERO
var floor_level := 0
var stair_id := ""
var health := MAX_HEALTH
var target_position := Vector2.ZERO
var target_floor := 0
var has_target := false
var attack_cooldown := 0.0
var _damage_flash_left := 0.0
var _navigation := LocalNavigation.new()


func setup(
		p_world_map: WorldMap,
		p_player: PlayerController,
		p_player_state: PlayerState,
		start_position: Vector2,
		start_floor: int = 0
	) -> void:
	world_map = p_world_map
	player = p_player
	player_state = p_player_state
	logical_position = start_position
	floor_level = start_floor
	target_position = start_position
	target_floor = start_floor
	add_to_group("zombies")
	NoiseBus.noise_emitted.connect(hear_noise)


func _process(delta: float) -> void:
	if world_map == null or player == null or health <= 0 or is_queued_for_deletion():
		return
	_damage_flash_left = maxf(0.0, _damage_flash_left - delta)
	var simulation_scale := GameTime.simulation_scale()
	if simulation_scale <= 0.0 or player_state.is_dead():
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta * simulation_scale)
	var player_on_same_floor := floor_level == player.floor_level and stair_id.is_empty() and player.stair_id.is_empty()
	var player_distance := logical_position.distance_to(player.logical_position) if player_on_same_floor else INF
	var lit_visual_range := VISUAL_RANGE * lerpf(0.55, 1.0, world_map.ambient_light())
	if (
		player_on_same_floor
		and player_distance <= lit_visual_range
		and world_map.has_line_of_sight(logical_position, player.logical_position, floor_level, player.floor_level)
	):
		target_position = player.logical_position
		if target_floor != player.floor_level:
			reset_navigation()
		target_floor = player.floor_level
		has_target = true
	elif not player.stair_id.is_empty() and world_map.stairs.has(player.stair_id):
		var link: StairLink = world_map.stairs[player.stair_id]
		var same_stair := not stair_id.is_empty() and stair_id == player.stair_id
		var sees_entry := (stair_id.is_empty() and floor_level == player.floor_level
			and logical_position.distance_to(player.logical_position) <= lit_visual_range
			and world_map.has_line_of_sight(logical_position, player.logical_position, floor_level))
		if same_stair or sees_entry:
			# Seeing the player enter a flight reveals its exit, not rooms above.
			target_floor = link.to_floor if player.floor_level == link.from_floor else link.from_floor
			target_position = link.end if target_floor == link.to_floor else link.start
			has_target = true

	if has_target:
		_move_toward_target(delta * simulation_scale)
		if floor_level == target_floor and stair_id.is_empty() and logical_position.distance_to(target_position) <= 0.20:
			has_target = false

	if _can_hit_player() and attack_cooldown <= 0.0:
		attack_cooldown = 1.8
		player_state.add_wound("Scratch", "right arm", 0.12, true)
		attacked_player.emit(logical_position)
		NoiseBus.emit_noise(logical_position, 3.0, "struggle", floor_level)


func _can_hit_player() -> bool:
	if player_state.is_dead():
		return false
	var planar_distance := logical_position.distance_to(player.logical_position)
	if not stair_id.is_empty() or not player.stair_id.is_empty():
		if stair_id.is_empty() or stair_id != player.stair_id:
			return false
		var height_difference := world_map.elevation_at(logical_position, floor_level, stair_id) - world_map.elevation_at(player.logical_position, player.floor_level, player.stair_id)
		return Vector2(planar_distance, height_difference).length() < 0.72
	return floor_level == player.floor_level and planar_distance < 0.72 and world_map.has_line_of_sight(logical_position, player.logical_position, floor_level, player.floor_level)


func hear_noise(noise_position: Vector2, radius: float, _category: String, noise_floor: int = 0) -> void:
	if world_map == null or health <= 0 or is_queued_for_deletion():
		return
	if world_map.sound_cost(logical_position, floor_level, noise_position, noise_floor) <= radius:
		for link: StairLink in world_map.stairs.values():
			if link.contains(noise_position) and noise_floor in [link.from_floor, link.to_floor]:
				noise_floor = link.to_floor if noise_floor == link.from_floor else link.from_floor
				noise_position = link.end if noise_floor == link.to_floor else link.start
				break
		if target_floor != noise_floor:
			if stair_id.is_empty():
				reset_navigation()
		target_position = noise_position
		target_floor = noise_floor
		has_target = true


func take_damage(amount: int) -> void:
	if amount <= 0 or health <= 0 or is_queued_for_deletion():
		return
	health = maxi(0, health - amount)
	_damage_flash_left = 0.16
	if health <= 0:
		died.emit(self)
		queue_free()


func reset_navigation() -> void:
	_navigation.reset()


func _move_toward_target(scaled_delta: float) -> void:
	var result := _navigation.advance(world_map, logical_position, floor_level, stair_id,
		target_position, target_floor, MOVE_SPEED, scaled_delta)
	logical_position = result["position"]
	floor_level = int(result["floor"])
	stair_id = String(result["stair_id"])
