class_name PlayerController
extends Node2D

signal attack_impact_requested(world_position: Vector2, direction: Vector2)
signal moved(world_position: Vector2)
signal action_intent()

const WALK_SPEED := 2.55
const SPRINT_MULTIPLIER := 1.55
const ATTACK_COOLDOWN := 0.45
const ATTACK_STAMINA_COST := 5.0
const ATTACK_ANIMATION_SPEED := 2.0
const ATTACK_ANIMATION_DURATION := 2.2666667 / ATTACK_ANIMATION_SPEED
# The weapon collision volume is sampled at this normalized attack-clip phase.
const ATTACK_CONTACT_PHASE := 0.46
const ATTACK_HIT_TIME := ATTACK_ANIMATION_DURATION * ATTACK_CONTACT_PHASE
const ATTACK_MOVE_MULTIPLIER := 0.28
const BACKWARD_MOVE_MULTIPLIER := 0.52

var world_map: WorldMap
var world_view: World3DView
var state: PlayerState
var logical_position := Vector2(4.5, 7.0)
var floor_level := 0
var stair_id := ""
var facing_direction := Vector2.DOWN
var look_pitch := 0.0
var aim_mode := false
var interaction_locked := false
var controls_enabled := true
var _attack_cooldown_left := 0.0
var _attack_flash_left := 0.0
var _last_exertion := 0.0
var _footstep_distance := 0.0
var visual_velocity := Vector2.ZERO
var visual_damage_remaining := 0.0
var visual_hit_region := ""
var visual_attack_id := 0
var visual_attack_remaining := 0.0
var _attack_impact_remaining := -1.0


func setup(p_world_map: WorldMap, p_state: PlayerState, start_position: Vector2) -> void:
	world_map = p_world_map
	state = p_state
	logical_position = start_position
	add_to_group("zombie_targets")


func _process(delta: float) -> void:
	_last_exertion = 0.0
	if world_map == null or state.is_dead():
		return
	var simulation_scale := GameTime.simulation_scale()
	aim_mode = controls_enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta * simulation_scale)
	_attack_flash_left = maxf(0.0, _attack_flash_left - delta * simulation_scale)
	visual_damage_remaining = maxf(0.0, visual_damage_remaining - delta * simulation_scale)
	visual_attack_remaining = maxf(0.0, visual_attack_remaining - delta * simulation_scale)
	if _attack_impact_remaining >= 0.0:
		_attack_impact_remaining -= delta * simulation_scale
		if _attack_impact_remaining <= 0.0:
			_attack_impact_remaining = -1.0
			attack_impact_requested.emit(logical_position, facing_direction)
	if not controls_enabled:
		visual_velocity = Vector2.ZERO
		return

	var move_input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	if move_input.length_squared() > 0.001 or aim_mode:
		action_intent.emit()
	if not interaction_locked and move_input.length_squared() > 0.001 and simulation_scale > 0.0:
		move_input = world_view.input_to_logical(move_input.normalized())
		var speed := WALK_SPEED * state.movement_multiplier()
		var sprinting := not aim_mode and Input.is_key_pressed(KEY_SHIFT) and state.survival.can_sprint()
		if sprinting:
			speed *= SPRINT_MULTIPLIER
			_last_exertion = 1.0
		if move_input.dot(facing_direction) < -0.35:
			speed *= BACKWARD_MOVE_MULTIPLIER
		if visual_attack_remaining > 0.0:
			speed *= ATTACK_MOVE_MULTIPLIER
		_last_exertion *= state.exertion_multiplier()
		var movement := move_input * speed * delta * simulation_scale
		var previous_position := logical_position
		var previous_point := ActorPerception.point(world_map, logical_position, floor_level, stair_id, 0.12)
		var result := world_map.move_actor(logical_position, floor_level, movement, stair_id)
		logical_position = result["position"]
		floor_level = int(result["floor"])
		stair_id = String(result["stair_id"])
		if logical_position != previous_position:
			visual_velocity = (logical_position - previous_position) / maxf(0.00001, delta * simulation_scale)
			_footstep_distance += previous_point.distance_to(ActorPerception.point(world_map, logical_position, floor_level, stair_id, 0.12))
			if _footstep_distance >= 0.75:
				_footstep_distance = fmod(_footstep_distance, 0.75)
				NoiseBus.emit_actor_noise(self, 4.3 if sprinting else 2.2, "footsteps", 1.0, 0.12)
			moved.emit(logical_position)
		else:
			_last_exertion = 0.0
			visual_velocity = Vector2.ZERO
	else:
		visual_velocity = Vector2.ZERO


func try_attack() -> void:
	if state.is_dead() or GameTime.simulation_scale() <= 0.0:
		return
	# Attacks are deliberately committed only from the right-click ready stance.
	# Keep this at the controller boundary so any future input path observes it.
	if not aim_mode:
		return
	action_intent.emit()
	if interaction_locked or _attack_cooldown_left > 0.0:
		return
	if state.survival.stamina < ATTACK_STAMINA_COST:
		return
	var performance := state.attack_performance()
	state.survival.stamina = maxf(0.0, state.survival.stamina - ATTACK_STAMINA_COST / maxf(0.25, performance))
	_attack_cooldown_left = maxf(ATTACK_COOLDOWN / maxf(0.25, performance), ATTACK_ANIMATION_DURATION)
	_attack_flash_left = 0.18
	visual_attack_id += 1
	visual_attack_remaining = ATTACK_ANIMATION_DURATION
	_attack_impact_remaining = ATTACK_HIT_TIME
	NoiseBus.emit_actor_noise(self, 4.4, "melee strike")


func interrupt_attack() -> void:
	_attack_impact_remaining = -1.0
	visual_attack_remaining = 0.0
	_attack_cooldown_left = maxf(_attack_cooldown_left, 0.18)


func exertion() -> float:
	return _last_exertion


func look_direction(heading: Vector2 = Vector2.ZERO) -> Vector3:
	if heading.is_zero_approx(): heading = facing_direction
	return Vector3(heading.x * cos(look_pitch), sin(look_pitch), heading.y * cos(look_pitch)).normalized()
