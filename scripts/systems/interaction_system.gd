class_name InteractionSystem
extends Node2D

signal notification_requested(message: String)
signal food_found()
signal rest_completed()
signal light_injury_received()
signal points_changed()
signal container_view_requested(id: String)

## Baseline real seconds at normal speed, authored independently for each container.
const CONTAINER_SEARCH_SECONDS := {
	"test_cabinet_0": 2.0, "test_cabinet_1": 3.0, "test_cabinet_2": 4.0,
	"test_cabinet_3": 3.0, "wardrobe": 5.0, "backpack_crate": 4.0,
	"test_supply_cache": 6.0, "grocery_shelf": 3.0,
	"grocery_upstairs": 5.0, "grocery_top": 6.0, "neighbour_pantry": 3.0,
}
const CLOTHING_CHANGE_GAME_SECONDS := 30.0
const CLOTHING_REPAIR_GAME_SECONDS := 60.0
const MEDICAL_ACTION_GAME_SECONDS := 60.0
const MAX_SLEEP_GAME_SECONDS := 12.0 * 3600.0

var world_map: WorldMap
var player: PlayerController
var player_state: PlayerState
var inventory: InventoryGrid
const CONTAINER_REACH := 1.2
var points: Array[Dictionary] = []
var active_action: Dictionary = {}
var pack_queue: Array[Dictionary] = []
var pre_sleep_speed := GameTime.SpeedMode.NORMAL
var _last_hazard_check_position := Vector2(INF, INF)
var _last_hazard_check_floor := -999


func setup(p_world_map: WorldMap, p_player: PlayerController, p_state: PlayerState,
		p_inventory: InventoryGrid) -> void:
	world_map = p_world_map
	player = p_player
	player_state = p_state
	inventory = p_inventory
	if world_map.definition.id == "orangeville_prototype":
		_build_demo_interactions()
	for point in points:
		if point.has("container"):
			(point["container"] as ContainerData).search_duration_game_seconds = float(CONTAINER_SEARCH_SECONDS.get(point["id"], 3.0)) * GameTime.GAME_SECONDS_PER_REAL_SECOND
			inventory.world[point["id"]] = point["container"]
	world_map.install_furniture(points)


func _build_demo_interactions() -> void:
	var foods := ItemCatalog.food_definitions()
	var liquids := ItemCatalog.liquid_definitions()
	var medical := ItemCatalog.medical_definitions()
	var packs := ItemCatalog.backpack_definitions()
	var tools := ItemCatalog.tool_definitions()
	var beans: ItemDefinition = foods["canned_beans"]
	var water: ItemDefinition = liquids["bottled_water"]
	points = [
		{"id": "bed", "kind": "bed", "label": "Safehouse bed", "position": Vector2(5.5, 3.5), "floor": 0, "radius": 0.8},
		{"id": "kitchen_tap", "kind": "water_source", "label": "Kitchen tap", "position": Vector2(5.5, 4.5), "floor": 0, "radius": 0.8},
		_container_point("grocery_shelf", "Grocery shelf", Vector2(12.7, 6.5), 0, beans, water),
		{"id": "glass", "kind": "hazard", "label": "Broken glass", "position": Vector2(8.5, 7.5), "floor": 0, "radius": 0.42, "triggered": false},
		{"id": "upstairs_bed", "kind": "bed", "label": "Upstairs safehouse bed", "position": Vector2(5.5, 3.5), "floor": 1, "radius": 0.8},
		_container_point("grocery_upstairs", "First-floor stockroom", Vector2(14.5, 6.5), 1, beans, water),
		_container_point("grocery_top", "Top-floor emergency kit", Vector2(14.5, 6.5), 2, beans, water),
		_container_point("neighbour_pantry", "Neighbour's pantry", Vector2(3.5, 10.5), 0, beans, water),
	]
	var shelf: ContainerData = points[2]["container"]
	for id in ["egg", "milk", "chicken", "beef", "cod", "apple", "berries", "carrot", "potato", "cabbage", "tomato", "canned_corn", "canned_tuna", "canned_sardines", "canned_tomato", "canned_vegetable_soup", "canned_fruit_cocktail", "chips", "biscuits", "granola_bar", "chocolate", "ice_cream", "ice_pop"]:
		shelf.contents.append(ItemStack.new(foods[id]))
	for id in ["canned_water", "juice"]:
		shelf.contents.append(ItemStack.new(liquids[id]))
	(points[7]["container"] as ContainerData).claimed_by = "neighbour"
	points.append(_temperature_container("refrigerator", "Refrigerator", Vector2(4.5, 3.5), 0, 4.0))
	points.append(_temperature_container("freezer", "Freezer", Vector2(3.5, 3.5), 0, -18.0))
	# Temperature starts at the surrounding ambient value when the item is created,
	# then approaches the appliance target through InventoryGrid's item simulation.
	var refrigerator: ContainerData = points[points.size() - 2]["container"]
	refrigerator.contents.append_array([ItemStack.new(foods["milk"]), ItemStack.new(foods["egg"]),
		ItemStack.new(foods["apple"]), ItemStack.new(liquids["juice"])])
	var freezer: ContainerData = points.back()["container"]
	freezer.contents.append_array([ItemStack.new(foods["chicken"]), ItemStack.new(foods["cod"]),
		ItemStack.new(foods["ice_cream"]), ItemStack.new(foods["ice_pop"])])
	var bandage: ItemDefinition = medical["bandage"]
	var disinfectant: ItemDefinition = medical["disinfectant"]
	var antibiotics: ItemDefinition = medical["antibiotics"]
	var painkillers: ItemDefinition = medical["painkillers"]
	var splint: ItemDefinition = medical["splint"]
	var burn_dressing: ItemDefinition = medical["burn_dressing"]
	var tool_case := ItemDefinition.new("test_tool_case", "Test tool case", Vector3(2, 2, 1), 2.0, ["tool"])
	var ration: ItemDefinition = foods["emergency_ration"]
	var small_pack := ItemStack.new(packs["small_backpack"])
	var large_pack := ItemStack.new(packs["hiking_backpack"])
	var broken_pack := ItemStack.new(packs["duffel_bag"])
	small_pack.units[0]["appearance"] = "medical"
	large_pack.units[0]["appearance"] = "travel"
	broken_pack.units[0]["appearance"] = "tool"
	broken_pack.units[0]["durability"] = 0.0
	points.insert(points.size() - 1, {"id": "backpack_crate", "kind": "container", "label": "Backpack crate",
		"position": Vector2(5.7, 7.0), "floor": 0, "radius": 0.9,
		"container": ContainerData.new("backpack_crate", "Backpack crate", [small_pack, large_pack, broken_pack])})
	points.insert(points.size() - 1, {"id": "test_supply_cache", "kind": "container", "label": "Test supply cache",
		"position": Vector2(4.5, 7.0), "floor": 0, "radius": 0.9,
		"container": ContainerData.new("test_supply_cache", "Test supply cache", [
			ItemStack.new(bandage, 3), ItemStack.new(medical["adhesive_bandage"]), ItemStack.new(disinfectant), ItemStack.new(medical["alcohol_wipes"]), ItemStack.new(antibiotics), ItemStack.new(painkillers),
			ItemStack.new(splint), ItemStack.new(burn_dressing), ItemStack.new(medical["antidepressants"]), ItemStack.new(medical["beta_blockers"]),
			ItemStack.new(medical["caffeine_pills"]), ItemStack.new(medical["sleeping_pills"]), ItemStack.new(medical["tweezers"]),
			ItemStack.new(medical["forceps"]), ItemStack.new(medical["suture_needle"]), ItemStack.new(medical["suture_needle_holder"]), ItemStack.new(medical["vitamins"]), ItemStack.new(tools["can_opener"]), ItemStack.new(tools["knife"]),
			ItemStack.new(tool_case), ItemStack.new(ration, 2)])})
	var locations := [Vector2(2.4, 2.7), Vector2(2.4, 3.5), Vector2(6.6, 2.7), Vector2(5.6, 11.2)]
	var labels := ["Kitchen cabinet", "Living room cabinet", "Bedroom dresser", "Neighbour cupboard"]
	var cabinet_floors := [0, 0, 1, 0]
	var snack: ItemDefinition = foods["granola_bar"]
	var hammer := ItemDefinition.new("cabinet_hammer", "Hammer", Vector3(4, 4, 30), 0.8, ["weapon", "tool"])
	hammer.weapon_attack_type = "swing"
	hammer.weapon_damage = 2
	var plank := ItemDefinition.new("cabinet_plank", "Long plank", Vector3(10, 4, 120), 3.0, ["tool"])
	for index in range(4):
		var snacks := ItemStack.new(snack, 3)
		for n in range(3): snacks.units[n]["flavor"] = ["Apple", "Berry", "Nut"][(index + n) % 3]
		var id := "test_cabinet_%d" % index
		var cabinet := ContainerData.new(id, labels[index], [snacks, ItemStack.new(hammer), ItemStack.new(plank)])
		cabinet.capacity = (ContainerData.CABINET_DIMENSIONS.x * ContainerData.CABINET_DIMENSIONS.y
			* ContainerData.CABINET_DIMENSIONS.z)
		points.insert(points.size() - 1, {"id": id, "kind": "container", "label": labels[index], "position": locations[index],
			"floor": cabinet_floors[index], "radius": CONTAINER_REACH, "container": cabinet, "furniture": true})
	var clothing_loot: Array[ItemStack] = []
	clothing_loot.append_array(ClothingCatalog.all_items())
	clothing_loot.append(ItemStack.new(ItemDefinition.clothing("shirt", "Cotton shirt", "inner_top",
		["Torso", "Left Arm", "Right Arm"], {"Torso": 15, "Left Arm": 10, "Right Arm": 10},
		{"Torso": 30, "Left Arm": 20, "Right Arm": 20}, {"Torso": 30, "Left Arm": 25, "Right Arm": 25}, 0.35, Vector3(25, 20, 3), 1)))
	clothing_loot.append(ItemStack.new(ItemDefinition.clothing("jacket", "Work jacket", "outer_top",
		["Torso", "Left Arm", "Right Arm"], {"Torso": 45, "Left Arm": 35, "Right Arm": 35},
		{"Torso": 55, "Left Arm": 40, "Right Arm": 40}, {"Torso": 60, "Left Arm": 45, "Right Arm": 45}, 1.1, Vector3(35, 25, 6), 2)))
	clothing_loot.append(ItemStack.new(ItemDefinition.clothing("trousers", "Trousers", "inner_bottom",
		["Left Leg", "Right Leg"], {"Left Leg": 20, "Right Leg": 20}, {"Left Leg": 35, "Right Leg": 35},
		{"Left Leg": 35, "Right Leg": 35}, 0.55, Vector3(30, 20, 4), 1)))
	clothing_loot.append(ItemStack.new(ItemDefinition.clothing("overpants", "Protective overpants", "outer_bottom",
		["Left Leg", "Right Leg"], {"Left Leg": 40, "Right Leg": 40}, {"Left Leg": 45, "Right Leg": 45},
		{"Left Leg": 55, "Right Leg": 55}, 0.9, Vector3(35, 25, 5), 2)))
	clothing_loot.append(ItemStack.new(ItemDefinition.clothing("cap", "Baseball cap", "hat", ["Head"],
		{"Head": 25}, {"Head": 15}, {"Head": 25}, 0.15, Vector3(20, 20, 12), 1)))
	clothing_loot.append(ItemStack.new(ItemDefinition.clothing("glasses", "Safety glasses", "glasses", ["Head"],
		{}, {"Head": 2}, {"Head": 15}, 0.05, Vector3(15, 5, 5), 1)))
	clothing_loot.append(ItemStack.new(ItemDefinition.clothing("mask", "Dust mask", "mask", ["Head"],
		{}, {"Head": 8}, {"Head": 12}, 0.04, Vector3(12, 8, 2), 1)))
	clothing_loot.append(ItemStack.new(ItemDefinition.clothing("boots", "Work boots", "shoes", ["Left Foot", "Right Foot"],
		{"Left Foot": 50, "Right Foot": 50}, {"Left Foot": 25, "Right Foot": 25},
		{"Left Foot": 50, "Right Foot": 50}, 1.2, Vector3(30, 25, 15), 1)))
	clothing_loot.append(ItemStack.new(ItemDefinition.clothing("gloves", "Work gloves", "gloves", ["Left Hand", "Right Hand"],
		{"Left Hand": 35, "Right Hand": 35}, {"Left Hand": 15, "Right Hand": 15},
		{"Left Hand": 30, "Right Hand": 30}, 0.2, Vector3(20, 12, 4), 1)))
	var needle := ItemDefinition.new("needle", "Needle", Vector3(5, 0.2, 0.2), 0.01, ["needle", "tool"])
	var thread := ItemDefinition.new("thread", "Thread", Vector3(5, 5, 2), 0.03, ["thread", "tool"])
	var flashlight := ItemDefinition.new("flashlight", "Flashlight", Vector3(4, 4, 18), 0.3, ["equipment", "tool"])
	flashlight.switchable = true
	clothing_loot.append_array([ItemStack.new(needle), ItemStack.new(thread), ItemStack.new(ClothingSystem.rag_definition(), 3), ItemStack.new(flashlight)])
	points.insert(points.size() - 1, {"id": "wardrobe", "kind": "container", "label": "Bedroom wardrobe",
		"position": Vector2(2.4, 2.7), "floor": 1, "radius": CONTAINER_REACH,
		"container": ContainerData.new("wardrobe", "Bedroom wardrobe", clothing_loot), "furniture": true})


func _container_point(id: String, label: String, pos: Vector2, floor: int,
		food: ItemDefinition, water: ItemDefinition) -> Dictionary:
	var bottles := ItemStack.new(water, 2)
	var cans := ItemStack.new(food, 2)
	cans.units[0]["flavor"] = "Tomato"
	cans.units[1]["flavor"] = "Chili"
	return {"id": id, "kind": "container", "label": label, "position": pos,
		"floor": floor, "radius": 0.9,
		"container": ContainerData.new(id, label, [cans, bottles])}

func _temperature_container(id: String, label: String, pos: Vector2, floor: int, temperature: float) -> Dictionary:
	var container := ContainerData.new(id, label)
	container.temperature_target = temperature
	return {"id": id, "kind": "container", "label": label, "position": pos, "floor": floor, "radius": 0.9, "container": container}


func _process(delta: float) -> void:
	if world_map == null or player_state.is_dead() or GameTime.simulation_scale() <= 0.0:
		return
	_check_hazards()
	_update_active_action(delta)


func request_interaction() -> void:
	if player_state.is_dead(): return
	var target := PlayerTargeting.interaction_target(self)
	if target.is_empty() or not target["reachable"]:
		notification_requested.emit("Look at a reachable door, window, container or bed." if target.is_empty() else String(target["reason"]))
		return
	if target["kind"] == "barrier":
		var barrier: Dictionary = target["data"]
		var open := not bool(barrier["open"])
		if world_map.set_barrier_open(barrier["id"], open):
			var sound_position: Vector2 = (Vector2(barrier["start"]) + Vector2(barrier["end"])) * 0.5
			NoiseBus.emit_action_noise_at(world_map, ActorPerception.point(world_map, sound_position,
				int(barrier["level"]), "", ActorPerception.CHEST_HEIGHT), String(barrier["kind"]),
				int(barrier["level"]), player.get_instance_id())
			if not open:
				player.logical_position = world_map.resolve_closed_barrier_overlap(
					barrier["id"], player.logical_position, player.floor_level,
					-player.facing_direction)
				player.stair_id = ""
			notification_requested.emit("%s %s." % ["Door" if barrier["kind"] == "door" else "Window", "opened" if open else "closed"])
		return
	var point: Dictionary = target["data"]
	if point.is_empty():
		notification_requested.emit("No reachable interaction on this floor.")
		return
	match String(point["kind"]):
		"container":
			var container: ContainerData = point["container"]
			if not String(point["id"]).begins_with("dropped_") and not container.is_open and not container.searched:
				if is_searching() and active_action["payload"]["id"] == point["id"]: return
				if not _pack_ready(): return
				_start_container_search(point)
				return
			if not String(point["id"]).begins_with("dropped_"):
				container.is_open = not container.is_open
				inventory.revision += 1
			if container.is_open or String(point["id"]).begins_with("dropped_"):
				container_view_requested.emit(point["id"])
		"bed":
			if not _pack_ready(): return
			if player_state.survival.fatigue < StatusConfig.SLEEP_FATIGUE_THRESHOLD and not player_state.effect_active("sleeping_pill"):
				notification_requested.emit("You are not tired enough to sleep.")
				return
			if (player_state.pain >= 60.0 or player_state.anxiety >= 60.0) and not player_state.effect_active("sleeping_pill"):
				notification_requested.emit("Pain or anxiety prevents sleep.")
				return
			if _danger_nearby():
				notification_requested.emit("It is too dangerous to sleep.")
				return
			pre_sleep_speed = GameTime.speed_mode
			_start_action("sleep", "Sleeping", MAX_SLEEP_GAME_SECONDS, point)
			GameTime.set_speed(GameTime.SpeedMode.SLEEP)
		"water_source":
			var held_empty := _held_refillable_container()
			if held_empty.is_empty():
				notification_requested.emit("Hold an empty can or bottle to fill it.")
				return
			request_refill_water_container(String(held_empty["unit"]["uid"]))


func request_sorting() -> void:
	inventory.sort_items()


func _reachable(point: Dictionary) -> bool:
	if point.has("container"):
		var eye := ActorPerception.point(world_map, player.logical_position, player.floor_level, player.stair_id, ActorPerception.EYE_HEIGHT)
		var bounds := PlayerTargeting.point_bounds(world_map, point)
		var direction := eye.direction_to(bounds.get_center())
		var hit := PlayerTargeting.ray_box(eye, direction, bounds, INF)
		if not world_map.has_spatial_line_of_sight(eye, eye + direction * maxf(0, hit - 0.02)): return false
	var target_tile := world_map.get_tile(point["position"], int(point["floor"]))
	var player_tile := world_map.get_tile(player.logical_position, player.floor_level)
	if target_tile != null and not target_tile.room_id.is_empty():
		if player_tile == null or player_tile.room_id != target_tile.room_id:
			return false
	return (player.stair_id.is_empty()
		and int(point["floor"]) == player.floor_level
		and player.logical_position.distance_to(point["position"]) <= (CONTAINER_REACH if point.has("container") else float(point["radius"]))
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


func prompt(target: Variant = null) -> String:
	if not active_action.is_empty():
		if is_searching():
			var seconds := float(active_action["remaining"]) / GameTime.GAME_SECONDS_PER_REAL_SECOND / player_state.action_efficiency("search")
			return "%s  %d%% · %.1f s at 1x · move / aim / Esc to cancel" % [active_action["label"], int(action_progress() * 100.0), seconds]
		return "%s  %d%% · move / aim / Esc to cancel" % [active_action["label"], int(action_progress() * 100.0)]
	if target == null: target = PlayerTargeting.interaction_target(self)
	if target.is_empty(): return ""
	if target["kind"] == "blocked": return "View blocked"
	var point: Dictionary = target["data"]
	var label := String(point.get("label", point["kind"].capitalize()))
	if not target["reachable"]: return "%s · %s" % [label, target["reason"]]
	if target["kind"] == "barrier":
		return "[E] %s %s" % ["Close" if point["open"] else "Open", point["kind"]]
	if point["kind"] == "container":
		var container: ContainerData = point["container"]
		if not String(point["id"]).begins_with("dropped_") and not container.is_open and not container.searched:
			var remaining := maxf(0, container.search_duration_game_seconds - container.search_progress_seconds)
			return "[E] Search %s (%.1f s at 1x)" % [point["label"], remaining / GameTime.GAME_SECONDS_PER_REAL_SECOND / player_state.action_efficiency("search")]
		return "[E] %s %s" % ["View" if String(point["id"]).begins_with("dropped_") else ("Close" if (point["container"] as ContainerData).is_open else "Open"), point["label"]]
	if point["kind"] == "water_source": return "[E] Fill held can or bottle · %s" % point["label"]
	return "[E] Sleep · %s" % point["label"]


func action_progress() -> float:
	if active_action.is_empty():
		return 0.0
	return clampf(1.0 - float(active_action["remaining"]) / float(active_action["duration"]), 0.0, 1.0)


func is_resting() -> bool:
	return active_action.get("kind", "") == "sleep"


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
	var was_sleeping := is_resting()
	active_action = {}
	pack_queue.clear()
	player.interaction_locked = false
	if was_sleeping: _restore_pre_sleep_speed()
	notification_requested.emit(message)
	return true


func _store_search_progress() -> void:
	if is_searching():
		var container: ContainerData = active_action["payload"]["container"]
		container.search_progress_seconds = action_progress() * float(active_action["duration"])


func _start_container_search(point: Dictionary) -> void:
	var container: ContainerData = point["container"]
	if container.searched:
		_open_searched_container(container)
		return
	_start_action("search", "Searching %s" % container.display_name, container.search_duration_game_seconds,
		point, maxf(0.0, container.search_duration_game_seconds - container.search_progress_seconds))
	NoiseBus.emit_action_noise(player, "player_search")


func _open_searched_container(container: ContainerData) -> void:
	container.is_open = true
	inventory.revision += 1
	container_view_requested.emit(container.id)


func _start_action(kind: String, label: String, duration: float, payload: Dictionary,
		remaining: float = -1.0) -> void:
	active_action = {"kind": kind, "label": label, "duration": duration,
		"remaining": duration if remaining < 0.0 else remaining, "payload": payload,
		"position": player.logical_position, "floor": player.floor_level}
	player.interaction_locked = true


func _update_active_action(delta: float) -> void:
	if active_action.is_empty() or GameTime.simulation_scale() <= 0.0:
		return
	var kind := String(active_action.get("kind", ""))
	var efficiency := player_state.action_efficiency(kind) if kind == "search" or (kind == "pack" and active_action["payload"].get("step") in ["repair", "treat"]) else 1.0
	var budget := delta * GameTime.GAME_SECONDS_PER_REAL_SECOND * GameTime.simulation_scale() * efficiency
	while not active_action.is_empty():
		if is_resting() and player_state.survival.fatigue <= 0.0:
			var sleep_completed := active_action
			active_action = {}
			player.interaction_locked = false
			_complete_action(sleep_completed)
			return
		var point: Dictionary = active_action["payload"]
		if (player_state.is_dead() or player.floor_level != int(active_action["floor"])
			or player.logical_position.distance_to(active_action["position"]) > 0.05
			or (point.has("position") and not _reachable(point))):
			interrupt_action("You moved away")
			return
		var elapsed := minf(budget, float(active_action["remaining"]))
		active_action["remaining"] -= elapsed
		budget -= elapsed
		if active_action["kind"] == "pack" and point.get("step") == "use":
			_advance_consumption(point["uid"], elapsed)
		_store_search_progress()
		if float(active_action["remaining"]) > 0.000000001:
			return
		var completed := active_action
		active_action = {}
		player.interaction_locked = false
		_complete_action(completed)
		if budget <= 0.000000001:
			return


func _complete_action(action: Dictionary) -> void:
	match String(action["kind"]):
		"pack":
			if _commit_pack_step(action["payload"]):
				_start_next_pack_step()
			else:
				pack_queue.clear()
				notification_requested.emit(inventory.last_error)
		"search":
			var container: ContainerData = action["payload"]["container"]
			container.searched = true
			container.search_progress_seconds = container.search_duration_game_seconds
			_open_searched_container(container)
		"sleep":
			_restore_pre_sleep_speed()
			rest_completed.emit()
			notification_requested.emit("You wake feeling rested.")
		"sort":
			inventory.sort_items()
			notification_requested.emit("Inventory sorted.")


func _check_hazards() -> void:
	if player_state.is_dead() or GameTime.simulation_scale() <= 0.0 or not player.stair_id.is_empty():
		return
	# Hazards are static points. Rechecking the whole interaction list while the
	# player is idle makes dropped-loot-heavy areas needlessly expensive.
	if (player.floor_level == _last_hazard_check_floor
		and player.logical_position.distance_squared_to(_last_hazard_check_position) < 0.0025):
		return
	_last_hazard_check_position = player.logical_position
	_last_hazard_check_floor = player.floor_level
	for point in points:
		if point["kind"] != "hazard" or bool(point["triggered"]) or not _reachable(point):
			continue
		point["triggered"] = true
		# Presentation caches use this signal to retire the world marker without
		# polling every interaction point every render frame.
		points_changed.emit()
		interrupt_action("Injured")
		player_state.add_wound("Laceration", "left calf", 8.0, false)
		light_injury_received.emit()
		notification_requested.emit("Broken glass: a light wound. Watch your footing.")


func _container_contents_label(container: ContainerData) -> String:
	var labels: Array[String] = []
	for stack in container.contents:
		labels.append(stack.label())
	return ", ".join(labels) if not labels.is_empty() else "empty"


func action_progress_for(container: ContainerData) -> float:
	return clampf(container.search_progress_seconds / container.search_duration_game_seconds, 0.0, 1.0)


func can_access(id: String) -> bool:
	if id in InventoryGrid.ROOTS or id in ["ground", "nearby_all"]: return true
	if inventory.world.has(id):
		for point in points:
			if point["id"] == id:
				return _reachable(point) and _contents_available(point)
		return false
	var found := inventory.find_unit(id)
	return not found.is_empty() and can_access(found["owner"])


func _pack_ready(resume_use: bool = false) -> bool:
	if player_state.is_dead() or GameTime.simulation_scale() <= 0: return false
	if not resume_use and not inventory.use_context.is_empty():
		# Abandon only the return plan, never ownership of the taken-out item.
		inventory.use_context = {}
	interrupt_action("Starting another action")
	return true

func _danger_nearby() -> bool:
	for actor in get_tree().get_nodes_in_group("zombies"):
		var zombie := actor as ZombieActor
		if zombie != null and zombie.health > 0 and zombie.floor_level == player.floor_level and zombie.logical_position.distance_to(player.logical_position) <= 4.0:
			return true
	return false

func _restore_pre_sleep_speed() -> void:
	if GameTime.speed_mode == GameTime.SpeedMode.SLEEP:
		GameTime.set_speed(pre_sleep_speed if pre_sleep_speed != GameTime.SpeedMode.SLEEP else GameTime.SpeedMode.NORMAL)


func operation_reason(uid: String, destination: String, require_free: bool = true) -> String:
	if player_state.is_dead(): return "Player is dead."
	if not player.stair_id.is_empty(): return "Reach a stair landing first."
	if require_free and not inventory.has_free_hand(): return "At least one empty hand is required."
	if not can_access(uid) or not can_access(destination): return "Item or container is out of reach."
	if not inventory.preview_moves([{"uid": uid, "destination": "ground" if destination == "nearby_all" else destination}]): return inventory.last_error
	return ""


func request_transfer(uid: String, destination: String) -> void:
	request_units([uid], destination)


func request_units(ids: Array, destination: String, require_free: bool = true) -> void:
	if ids.is_empty(): return
	if destination == "nearby_all": destination = "ground"
	if not require_free:
		for uid in ids:
			var found := inventory.find_unit(uid)
			if destination != "ground" or found.is_empty() or not found["owner"] in InventoryGrid.HANDS:
				require_free = true
				break
	var reason := operation_reason(ids[0], destination, require_free)
	if not reason.is_empty():
		notification_requested.emit(reason)
		return
	if not _pack_ready(): return
	for uid in ids:
		pack_queue.append({"step": "move", "uid": uid, "destination": destination, "free_hand": require_free})
	_begin_pack_queue()


func request_batch(source: String, destination: String) -> void:
	var ids: Array[String] = []
	for stack: ItemStack in inventory.contents(source):
		for unit in stack.units: ids.append(unit["uid"])
	request_units(ids, destination)


func request_pickup(uid: String) -> void:
	if not can_access(uid) or not player.stair_id.is_empty(): return
	var plan := inventory.pickup_plan(uid)
	if plan.is_empty():
		notification_requested.emit(inventory.last_error if not inventory.last_error.is_empty() else "Already held.")
		return
	if not _pack_ready(): return
	pack_queue = plan
	_begin_pack_queue()


func nearby_containers() -> Array[Dictionary]:
	var nearby: Array[Dictionary] = []
	for point in points:
		if point.has("container") and _reachable(point) and _contents_available(point): nearby.append(point)
	nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ag := String(a["id"]).begins_with("dropped_")
		var bg := String(b["id"]).begins_with("dropped_")
		if ag != bg: return ag
		var ad := player.logical_position.distance_squared_to(a["position"])
		var bd := player.logical_position.distance_squared_to(b["position"])
		if not is_equal_approx(ad, bd): return ad < bd
		if a["label"] != b["label"]: return a["label"] < b["label"]
		return a["id"] < b["id"])
	return nearby


func _contents_available(point: Dictionary) -> bool:
	if String(point["id"]).begins_with("dropped_"):
		return player.logical_position.distance_to(point["position"]) <= 0.65
	return (point["container"] as ContainerData).is_open


func _ground_container() -> String:
	# Ground is a location, not an item. Reuse its existing pile so repeated
	# drops cannot create an ever-growing list of overlapping containers/markers.
	for point in points:
		if not String(point.get("id", "")).begins_with("dropped_"):
			continue
		if int(point.get("floor", -999)) != player.floor_level:
			continue
		var point_position: Vector2 = point["position"]
		if point_position.distance_squared_to(player.logical_position) < 0.0025:
			return String(point["id"])
	var id := "dropped_" + ItemStack.new_uid()
	var container := ContainerData.new(id, "Set-down belongings")
	container.searched = true
	points.append({"id": id, "kind": "container", "label": container.display_name,
		"position": player.logical_position, "floor": player.floor_level, "radius": 0.9, "container": container})
	inventory.world[id] = container
	points_changed.emit()
	return id

func spawn_ground_stack(stack: ItemStack) -> String:
	var id := _ground_container()
	inventory.world[id].contents.append(stack)
	inventory.revision += 1
	return id


func request_search(id: String) -> void:
	if can_access(id): container_view_requested.emit(id)


func _free_hand_ready() -> bool:
	if not inventory.has_free_hand():
		notification_requested.emit("At least one empty hand is required.")
		return false
	return true


func request_equip(uid: String) -> void:
	if not _free_hand_ready() or not can_access(uid): return
	var found := inventory.find_unit(uid)
	if found.is_empty() or not "backpack" in found["stack"].definition.tags or found["unit"]["durability"] <= 0:
		notification_requested.emit("This backpack cannot be equipped.")
		return
	if found["owner"] == "equipment": return
	if not _pack_ready(): return
	if inventory.equipped != null:
		if not player.stair_id.is_empty():
			notification_requested.emit("Reach a stair landing before setting down a backpack.")
			return
		pack_queue.append({"step": "move", "uid": inventory.equipped.units[0]["uid"], "destination": "ground"})
	pack_queue.append({"step": "move", "uid": uid, "destination": "equipment"})
	if not inventory.preview_moves(pack_queue):
		pack_queue.clear()
		notification_requested.emit(inventory.last_error)
		return
	_begin_pack_queue()


func request_unequip() -> void:
	if not _free_hand_ready() or not _pack_ready() or inventory.equipped == null: return
	if not player.stair_id.is_empty():
		notification_requested.emit("Reach a stair landing before setting down a backpack.")
		return
	pack_queue = [{"step": "move", "uid": inventory.equipped.units[0]["uid"], "destination": "ground"}]
	_begin_pack_queue()

func request_wear(uid: String) -> void:
	var found := inventory.find_unit(uid)
	if found.is_empty() or not can_access(uid) or found["stack"].definition.clothing_slot.is_empty(): return
	var slot: String = found["stack"].definition.clothing_slot
	if found["owner"] == slot: return
	var plan: Array[Dictionary] = []
	if not inventory.contents(slot).is_empty():
		plan.append({"step": "unwear", "uid": inventory.contents(slot)[0].units[0]["uid"], "destination": "loose"})
	plan.append({"step": "wear", "uid": uid, "destination": slot})
	if not inventory.preview_moves(plan):
		notification_requested.emit(inventory.last_error)
		return
	if not _pack_ready(): return
	pack_queue = plan
	_begin_pack_queue()

func request_remove_clothing(slot: String) -> void:
	if slot not in InventoryGrid.CLOTHING_SLOTS or inventory.contents(slot).is_empty(): return
	var step := {"step": "unwear", "uid": inventory.contents(slot)[0].units[0]["uid"], "destination": "loose"}
	if not inventory.preview_moves([step]):
		notification_requested.emit(inventory.last_error)
		return
	if not _pack_ready(): return
	pack_queue = [step]
	_begin_pack_queue()

func repair_reason(uid: String, region: String) -> String:
	var found := inventory.find_unit(uid)
	if found.is_empty() or not inventory.carried(uid): return "garment must be carried"
	var item: ItemDefinition = found["stack"].definition
	if region not in item.clothing_regions: return "region not covered"
	var current := float(found["unit"].get("clothing_durability", {}).get(region, 0.0))
	var maximum := float(item.clothing_max_durability.get(region, 0.0))
	if current <= 0: return "garment is destroyed"
	if current >= maximum: return "already fully repaired"
	for tag in ["needle", "thread", "rag"]:
		if inventory.first_with_tag(tag).is_empty(): return "requires Needle, Thread and Rag"
	return ""

func request_repair(uid: String, region: String) -> void:
	var reason := repair_reason(uid, region)
	if not reason.is_empty():
		notification_requested.emit(reason)
		return
	if not _pack_ready(): return
	pack_queue = [{"step": "repair", "uid": uid, "destination": inventory.find_unit(uid)["owner"],
		"region": region, "rag_uid": inventory.first_with_tag("rag")}]
	_begin_pack_queue()

func treatment_reason(item_uid: String, wound_id: String) -> String:
	var found := inventory.find_unit(item_uid)
	if found.is_empty() or not inventory.carried(item_uid): return "medical item must be carried"
	var treatment: String = found["stack"].definition.medical_action
	if treatment.is_empty(): return "item has no medical use"
	if treatment not in ["painkiller", "antidepressant", "beta_blocker", "caffeine", "sleeping_pill"]:
		var wound := player_state.wound_by_id(wound_id)
		if wound.is_empty(): return "select an injury"
		if treatment == "splint" and wound["type"] != "Fracture": return "splints treat fractures"
		if treatment == "burn_dressing" and wound["type"] != "Burn": return "dressing treats burns"
		if treatment == "remove_glass" and wound.get("foreign_body", "none") != "glass": return "tweezers remove glass fragments"
		if treatment == "remove_bullet":
			if wound.get("foreign_body", "none") != "bullet": return "forceps remove bullets"
			if inventory.first_medical_action("remove_glass").is_empty(): return "bullet removal also requires tweezers"
		if treatment == "suture" and (not wound.get("requires_sutures", false) or wound.get("foreign_body", "none") != "none"): return "remove the foreign body before suturing"
	return ""

func request_treatment(item_uid: String, wound_id: String = "") -> void:
	var reason := treatment_reason(item_uid, wound_id)
	if not reason.is_empty():
		notification_requested.emit(reason)
		return
	if not _pack_ready(): return
	var found := inventory.find_unit(item_uid)
	pack_queue = [{"step": "treat", "uid": item_uid, "destination": found["owner"],
		"wound_id": wound_id, "treatment": found["stack"].definition.medical_action}]
	_begin_pack_queue()

func request_disinfect_bandage(uid: String) -> void:
	var found := inventory.find_unit(uid)
	if found.is_empty() or "bandage" not in found["stack"].definition.tags:
		notification_requested.emit("Select a clean bandage.")
		return
	if float(found["unit"].get("bandage_absorption", 0.0)) > 0.0:
		notification_requested.emit("Wash bloodied bandages before disinfecting them.")
		return
	var disinfectant_uid := inventory.first_medical_action("disinfectant")
	if disinfectant_uid.is_empty():
		notification_requested.emit("Disinfectant is required.")
		return
	inventory.remove_unit(disinfectant_uid)
	found["unit"]["bandage_disinfected"] = true
	inventory.revision += 1
	notification_requested.emit("Bandage disinfected.")

func request_wash_bandage(uid: String) -> void:
	var found := inventory.find_unit(uid)
	if found.is_empty() or "bandage" not in found["stack"].definition.tags:
		notification_requested.emit("Select a bandage.")
		return
	var absorption := float(found["unit"].get("bandage_absorption", 0.0))
	if absorption <= 0.0 or absorption >= 28.0:
		notification_requested.emit("Only bloodied, non-dirty bandages can be washed.")
		return
	var water_uid := inventory.first_with_tag("water")
	if water_uid.is_empty():
		notification_requested.emit("Water is required.")
		return
	if not _pack_ready(): return
	pack_queue = [{"step": "wash", "uid": uid, "destination": found["owner"], "water_uid": water_uid, "absorption": absorption}]
	_begin_pack_queue()

func refill_reason(uid: String) -> String:
	var found := inventory.find_unit(uid)
	if found.is_empty() or not inventory.carried(uid): return "empty container must be carried"
	if not String(found["stack"].definition.id) in ["empty_can", "empty_bottle"]: return "only empty cans and bottles can be filled"
	for point in points:
		if point["kind"] == "water_source" and _reachable(point): return ""
	return "reach a water source"

func request_refill_water_container(uid: String) -> void:
	var reason := refill_reason(uid)
	if not reason.is_empty():
		notification_requested.emit(reason)
		return
	if not _pack_ready(): return
	var found := inventory.find_unit(uid)
	pack_queue = [{"step": "fill", "uid": uid, "destination": found["owner"]}]
	_begin_pack_queue()

func _held_refillable_container() -> Dictionary:
	for slot in InventoryGrid.HANDS:
		for stack: ItemStack in inventory.contents(slot):
			if stack.definition.id in ["empty_can", "empty_bottle"] and not stack.units.is_empty():
				return {"stack": stack, "unit": stack.units[0], "owner": slot}
	return {}


func request_use(uid: String) -> void:
	if uid.is_empty() and not inventory.use_context.is_empty(): uid = inventory.use_context["uid"]
	var found := inventory.find_unit(uid)
	if found.is_empty() or not can_access(uid): return
	if not "food" in found["stack"].definition.tags and not "water" in found["stack"].definition.tags: return
	var definition: ItemDefinition = found["stack"].definition
	if definition.requires_opening and not bool(found["unit"].get("opened", false)):
		if "canned" in definition.tags and not inventory.held_tag("can_opener") and not inventory.held_tag("knife"):
			notification_requested.emit("Hold a can opener or knife to open this can.")
			return
		found["unit"]["opened"] = true
		inventory.revision += 1
		notification_requested.emit("Opened %s." % definition.display_name)
		return
	if not _usable_food(found): return
	var origin: String = found["owner"]
	var return_after := inventory.carried(uid) and not origin in InventoryGrid.HANDS
	var resume: bool = inventory.use_context.get("uid", "") == uid
	var plan: Array[Dictionary] = []
	if not origin in InventoryGrid.HANDS:
		plan = inventory.pickup_plan(uid)
		if plan.is_empty():
			notification_requested.emit(inventory.last_error)
			return
		plan[-1]["step"] = "take"
		plan[-1]["origin"] = origin
		plan[-1]["return_after"] = return_after
	if not _pack_ready(true): return
	if not resume: inventory.use_context = {}
	if origin in InventoryGrid.HANDS and inventory.use_context.is_empty():
		inventory.use_context = {"uid": uid, "origin": origin, "used": false, "return_after": false}
	pack_queue = plan
	if not inventory.use_context.get("used", false):
		pack_queue.append({"step": "use", "uid": uid, "destination": origin})
	pack_queue.append({"step": "return", "uid": uid, "destination": origin})
	_begin_pack_queue()


func _begin_pack_queue() -> void:
	var total := pack_queue.size()
	for index in range(total):
		pack_queue[index]["index"] = index + 1
		pack_queue[index]["total"] = total
	_start_next_pack_step()


func _start_next_pack_step() -> void:
	if pack_queue.is_empty():
		notification_requested.emit("Inventory action complete.")
		return
	var step: Dictionary = pack_queue.pop_front()
	var found := inventory.find_unit(step["uid"])
	var title: String = found["stack"].definition.display_name if not found.is_empty() else "item"
	if step["step"] in ["move", "take", "wear", "unwear"] and (not can_access(step["uid"]) or not inventory.preview_moves([step])):
		pack_queue.clear()
		notification_requested.emit(inventory.last_error)
		return
	if step["step"] == "repair" and not repair_reason(step["uid"], step["region"]).is_empty():
		pack_queue.clear()
		notification_requested.emit(repair_reason(step["uid"], step["region"]))
		return
	if step["step"] == "treat" and not treatment_reason(step["uid"], step.get("wound_id", "")).is_empty():
		pack_queue.clear()
		notification_requested.emit(treatment_reason(step["uid"], step.get("wound_id", "")))
		return
	if step["step"] == "fill" and not refill_reason(step["uid"]).is_empty():
		pack_queue.clear()
		notification_requested.emit(refill_reason(step["uid"]))
		return
	_start_action("pack", "%s: %s %d/%d" % [String(step["step"]).capitalize(), title,
		int(step.get("index", 1)), int(step.get("total", pack_queue.size() + 1))],
		pack_step_duration(step), step)


func pack_step_duration(step: Dictionary) -> float:
	if step["step"] in ["wear", "unwear"]: return CLOTHING_CHANGE_GAME_SECONDS
	if step["step"] == "repair": return CLOTHING_REPAIR_GAME_SECONDS
	if step["step"] == "treat": return MEDICAL_ACTION_GAME_SECONDS
	if step["step"] == "wash": return maxf(1.0, float(step.get("absorption", 0.0)) * 30.0)
	if step["step"] == "fill":
		var refill_found := inventory.find_unit(step["uid"])
		if refill_found.is_empty(): return 0.000001
		return float(refill_found["stack"].definition.liquid_capacity_ml) * 60.0 / 100.0
	if step["step"] == "return" and not inventory.use_context.get("return_after", true): return 0.000001
	if step["step"] == "use":
		var target := _consumable(step["uid"])
		if target.is_empty(): return 0.000001
		var item: ItemDefinition = target["stack"].definition
		var water := "water" in item.tags
		var amount := float(target["unit"].get("liquid_ml", item.liquid_capacity_ml)) if water and item.liquid_capacity_ml > 0.0 else (item.volume() if water else item.unit_weight * 1000.0)
		var reserve := player_state.survival.thirst if water else player_state.survival.hunger
		var benefit := _restore_amount(item, water)
		var fraction := minf(float(target["unit"].get("remaining", 1.0)), maxf(0.0, 100.0 - reserve) / maxf(0.000001, benefit))
		var rate := 100.0 if water else (item.consumption_rate_per_game_minute if item.consumption_rate_per_game_minute > 0.0 else 60.0)
		return maxf(0.000001, amount * fraction / rate * 60.0)
	var found := inventory.find_unit(step["uid"])
	if found.is_empty(): return 0.000001
	var single := ItemStack.from_unit(found["stack"].definition, found["unit"])
	var destination: String = step["destination"]
	if step["step"] == "move" and (found["owner"] == "equipment" or destination == "equipment"):
		return 2.0 * (single.total_weight() / 100.0 + 1.0)
	var divisor := 200.0 if destination.begins_with("dropped_") or destination == "ground" else 100.0
	return maxf(0.000001, single.total_weight() * single.total_volume() / divisor)


func _consumable(uid: String) -> Dictionary:
	var found := inventory.find_unit(uid)
	if found.is_empty(): return {}
	if found["stack"].definition.capacity() <= 0 or ("water" in found["stack"].definition.tags and found["stack"].definition.liquid_capacity_ml > 0.0): return found
	for child: ItemStack in found["unit"]["contents"]:
		if "water" in child.definition.tags or "food" in child.definition.tags:
			return inventory.find_unit(child.units[0]["uid"])
	return {}

func _usable_food(found: Dictionary) -> bool:
	var item: ItemDefinition = found["stack"].definition
	var unit: Dictionary = found["unit"]
	if item.requires_opening and not bool(unit.get("opened", false)):
		notification_requested.emit("Open this item first.")
		return false
	if item.freshness_lifetime_days > 0.0 and float(unit.get("freshness", 100.0)) <= 0.0:
		notification_requested.emit("Spoiled items cannot be consumed.")
		return false
	if ("food" in item.tags or "water" in item.tags) and float(unit.get("temperature", 20.0)) <= 0.0 and not item.edible_frozen:
		notification_requested.emit("This item must thaw above 0°C first.")
		return false
	return true


func _advance_consumption(uid: String, seconds: float) -> void:
	var found := _consumable(uid)
	if found.is_empty():
		active_action["remaining"] = 0.0
		return
	var item: ItemDefinition = found["stack"].definition
	var water := "water" in item.tags
	var original_amount := float(found["unit"].get("liquid_ml", item.liquid_capacity_ml)) if water and item.liquid_capacity_ml > 0.0 else (item.volume() if water else item.unit_weight * 1000.0)
	var reserve := player_state.survival.thirst if water else player_state.survival.hunger
	var benefit := _restore_amount(item, water)
	var remaining := float(found["unit"].get("remaining", 1.0))
	var rate := 100.0 if water else (item.consumption_rate_per_game_minute if item.consumption_rate_per_game_minute > 0.0 else 60.0)
	var fraction := minf(remaining, minf(seconds * rate / 60.0 / maxf(0.000001, original_amount), maxf(0.0, 100.0 - reserve) / benefit))
	if water: player_state.survival.drink(fraction * benefit)
	else:
		player_state.survival.eat(fraction * benefit)
		var happiness_multiplier := 0.5 if float(found["unit"].get("freshness", 100.0)) < 50.0 else 1.0
		player_state.unhappiness = clampf(player_state.unhappiness - fraction * item.happiness_effect * happiness_multiplier, 0.0, 100.0)
	found["unit"]["remaining"] = remaining - fraction
	if water and item.liquid_capacity_ml > 0.0: found["unit"]["liquid_ml"] = maxf(0.0, original_amount * (remaining - fraction))
	if remaining - fraction <= 0.000001:
		var stack: ItemStack = found["stack"]
		var owner: String = found["owner"]
		stack.units.erase(found["unit"])
		if stack.quantity == 0: inventory.contents(found["owner"]).erase(stack)
		if water and not item.empty_container_id.is_empty() and item.empty_container_id != "empty_juice_box":
			var empty: Variant = ItemCatalog.liquid_definitions().get(item.empty_container_id, null)
			if empty is ItemDefinition: inventory.contents(owner).append(ItemStack.new(empty))
		if inventory.find_unit(uid).is_empty(): inventory.use_context = {}
		active_action["remaining"] = 0.0
	if reserve + fraction * benefit >= 100.0: active_action["remaining"] = 0.0
	inventory.revision += 1

func _restore_amount(item: ItemDefinition, water: bool) -> float:
	var amount := item.thirst_restore if water else item.hunger_restore
	return amount if amount > 0.0 else (32.0 if water else 24.0)


func _commit_pack_step(step: Dictionary) -> bool:
	var uid: String = step["uid"]
	var found := inventory.find_unit(uid)
	inventory.last_error = "Item is no longer reachable. Completed steps kept."
	if step["step"] == "use" and inventory.use_context.is_empty() and found.is_empty(): return true
	if step["step"] == "return" and inventory.use_context.is_empty(): return true
	if found.is_empty() or not can_access(uid): return false
	var kind: String = step["step"]
	if kind in ["move", "take", "wear", "unwear"]:
		if (step.get("free_hand", false) or found["owner"] == "equipment" or step["destination"] == "equipment") and not inventory.has_free_hand():
			inventory.last_error = "At least one empty hand is required."
			return false
		var destination: String = step["destination"]
		if not can_access(destination): return false
		if not inventory.preview_moves([step]): return false
		if destination == "ground": destination = _ground_container()
		var moved := inventory.move_unit(uid, destination)
		if moved and kind == "take":
			inventory.use_context = {"uid": uid, "origin": step["origin"], "used": false, "return_after": step.get("return_after", true)}
		if moved and "food" in found["stack"].definition.tags and inventory.carried(uid): food_found.emit()
		return moved
	if kind == "repair":
		var reason := repair_reason(uid, step["region"])
		if not reason.is_empty():
			inventory.last_error = reason
			return false
		var rag_uid := inventory.first_with_tag("rag")
		if rag_uid.is_empty(): return false
		var item: ItemDefinition = found["stack"].definition
		var region: String = step["region"]
		inventory.remove_unit(rag_uid)
		found["unit"]["clothing_durability"][region] = minf(float(item.clothing_max_durability[region]),
			float(found["unit"]["clothing_durability"][region]) + float(item.clothing_max_durability[region]) * 0.1)
		inventory.revision += 1
		return true
	if kind == "wash":
		var absorption := float(found["unit"].get("bandage_absorption", 0.0))
		if absorption <= 0.0 or absorption >= 28.0: return false
		var water := inventory.find_unit(String(step.get("water_uid", "")))
		if water.is_empty():
			inventory.last_error = "Water is no longer available."
			return false
		var water_needed := 100.0 * absorption / 28.0
		if water["stack"].definition.liquid_capacity_ml > 0.0:
			if float(water["unit"].get("liquid_ml", 0.0)) < water_needed: return false
			water["unit"]["liquid_ml"] = float(water["unit"].get("liquid_ml", 0.0)) - water_needed
			water["unit"]["remaining"] = water["unit"]["liquid_ml"] / water["stack"].definition.liquid_capacity_ml
		found["unit"]["bandage_absorption"] = 0.0
		found["unit"]["bandage_disinfected"] = false
		inventory.revision += 1
		return true
	if kind == "fill":
		var replacement_id: String = {"empty_can": "canned_water", "empty_bottle": "bottled_water"}.get(found["stack"].definition.id, "")
		var water: Variant = ItemCatalog.liquid_definitions().get(replacement_id, null)
		if not water is ItemDefinition: return false
		var owner: String = found["owner"]
		var old_stack: ItemStack = found["stack"]
		old_stack.units.erase(found["unit"])
		if old_stack.quantity == 0: inventory.contents(owner).erase(old_stack)
		inventory.contents(owner).append(ItemStack.new(water))
		inventory.revision += 1
		return true
	if kind == "treat":
		if not treatment_reason(uid, step.get("wound_id", "")).is_empty(): return false
		var wound := player_state.wound_by_id(step.get("wound_id", ""))
		var treatment: String = step["treatment"]
		if treatment == "bandage" and not wound.is_empty() and bool(wound.get("bandaged", false)):
			var bandage_definitions := ItemCatalog.medical_definitions()
			var old_definition: Variant = bandage_definitions.get(String(wound.get("bandage_item_id", "bandage")), bandage_definitions["bandage"])
			var returned := ItemStack.new(old_definition as ItemDefinition)
			returned.units[0]["bandage_absorption"] = float(wound.get("bandage_absorption", 0.0))
			returned.units[0]["bandage_disinfected"] = bool(wound.get("bandage_disinfected", false))
			inventory.contents(found["owner"]).append(returned)
		if not player_state.treat_wound(step.get("wound_id", ""), treatment): return false
		if treatment == "bandage" and not wound.is_empty():
			wound["bandage_disinfected"] = bool(found["unit"].get("bandage_disinfected", false))
			wound["bandage_item_id"] = found["stack"].definition.id
		if not "tool" in found["stack"].definition.tags: inventory.remove_unit(uid)
		return true
	if inventory.use_context.get("uid", "") != uid or not found["owner"] in InventoryGrid.HANDS: return false
	if kind == "return":
		var origin: String = inventory.use_context["origin"]
		if inventory.use_context.get("return_after", true) and origin != found["owner"]:
			if not inventory.has_free_hand():
				inventory.last_error = "No empty hand to return item; it remains held."
				inventory.use_context = {}
				return false
			if not can_access(origin) or not inventory.move_unit(uid, origin): return false
		inventory.use_context = {}
		return true
	if kind != "use" or inventory.use_context["used"]: return false
	inventory.use_context["used"] = true
	inventory.revision += 1
	return true
