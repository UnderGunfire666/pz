class_name ZombieActor
extends Node2D

var appearance := CharacterAppearance.new()
var inventory := InventoryGrid.new()
var clothing := ClothingSystem.new(inventory)

signal died(zombie: ZombieActor)
signal attacked_player(world_position: Vector2)

enum Awareness { IDLE, VISUAL, VISUAL_MEMORY, SOUND, GROUP, SEARCH, MIGRATION, WANDER }

const MOVE_SPEED := 0.58
const VISUAL_RANGE := 9.6
const MAX_HEALTH := 2
const BODY_DAMAGE_PER_POINT := 50.0
const HEAD_DAMAGE_MULTIPLIER := 2
const TURN_SPEED := 2.5
const MOVE_TURN_ALIGNMENT := 0.82
const ATTACK_STANDOFF_DISTANCE := 0.72
const ATTACK_ANIMATION_DURATION := 2.633
const ATTACK_HIT_TIME := ATTACK_ANIMATION_DURATION * 0.46
const ATTACK_MOVE_MULTIPLIER := 0.28
const BACKWARD_MOVE_MULTIPLIER := 0.52
const WANDER_MIN_DISTANCE := 4.0
const WANDER_MAX_DISTANCE := 10.0
const WANDER_MIN_WAIT_GAME_SECONDS := 20.0
const WANDER_MAX_WAIT_GAME_SECONDS := 45.0
const WANDER_CANDIDATE_ATTEMPTS := 12

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
var body_health := ActorBody.healthy_regions()
var last_hit_region := ""
var target_position := Vector2.ZERO
var target_floor := 0
var target_stair_id := ""
var has_target := false
var attack_cooldown := 0.0
var facing_direction := Vector2.DOWN
var look_pitch := 0.0
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
var wander_next_game_seconds := 0.0
var wander_seed := 1
var _perception_game_seconds_left := 0.0
var _search_step := 0
var _damage_flash_left := 0.0
var _navigation := LocalNavigation.new()
var _logic_tick_interval := 0.0
var _logic_tick_elapsed := 0.0
var visual_attack_remaining := 0.0
var visual_attack_id := 0
var _attack_impact_remaining := -1.0
var _attack_target: Node


func setup(p_world_map: WorldMap, p_player: PlayerController, p_player_state: PlayerState,
		start_position: Vector2, start_floor: int = 0, p_rules: ZombieWorldRules = null) -> void:
	world_map = p_world_map
	var outfit_rng := RandomNumberGenerator.new()
	outfit_rng.seed = int(absf(start_position.x * 92821.0 + start_position.y * 68917.0)) + start_floor * 19391
	# The retained zombie body is male; underwear follows its body type.
	inventory.wearer_gender = appearance.gender
	ClothingCatalog.dress(inventory, outfit_rng)
	player = p_player
	player_state = p_player_state
	world_rules = p_rules
	logical_position = start_position
	floor_level = start_floor
	target_position = start_position
	target_floor = start_floor
	wander_seed = _wander_seed_for(start_position, start_floor)
	_schedule_next_wander()
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
	visual_attack_remaining = maxf(0.0, visual_attack_remaining - delta * GameTime.simulation_scale())
	if _attack_impact_remaining >= 0.0:
		_attack_impact_remaining -= delta * GameTime.simulation_scale()
		if _attack_impact_remaining <= 0.0:
			_resolve_attack_impact()
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
	_update_idle_wander()
	var target_point := ActorPerception.point(world_map, target_position, target_floor, target_stair_id, ActorPerception.CHEST_HEIGHT)
	if has_target:
		ActorCombat.turn_toward(self, target_point, scaled_delta, TURN_SPEED)
		# Stair elevation can make a remembered target point sharply lower than the
		# player body currently within claw range. Keep the visual/combat aim in a
		# close-quarters cone; ActorCombat still resolves the exact body surface.
		look_pitch = clampf(look_pitch, -0.55, 0.55)
	if has_target and _can_advance_toward_target(target_point):
		_move_toward_target(scaled_delta)
		if ((target_stair_id.is_empty() and floor_level == target_floor and stair_id.is_empty()) \
			or (not target_stair_id.is_empty() and stair_id == target_stair_id)) and logical_position.distance_to(target_position) <= 0.20:
			_reached_target()
	var victim: Node = null
	if attack_cooldown <= 0.0 and _attack_impact_remaining < 0.0:
		victim = ActorCombat.select_target(self, get_tree().get_nodes_in_group("zombie_targets"), ActorCombat.direction(self), ActorCombat.ZOMBIE_REACH)
	if victim != null and attack_cooldown <= 0.0:
		attack_cooldown = ATTACK_ANIMATION_DURATION
		visual_attack_remaining = ATTACK_ANIMATION_DURATION
		visual_attack_id += 1
		_attack_target = victim
		_attack_impact_remaining = ATTACK_HIT_TIME
		NoiseBus.emit_action_noise(self, "zombie_attack")


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
		if candidate.get("world_map") != world_map: continue
		if candidate is SurvivorNPC and candidate.health <= 0: continue
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
		Awareness.WANDER: _clear_target()
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
	if float(heard["strength"]) < _rule("hearing_threshold", 0.55): return
	# A last visual observation remains stronger evidence during its switch lock.
	# While investigating a sound, compare received strength rather than the
	# emitter's loudness: a distant loud event must not replace a clearer clue.
	if now < stimulus_lock_until and awareness == Awareness.VISUAL_MEMORY:
		return
	if now < stimulus_lock_until and awareness == Awareness.SOUND \
		and float(heard["strength"]) <= last_heard_strength:
		return
	if stimulus.world_time == last_stimulus_time and not last_hearing.is_empty():
		var previous_position: Vector2 = last_hearing.get("position", Vector2.INF)
		if String(last_hearing.get("event_type", "")) == String(heard["event_type"]) \
			and previous_position.distance_to(heard["position"]) < 0.2:
			return
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
	if awareness not in [Awareness.IDLE, Awareness.WANDER]: return false
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
	_schedule_next_wander()


func _update_idle_wander() -> void:
	if awareness != Awareness.IDLE or has_target or GameTime.elapsed_game_seconds < wander_next_game_seconds:
		return
	var selected: Dictionary = {}
	var selected_score := -INF
	for _attempt in range(WANDER_CANDIDATE_ATTEMPTS):
		var angle := _next_wander_random() * TAU
		var distance := lerpf(WANDER_MIN_DISTANCE, WANDER_MAX_DISTANCE, _next_wander_random())
		var candidate := logical_position + Vector2(cos(angle), sin(angle)) * distance
		if not world_map.can_stand(candidate, floor_level):
			continue
		if world_map.find_path(logical_position, floor_level, candidate, floor_level).is_empty():
			continue
		# Pressure is authored world data. It gives idle movement a loose tendency
		# toward inhabited areas without replacing normal path validation.
		var score := world_map.pressure_at(candidate, floor_level) + _next_wander_random() * 0.35
		if score > selected_score:
			selected = {"position": candidate, "floor": floor_level}
			selected_score = score
	if selected.is_empty():
		_schedule_next_wander()
		return
	target_position = selected["position"]
	target_floor = int(selected["floor"])
	target_stair_id = ""
	target_actor_id = ""
	awareness = Awareness.WANDER
	has_target = true
	reset_navigation()


func _schedule_next_wander() -> void:
	wander_next_game_seconds = GameTime.elapsed_game_seconds + lerpf(
		WANDER_MIN_WAIT_GAME_SECONDS, WANDER_MAX_WAIT_GAME_SECONDS, _next_wander_random())


func _wander_seed_for(position: Vector2, floor: int) -> int:
	var seed := int(absf(position.x * 92821.0 + position.y * 68917.0 + float(floor) * 19391.0)) % 2147483646
	return seed + 1


func _next_wander_random() -> float:
	wander_seed = (wander_seed * 48271) % 2147483647
	if wander_seed <= 0:
		wander_seed = 1
	return float(wander_seed) / 2147483647.0


func _can_hit_player() -> bool:
	if player_state.is_dead(): return false
	return not ActorCombat.contact(self, player, ActorCombat.direction(self), ActorCombat.ZOMBIE_REACH).is_empty()


func _can_advance_toward_target(target_point: Vector3) -> bool:
	var planar_target := Vector2(target_point.x, target_point.z)
	var offset := planar_target - logical_position
	if offset.length_squared() > 0.000001 and facing_direction.dot(offset.normalized()) < MOVE_TURN_ALIGNMENT:
		return false
	# A tracked player is approached only to the attack stand-off distance. The
	# body contact test still determines whether a scratch is legal.
	if target_actor_id == "player" and floor_level == player.floor_level and stair_id == player.stair_id \
		and logical_position.distance_to(player.logical_position) <= ATTACK_STANDOFF_DISTANCE:
		return false
	return true

func receive_hit(amount: int, region: String) -> void:
	if amount <= 0 or health <= 0 or is_queued_for_deletion(): return
	if region not in PlayerState.BODY_REGIONS: return
	last_hit_region = region
	_damage_flash_left = 0.28
	interrupt_attack()
	body_health[region] = maxf(0.0, float(body_health[region]) - amount * BODY_DAMAGE_PER_POINT)
	take_damage(amount * (HEAD_DAMAGE_MULTIPLIER if region == "Head" else 1))


func arm_performance() -> float:
	var condition := minf(float(body_health["Left Arm"]), float(body_health["Right Arm"]))
	condition = minf(condition, minf(float(body_health["Left Hand"]), float(body_health["Right Hand"])))
	return lerpf(0.5, 1.0, condition / 100.0)


func leg_performance() -> float:
	var condition := minf(float(body_health["Left Leg"]), float(body_health["Right Leg"]))
	condition = minf(condition, minf(float(body_health["Left Foot"]), float(body_health["Right Foot"])))
	return lerpf(0.5, 1.0, condition / 100.0)


func take_damage(amount: int) -> void:
	if amount <= 0 or health <= 0 or is_queued_for_deletion(): return
	health = maxi(0, health - amount)
	_damage_flash_left = 0.28
	if health <= 0:
		died.emit(self)
		queue_free()


func reset_navigation() -> void:
	_navigation.reset()


func _move_toward_target(scaled_delta: float) -> void:
	var speed := MOVE_SPEED * leg_performance()
	if visual_attack_remaining > 0.0: speed *= ATTACK_MOVE_MULTIPLIER
	if not target_position.is_equal_approx(logical_position) and facing_direction.dot(logical_position.direction_to(target_position)) < -0.35:
		speed *= BACKWARD_MOVE_MULTIPLIER
	var result := _navigation.advance(world_map, logical_position, floor_level, stair_id,
		target_position, target_floor, speed, scaled_delta, target_stair_id)
	logical_position = result["position"]
	floor_level = int(result["floor"])
	stair_id = String(result["stair_id"])
	# Facing is updated by turn_toward before movement. Do not replace it with the
	# path direction or a zombie would snap around when its target is behind it.


func _resolve_attack_impact() -> void:
	_attack_impact_remaining = -1.0
	var victim := _attack_target
	_attack_target = null
	if not is_instance_valid(victim) or victim.is_queued_for_deletion(): return
	var hit := ActorCombat.contact(self, victim, ActorCombat.direction(self), ActorCombat.ZOMBIE_REACH)
	if hit.is_empty(): return
	if victim is PlayerController:
		victim.state.receive_hit("Scratch", hit["region"], 12.0 * arm_performance(), true)
		victim.interrupt_attack()
		victim.visual_damage_remaining = 0.18
		victim.visual_hit_region = hit["region"]
		ActorCombat.apply_hit_recoil(victim, logical_position.direction_to(victim.logical_position), 0.10)
		attacked_player.emit(logical_position)
	else:
		victim.receive_hit(12.0 * arm_performance(), hit["region"])
		ActorCombat.apply_hit_recoil(victim, logical_position.direction_to(victim.logical_position), 0.10)


func interrupt_attack() -> void:
	_attack_impact_remaining = -1.0
	visual_attack_remaining = 0.0
	attack_cooldown = maxf(attack_cooldown, 0.18)


func _rule(property: String, fallback: float) -> float:
	return float(world_rules.get(property)) if world_rules != null else fallback


func perception_save_data() -> Dictionary:
	return {"awareness": int(awareness), "target_actor_id": target_actor_id, "target_stair_id": target_stair_id,
		"visual_memory_expires_at": visual_memory_expires_at, "sound_memory_expires_at": sound_memory_expires_at,
		"search_expires_at": search_expires_at, "stimulus_lock_until": stimulus_lock_until,
		"last_stimulus_time": last_stimulus_time, "last_stimulus_loudness": last_stimulus_loudness,
		"last_heard_strength": last_heard_strength,
		"migration_area_id": migration_area_id, "wander_next_game_seconds": wander_next_game_seconds,
		"wander_seed": wander_seed, "facing": facing_direction, "look_pitch": look_pitch}


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
	wander_next_game_seconds = float(data.get("wander_next_game_seconds", GameTime.elapsed_game_seconds))
	wander_seed = maxi(1, int(data.get("wander_seed", 1)))
	facing_direction = data["facing"]
	look_pitch = float(data.get("look_pitch", 0.0))
