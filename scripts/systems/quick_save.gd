class_name QuickSave
extends RefCounted

## A single versioned local slot. Only primitive Variant data is decoded.
## In-flight player actions are cancelled; per-container search progress survives.
const VERSION := 1
const PATH := "user://afterlight_mvp_v1.save"


static func save_game(game: MVPGameRoot, path: String = PATH) -> bool:
	game.interactions.interrupt_action("Saved")
	var data := snapshot(game)
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
		var entry := {"id": point["id"]}
		if point.has("container"):
			var container: ContainerData = point["container"]
			entry.merge({"searched": container.searched, "progress": container.search_progress_seconds,
				"contents": _pack_items(container.contents)})
		if point.has("triggered"):
			entry["triggered"] = point["triggered"]
		containers.append(entry)
	var inventory: Array = []
	for placement in game.inventory.placements:
		inventory.append({"stack": _pack_item(placement["stack"]), "slot": placement["slot"]})
	var zombies: Array = []
	for zombie: ZombieActor in game.zombie_spawner.active_zombies:
		if not is_instance_valid(zombie) or zombie.health <= 0 or zombie.is_queued_for_deletion():
			continue
		var entry := _actor_data(zombie)
		entry.merge({"health": zombie.health, "target": zombie.target_position,
			"target_floor": zombie.target_floor, "has_target": zombie.has_target,
			"cooldown": zombie.attack_cooldown})
		zombies.append(entry)
	var npc_data := _actor_data(game.npc)
	npc_data["survival"] = _survival_data(game.npc.survival)
	npc_data["brain"] = game.npc.brain.to_save_data()
	npc_data["known_containers"] = game.npc.known_container_ids.duplicate()
	return {"version": VERSION, "clock": GameTime.elapsed_game_seconds,
		"player": _actor_data(game.player), "facing": game.player.facing_direction,
		"health": game.player_state.health, "survival": _survival_data(game.player_state.survival),
		"wounds": game.player_state.wounds.duplicate(true),
		"traits": game.player_state.traits.to_save_data(),
		"virus_exposure": game.player_state.zombie_virus_exposure,
		"virus_progress": game.player_state.zombie_virus_infection_progress,
		"inventory": inventory, "points": containers, "zombies": zombies, "npc": npc_data,
		"seen": game.visibility.seen_tiles.duplicate(), "milestones": game.milestones.duplicate(),
		"rest_origin": game.rest_origin, "rest_floor": game.rest_floor,
		"encountered": game.encountered_zombie, "encounter_origin": game.encounter_origin,
		"respawn": game.zombie_spawner.respawn_game_seconds}


static func validate(data: Dictionary, game: MVPGameRoot) -> bool:
	# Validate the entire snapshot before replacing live state.
	var required := ["version", "clock", "player", "facing", "health", "survival", "wounds",
		"traits", "virus_exposure", "virus_progress", "inventory", "points", "zombies", "npc",
		"seen", "milestones", "rest_origin", "rest_floor", "encountered", "encounter_origin", "respawn"]
	for key in required:
		if not data.has(key):
			return false
	if data["version"] != VERSION or not _valid_actor(data["player"], game.world_map):
		return false
	if not _valid_actor(data["npc"], game.world_map) or not data["npc"].get("brain") is Dictionary or not data["npc"].get("known_containers") is Array:
		return false
	if not _valid_survival(data["survival"]) or not _valid_survival(data["npc"].get("survival")):
		return false
	if not data["facing"] is Vector2 or not data["rest_origin"] is Vector2 or not data["encounter_origin"] is Vector2:
		return false
	for key in ["clock", "health", "virus_progress", "respawn"]:
		if not _number(data[key]):
			return false
	if float(data["health"]) < 0.0 or float(data["health"]) > PlayerState.MAX_HEALTH:
		return false
	if not data["wounds"] is Array or not data["inventory"] is Array or not data["points"] is Array or not data["zombies"] is Array:
		return false
	for wound in data["wounds"]:
		if not wound is Dictionary or not wound.has_all(["type", "location", "severity", "wound_infection"]):
			return false
		if not _number(wound["severity"]):
			return false
	for key in ["traits", "seen", "milestones"]:
		if not data[key] is Dictionary:
			return false
	for key in data["seen"]:
		if not key is Vector3i or not data["seen"][key] is bool:
			return false
	if not data["virus_exposure"] is bool or not data["encountered"] is bool or not data["rest_floor"] is int:
		return false
	var brain: Dictionary = data["npc"]["brain"]
	if not brain.has_all(["traits", "relationships", "memories", "last_noise_position"]):
		return false
	if not brain["traits"] is Dictionary or not brain["relationships"] is Dictionary or not brain["memories"] is Array or not brain["last_noise_position"] is Vector2:
		return false
	for memory in brain["memories"]:
		if not memory is String:
			return false
	for key in game.milestones:
		if not data["milestones"].get(key) is bool:
			return false
	for entry in data["zombies"]:
		if not _valid_actor(entry, game.world_map) or not entry.has_all(["health", "target", "target_floor", "has_target", "cooldown"]):
			return false
		if not entry["target"] is Vector2 or not _number(entry["cooldown"]) or not entry["health"] is int or not entry["target_floor"] is int or not entry["has_target"] is bool:
			return false
		if entry["health"] <= 0 or entry["health"] > ZombieActor.MAX_HEALTH:
			return false
	var pack := InventoryGrid.new(game.inventory.grid_size, game.inventory.max_weight)
	for entry in data["inventory"]:
		if not entry is Dictionary or not _valid_item(entry.get("stack")) or not entry.get("slot") is Vector2i:
			return false
		var stack := _unpack_item(entry["stack"])
		if not pack._fits(entry["slot"], stack.definition.grid_size):
			return false
		pack.placements.append({"stack": stack, "slot": entry["slot"]})
	if pack.current_weight() > pack.max_weight:
		return false
	var point_ids: Dictionary = {}
	for entry in data["points"]:
		if not entry is Dictionary or not entry.get("id") is String or point_ids.has(entry["id"]):
			return false
		point_ids[entry["id"]] = true
		if entry.has("contents"):
			if not entry["contents"] is Array or not _number(entry.get("progress")) or not entry.get("searched") is bool:
				return false
			for item in entry["contents"]:
				if not _valid_item(item):
					return false
	for point in game.interactions.points:
		if not point_ids.has(point["id"]):
			return false
		for entry in data["points"]:
			if entry["id"] == point["id"]:
				if point.has("container") and not entry.has("contents"):
					return false
				if point.has("triggered") and not entry.get("triggered") is bool:
					return false
	return true


static func restore(game: MVPGameRoot, data: Dictionary) -> void:
	game.interactions.interrupt_action("Loading")
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	GameTime.elapsed_game_seconds = data["clock"]
	GameTime.last_advanced_game_seconds = 0.0
	_restore_actor(game.player, data["player"])
	game.player.facing_direction = data["facing"]
	game.player._attack_cooldown_left = PlayerController.ATTACK_COOLDOWN
	game.player._attack_flash_left = 0.0
	game.player_state.health = data["health"]
	game.player_state.wounds.assign(data["wounds"])
	game.player_state.traits.load_save_data(data["traits"])
	game.player_state.zombie_virus_exposure = data["virus_exposure"]
	game.player_state.zombie_virus_infection_progress = data["virus_progress"]
	_restore_survival(game.player_state.survival, data["survival"])
	game.inventory.placements.clear()
	for entry in data["inventory"]:
		game.inventory.placements.append({"stack": _unpack_item(entry["stack"]), "slot": entry["slot"]})
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
	game.zombie_spawner.respawn_game_seconds = data["respawn"]
	_restore_actor(game.npc, data["npc"])
	_restore_survival(game.npc.survival, data["npc"]["survival"])
	game.npc.brain.load_save_data(data["npc"]["brain"])
	game.npc.known_container_ids.assign(data["npc"]["known_containers"])
	game.npc.cancel_current_task()
	game.visibility.seen_tiles = data["seen"].duplicate()
	game.visibility.invalidate()
	game.visibility.refresh(game.player.logical_position, game.player.facing_direction, false, game.player.floor_level)
	game.milestones = data["milestones"].duplicate()
	game.rest_origin = data["rest_origin"]
	game.rest_floor = data["rest_floor"]
	game.encountered_zombie = data["encountered"]
	game.encounter_origin = data["encounter_origin"]


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


static func _pack_items(items: Array[ItemStack]) -> Array:
	var result: Array = []
	for item in items:
		result.append(_pack_item(item))
	return result


static func _pack_item(stack: ItemStack) -> Dictionary:
	var item := stack.definition
	return {"id": item.id, "name": item.display_name, "size": item.grid_size,
		"weight": item.unit_weight, "tags": item.tags.duplicate(), "quantity": stack.quantity}


static func _valid_item(data: Variant) -> bool:
	if not data is Dictionary or not data.has_all(["id", "name", "size", "weight", "tags", "quantity"]):
		return false
	if not data["tags"] is Array:
		return false
	for tag in data["tags"]:
		if not tag is String:
			return false
	return (data["id"] is String and data["name"] is String and data["size"] is Vector2i
		and data["size"].x > 0 and data["size"].y > 0 and _number(data["weight"])
		and data["weight"] >= 0 and data["tags"] is Array
		and data["quantity"] is int and data["quantity"] > 0)


static func _unpack_item(data: Dictionary) -> ItemStack:
	var tags: Array[String] = []
	tags.assign(data["tags"])
	return ItemStack.new(ItemDefinition.new(data["id"], data["name"], data["size"], data["weight"], tags), data["quantity"])


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
