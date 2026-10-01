class_name ZombiePressureTests
extends RefCounted


static func run(game: MVPGameRoot, check: Callable) -> void:
	var spawner := game.zombie_spawner
	var catalog := spawner.area_catalog
	check.call(catalog.validate(game.world_map).is_empty(),
		"zombie area resources have unique valid IDs, adjacency and stand points")
	var initial := spawner._living_count()
	var current_identity := QuickSave.map_identity(game.world_map.definition)
	var legacy_identity := {"id": "orangeville_prototype", "format_version": 1,
		"content_hash": "64917b6b843659b75e7621d51cfe79bd92df821324e02daf3ce3df03d71eca4f"}
	check.call(QuickSave._compatible_map_identity(legacy_identity, current_identity), "audited bundled-map heat migration accepts the previous version-eight save identity")
	var changed_identity := current_identity.duplicate()
	changed_identity.content_hash = "changed_geometry"
	check.call(not QuickSave._compatible_map_identity(legacy_identity, changed_identity), "legacy save compatibility never bypasses edited-map geometry validation")
	var limits := catalog.rules.population_range(spawner.population_preset)
	check.call(initial >= limits.x and initial <= limits.y,
		"heatmap spawning selects a finite total within the saved population preset")
	var candidates := game.world_map.initial_zombie_spawn_candidates()
	check.call(candidates.size() > 16 and spawner.active_zombies.all(func(zombie: ZombieActor) -> bool:
		return game.world_map.pressure_at(zombie.logical_position, zombie.floor_level) > 0.0),
		"initial zombies come from weighted walkable heatmap cells rather than fixed area points")
	var pressure_before := catalog.area("corner_store").pressure
	var victim: ZombieActor = spawner.active_zombies[0]
	victim.take_damage(ZombieActor.MAX_HEALTH)
	check.call(spawner._living_count() == initial - 1, "killing a zombie permanently lowers living population")
	GameTime.last_advanced_game_seconds = catalog.rules.migration_interval_game_minutes * 120.0
	spawner._process(0.0)
	check.call(spawner._living_count() == initial - 1,
		"world updates never spawn a replacement in the visible area or elsewhere")

	_reset_population(spawner)
	var scheduled_count := spawner._living_count()
	var scheduled := spawner._request_one_migration()
	check.call(scheduled and spawner._living_count() == scheduled_count,
		"authored pressure and adjacency schedule migration without changing population")
	_reset_population(spawner)
	var migrant: ZombieActor = spawner.active_zombies[0] if not spawner.active_zombies.is_empty() else null
	if migrant != null:
		# Migration destinations remain authored separately. Place a controlled
		# idle actor on the road instead of assuming initial spawning uses that
		# legacy population point.
		migrant.logical_position = Vector2(8.5, 7.5)
		migrant.floor_level = 0
		migrant.stair_id = ""
	var population_before := spawner._living_count()
	var moved := migrant != null and migrant.request_migration(Vector2(16.5, 12.5), 0, "outskirts")
	if migrant != null:
		for _step in range(1200):
			migrant._move_toward_target(0.08)
			if migrant.floor_level == 0 and migrant.logical_position.distance_to(Vector2(16.5, 12.5)) < 0.2: break
	check.call(moved and migrant.logical_position.distance_to(Vector2(16.5, 12.5)) < 0.2
		and spawner._living_count() == population_before,
		"migration physically transfers a living zombie into another area without duplication")

	var heard_at := Vector2(16.0, 11.8)
	NoiseBus.emit_noise(heard_at, 8.0, "test noise", 0, 1.0)
	check.call(migrant.awareness == ZombieActor.Awareness.SOUND and migrant.target_actor_id.is_empty()
		and migrant.target_position.is_equal_approx(heard_at),
		"sound creates an anonymous temporary investigation point")
	var sound_target := migrant.target_position
	var old_player_position := game.player.logical_position
	var old_player_floor := game.player.floor_level
	game.player.logical_position = Vector2(15.7, 11.8)
	check.call(migrant.target_position == sound_target and migrant.target_actor_id.is_empty(),
		"hearing does not reveal the emitter actor or track its live position")
	game.player.logical_position = old_player_position
	game.player.floor_level = old_player_floor
	check.call(is_equal_approx(catalog.area("corner_store").pressure, pressure_before),
		"temporary noise and migration never mutate static area pressure resources")

	var old_zombie_position := migrant.logical_position
	var old_zombie_floor := migrant.floor_level
	var old_facing := migrant.facing_direction
	var old_npc_position := game.npc.logical_position
	var old_npc_floor := game.npc.floor_level
	migrant.logical_position = Vector2(8.5, 7.5)
	migrant.floor_level = 0
	migrant.stair_id = ""
	migrant.facing_direction = Vector2.LEFT
	game.player.logical_position = Vector2(7.5, 7.5)
	game.player.floor_level = 0
	game.npc.logical_position = Vector2(8.5, 6.5)
	game.npc.floor_level = 0
	check.call(migrant._can_see_actor(game.player) and migrant._can_see_actor(game.npc),
		"players and NPCs use the same zombie sight and occlusion query")
	game.player.logical_position = old_player_position
	game.npc.logical_position = old_npc_position
	game.npc.floor_level = old_npc_floor
	migrant.logical_position = old_zombie_position
	migrant.floor_level = old_zombie_floor
	migrant.facing_direction = old_facing

	migrant.awareness = ZombieActor.Awareness.VISUAL_MEMORY
	migrant.has_target = true
	migrant.visual_memory_expires_at = GameTime.elapsed_game_seconds - 1.0
	migrant._update_memory()
	check.call(not migrant.has_target and migrant.awareness == ZombieActor.Awareness.IDLE,
		"visual memory expires against unified world time")
	migrant.hear_noise(NoiseStimulus.new(migrant.logical_position + Vector2(0.5, 0.0), 2.0, "search", migrant.floor_level, 2.0, GameTime.elapsed_game_seconds))
	migrant.sound_memory_expires_at = GameTime.elapsed_game_seconds - 1.0
	migrant._update_memory()
	check.call(migrant.awareness == ZombieActor.Awareness.SEARCH,
		"expired auditory pursuit becomes a local search rather than actor tracking")
	migrant.search_expires_at = GameTime.elapsed_game_seconds - 1.0
	migrant._update_memory()
	check.call(migrant.awareness == ZombieActor.Awareness.IDLE and not migrant.has_target,
		"local search ends after the configured world-time duration")

	var observer: ZombieActor = spawner.active_zombies[0]
	var peer: ZombieActor = spawner.active_zombies[1]
	observer.logical_position = Vector2(8.5, 8.5)
	observer.floor_level = 0
	observer.stair_id = ""
	peer.logical_position = Vector2(8.5, 9.2)
	peer.floor_level = 0
	peer.stair_id = ""
	peer._clear_target()
	spawner.share_visual_observation(observer, Vector2(9.5, 8.5), 0)
	check.call(peer.awareness == ZombieActor.Awareness.GROUP and spawner._living_count() == population_before,
		"nearby zombies loosely converge without a leader or population change")
	var paused_position := peer.logical_position
	var paused_awareness := peer.awareness
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	NoiseBus.emit_noise(peer.logical_position, 10.0, "paused noise", peer.floor_level, 5.0)
	peer._process(10.0)
	check.call(peer.logical_position == paused_position and peer.awareness == paused_awareness,
		"pause freezes zombie movement, new noise perception and memory")
	var old_clock := GameTime.elapsed_game_seconds
	peer.awareness = ZombieActor.Awareness.VISUAL_MEMORY
	peer.has_target = true
	peer.visual_memory_expires_at = old_clock + 30.0
	GameTime.set_speed(GameTime.SpeedMode.FAST)
	GameTime._process(0.5)
	peer._update_memory()
	check.call(peer.awareness == ZombieActor.Awareness.IDLE,
		"fast-forward advances zombie memory using the unified world clock")
	GameTime.elapsed_game_seconds = old_clock
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)

	_reset_population(spawner)
	GameTime.last_advanced_game_seconds = 0.0


static func _reset_population(spawner: ZombieSpawner) -> void:
	spawner.clear_population()
	spawner.population_initialized = false
	spawner.initial_population_count = 0
	spawner.migration_game_seconds = 0.0
	spawner.seed_demo_population()
