class_name QuickSave
extends RefCounted

## A single versioned local slot. Only primitive Variant data is decoded.
## Pack steps resume from saved progress; other actions stop with search progress retained.
const VERSION := 10
const PATH := "user://afterlight_mvp_v10.save"
const LEGACY_PATH_V9 := "user://afterlight_mvp_v9.save"
const LEGACY_PATH_V8 := "user://afterlight_mvp_v8.save"
const LEGACY_PATH_V7 := "user://afterlight_mvp_v7.save"
const LEGACY_PATH := "user://afterlight_mvp_v6.save"
const LEGACY_PATH_V5 := "user://afterlight_mvp_v5.save"
const LEGACY_PATH_V4 := "user://afterlight_mvp_v4.save"
const LEGACY_PATH_V3 := "user://afterlight_mvp_v3.save"


static func save_game(game: MVPGameRoot, path: String = PATH) -> bool:
	if game.interactions.active_action.get("kind") != "pack":
		game.interactions.interrupt_action("Saved")
	var data := snapshot(game)
	if not validate(data, game):
		game.show_notification("Current state is invalid; previous save retained.")
		return false
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		game.show_notification("Cannot write save: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_var(data, false)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		game.show_notification("Save write failed; previous save retained.")
		return false
	var result := DirAccess.rename_absolute(temp_path, path)
	if result != OK:
		game.show_notification("Cannot finish save; previous save retained.")
		return false
	game.show_notification("Saved current floor, supplies and search progress.")
	return true


static func load_game(game: MVPGameRoot, path: String = PATH) -> bool:
	if path == PATH and not FileAccess.file_exists(path):
		if FileAccess.file_exists(LEGACY_PATH_V9): path = LEGACY_PATH_V9
		elif FileAccess.file_exists(LEGACY_PATH_V8): path = LEGACY_PATH_V8
		elif FileAccess.file_exists(LEGACY_PATH_V7): path = LEGACY_PATH_V7
		elif FileAccess.file_exists(LEGACY_PATH): path = LEGACY_PATH
		elif FileAccess.file_exists(LEGACY_PATH_V5): path = LEGACY_PATH_V5
		elif FileAccess.file_exists(LEGACY_PATH_V4): path = LEGACY_PATH_V4
		elif FileAccess.file_exists(LEGACY_PATH_V3): path = LEGACY_PATH_V3
	if not FileAccess.file_exists(path):
		game.show_notification("No quick save yet. Press F5 to save.")
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		game.show_notification("Cannot read quick save.")
		return false
	var data: Variant = file.get_var(false)
	file.close()
	if not data is Dictionary or not validate(data, game):
		game.show_notification("Incompatible or damaged save; current run kept.")
		return false
	restore(game, data)
	game.show_notification("Loaded. World paused; choose 1x when ready.")
	return true


static func snapshot(game: MVPGameRoot) -> Dictionary:
	var containers: Array = []
	for point in game.interactions.points:
		var entry := {"id": point["id"], "position": point["position"], "floor": point["floor"], "label": point["label"]}
		if point.has("container"):
			var container: ContainerData = point["container"]
			entry.merge({"searched": container.searched, "progress": container.search_progress_seconds,
				"contents": _pack_items(container.contents)})
		if point.has("triggered"):
			entry["triggered"] = point["triggered"]
		containers.append(entry)
	var inventory := {"loose": _pack_items(game.inventory.loose), "equipment": _pack_items(game.inventory.equipment),
		"use_context": game.inventory.use_context.duplicate(true)}
	inventory["strength"] = game.inventory.strength
	for root in InventoryGrid.ROOTS:
		if not inventory.has(root): inventory[root] = _pack_items(game.inventory.contents(root))
	var zombies: Array = []
	for zombie: ZombieActor in game.zombie_spawner.active_zombies:
		if not is_instance_valid(zombie) or zombie.health <= 0 or zombie.is_queued_for_deletion():
			continue
		var entry := _actor_data(zombie)
		entry.merge({"health": zombie.health, "target": zombie.target_position,
			"target_floor": zombie.target_floor, "has_target": zombie.has_target,
			"cooldown": zombie.attack_cooldown, "perception": zombie.perception_save_data()})
		zombies.append(entry)
	var npc_data := _actor_data(game.npc)
	npc_data["facing"] = game.npc.facing_direction
	npc_data["threat_memory_until"] = game.npc.threat_memory_until
	npc_data["threat_memory_position"] = game.npc.threat_memory_position
	npc_data["survival"] = _survival_data(game.npc.survival)
	npc_data["brain"] = game.npc.brain.to_save_data()
	npc_data["known_containers"] = game.npc.known_container_ids.duplicate()
	return {"version": VERSION, "map_identity": map_identity(game.world_map.definition), "clock": GameTime.elapsed_game_seconds,
		"player": _actor_data(game.player), "facing": game.player.facing_direction,
		"health": game.player_state.health, "survival": _survival_data(game.player_state.survival),
		"wounds": game.player_state.wounds.duplicate(true),
		"player_status": game.player_state.to_save_data(),
		"character": game.player_state.character.to_save_data(),
		"pack_action": game.interactions.active_action.duplicate(true) if game.interactions.active_action.get("kind") == "pack" else {},
		"pack_queue": game.interactions.pack_queue.duplicate(true),
		"inventory": inventory, "points": containers, "zombies": zombies, "npc": npc_data,
		"barriers": game.world_map.barrier_save_data(),
		"milestones": game.milestones.duplicate(),
		"rest_origin": game.rest_origin, "rest_floor": game.rest_floor,
		"encountered": game.encountered_zombie, "encounter_origin": game.encounter_origin,
		"population": {"initialized": game.zombie_spawner.population_initialized,
			"preset": game.zombie_spawner.population_preset,
			"initial_count": game.zombie_spawner.initial_population_count,
			"migration_elapsed": game.zombie_spawner.migration_game_seconds}}


static func validate(data: Dictionary, game: MVPGameRoot) -> bool:
	if data.get("version") == 3: data = _migrate_v3(data)
	if data.get("version") == 4: data = _migrate_v4(data)
	if data.get("version") == 5: data = _migrate_v5(data)
	if data.get("version") == 6: data = _migrate_v6(data)
	if data.get("version") == 7: data = _migrate_v7(data)
	if data.get("version") == 8: data = _migrate_v8(data)
	if data.get("version") == 9: data = _migrate_v9(data)
	if not _compatible_map_identity(data.get("map_identity"), map_identity(game.world_map.definition)):
		return false
	# Validate the entire snapshot before replacing live state.
	var required := ["version", "clock", "player", "facing", "health", "survival", "wounds",
		"character", "player_status", "inventory", "points", "zombies", "npc",
		"milestones", "rest_origin", "rest_floor", "encountered", "encounter_origin", "population", "barriers"]
	for key in required:
		if not data.has(key):
			return false
	if data["version"] != VERSION or not _valid_actor(data["player"], game.world_map):
		return false
	if not _valid_barrier_states(data["barriers"], game.world_map): return false
	if not _valid_actor(data["npc"], game.world_map) or not data["npc"].get("brain") is Dictionary or not data["npc"].get("known_containers") is Array:
		return false
	if not _valid_survival(data["survival"]) or not _valid_survival(data["npc"].get("survival")):
		return false
	for key in ["facing", "threat_memory_position"]:
		var value: Variant = data["npc"].get(key, Vector2.ZERO)
		if not value is Vector2 or not value.is_finite(): return false
	var memory_time: Variant = data["npc"].get("threat_memory_until", 0.0)
	if not (memory_time is float or memory_time is int) or not is_finite(float(memory_time)): return false
	if not PlayerState.valid_status_data(data["player_status"]): return false
	if not CharacterProgression.valid_save_data(data["character"], game.character_catalog): return false
	if not data["facing"] is Vector2 or not data["rest_origin"] is Vector2 or not data["encounter_origin"] is Vector2:
		return false
	for key in ["clock", "health"]:
		if not _number(data[key]):
			return false
	if float(data["health"]) < 0.0 or float(data["health"]) > PlayerState.MAX_HEALTH:
		return false
	if not data["wounds"] is Array or not data["inventory"] is Dictionary or not data["points"] is Array or not data["zombies"] is Array:
		return false
	for wound in data["wounds"]:
		if not wound is Dictionary or not wound.has_all(["type", "location", "severity", "wound_infection"]):
			return false
		if not _number(wound["severity"]):
			return false
	if not data["milestones"] is Dictionary: return false
	if not data["encountered"] is bool or not data["rest_floor"] is int:
		return false
	var brain: Dictionary = data["npc"]["brain"]
	for key in ["last_noise_time", "last_noise_strength", "noise_memory_until", "noise_lock_until"]:
		if not _number(brain.get(key, 0.0)): return false
	if float(brain.get("last_noise_strength", 0.0)) < 0.0 or not brain.get("last_noise_danger", false) is bool: return false
	if not brain.has_all(["traits", "relationships", "memories", "last_noise_position"]):
		return false
	if not brain["traits"] is Dictionary or not brain["relationships"] is Dictionary or not brain["memories"] is Array or not brain["last_noise_position"] is Vector2:
		return false
	if not brain["last_noise_position"].is_finite() or not brain.get("last_noise_floor", 0) is int: return false
	for memory in brain["memories"]:
		if not memory is String:
			return false
	for key in game.milestones:
		if not data["milestones"].get(key) is bool:
			return false
	for entry in data["zombies"]:
		if not _valid_actor(entry, game.world_map) or not entry.has_all(["health", "target", "target_floor", "has_target", "cooldown", "perception"]):
			return false
		if not entry["target"] is Vector2 or not _number(entry["cooldown"]) or not entry["health"] is int or not entry["target_floor"] is int or not entry["has_target"] is bool:
			return false
		if entry["health"] <= 0 or entry["health"] > ZombieActor.MAX_HEALTH:
			return false
		if not _valid_zombie_perception(entry["perception"]): return false
		if not entry["target"].is_finite(): return false
		var target_stair: String = entry["perception"].get("target_stair_id", "")
		if not target_stair.is_empty() and not _valid_actor({"position": entry["target"],
			"floor": entry["target_floor"], "stair": target_stair}, game.world_map): return false
	var population: Variant = data["population"]
	if not population is Dictionary or not population.get("initialized") is bool or not population.get("initial_count") is int or not _number(population.get("migration_elapsed")): return false
	var preset: Variant = population.get("preset", "Normal")
	if not preset is String or not preset in ["Very Few", "Few", "Normal", "Many", "Very Many", "Extremely Many"]: return false
	if population["initial_count"] < data["zombies"].size() or population["initial_count"] > game.zombie_spawner.area_catalog.rules.population_range(preset).y: return false
	if float(population["migration_elapsed"]) < 0.0: return false
	var pack := InventoryGrid.new(false)
	pack.penalty_limit = game.inventory.penalty_limit
	pack.absolute_limit = game.inventory.absolute_limit
	if not data["inventory"].get("strength") is int or data["inventory"]["strength"] < 0: return false
	pack.strength = data["inventory"]["strength"]
	for root in InventoryGrid.ROOTS:
		if not data["inventory"].get(root) is Array: return false
		for entry in data["inventory"][root]:
			if not _valid_item(entry): return false
			pack.contents(root).append(_unpack_item(entry))
	if not data["inventory"].get("use_context") is Dictionary: return false
	pack.use_context = data["inventory"]["use_context"].duplicate(true)
	if not _valid_pack_action(data.get("pack_action"), data.get("pack_queue"), data["player"]): return false
	var point_ids: Dictionary = {}
	var known_ids: Array[String] = []
	for point in game.interactions.points: known_ids.append(point["id"])
	for entry in data["points"]:
		if not entry is Dictionary or not entry.get("id") is String or point_ids.has(entry["id"]):
			return false
		point_ids[entry["id"]] = true
		if not entry["id"] in known_ids and not entry["id"].begins_with("dropped_"): return false
		if entry["id"].begins_with("dropped_") and not entry.has("contents"): return false
		if entry.has("contents"):
			if not entry["contents"] is Array or not _number(entry.get("progress")) or not entry.get("searched") is bool:
				return false
			var container := ContainerData.new(entry["id"], entry.get("label", "Container"))
			if game.inventory.world.has(entry["id"]): container.capacity = game.inventory.world[entry["id"]].capacity
			for item in entry["contents"]:
				if not _valid_item(item):
					return false
				container.contents.append(_unpack_item(item))
			pack.world[entry["id"]] = container
			if entry["id"].begins_with("dropped_"):
				if not entry.get("position") is Vector2 or not entry.get("floor") is int or not entry.get("label") is String: return false
				if not game.world_map.can_stand(entry["position"], entry["floor"]): return false
	for point in game.interactions.points:
		if String(point["id"]).begins_with("dropped_"): continue
		if not point_ids.has(point["id"]):
			return false
		for entry in data["points"]:
			if entry["id"] == point["id"]:
				if point.has("container") and not entry.has("contents"):
					return false
				if point.has("triggered") and not entry.get("triggered") is bool:
					return false
	if not pack.all_valid(): return false
	var steps: Array = data["pack_queue"].duplicate()
	if not data["pack_action"].is_empty(): steps.append(data["pack_action"]["payload"])
	for step in steps:
		if pack.find_unit(step["uid"]).is_empty() and not (step["step"] == "return" and pack.use_context.is_empty()): return false
		if step["step"] in ["move", "take"] and step["destination"] != "ground" and not pack.has_container(step["destination"]): return false
	return true


static func restore(game: MVPGameRoot, data: Dictionary) -> void:
	if data.get("version") == 3: data = _migrate_v3(data)
	if data.get("version") == 4: data = _migrate_v4(data)
	if data.get("version") == 5: data = _migrate_v5(data)
	if data.get("version") == 6: data = _migrate_v6(data)
	if data.get("version") == 7: data = _migrate_v7(data)
	if data.get("version") == 8: data = _migrate_v8(data)
	if data.get("version") == 9: data = _migrate_v9(data)
	if not validate(data, game): return
	game.interactions.interrupt_action("Loading")
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	game.world_map.restore_barrier_states(data["barriers"])
	GameTime.elapsed_game_seconds = data["clock"]
	GameTime.last_advanced_game_seconds = 0.0
	_restore_actor(game.player, data["player"])
	game.player.facing_direction = data["facing"]
	game.world_3d_view.sync_view_to_player()
	game.player._attack_cooldown_left = PlayerController.ATTACK_COOLDOWN
	game.player._attack_flash_left = 0.0
	game.player_state.health = data["health"]
	game.player_state.load_save_data(data["player_status"])
	game.player_state.character.load_save_data(data["character"])
	_restore_survival(game.player_state.survival, data["survival"])
	game.inventory.strength = data["inventory"]["strength"]
	for root in InventoryGrid.ROOTS:
		game.inventory.contents(root).clear()
		for entry in data["inventory"][root]:
			game.inventory.contents(root).append(_unpack_item(entry))
	game.inventory.use_context = data["inventory"]["use_context"].duplicate(true)
	game.inventory.revision += 1
	game.interactions.points = game.interactions.points.filter(func(point: Dictionary) -> bool: return not String(point["id"]).begins_with("dropped_"))
	for saved in data["points"]:
		if String(saved["id"]).begins_with("dropped_"):
			game.interactions.points.append({"id": saved["id"], "kind": "container", "position": saved["position"],
				"floor": saved["floor"], "radius": 0.9, "label": saved["label"],
				"container": ContainerData.new(saved["id"], saved["label"])})
	game.inventory.world.clear()
	for point in game.interactions.points:
		for saved in data["points"]:
			if saved["id"] != point["id"]:
				continue
			if point.has("container"):
				var container: ContainerData = point["container"]
				container.contents.clear()
				for item in saved["contents"]:
					container.contents.append(_unpack_item(item))
				container.searched = saved["searched"]
				container.search_progress_seconds = saved["progress"]
				game.inventory.world[point["id"]] = container
			if point.has("triggered"):
				point["triggered"] = saved.get("triggered", false)
	game.zombie_spawner.clear_population()
	for entry in data["zombies"]:
		var spawn_pos: Vector2 = entry["position"]
		if not String(entry["stair"]).is_empty():
			var link: StairLink = game.world_map.stairs[entry["stair"]]
			spawn_pos = link.start if int(entry["floor"]) == link.from_floor else link.end
		var zombie := game.zombie_spawner._spawn(spawn_pos, entry["floor"])
		if zombie == null:
			continue
		_restore_actor(zombie, entry)
		zombie.health = entry["health"]
		zombie.target_position = entry["target"]
		zombie.target_floor = entry["target_floor"]
		zombie.has_target = entry["has_target"]
		zombie.attack_cooldown = entry["cooldown"]
		zombie.load_perception_save_data(entry["perception"])
	game.zombie_spawner.population_initialized = data["population"]["initialized"]
	game.zombie_spawner.initial_population_count = data["population"]["initial_count"]
	game.zombie_spawner.population_preset = data["population"].get("preset", "Normal")
	game.zombie_spawner.migration_game_seconds = data["population"]["migration_elapsed"]
	_restore_actor(game.npc, data["npc"])
	game.npc.facing_direction = data["npc"].get("facing", Vector2.DOWN)
	game.npc.threat_memory_until = data["npc"].get("threat_memory_until", 0.0)
	game.npc.threat_memory_position = data["npc"].get("threat_memory_position", Vector2.ZERO)
	_restore_survival(game.npc.survival, data["npc"]["survival"])
	game.npc.brain.load_save_data(data["npc"]["brain"])
	game.npc.known_container_ids.assign(data["npc"]["known_containers"])
	game.npc.cancel_current_task()
	game.milestones = data["milestones"].duplicate()
	game.rest_origin = data["rest_origin"]
	game.rest_floor = data["rest_floor"]
	game.encountered_zombie = data["encountered"]
	game.encounter_origin = data["encounter_origin"]
	game.interactions.active_action = data["pack_action"].duplicate(true)
	game.interactions.pack_queue.assign(data["pack_queue"].duplicate(true))
	game.player.interaction_locked = not game.interactions.active_action.is_empty()
	game.interactions.points_changed.emit()
	game.world_3d_view.refresh_after_load()


static func _actor_data(actor: Node) -> Dictionary:
	return {"position": actor.get("logical_position"), "floor": actor.get("floor_level"), "stair": actor.get("stair_id")}


static func _restore_actor(actor: Node, data: Dictionary) -> void:
	actor.set("logical_position", data["position"])
	actor.set("floor_level", data["floor"])
	actor.set("stair_id", data["stair"])


static func _valid_actor(data: Variant, map: WorldMap) -> bool:
	if not data is Dictionary or not data.get("position") is Vector2 or not data.get("floor") is int or not data.get("stair") is String:
		return false
	var pos: Vector2 = data["position"]
	if not pos.is_finite():
		return false
	if data["stair"] == "":
		return map.can_stand(pos, data["floor"])
	if not map.stairs.has(data["stair"]):
		return false
	var link = map.stairs[data["stair"]]
	var closest := Geometry2D.get_closest_point_to_segment(pos, link.start, link.end)
	return data["floor"] in [link.from_floor, link.to_floor] and pos.distance_to(closest) <= link.width * 0.5


static func _survival_data(survival: SurvivalSystem) -> Dictionary:
	return {"hunger": survival.hunger, "thirst": survival.thirst, "fatigue": survival.fatigue, "stamina": survival.stamina}


static func _restore_survival(survival: SurvivalSystem, data: Dictionary) -> void:
	for key in ["hunger", "thirst", "fatigue", "stamina"]:
		survival.set(key, data[key])


static func _valid_survival(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for key in ["hunger", "thirst", "fatigue", "stamina"]:
		if not _number(data.get(key)) or float(data[key]) < 0.0 or float(data[key]) > 100.0:
			return false
	return true


static func _pack_items(items: Array) -> Array:
	var result: Array = []
	for item in items:
		result.append(_pack_item(item))
	return result


static func _pack_item(stack: ItemStack) -> Dictionary:
	return InventoryCodec.pack(stack)


static func _valid_item(data: Variant) -> bool:
	return InventoryCodec.valid(data)


static func _unpack_item(data: Dictionary) -> ItemStack:
	return InventoryCodec.unpack(data)


static func _valid_pack_action(action: Variant, queue: Variant, player_data: Dictionary) -> bool:
	if not action is Dictionary or not queue is Array or queue.size() > 4096: return false
	if action.is_empty(): return queue.is_empty()
	if action.get("kind") != "pack" or not action.get("label") is String: return false
	if not _number(action.get("duration")) or not _number(action.get("remaining")): return false
	if action["duration"] <= 0 or action["remaining"] < 0 or action["remaining"] > action["duration"]: return false
	if action.get("position") != player_data["position"] or action.get("floor") != player_data["floor"]: return false
	var steps: Array = queue.duplicate()
	steps.append(action.get("payload"))
	for step in steps:
		if not step is Dictionary or not step.get("step") in ["move", "take", "use", "return", "wear", "unwear", "repair", "treat"]: return false
		if not step.get("uid") is String or not step.get("destination") is String: return false
		if step.get("step") == "repair" and (not step.get("region") is String or not step.get("rag_uid") is String): return false
		if step.get("step") == "treat" and (not step.get("wound_id") is String or not step.get("treatment") is String): return false
		if not step.get("index", 1) is int or not step.get("total", 1) is int or step.get("index", 1) < 1 or step.get("total", 1) < step.get("index", 1): return false
		if step["step"] == "take" and (not step.get("origin") is String or not step.get("return_after") is bool): return false
		for flag in ["free_hand", "pickup", "displace"]:
			if not step.get(flag, false) is bool: return false
	return true


static func _migrate_v3(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	data["version"] = 4
	if data.get("inventory") is Dictionary:
		for slot in InventoryGrid.CLOTHING_SLOTS:
			if not data["inventory"].has(slot): data["inventory"][slot] = []
	return _migrate_v4(data)

static func _migrate_v4(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	data["version"] = 5
	# v4 stored fatigue as accumulated tiredness; v5 stores a rested reserve.
	if data.get("survival") is Dictionary:
		data["survival"]["fatigue"] = 100.0 - float(data["survival"].get("fatigue", 0.0))
	if data.get("npc") is Dictionary and data["npc"].get("survival") is Dictionary:
		data["npc"]["survival"]["fatigue"] = 100.0 - float(data["npc"]["survival"].get("fatigue", 0.0))
	var state := PlayerState.new()
	state.wounds.assign(data.get("wounds", []))
	for wound in state.wounds:
		# Only the old schema stores fractional wound severity.
		var severity := float(wound.get("severity", 0.0))
		if severity <= 1.0: wound["severity"] = severity * 100.0
		state._normalize_wound(wound)
	state.zombie_virus_exposure = data.get("virus_exposure", false)
	if state.zombie_virus_exposure:
		var old_progress := clampf(float(data.get("virus_progress", 0.0)), 0.0, 1.0)
		state.zombie_virus_deadline = float(data.get("clock", 0.0)) + StatusConfig.VIRUS_LATENT_MIN_SECONDS * (1.0 - old_progress)
	data["wounds"] = state.wounds.duplicate(true)
	data["player_status"] = state.to_save_data()
	return _migrate_v5(data)

static func _migrate_v5(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	data["version"] = 6
	var catalog := CharacterCatalog.new()
	var character := CharacterProgression.new()
	character.setup(catalog)
	character.creation_complete = true
	data["character"] = character.to_save_data()
	data.erase("traits")
	return _migrate_v6(data)


static func _migrate_v6(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	data["version"] = 7
	var now := float(data.get("clock", 0.0))
	for zombie in data.get("zombies", []):
		if not zombie is Dictionary: continue
		zombie["perception"] = {"awareness": ZombieActor.Awareness.VISUAL_MEMORY if zombie.get("has_target", false) else ZombieActor.Awareness.IDLE,
			"target_actor_id": "", "visual_memory_expires_at": now + 90.0,
			"sound_memory_expires_at": now, "search_expires_at": now,
			"stimulus_lock_until": now, "last_stimulus_time": -1.0,
			"last_stimulus_loudness": 0.0, "migration_area_id": "", "facing": Vector2.DOWN}
	data["population"] = {"initialized": true, "initial_count": data.get("zombies", []).size(),
		"migration_elapsed": maxf(0.0, float(data.get("respawn", 0.0)))}
	data.erase("respawn")
	return data


static func map_identity(definition: Resource) -> Dictionary:
	return {"id": definition.get("id"), "format_version": definition.get("format_version"),
		"content_hash": var_to_bytes(_static_content(definition)).hex_encode().sha256_text()}


static func _compatible_map_identity(saved: Variant, current: Dictionary) -> bool:
	if saved == current: return true
	# Exact, audited migration pair: c8bcc79 bundled map -> heatmap format 2.
	# Geometry is unchanged; existing zombies keep their saved state. Never
	# accept arbitrary maps/edited geometry merely because their IDs match.
	return saved == {"id": "orangeville_prototype", "format_version": 1,
		"content_hash": "64917b6b843659b75e7621d51cfe79bd92df821324e02daf3ce3df03d71eca4f"} and current == {
		"id": "orangeville_prototype", "format_version": 2,
		"content_hash": "4e1f18a10eb7f476de9df5442477a9a9efb71db3402970884bf9a5b642d15b2d"}


static func _static_content(value: Variant) -> Variant:
	# Hash exported values recursively, including external template/terrain
	# resources. Paths alone miss edited dependencies; instance IDs are unstable.
	if value is Resource:
		var properties: Dictionary = {}
		for property in value.get_property_list():
			if int(property["usage"]) & PROPERTY_USAGE_STORAGE and int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				properties[String(property["name"])] = _static_content(value.get(property["name"]))
		return [value.get_script().resource_path, _static_content(properties)]
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var pairs: Array = []
		for key in keys: pairs.append([key, _static_content(value[key])])
		return pairs
	if value is Array:
		var items: Array = []
		for item in value: items.append(_static_content(item))
		return items
	return value


static func _migrate_v7(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	data["version"] = 8
	# Historical saves have no map identity. They belonged to the bundled map;
	# never assign them the identity of an arbitrary currently selected map.
	if not data.has("map_identity"):
		data["map_identity"] = map_identity(WorldMap.DEFAULT_MAP)
	return _migrate_v8(data)


static func _migrate_v8(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	data["version"] = 9
	# Preserve the historical static openings of pre-barrier saves.
	data["barriers"] = {}
	return _migrate_v9(data)


static func _migrate_v9(source: Dictionary) -> Dictionary:
	# Migration only changes a copy in memory. Legacy slot files remain intact;
	# subsequent default saves use the separate v10 path.
	var data := source.duplicate(true)
	data["version"] = VERSION
	data.erase("seen")
	return data

static func _valid_zombie_perception(data: Variant) -> bool:
	if not data is Dictionary or not _number(data.get("last_heard_strength", 0.0)): return false
	if float(data.get("last_heard_strength", 0.0)) < 0.0: return false
	if not data is Dictionary or not data.has_all(["awareness", "target_actor_id", "visual_memory_expires_at",
		"sound_memory_expires_at", "search_expires_at", "stimulus_lock_until", "last_stimulus_time",
		"last_stimulus_loudness", "migration_area_id", "facing"]): return false
	if not data["awareness"] is int or data["awareness"] < ZombieActor.Awareness.IDLE or data["awareness"] > ZombieActor.Awareness.MIGRATION: return false
	if not data["target_actor_id"] is String or not data["migration_area_id"] is String or not data["facing"] is Vector2: return false
	if not data["facing"].is_finite(): return false
	if not data.get("target_stair_id", "") is String: return false
	for key in ["visual_memory_expires_at", "sound_memory_expires_at", "search_expires_at", "stimulus_lock_until", "last_stimulus_time", "last_stimulus_loudness"]:
		if not _number(data[key]): return false
	return true


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _valid_barrier_states(states: Variant, world_map: WorldMap) -> bool:
	if not states is Dictionary: return false
	if states.is_empty(): return true
	for id: String in states:
		if not world_map.barriers.has(id) or not states[id] is bool:
			return false
	return states.size() == world_map.barriers.size()
