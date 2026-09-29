class_name InteractionSystem
extends Node2D

signal notification_requested(message: String)
signal food_found()
signal rest_completed()
signal light_injury_received()

const SEARCH_DURATION_GAME_SECONDS := 360.0

var world_map: WorldMap
var player: PlayerController
var player_state: PlayerState
var inventory: InventoryGrid
var visibility_system: VisibilitySystem
var points: Array[Dictionary] = []
var active_action: Dictionary = {}


func setup(p_world_map: WorldMap, p_player: PlayerController, p_state: PlayerState,
		p_inventory: InventoryGrid, p_visibility: VisibilitySystem) -> void:
	world_map = p_world_map
	player = p_player
	player_state = p_state
	inventory = p_inventory
	visibility_system = p_visibility
	_build_demo_interactions()


func _build_demo_interactions() -> void:
	var beans := ItemDefinition.new("canned_beans", "Canned beans", Vector2i(1, 1), 0.45, ["food"])
	var water := ItemDefinition.new("bottled_water", "Bottled water", Vector2i(1, 2), 0.75, ["water"])
	points = [
		{"id": "bed", "kind": "bed", "label": "Safehouse bed", "position": Vector2(5.5, 3.5), "floor": 0, "radius": 0.8},
		_container_point("grocery_shelf", "Grocery shelf", Vector2(12.7, 6.5), 0, beans, water),
		{"id": "glass", "kind": "hazard", "label": "Broken glass", "position": Vector2(8.5, 7.5), "floor": 0, "radius": 0.42, "triggered": false},
		{"id": "upstairs_bed", "kind": "bed", "label": "Upstairs safehouse bed", "position": Vector2(5.5, 3.5), "floor": 1, "radius": 0.8},
		_container_point("grocery_upstairs", "First-floor stockroom", Vector2(14.5, 6.5), 1, beans, water),
		_container_point("grocery_top", "Top-floor emergency kit", Vector2(14.5, 6.5), 2, beans, water),
		_container_point("neighbour_pantry", "Neighbour's pantry", Vector2(3.5, 10.5), 0, beans, water),
	]
	(points.back()["container"] as ContainerData).claimed_by = "neighbour"
	var bandage := ItemDefinition.new("test_bandage", "Test bandage", Vector2i(1, 1), 0.1, ["medical"])
	var tool_case := ItemDefinition.new("test_tool_case", "Test tool case", Vector2i(2, 2), 2.0, ["tool"])
	var ration := ItemDefinition.new("test_ration", "Test ration", Vector2i(2, 1), 0.5, ["food"])
	points.insert(points.size() - 1, {"id": "test_supply_cache", "kind": "container", "label": "Test supply cache",
		"position": Vector2(4.5, 7.0), "floor": 0, "radius": 0.9,
		"container": ContainerData.new("test_supply_cache", "Test supply cache", [
			ItemStack.new(bandage, 3), ItemStack.new(tool_case), ItemStack.new(ration, 2)])})


func _container_point(id: String, label: String, pos: Vector2, floor: int,
		food: ItemDefinition, water: ItemDefinition) -> Dictionary:
	return {"id": id, "kind": "container", "label": label, "position": pos,
		"floor": floor, "radius": 0.9,
		"container": ContainerData.new(id, label, [ItemStack.new(food, 2), ItemStack.new(water, 2)])}


func _process(delta: float) -> void:
	if world_map == null or player_state.is_dead() or GameTime.simulation_scale() <= 0.0:
		return
	_check_hazards()
	_update_active_action(delta)


func request_interaction() -> void:
	if not active_action.is_empty() or player_state.is_dead() or GameTime.simulation_scale() <= 0.0:
		return
	var point := nearest_point()
	if point.is_empty():
		notification_requested.emit("No reachable interaction on this floor.")
		return
	match String(point["kind"]):
		"container":
			_start_container_search(point)
		"bed":
			_start_action("rest", "Resting", 900.0, point)


func request_sorting() -> void:
	if not active_action.is_empty() or player_state.is_dead() or GameTime.simulation_scale() <= 0.0:
		return
	if not inventory.placements.is_empty():
		_start_action("sort", "Sorting inventory", 45.0, {})


func _reachable(point: Dictionary) -> bool:
	var target_tile := world_map.get_tile(point["position"], int(point["floor"]))
	var player_tile := world_map.get_tile(player.logical_position, player.floor_level)
	if target_tile != null and not target_tile.room_id.is_empty():
		if player_tile == null or player_tile.room_id != target_tile.room_id:
			return false
	return (player.stair_id.is_empty()
		and int(point["floor"]) == player.floor_level
		and player.logical_position.distance_to(point["position"]) <= float(point["radius"])
		and world_map.has_line_of_sight(player.logical_position, point["position"], player.floor_level))


func nearest_point() -> Dictionary:
	var closest: Dictionary = {}
	var shortest := INF
	for point in points:
		if point["kind"] == "hazard" or not _reachable(point):
			continue
		var distance := player.logical_position.distance_to(point["position"])
		if distance < shortest:
			closest = point
			shortest = distance
	return closest


func prompt() -> String:
	if not active_action.is_empty():
		return "%s  %d%% · move / aim / Esc to cancel" % [active_action["label"], int(action_progress() * 100.0)]
	var point := nearest_point()
	if point.is_empty():
		return ""
	if point["kind"] == "container":
		var container: ContainerData = point["container"]
		if container.searched:
			return "[E] %s: %s" % [point["label"], _container_contents_label(container)]
		return "[E] Search %s (%d%%)" % [point["label"], int(action_progress_for(container) * 100.0)]
	return "[E] Rest · %s" % point["label"]


func action_progress() -> float:
	if active_action.is_empty():
		return 0.0
	return clampf(1.0 - float(active_action["remaining"]) / float(active_action["duration"]), 0.0, 1.0)


func is_resting() -> bool:
	return active_action.get("kind", "") == "rest"


func is_searching() -> bool:
	return active_action.get("kind", "") == "search"


func interrupt_action(reason: String = "Action interrupted") -> bool:
	if active_action.is_empty():
		return false
	var message := reason
	if is_searching():
		var container: ContainerData = active_action["payload"]["container"]
		_store_search_progress()
		message += ". Search saved: %d%%" % int(action_progress_for(container) * 100.0)
	active_action = {}
	player.interaction_locked = false
	notification_requested.emit(message)
	return true


func _store_search_progress() -> void:
	if is_searching():
		var container: ContainerData = active_action["payload"]["container"]
		container.search_progress_seconds = action_progress() * float(active_action["duration"])


func _start_container_search(point: Dictionary) -> void:
	var container: ContainerData = point["container"]
	if container.searched:
		_collect_contents(container)
		return
	_start_action("search", "Searching %s" % container.display_name, SEARCH_DURATION_GAME_SECONDS,
		point, maxf(0.0, SEARCH_DURATION_GAME_SECONDS - container.search_progress_seconds))
	NoiseBus.emit_noise(player.logical_position, 2.5, "searching", player.floor_level)


func _start_action(kind: String, label: String, duration: float, payload: Dictionary,
		remaining: float = -1.0) -> void:
	active_action = {"kind": kind, "label": label, "duration": duration,
		"remaining": duration if remaining < 0.0 else remaining, "payload": payload,
		"position": player.logical_position, "floor": player.floor_level}
	player.interaction_locked = true


func _update_active_action(delta: float) -> void:
	if active_action.is_empty() or GameTime.simulation_scale() <= 0.0:
		return
	var point: Dictionary = active_action["payload"]
	if (player_state.is_dead() or player.floor_level != int(active_action["floor"])
		or player.logical_position.distance_to(active_action["position"]) > 0.05
		or (not point.is_empty() and not _reachable(point))):
		interrupt_action("You moved away")
		return
	active_action["remaining"] = maxf(0.0, float(active_action["remaining"])
		- delta * GameTime.GAME_SECONDS_PER_REAL_SECOND * GameTime.simulation_scale())
	_store_search_progress()
	if float(active_action["remaining"]) > 0.0:
		return
	var completed := active_action
	active_action = {}
	player.interaction_locked = false
	_complete_action(completed)


func _complete_action(action: Dictionary) -> void:
	match String(action["kind"]):
		"search":
			var container: ContainerData = action["payload"]["container"]
			container.searched = true
			container.search_progress_seconds = SEARCH_DURATION_GAME_SECONDS
			_collect_contents(container)
		"rest":
			# Recovery is applied continuously by SurvivalSystem, once only.
			rest_completed.emit()
			notification_requested.emit("Rest complete. You can rest again or explore.")
		"sort":
			inventory.sort_items()
			notification_requested.emit("Inventory sorted.")


func _collect_contents(container: ContainerData) -> void:
	var collected := false
	for stack: ItemStack in container.contents.duplicate():
		if inventory.add_item(stack):
			container.contents.erase(stack)
			collected = true
			if "food" in stack.definition.tags:
				food_found.emit()
	var suffix := "Packed supplies. " if collected else ""
	notification_requested.emit(suffix + "Remaining: " + _container_contents_label(container))


func _check_hazards() -> void:
	if player_state.is_dead() or GameTime.simulation_scale() <= 0.0 or not player.stair_id.is_empty():
		return
	for point in points:
		if point["kind"] != "hazard" or bool(point["triggered"]) or not _reachable(point):
			continue
		point["triggered"] = true
		interrupt_action("Injured")
		player_state.add_wound("Glass cut", "left calf", 0.08, false)
		light_injury_received.emit()
		notification_requested.emit("Broken glass: a light wound. Watch your footing.")


func _container_contents_label(container: ContainerData) -> String:
	var labels: Array[String] = []
	for stack in container.contents:
		labels.append(stack.label())
	return ", ".join(labels) if not labels.is_empty() else "empty"


func action_progress_for(container: ContainerData) -> float:
	return clampf(container.search_progress_seconds / SEARCH_DURATION_GAME_SECONDS, 0.0, 1.0)
