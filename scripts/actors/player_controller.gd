class_name PlayerController
extends Node2D

signal attack_requested(world_position: Vector2, direction: Vector2)
signal moved(world_position: Vector2)
signal action_intent()

const WALK_SPEED := 2.55
const SPRINT_MULTIPLIER := 1.55
const ATTACK_COOLDOWN := 0.45
const ATTACK_STAMINA_COST := 5.0

var world_map: WorldMap
var world_view: World3DView
var state: PlayerState
var logical_position := Vector2(4.5, 7.0)
var floor_level := 0
var stair_id := ""
var facing_direction := Vector2.DOWN
var aim_mode := false
var interaction_locked := false
var _attack_cooldown_left := 0.0
var _attack_flash_left := 0.0
var _last_exertion := 0.0
var _footstep_distance := 0.0


func setup(p_world_map: WorldMap, p_state: PlayerState, start_position: Vector2) -> void:
	world_map = p_world_map
	state = p_state
	logical_position = start_position


func _process(delta: float) -> void:
	_last_exertion = 0.0
	if world_map == null or state.is_dead():
		return
	var simulation_scale := GameTime.simulation_scale()
	aim_mode = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta * simulation_scale)
	_attack_flash_left = maxf(0.0, _attack_flash_left - delta)

	var move_input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	if move_input.length_squared() > 0.001 or aim_mode:
		action_intent.emit()
	if not interaction_locked and move_input.length_squared() > 0.001 and simulation_scale > 0.0:
		move_input = world_view.input_to_logical(move_input.normalized())
		var speed := WALK_SPEED
		var sprinting := Input.is_key_pressed(KEY_SHIFT) and state.survival.can_sprint()
		if sprinting:
			speed *= SPRINT_MULTIPLIER
			_last_exertion = 1.0
		else:
			_last_exertion = 0.22
		var movement := move_input * speed * delta * simulation_scale
		var previous_position := logical_position
		var result := world_map.move_actor(logical_position, floor_level, movement, stair_id)
		logical_position = result["position"]
		floor_level = int(result["floor"])
		stair_id = String(result["stair_id"])
		if logical_position != previous_position:
			_footstep_distance += previous_position.distance_to(logical_position)
			if _footstep_distance >= 0.75:
				_footstep_distance = 0.0
				NoiseBus.emit_noise(logical_position, 4.0 if sprinting else 1.6, "footsteps", floor_level)
			moved.emit(logical_position)
		else:
			_last_exertion = 0.0
		if not aim_mode:
			facing_direction = move_input

	if aim_mode:
		var aim_target := world_view.mouse_to_logical(
			get_viewport().get_mouse_position(),
			floor_level
		)
		var aim_vector := aim_target - logical_position
		if aim_vector.length_squared() > 0.001:
			facing_direction = aim_vector.normalized()


func try_attack() -> void:
	if state.is_dead() or GameTime.simulation_scale() <= 0.0:
		return
	action_intent.emit()
	if interaction_locked or _attack_cooldown_left > 0.0:
		return
	if state.survival.stamina < ATTACK_STAMINA_COST:
		return
	state.survival.stamina -= ATTACK_STAMINA_COST
	_attack_cooldown_left = ATTACK_COOLDOWN
	_attack_flash_left = 0.18
	attack_requested.emit(logical_position, facing_direction)
	NoiseBus.emit_noise(logical_position, 4.4, "melee strike", floor_level)


func exertion() -> float:
	return _last_exertion
