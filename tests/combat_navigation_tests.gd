extends RefCounted

static func flat_map() -> WorldMap:
	var map := WorldMap.new()
	map.width = 12
	map.height = 12
	for level in 2:
		var floor := FloorData.new(level)
		for x in 12:
			for y in 12: floor.tiles[Vector2i(x, y)] = WorldTileData.new("floor", true)
		map.floors[level] = floor
	return map


static func run(game: MVPGameRoot, check: Callable) -> void:
	var map := flat_map()
	var p := PlayerController.new()
	p.world_map = map
	p.logical_position = Vector2(3, 3)
	p.state = game.player_state
	var z := ZombieActor.new()
	z.world_map = map
	z.logical_position = Vector2(3, 5)
	check.call(PlayerTargeting.melee_target(p, [z], p.look_direction()) == z, "player reach now hits a target two units away")
	z.logical_position.x += 0.7
	check.call(PlayerTargeting.melee_target(p, [z], p.look_direction()) == z, "melee sweep covers a nearby off-center body")
	p.facing_direction = Vector2.RIGHT
	check.call(PlayerTargeting.melee_target(p, [z], p.look_direction()) == null, "turning the view rotates the whole attack volume")
	p.facing_direction = Vector2.DOWN
	p.look_pitch = deg_to_rad(85)
	check.call(PlayerTargeting.melee_target(p, [z], p.look_direction()) == null, "looking upward moves the attack volume away from level enemies")
	p.look_pitch = 0
	z.logical_position = Vector2(3, 5.5)
	check.call(PlayerTargeting.melee_target(p, [z], p.look_direction()) == null and PlayerTargeting.melee_target(p, [z], p.look_direction(), ActorCombat.WEAPON_REACH) == z, "held weapons extend reach beyond unarmed range")
	z.logical_position = Vector2(3, 4)
	map._add_wall(Vector2(2, 3.5), Vector2(5, 3.5), "", 0)
	check.call(PlayerTargeting.melee_target(p, [z], p.look_direction()) == null, "cone sweep cannot hit through a nearby wall")
	map.floors[0].wall_faces.clear()
	map.rebuild_spatial_index()
	z.floor_level = 1
	var eye := ActorPerception.point(map, p.logical_position, 0, "", ActorPerception.EYE_HEIGHT)
	var target := ActorPerception.point(map, z.logical_position, 1, "", ActorPerception.EYE_HEIGHT)
	check.call(ActorCombat.contact(p, z, eye.direction_to(target), 4).is_empty(), "expanded vertical melee remains blocked by a floor slab")
	z.floor_level = 0
	z.facing_direction = Vector2.DOWN
	check.call(ActorCombat.contact(z, p, ActorCombat.direction(z), ActorCombat.ZOMBIE_REACH).is_empty(), "zombies cannot scratch a victim behind their facing")
	z.logical_position = p.logical_position + Vector2(0, 0.1)
	check.call(ActorCombat.contact(z, p, ActorCombat.direction(z), ActorCombat.ZOMBIE_REACH).is_empty(), "overlapping body proxies do not permit attacks behind the actor")
	z.logical_position = p.logical_position + Vector2(0, 1.0)
	z.facing_direction = Vector2.UP
	check.call(not ActorCombat.contact(z, p, ActorCombat.direction(z), ActorCombat.ZOMBIE_REACH).is_empty(), "zombie attack uses the same directional volume")
	var npc := SurvivorNPC.new()
	game.actor_layer.add_child(npc)
	npc.world_map = map
	npc.logical_position = p.logical_position
	npc.facing_direction = Vector2.DOWN
	game.actor_layer.add_child(z)
	z.add_to_group("zombies")
	npc.set_process(false)
	z.set_process(false)
	check.call(npc._defend(0.1) and z.health == 1, "NPC performs a directional close-range defensive attack")
	npc._defend(0.1)
	check.call(z.health == 1, "NPC defense respects attack cooldown")
	npc.add_to_group("zombie_targets")
	p.logical_position = Vector2(10, 10)
	z.player = p
	z.player_state = game.player_state
	z._perception_game_seconds_left = 100
	z._process(0.01)
	check.call(npc.health == 88.0, "zombies can damage an NPC using the shared combat volume")
	npc.take_damage(100)
	check.call(ActorCombat.select_target(z, [npc], ActorCombat.direction(z), ActorCombat.ZOMBIE_REACH) == null, "dead NPCs cannot be attacked again")
	npc.free()
	z.free()
	p.free()
	map.free()
	_navigation(check)
	_save(game, check)
	_cache(check)


static func _navigation(check: Callable) -> void:
	var map := flat_map()
	map._add_wall(Vector2(5, 1), Vector2(5, 8), "", 0)
	map._add_wall(Vector2(5, 8), Vector2(8, 8), "", 0)
	map._build_navigation()
	var nav := LocalNavigation.new()
	var goal := Vector2(6, 4)
	var state := {"position": Vector2(4, 4), "floor": 0, "stair_id": ""}
	# A stale/blocked shortcut must recover to a genuinely different route.
	nav._path = [{"position": goal, "floor": 0}]
	nav._planned_target = goal
	nav._planned_floor = 0
	nav._planned_world_revision = map.revision
	var safe := true
	for step in 500:
		state = nav.advance(map, state["position"], state["floor"], state["stair_id"], goal, 0, 1.0, 0.05)
		safe = safe and map.can_stand(state["position"], 0)
	check.call(Vector2(state["position"]).distance_to(goal) < 0.05 and safe and nav._conservative, "blocked wall-corner shortcut recovers along grid waypoints without crossing walls")
	map.free()
	map = flat_map()
	var link := StairLink.new("test", "", Vector2(3, 5), Vector2(7, 5), 0, 1, 0.8)
	map.stairs[link.id] = link
	map.rebuild_spatial_index()
	map._build_navigation()
	nav = LocalNavigation.new()
	state = {"position": Vector2(2, 4.8), "floor": 0, "stair_id": ""}
	var stayed_ground := true
	for step in 40:
		state = nav.advance(map, state["position"], state["floor"], state["stair_id"], Vector2(3.15, 4.8), 0, 1.0, 0.1)
		stayed_ground = stayed_ground and String(state["stair_id"]).is_empty() and state["floor"] == 0
	check.call(stayed_ground and Vector2(state["position"]).distance_to(Vector2(3.15, 4.8)) < 0.05, "ground route past a stair entrance never accidentally acquires stairs")
	for reverse in [false, true]:
		nav = LocalNavigation.new()
		state = {"position": Vector2(8, 5) if reverse else Vector2(2, 4.8), "floor": 1 if reverse else 0, "stair_id": ""}
		goal = Vector2(2, 4.8) if reverse else Vector2(8, 5)
		var floor_goal := 0 if reverse else 1
		for step in 250: state = nav.advance(map, state["position"], state["floor"], state["stair_id"], goal, floor_goal, 1.0, 0.1)
		check.call(state["floor"] == floor_goal and String(state["stair_id"]).is_empty() and Vector2(state["position"]).distance_to(goal) < 0.05, "offset approach traverses staircase and leaves the landing in both directions")
	for actor in [ZombieActor.new(), SurvivorNPC.new()]:
		actor.world_map = map
		actor.logical_position = Vector2(2, 4.8)
		actor.target_position = Vector2(8, 5)
		actor.target_floor = 1
		for step in 250: actor._move_toward_target(0.1)
		check.call(actor.floor_level == 1 and actor.stair_id.is_empty() and actor.logical_position.distance_to(actor.target_position) < 0.05, "both zombie and NPC movement controllers complete the offset stair route")
		actor.free()
	map._add_wall(Vector2(7, 4), Vector2(7, 6), "", 1)
	map._build_navigation()
	map.revision += 1
	nav = LocalNavigation.new()
	state = {"position": Vector2(5, 5), "floor": 0, "stair_id": link.id}
	var escaped := false
	for step in 160:
		state = nav.advance(map, state["position"], state["floor"], state["stair_id"], Vector2(8, 5), 1, 1.5, 0.1)
		if String(state["stair_id"]).is_empty() and state["floor"] == 0:
			escaped = true
			break
	check.call(escaped, "blocked stair exit reverses to the reachable landing instead of sticking or crossing a wall")
	_measure(map)
	map.free()


static func _save(game: MVPGameRoot, check: Callable) -> void:
	var original := QuickSave.snapshot(game)
	var speed := GameTime.speed_mode
	game.npc.health = 76.0
	game.npc.attack_cooldown = 0.7
	game.npc.look_pitch = -0.3
	var data := QuickSave.snapshot(game)
	check.call(QuickSave.validate(data, game), "NPC combat state produces a valid v10 save")
	game.npc.health = 1
	QuickSave.restore(game, data)
	check.call(game.npc.health == 76.0 and game.npc.attack_cooldown == 0.7 and game.npc.look_pitch == -0.3, "NPC health cooldown and aim survive restore")
	for key in ["health", "attack_cooldown", "look_pitch"]: data["npc"].erase(key)
	QuickSave.restore(game, data)
	check.call(game.npc.health == 100 and game.npc.attack_cooldown == 0 and game.npc.look_pitch == 0, "old v10 NPC saves use compatible combat defaults")
	for key in ["health", "attack_cooldown", "look_pitch"]:
		var broken := original.duplicate(true)
		broken["npc"][key] = NAN
		check.call(not QuickSave.validate(broken, game), "invalid NPC combat numbers are rejected before restore")
	QuickSave.restore(game, original)
	GameTime.set_speed(speed)


static func _measure(map: WorldMap) -> void:
	var navs: Array[LocalNavigation] = []
	var states: Array[Dictionary] = []
	var targets: Array = []
	var attacker := ZombieActor.new()
	attacker.world_map = map
	attacker.logical_position = Vector2(5, 2)
	for i in 32:
		navs.append(LocalNavigation.new())
		states.append({"position": Vector2(2 + (i % 4) * 0.15, 3.5), "floor": 0, "stair_id": ""})
		var target := ZombieActor.new()
		target.world_map = map
		target.logical_position = Vector2(3 + (i % 8) * 0.5, 2.5 + (i / 8) * 0.5)
		targets.append(target)
	var samples: Array[int] = []
	for tick in 100:
		var start := Time.get_ticks_usec()
		for i in 32:
			var state := states[i]
			states[i] = navs[i].advance(map, state["position"], state["floor"], state["stair_id"], Vector2(8, 5), 0, 0.8, 0.1)
			ActorCombat.select_target(attacker, targets, Vector3.BACK, ActorCombat.ZOMBIE_REACH)
		samples.append(Time.get_ticks_usec() - start)
	samples.sort()
	print("Combat/navigation CPU sample: 32 navigators + 32 melee queries x 32 candidates; p50=%dus p95=%dus max=%dus (no rendering)." % [samples[50], samples[95], samples[99]])
	for target in targets: target.free()
	attacker.free()


static func _cache(check: Callable) -> void:
	var map := flat_map()
	map._build_navigation()
	var from := Vector2(2, 2)
	var to := Vector2(4, 2)
	var route := map.find_path(from, 0, to, 0)
	route[0]["position"] = Vector2(100, 100)
	check.call(map.find_path(from, 0, to, 0)[0]["position"] == to and map.path_cache_hits > 0, "shared path cache returns independent copies")
	map.barriers["gate"] = {"id": "gate", "start": Vector2(3, 0), "end": Vector2(3, 12), "kind": "door", "level": 0, "building_id": "", "open": true}
	map.set_barrier_open("gate", false)
	check.call(map.find_path(from, 0, to, 0).is_empty(), "closing a barrier invalidates a cached route before another actor can use it")
	var navigation := LocalNavigation.new()
	var displaced := navigation.advance(map, Vector2(3, 2), 0, "", to, 0, 1, 0.1)
	check.call(map.can_stand(displaced["position"], 0) and Vector2(displaced["position"]).x < 3, "a door closing over AI resolves to a valid nearby point without forcing it through the door")
	map.set_barrier_open("gate", true)
	check.call(not map.find_path(from, 0, to, 0).is_empty(), "opening a barrier invalidates cached unreachable results")
	for i in 72: map.find_path(from + Vector2(i * 0.003, 0), 0, to, 0)
	check.call(map._path_cache.size() <= 64, "shared navigation cache has a fixed memory bound")
	map.free()
