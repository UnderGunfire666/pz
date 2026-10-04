class_name ZombieActor
extends Node2D

signal died(zombie: ZombieActor)
signal attacked_player(world_position: Vector2)

enum Awareness { IDLE, VISUAL, VISUAL_MEMORY, SOUND, GROUP, SEARCH, MIGRATION }

const MOVE_SPEED := 0.58
const VISUAL_RANGE := 4.8
const MAX_HEALTH := 2

var world_map: WorldMap
var player: PlayerController
var player_state: PlayerState
var world_rules: ZombieWorldRules
var spawner: ZombieSpawner
var simulation_active := true
var logical_position := Vector2.ZERO
var floor_level := 0
var stair_id := ""
var health := MAX_HEALTH
var target_position := Vector2.ZERO
var target_floor := 0
var target_stair_id := ""
var has_target := false
var attack_cooldown := 0.0
var facing_direction := Vector2.DOWN
var awareness: Awareness = Awareness.IDLE
var target_actor_id := ""
var visual_memory_expires_at := 0.0
var sound_memory_expires_at := 0.0
var search_expires_at := 0.0
var stimulus_lock_until := 0.0
var last_stimulus_time := -1.0
var last_stimulus_loudness := 0.0
var last_heard_strength := 0.0
var last_hearing: Dictionary = {}
var migration_area_id := ""
var _perception_game_seconds_left := 0.0
var _search_step := 0
var _damage_flash_left := 0.0
var _navigation := LocalNavigation.new()
var _logic_tick_interval := 0.0
var _logic_tick_elapsed := 0.0


func setup(p_world_map: WorldMap, p_player: PlayerController, p_player_state: PlayerState,
		start_position: Vector2, start_floor: int = 0, p_rules: ZombieWorldRules = null) -> void:
	world_map = p_world_map
	player = p_player
	player_state = p_player_state
	world_rules = p_rules
	logical_position = start_position
	floor_level = start_floor
	target_position = start_position
	target_floor = start_floor
	add_to_group("zombies")
	if simulation_active and not NoiseBus.noise_emitted.is_connected(hear_noise):
		NoiseBus.noise_emitted.connect(hear_noise)


func set_simulation_active(active: bool) -> void:
	simulation_active = active
	set_process(active)
	_logic_tick_elapsed = 0.0
	if not active and NoiseBus.noise_emitted.is_connected(hear_noise):
		NoiseBus.noise_emitted.disconnect(hear_noise)
	elif active and world_map != null and not NoiseBus.noise_emitted.is_connected(hear_noise):
		NoiseBus.noise_emitted.connect(hear_noise)


func set_logic_tick_interval(interval: float) -> void:
	_logic_tick_interval = maxf(0.0, interval)
	if _logic_tick_interval <= 0.0:
		_logic_tick_elapsed = 0.0


func _process(delta: float) -> void:
	if world_map == null or player == null or health <= 0 or is_queued_for_deletion(): return
	_damage_flash_left = maxf(0.0, _damage_flash_left - delta)
	if _logic_tick_interval > 0.0:
		_logic_tick_elapsed += delta
		if _logic_tick_elapsed < _logic_tick_interval:
			return
		delta = _logic_tick_elapsed
		_logic_tick_elapsed = 0.0
	var scale := GameTime.simulation_scale()
	if scale <= 0.0 or player_state.is_dead(): return
	var scaled_delta := delta * scale
	var game_seconds := scaled_delta * GameTime.GAME_SECONDS_PER_REAL_SECOND
	attack_cooldown = maxf(0.0, attack_cooldown - scaled_delta)
	_perception_game_seconds_left -= game_seconds
	if _perception_game_seconds_left <= 0.0:
		_perception_game_seconds_left = _rule("perception_interval_game_seconds", 1.5)
		_update_perception()
	_update_memory()
	if has_target:
		_move_toward_target(scaled_delta)
		if ((target_stair_id.is_empty() and floor_level == target_floor and stair_id.is_empty()) \
			or (not target_stair_id.is_empty() and stair_id == target_stair_id)) and logical_position.distance_to(target_position) <= 0.20:
			_reached_target()
	if _can_hit_player() and attack_cooldown <= 0.0:
		attack_cooldown = 1.8
		player_state.receive_hit("Scratch", "Right Arm", 12.0, true)
		attacked_player.emit(logical_position)
		NoiseBus.emit_actor_noise(self, 3.0, "struggle")


func _update_perception() -> void:
	var visible := _nearest_visible_target()
	if visible != null:
		_observe_target(visible)
	elif awareness == Awareness.VISUAL:
		awareness = Awareness.VISUAL_MEMORY


func _nearest_visible_target() -> Node:
	var nearest: Node = null
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group("zombie_targets"):
		if not is_instance_valid(candidate): continue
		if candidate is PlayerController and candidate.state.is_dead(): continue
		var distance := ActorPerception.point(world_map, logical_position, floor_level, stair_id, 0.0).distance_to(
			ActorPerception.point(world_map, candidate.logical_position, candidate.floor_level, candidate.stair_id, 0.0))
		if distance < nearest_distance and _can_see_actor(candidate):
			nearest = candidate
			nearest_distance = distance
	return nearest


func _can_see_actor(actor: Node) -> bool:
	var sight_range := _rule("sight_range", VISUAL_RANGE) * lerpf(0.55, 1.0, world_map.ambient_light())
	return ActorPerception.sees_actor(world_map, self, actor, sight_range,
		_rule("sight_half_angle_degrees", 72.0), _rule("peripheral_range", 1.25))

func _observe_target(actor: Node) -> void:
	var actor_position: Vector2 = actor.get("logical_position")
	var actor_floor: int = actor.get("floor_level")
	var actor_stair: String = actor.get("stair_id")
	target_actor_id = "player" if actor is PlayerController else String(actor.get("actor_id"))
	target_position = actor_position
	target_floor = actor_floor
	target_stair_id = actor_stair
	awareness = Awareness.VISUAL
	has_target = true
	visual_memory_expires_at = GameTime.elapsed_game_seconds + _rule("visual_memory_game_seconds", 90.0)
	stimulus_lock_until = GameTime.elapsed_game_seconds + _rule("stimulus_switch_lock_game_seconds", 6.0)
	if spawner != null: spawner.share_visual_observation(self, target_position, target_floor)


func _update_memory() -> void:
	var now := GameTime.elapsed_game_seconds
	if awareness in [Awareness.VISUAL, Awareness.VISUAL_MEMORY, Awareness.GROUP] and now >= visual_memory_expires_at:
		_clear_target()
	elif awareness == Awareness.SOUND and now >= sound_memory_expires_at:
		_begin_search()
	elif awareness == Awareness.SEARCH and now >= search_expires_at:
		_clear_target()


func _reached_target() -> void:
	match awareness:
		Awareness.MIGRATION: _clear_target()
		Awareness.VISUAL: pass # Hold contact until the next perception sample updates or loses it.
		Awareness.VISUAL_MEMORY, Awareness.SOUND, Awareness.GROUP: _begin_search()
		Awareness.SEARCH: _set_next_search_point()
		_: _clear_target()


func _begin_search() -> void:
	awareness = Awareness.SEARCH
	target_actor_id = ""
	search_expires_at = GameTime.elapsed_game_seconds + _rule("search_game_seconds", 35.0)
	_search_step = 0
	if not stair_id.is_empty() and world_map.stairs.has(stair_id):
		var link: StairLink = world_map.stairs[stair_id]
		var go_up := link.progress_at(logical_position) >= 0.5
		target_position = link.end if go_up else link.start
		target_floor = link.to_floor if go_up else link.from_floor
		target_stair_id = ""
		has_target = true
		reset_navigation()
		return
	target_stair_id = ""
	_set_next_search_point()


func _set_next_search_point() -> void:
	if GameTime.elapsed_game_seconds >= search_expires_at:
		_clear_target()
		return
	var offsets: Array[Vector2] = [Vector2(0.7, 0.0), Vector2(0.0, 0.7), Vector2(-0.7, 0.0), Vector2(0.0, -0.7)]
	for attempt in range(offsets.size()):
		var candidate: Vector2 = target_position + offsets[(_search_step + attempt) % offsets.size()]
		if world_map.can_stand(candidate, target_floor) and not world_map.find_path(logical_position, floor_level, candidate, target_floor).is_empty():
			target_position = candidate
			_search_step += attempt + 1
			has_target = true
			reset_navigation()
			return
	_clear_target()


func hear_noise(stimulus: NoiseStimulus) -> void:
	# Dormant actors retain memory but only player proximity wakes them.
	if (not simulation_active or world_map == null or health <= 0 or is_queued_for_deletion() or awareness == Awareness.VISUAL
		or GameTime.simulation_scale() <= 0.0): return
	var now := GameTime.elapsed_game_seconds
	if stimulus == null or stimulus.world_time < last_stimulus_time: return
	var heard := ActorHearing.sample(world_map, self, stimulus, now)
	if heard.is_empty(): return
	# A last visual observation remains stronger evidence during its switch lock.
	if now < stimulus_lock_until:
		if awareness == Awareness.VISUAL_MEMORY or float(heard["strength"]) <= last_heard_strength * 1.25: return
	if stair_id.is_empty() and (target_floor != int(heard["floor"]) or target_position.distance_to(heard["position"]) > 0.2): reset_navigation()
	target_position = heard["position"]
	target_floor = int(heard["floor"])
	target_stair_id = ""
	target_actor_id = ""
	awareness = Awareness.SOUND
	has_target = true
	last_stimulus_time = stimulus.world_time
	last_stimulus_loudness = stimulus.loudness
	last_heard_strength = float(heard["strength"])
	last_hearing = heard
	NoiseBus.record_hearing(self, heard)
	sound_memory_expires_at = stimulus.world_time + _rule("sound_memory_game_seconds", 55.0)
	stimulus_lock_until = now + _rule("stimulus_switch_lock_game_seconds", 6.0)


func observe_group_target(position: Vector2, floor: int, observed_at: float, observed_stair: String = "") -> void:
	if awareness in [Awareness.VISUAL, Awareness.VISUAL_MEMORY] or observed_at < last_stimulus_time: return
	target_position = position
	target_floor = floor
	target_stair_id = observed_stair
	target_actor_id = ""
	awareness = Awareness.GROUP
	has_target = true
	last_stimulus_time = observed_at
	visual_memory_expires_at = observed_at + _rule("visual_memory_game_seconds", 90.0)
	if stair_id.is_empty(): reset_navigation()


func request_migration(position: Vector2, floor: int, area_id: String) -> bool:
	if awareness != Awareness.IDLE or has_target: return false
	target_position = position
	target_floor = floor
	target_stair_id = ""
	migration_area_id = area_id
	awareness = Awareness.MIGRATION
	has_target = true
	reset_navigation()
	return true


func _clear_target() -> void:
	has_target = false
	awareness = Awareness.IDLE
	stimulus_lock_until = 0.0
	last_heard_strength = 0.0
	target_actor_id = ""
	target_stair_id = ""
	migration_area_id = ""
	reset_navigation()


func _can_hit_player() -> bool:
	if player_state.is_dead(): return false
	var from := ActorPerception.point(world_map, logical_position, floor_level, stair_id, ActorPerception.CHEST_HEIGHT)
	var to := ActorPerception.point(world_map, player.logical_position, player.floor_level, player.stair_id, ActorPerception.CHEST_HEIGHT)
	return from.distance_to(to) < 0.72 and world_map.has_spatial_line_of_sight(from, to)

func take_damage(amount: int) -> void:
	if amount <= 0 or health <= 0 or is_queued_for_deletion(): return
	health = maxi(0, health - amount)
	_damage_flash_left = 0.16
	if health <= 0:
		died.emit(self)
		queue_free()


func reset_navigation() -> void:
	_navigation.reset()


func _move_toward_target(scaled_delta: float) -> void:
	var previous := logical_position
	var result := _navigation.advance(world_map, logical_position, floor_level, stair_id,
		target_position, target_floor, MOVE_SPEED, scaled_delta, target_stair_id)
	logical_position = result["position"]
	floor_level = int(result["floor"])
	stair_id = String(result["stair_id"])
	if logical_position.distance_squared_to(previous) > 0.000001:
		facing_direction = previous.direction_to(logical_position)


func _rule(property: String, fallback: float) -> float:
	return float(world_rules.get(property)) if world_rules != null else fallback


func perception_save_data() -> Dictionary:
	return {"awareness": int(awareness), "target_actor_id": target_actor_id, "target_stair_id": target_stair_id,
		"visual_memory_expires_at": visual_memory_expires_at, "sound_memory_expires_at": sound_memory_expires_at,
		"search_expires_at": search_expires_at, "stimulus_lock_until": stimulus_lock_until,
		"last_stimulus_time": last_stimulus_time, "last_stimulus_loudness": last_stimulus_loudness,
		"last_heard_strength": last_heard_strength,
		"migration_area_id": migration_area_id, "facing": facing_direction}


func load_perception_save_data(data: Dictionary) -> void:
	awareness = int(data["awareness"])
	target_actor_id = data["target_actor_id"]
	target_stair_id = data.get("target_stair_id", "")
	visual_memory_expires_at = data["visual_memory_expires_at"]
	sound_memory_expires_at = data["sound_memory_expires_at"]
	search_expires_at = data["search_expires_at"]
	stimulus_lock_until = data["stimulus_lock_until"]
	last_stimulus_time = data["last_stimulus_time"]
	last_stimulus_loudness = data["last_stimulus_loudness"]
	last_heard_strength = float(data.get("last_heard_strength", 0.0))
	last_hearing = {}
	migration_area_id = data["migration_area_id"]
	facing_direction = data["facing"]
