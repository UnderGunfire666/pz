extends RefCounted


class CountingMap extends WorldMap:
	var sound_queries := 0
	func trace_sound(from: Vector3, to: Vector3, max_cost: float = INF) -> Dictionary:
		sound_queries += 1
		return super.trace_sound(from, to, max_cost)


static func run(game: MVPGameRoot, check: Callable) -> void:
	var map := _flat_map()
	var ear := Vector3(2.0, 1.62, 3.0)
	var source := Vector3(6.0, 1.62, 3.0)
	check.call(is_equal_approx(float(map.trace_sound(ear, source)["cost"]), 4.0), "hearing uses Euclidean 3D distance in open space")
	map._add_wall(Vector2(4, 1), Vector2(4, 3), "", 0)
	map._add_wall(Vector2(4, 3), Vector2(4, 5), "", 0)
	var wall := map.trace_sound(ear, source)
	check.call(is_equal_approx(float(wall["cost"]), 6.5) and wall["obstacles"]["wall"] == 1, "joined wall seam attenuates once")
	check.call(is_equal_approx(float(map.trace_sound(source, ear)["cost"]), 6.5), "sound propagation is reciprocal")
	map.floors[0].wall_faces.clear()
	map.rebuild_spatial_index()
	map._register_barrier("test_door", Vector2(4, 1), Vector2(4, 5), 0, "", "door", false)
	var closed := float(map.trace_sound(ear, source)["cost"])
	map.set_barrier_open("test_door", true)
	var opened := float(map.trace_sound(ear, source)["cost"])
	map.set_barrier_open("test_door", false)
	check.call(is_equal_approx(closed, 5.6) and is_equal_approx(opened, 4.0)
		and is_equal_approx(float(map.trace_sound(ear, source)["cost"]), closed), "door opening and reclosing immediately change acoustic loss")
	map.set_barrier_open("test_door", true)
	map._register_barrier("test_window", Vector2(4, 1), Vector2(4, 5), 0, "", "window", false)
	check.call(is_equal_approx(float(map.trace_sound(ear, source)["cost"]), 4.8), "closed glass transmits more than a closed door or wall")
	map.set_barrier_open("test_window", true)
	check.call(is_equal_approx(float(map.trace_sound(ear, source)["cost"]), 4.0), "open window removes its acoustic penalty")
	var upper := ear + Vector3.UP * map.floor_height
	var slab := map.trace_sound(ear, upper)
	check.call(is_equal_approx(float(slab["cost"]), 9.0) and slab["obstacles"]["floor"] == 1,
		"stacked floors use height and slab loss even without a stair connection")
	check.call(is_equal_approx(float(map.trace_sound(ear, ear + Vector3.UP * 6.0)["cost"]), 18.0), "each crossed floor attenuates separately")
	map.floors[1].tiles.erase(Vector2i(2, 3))
	check.call(is_equal_approx(float(map.trace_sound(ear, upper)["cost"]), 3.0), "unsupported upper space does not invent a floor barrier")
	map.floors[1].tiles[Vector2i(2, 3)] = WorldTileData.new("floor", true)
	var roof := BuildingData.new("roof", "roof", Rect2i(1, 1, 6, 6), "", 0.0)
	roof.floor_count = 3
	map.buildings[roof.id] = roof
	check.call(map.trace_sound(Vector3(2, 8, 3), Vector3(2, 10, 3))["obstacles"]["roof"] == 1, "roof attenuates the 3D sound segment")
	map.buildings.clear()
	_geometry_stairs(map, check)
	_listener_behaviour(game, map, check)
	_save_compatibility(game, check)
	_dense_sample(map, check)
	map.free()


static func _geometry_stairs(map: WorldMap, check: Callable) -> void:
	var link := StairLink.new("hearing_stair", "", Vector2(8, 4), Vector2(8, 8), 0, 1, 1.0)
	map.stairs[link.id] = link
	map.rebuild_spatial_index()
	var bottom := ActorPerception.point(map, link.start, 0, "", 1.62)
	var top := ActorPerception.point(map, link.end, 1, "", 1.62)
	var result := map.trace_sound(bottom, top)
	check.call(result["obstacles"]["floor"] == 0 and result["obstacles"]["stairs"] == 0
		and is_equal_approx(float(result["cost"]), 5.0), "stair opening carries sound without a phantom floor or step penalty")
	var under := map.trace_sound(Vector3(8, 0.2, 6), Vector3(8, 2.8, 6))
	check.call(under["obstacles"]["stairs"] == 1, "stair structure is counted once when sound crosses its treads")
	var emitter := SurvivorNPC.new()
	emitter.world_map = map
	emitter.logical_position = link.start.lerp(link.end, 0.5)
	emitter.stair_id = link.id
	var noise := NoiseBus.emit_actor_noise(emitter, 12.0, "stairs")
	check.call(is_equal_approx(noise.spatial_position.y, 2.55) and noise.source_stair_id == link.id, "emission snapshots the actual mid-stair source elevation")
	var listener := ZombieActor.new()
	listener.world_map = map
	listener.logical_position = link.start
	var now := GameTime.elapsed_game_seconds
	var heard := ActorHearing.sample(map, listener, noise, now)
	check.call(not heard.is_empty() and heard["floor"] == 0 and Vector2(heard["position"]).distance_to(link.start) < 1.5,
		"mid-stair sound selects the listener-side landing without predicting source travel")
	emitter.stair_id = ""
	noise = NoiseBus.emit_actor_noise(emitter, 12.0, "under stairs")
	heard = ActorHearing.sample(map, listener, noise, now)
	check.call(is_equal_approx(noise.spatial_position.y, ActorPerception.CHEST_HEIGHT) and heard["floor"] == 0
		and Vector2(heard["position"]).distance_to(link.start) > 1.0, "standing beneath a stair never implies climbing it")
	emitter.stair_id = link.id
	listener.stair_id = link.id
	listener.logical_position = link.start.lerp(link.end, 0.75)
	noise = NoiseBus.emit_actor_noise(emitter, 12.0, "stairs")
	heard = ActorHearing.sample(map, listener, noise, now)
	var expected_distance := ActorPerception.point(map, listener.logical_position, 0, link.id, 1.62).distance_to(noise.spatial_position)
	check.call(is_equal_approx(float(heard["distance"]), expected_distance), "listener ear height follows its own stair progress")
	var captured := noise.spatial_position
	emitter.logical_position += Vector2.ONE
	emitter.free()
	check.call(noise.spatial_position == captured, "noise snapshot survives emitter movement and deletion")
	listener.free()


static func _listener_behaviour(game: MVPGameRoot, map: CountingMap, check: Callable) -> void:
	var zombie := ZombieActor.new()
	zombie.world_map = map
	zombie.logical_position = Vector2(2, 10)
	var npc := SurvivorNPC.new()
	npc.world_map = map
	npc.logical_position = zombie.logical_position
	npc.home_position = npc.logical_position
	npc.home_floor = 0
	game.add_child(npc)
	npc.set_process(false)
	var now := GameTime.elapsed_game_seconds
	var noise := NoiseStimulus.new(Vector2(3, 10), 8.0, "footsteps", 0, 1.0, now)
	zombie.hear_noise(noise)
	npc.hear_noise(noise)
	check.call(zombie.awareness == ZombieActor.Awareness.SOUND and zombie.target_position == npc.brain.last_noise_position
		and zombie.target_position != noise.world_position, "zombie and NPC share the same anonymous approximate sound clue")
	check.call(zombie.target_actor_id.is_empty() and npc.threat_memory_until <= now, "ordinary sound grants no identity and does not trigger blind NPC flight")
	var old_target := zombie.target_position
	var memory_count := npc.brain.memories.size()
	zombie.hear_noise(noise)
	npc.hear_noise(noise)
	check.call(npc.brain.memories.size() == memory_count and zombie.target_position == old_target, "duplicate sounds do not churn targets or spam memories")
	var weak := NoiseStimulus.new(Vector2(5, 10), 2.0, "distant", 0, 2.0, now)
	zombie.hear_noise(weak)
	check.call(zombie.target_position == old_target, "higher emitted loudness cannot override a stronger received clue")
	var strong := NoiseStimulus.new(Vector2(2, 11), 14.0, "nearby", 0, 1.0, now)
	zombie.hear_noise(strong)
	check.call(zombie.target_position != old_target, "stronger received sound can interrupt the switch lock")
	zombie.awareness = ZombieActor.Awareness.VISUAL
	old_target = zombie.target_position
	zombie.hear_noise(noise)
	check.call(zombie.target_position == old_target, "sound cannot override current visual contact")
	zombie.awareness = ZombieActor.Awareness.VISUAL_MEMORY
	zombie.hear_noise(NoiseStimulus.new(Vector2(4, 10), 100.0, "bang", 0, 1.0, now))
	check.call(zombie.awareness == ZombieActor.Awareness.VISUAL_MEMORY, "recent visual memory keeps priority during its lock")
	var expired := NoiseStimulus.new(Vector2(2, 10), 100.0, "stale", 0, 1.0, now - 7.0)
	check.call(ActorHearing.sample(map, npc, expired, now).is_empty(), "expired event cannot create a fresh memory")
	expired.world_time = now + 1.0
	check.call(ActorHearing.sample(map, npc, expired, now).is_empty(), "future event is rejected")
	expired.world_time = now
	expired.audible_range = 0.0
	check.call(ActorHearing.sample(map, npc, expired, now).is_empty(), "zero-radius sound is silent even at the same position")
	noise.emitter_instance_id = npc.get_instance_id()
	check.call(ActorHearing.sample(map, npc, noise, now).is_empty(), "NPC ignores its own emission without holding an emitter reference")
	noise.emitter_instance_id = 0
	noise.map_instance_id = game.world_map.get_instance_id()
	check.call(ActorHearing.sample(map, npc, noise, now).is_empty(), "sounds from another world do not leak to listeners")
	noise.map_instance_id = 0
	var before := map.sound_queries
	var far := NoiseStimulus.new(Vector2(1000, 1000), 2.0, "far", 2, 1.0, now)
	check.call(ActorHearing.sample(map, npc, far, now).is_empty() and map.sound_queries == before, "3D range rejection avoids geometry work across floors")
	var stacked := NoiseStimulus.new(npc.logical_position, 7.0, "upper", 1, 1.0, now)
	check.call(ActorHearing.sample(map, npc, stacked, now).is_empty(), "quiet stacked sound cannot penetrate a solid slab")
	stacked.audible_range = 12.0
	check.call(not ActorHearing.sample(map, npc, stacked, now).is_empty(), "loud sound can penetrate a slab without a navigation connection")
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	npc.hear_noise(NoiseStimulus.new(Vector2(3, 10), 10.0, "struggle", 0, 1.0, now))
	check.call(npc.threat_memory_until <= now, "pause prevents NPC auditory reactions")
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	npc.hear_noise(NoiseStimulus.new(Vector2(3, 10), 10.0, "struggle", 0, 1.0, now))
	check.call(npc.brain.noise_memory_until > now and npc.brain.last_noise_danger and npc.brain.last_noise_position != Vector2(3, 10)
		and npc.decision_cooldown == 0.0, "audible danger interrupts NPC task using approximate threat memory")
	# Isolate visual perception from this auditory decision check.
	npc.logical_position = Vector2(40, 40)
	npc._choose_goal()
	check.call(npc.brain.current_goal == NPCBrain.Goal.FLEE, "danger sound participates in NPC goal selection")
	var threat_clue := npc.brain.last_noise_position
	npc.logical_position = Vector2(2, 10)
	npc.hear_noise(NoiseStimulus.new(Vector2(2, 11), 100.0, "footsteps", 0, 1.0, now))
	check.call(npc.brain.last_noise_position == threat_clue and npc.brain.last_noise_danger, "ordinary sound cannot erase an active danger clue")
	npc.threat_memory_until = now + 30.0
	npc.threat_memory_position = Vector2(12, 12)
	npc.hear_noise(NoiseStimulus.new(Vector2(2, 11), 100.0, "struggle", 0, 1.0, now))
	check.call(npc.threat_memory_position == Vector2(12, 12), "auditory update preserves a still-active visual threat")
	npc.logical_position = Vector2(40, 40)
	GameTime.elapsed_game_seconds = now + 46.0
	npc._choose_goal()
	check.call(npc.brain.current_goal != NPCBrain.Goal.FLEE, "NPC sound threat expires on the simulation clock")
	GameTime.elapsed_game_seconds = now
	zombie.free()
	npc.free()


static func _save_compatibility(game: MVPGameRoot, check: Callable) -> void:
	var brain := NPCBrain.new()
	brain.last_noise_time = GameTime.elapsed_game_seconds
	brain.last_noise_strength = 3.25
	brain.last_noise_danger = true
	brain.noise_memory_until = brain.last_noise_time + 45.0
	brain.noise_lock_until = brain.last_noise_time + 6.0
	var data := brain.to_save_data()
	var restored := NPCBrain.new()
	restored.load_save_data(data)
	check.call(restored.to_save_data() == data, "NPC auditory strength, locks and expiry survive save roundtrip")
	for key in ["last_noise_time", "last_noise_strength", "last_noise_danger", "noise_memory_until", "noise_lock_until"]: data.erase(key)
	restored.load_save_data(data)
	check.call(restored.last_noise_time == -1.0 and restored.noise_memory_until == 0.0, "legacy NPC memory loads as inactive without inventing a fresh clue")
	var zombie := ZombieActor.new()
	zombie.last_heard_strength = 3.25
	data = zombie.perception_save_data()
	zombie.last_heard_strength = 0.0
	zombie.load_perception_save_data(data)
	check.call(zombie.last_heard_strength == 3.25, "zombie received strength survives save roundtrip")
	data.erase("last_heard_strength")
	zombie.load_perception_save_data(data)
	check.call(zombie.last_heard_strength == 0.0 and QuickSave._valid_zombie_perception(data), "legacy zombie memory accepts missing received strength")
	zombie.free()
	var snapshot := QuickSave.snapshot(game)
	snapshot["npc"]["brain"]["noise_memory_until"] = NAN
	check.call(not QuickSave.validate(snapshot, game), "save validation rejects non-finite auditory expiry before mutation")
	snapshot = QuickSave.snapshot(game)
	snapshot["npc"]["brain"]["last_noise_danger"] = "invalid"
	check.call(not QuickSave.validate(snapshot, game), "save validation rejects invalid auditory danger flag")


static func _dense_sample(map: CountingMap, check: Callable) -> void:
	# Small, densely partitioned three-floor map, no renderer or navigation needed.
	for level in range(3):
		for x in range(1, 16):
			for y in range(16): map._add_wall(Vector2(x, y), Vector2(x, y + 1), "", level)
	map.rebuild_spatial_index()
	var listeners: Array[ZombieActor] = []
	for i in range(128):
		var actor := ZombieActor.new()
		actor.world_map = map
		actor.logical_position = Vector2(0.5 + i % 16, 0.5 + (i / 16))
		actor.floor_level = i % 3
		listeners.append(actor)
	var noise := NoiseStimulus.new(Vector2(8.5, 4.5), 12.0, "dense", 1, 1.0, GameTime.elapsed_game_seconds)
	var samples: Array[int] = []
	var heard := 0
	var cutoff_matches := true
	for actor in listeners:
		var from := ActorPerception.point(map, actor.logical_position, actor.floor_level, "", 1.62)
		var to := ActorPerception.point(map, noise.world_position, noise.floor_level, "", 1.05)
		var exact := float(map.trace_sound(from, to)["cost"])
		var bounded := float(map.trace_sound(from, to, 12.0)["cost"])
		cutoff_matches = cutoff_matches and ((exact >= 12.0 and bounded >= 12.0) or is_equal_approx(exact, bounded))
	check.call(cutoff_matches, "budget cutoff preserves audibility and all audible propagation costs")
	for repeat in range(20):
		var started := Time.get_ticks_usec()
		for actor in listeners:
			if not ActorHearing.sample(map, actor, noise, GameTime.elapsed_game_seconds).is_empty(): heard += 1
		samples.append(Time.get_ticks_usec() - started)
	samples.sort()
	check.call(heard > 0 and heard < 2560 and map._nav_points.is_empty(), "dense hearing filters listeners without performing navigation searches")
	print("Hearing CPU sample: 128 listeners, 720 wall segments, 3 floors; 20 events p50=%dus p95=%dus max=%dus (headless, not frame/GPU time)." % [samples[10], samples[18], samples[19]])
	for actor in listeners: actor.free()


static func _flat_map() -> CountingMap:
	var map := CountingMap.new()
	map.width = 16
	map.height = 16
	for level in range(3):
		var floor := FloorData.new(level)
		for y in range(16):
			for x in range(16): floor.tiles[Vector2i(x, y)] = WorldTileData.new("floor", true)
		map.floors[level] = floor
	return map
