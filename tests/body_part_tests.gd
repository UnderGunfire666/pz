extends RefCounted

static func run(game: MVPGameRoot, check: Callable) -> void:
	var map := preload("res://tests/combat_navigation_tests.gd").flat_map()
	var p := PlayerController.new()
	var state := PlayerState.new()
	p.setup(map, state, Vector2(3, 3))
	game.actor_layer.add_child(p)
	p.set_process(false)
	var z := ZombieActor.new()
	z.setup(map, p, state, Vector2(3, 4))
	game.actor_layer.add_child(z)
	z.set_process(false)
	for actor: Node in [p, z]:
		for facing in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			actor.facing_direction = facing
			var transform := ActorBody.transform_for(actor)
			var volumes := ActorBody.volumes(actor)
			for region: String in volumes:
				var bounds: AABB = volumes[region][0] if volumes[region] is Array else volumes[region]
				var center := bounds.get_center()
				var hittable := false
				for approach: Vector3 in [Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
					var origin := transform * (center + approach * 1.2)
					var hit := ActorBody.ray_hit(actor, origin, transform.basis * -approach, 2.0)
					hittable = hittable or hit.get("region", "") == region
				check.call(hittable, "body ray identifies %s at facing %s without a visual instance" % [region, facing])
	# Actual zombie attack path must feed the resolved region into PlayerState.
	z.facing_direction = Vector2.UP
	p.facing_direction = Vector2.DOWN
	z.look_pitch = -0.35
	z._perception_game_seconds_left = 1000
	var contact := ActorCombat.contact(z, p, ActorCombat.direction(z), ActorCombat.ZOMBIE_REACH)
	check.call(not contact.is_empty() and contact["region"] == "Torso", "aimed zombie strike resolves torso")
	z.logical_position = p.logical_position + Vector2(0, 3.1)
	check.call(not ActorBody.collision_enabled(z) and ActorCombat.contact(z, p, ActorCombat.direction(z), 5.0).is_empty(),
		"zombie hurtboxes outside the three-tile player bubble are inactive")
	z.logical_position = Vector2(3, 4)
	if not contact.is_empty():
		z._process(0.0)
		check.call(state.wounds.is_empty(), "zombie wind-up does not apply damage before its collision window")
		z._process(ZombieActor.ATTACK_HIT_TIME + 0.01)
		check.call(state.wounds.size() == 1 and state.wounds[0]["region"] == contact["region"]
			and state.body_health["Torso"] == 88.0 and state.body_health["Right Arm"] == 100.0,
			"zombie collision window creates a wound on the contacted body region instead of fixed right arm")
		check.call(p.visual_damage_remaining > 0.0, "contacted player body region triggers a short damage visual")
		check.call(p.visual_attack_remaining == 0.0, "a body collision interrupts the player's pending attack")
		z.visual_attack_remaining = ZombieActor.ATTACK_ANIMATION_DURATION
		z._attack_impact_remaining = ZombieActor.ATTACK_HIT_TIME
		z.receive_hit(1, "Left Arm")
		check.call(z.visual_attack_remaining == 0.0 and z._attack_impact_remaining < 0.0,
			"a body collision interrupts a zombie attack")
	# A rear-facing zombie turns before it advances and holds an attack stand-off
	# distance rather than trying to navigate into the player's centre.
	z.logical_position = Vector2(3, 6)
	z.facing_direction = Vector2.DOWN
	z.target_position = p.logical_position
	z.target_floor = p.floor_level
	z.target_stair_id = p.stair_id
	z.target_actor_id = "player"
	z.awareness = ZombieActor.Awareness.VISUAL
	z.has_target = true
	z.visual_memory_expires_at = GameTime.elapsed_game_seconds + 60.0
	z.attack_cooldown = 10.0
	z._perception_game_seconds_left = 1000.0
	var before_turn := z.logical_position
	z._process(0.1)
	check.call(z.logical_position.is_equal_approx(before_turn) and z.facing_direction.distance_to(Vector2.DOWN) > 0.01,
		"rear-facing zombie turns in place before pursuing a player")
	for step in 80: z._process(0.1)
	var separation := z.logical_position.distance_to(p.logical_position)
	check.call(separation >= ZombieActor.ATTACK_STANDOFF_DISTANCE - ZombieActor.MOVE_SPEED * 0.1
		and separation < 1.1, "zombie stops at attack distance without overlapping the player centre")
	var inventory := InventoryGrid.new(false)
	state.setup_inventory(inventory)
	var coat := ClothingTests.garment("body_test_coat", "outer_top", ["Torso"], {"Torso": 100}, {"Torso": 100})
	inventory.contents("outer_top").append(coat)
	var before: float = state.body_health["Torso"]
	state.receive_hit("Scratch", contact.get("region", "Torso"), 12, true, 0.0, 1.0)
	check.call(state.body_health["Torso"] == before, "resolved torso region passes through existing clothing protection")
	z.receive_hit(1, "Left Leg")
	check.call(z.body_health["Left Leg"] == 50.0 and z.body_health["Right Leg"] == 100.0 and z.leg_performance() < 1.0,
		"zombie leg damage is regional and slows locomotion")
	var head_target := ZombieActor.new()
	game.actor_layer.add_child(head_target)
	head_target.receive_hit(1, "Head")
	check.call(head_target.health == 0 and head_target.is_queued_for_deletion(), "head strikes apply the documented twofold zombie damage")
	z.free()
	p.free()
	map.free()
	var baseline := QuickSave.snapshot(game)
	var saved_speed := GameTime.speed_mode
	game.zombie_spawner.clear_population()
	var survivor := game.zombie_spawner._spawn(Vector2(18.5, 13.5), 0)
	check.call(survivor != null, "body save fixture spawns in valid space")
	if survivor != null:
		survivor.receive_hit(1, "Right Arm")
		var snapshot := QuickSave.snapshot(game)
		check.call(QuickSave.validate(snapshot, game), "regional zombie damage produces a valid v11 snapshot")
		QuickSave.restore(game, snapshot)
		var restored := false
		for zombie: ZombieActor in game.zombie_spawner.active_zombies:
			if zombie.logical_position == Vector2(18.5, 13.5):
				restored = zombie.body_health["Right Arm"] == 50.0 and zombie.health == 1 and zombie.arm_performance() < 1.0
		check.call(restored, "save restore preserves zombie region health and combat impairment")
		var broken := snapshot.duplicate(true)
		broken["zombies"][0]["body_health"]["Head"] = NAN
		check.call(not QuickSave.validate(broken, game), "NaN body health is rejected before restoration")
		var legacy := snapshot.duplicate(true)
		legacy["version"] = 10
		for entry in legacy["zombies"]: entry.erase("body_health")
		var path := "user://body_parts_v10_test.save"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_var(legacy, false)
		file.close()
		var bytes := FileAccess.get_file_as_bytes(path)
		check.call(QuickSave.load_game(game, path) and FileAccess.get_file_as_bytes(path) == bytes,
			"real v10 file migrates without rewriting source bytes")
		check.call(not legacy["zombies"][0].has("body_health"), "migration does not mutate the source snapshot")
		check.call(ActorBody.valid_health(game.zombie_spawner.active_zombies[0].body_health), "legacy zombies acquire valid regional health")
		DirAccess.remove_absolute(path)
	QuickSave.restore(game, baseline)
	GameTime.set_speed(saved_speed)
