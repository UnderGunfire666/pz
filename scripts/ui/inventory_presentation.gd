class_name InventoryPresentation
extends RefCounted

const PREF_PATH := "user://inventory_ui.cfg"
const PREF_VERSION := 2
const SORTS := ["acquired", "weight", "volume", "name", "category"]
var sides: Array[Dictionary] = [
	{"selected": "all_carried", "sort": "acquired", "descending": true, "expanded": {}, "splits": {}},
	{"selected": "ground", "sort": "acquired", "descending": true, "expanded": {}, "splits": {}}]

func load_preferences(path: String = PREF_PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	var legacy := int(config.get_value("meta", "version", 1)) < PREF_VERSION
	for side in range(2):
		var section := str(side)
		var selected: Variant = config.get_value(section, "selected", sides[side]["selected"])
		var sort: Variant = config.get_value(section, "sort", "acquired")
		var descending: Variant = config.get_value(section, "descending", true)
		if selected is String: sides[side]["selected"] = selected
		if sort is String and sort in SORTS: sides[side]["sort"] = sort
		if descending is bool: sides[side]["descending"] = descending
		for key in ["expanded", "splits"]:
			var value: Variant = config.get_value(section, key, {})
			if value is Dictionary and value.size() < 4096:
				var clean := {}
				for id in value:
					if id is String and ((key == "expanded" and value[id] is bool) or (key == "splits" and value[id] is String)):
						clean[id] = value[id]
				sides[side][key] = clean
	if legacy:
		sides[0]["selected"] = "all_carried"
		save_preferences(path)

func save_preferences(path: String = PREF_PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", PREF_VERSION)
	for side in range(2):
		for key in sides[side]: config.set_value(str(side), key, sides[side][key])
	return config.save(path)

func containers(game: MVPGameRoot, side: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if side == 0:
		result.append({"id": "all_carried", "name": "All carried", "short_name": "All"})
		result.append({"id": "loose", "name": "Carried"})
		if game.inventory.equipped != null: result.append({"id": "equipped", "name": "Equipped Backpack", "short_name": "Backpack"})
		result.append({"id": "worn_clothing", "name": "Worn clothing", "short_name": "Clothing"})
		for hand in InventoryGrid.HANDS:
			if not game.inventory.contents(hand).is_empty():
				var short: String = {"left_hand": "L Hand", "right_hand": "R Hand", "two_hands": "2 Hands"}[hand]
				result.append({"id": hand, "name": String(hand).capitalize(), "short_name": short})
		var selected: String = sides[side]["selected"]
		if selected not in ["all_carried", "loose", "equipped"] and selected not in InventoryGrid.HANDS:
			var found := game.inventory.find_unit(selected)
			if not found.is_empty() and game.inventory.carried(selected) and found["stack"].definition.capacity() > 0:
				result.append({"id": selected, "name": found["stack"].definition.display_name})
	else:
		result.append({"id": "ground", "name": "Ground"})
		for point in game.interactions.nearby_containers():
			if not String(point["id"]).begins_with("dropped_"):
				result.append({"id": point["id"], "name": point["label"], "short_name": _short_world_name(point)})
		result.append({"id": "nearby_all", "name": "Nearby All", "short_name": "All near"})
	var valid := false
	for entry in result:
		if entry["id"] == sides[side]["selected"]: valid = true
	if not valid: sides[side]["selected"] = "all_carried" if side == 0 else "ground"
	return result

func _short_world_name(point: Dictionary) -> String:
	var id := String(point["id"])
	if id.begins_with("test_cabinet_"):
		return "Cab %s" % String.chr(65 + int(id.trim_prefix("test_cabinet_")))
	if id == "backpack_crate": return "Packs"
	if id == "test_supply_cache": return "Supply"
	var words := String(point["label"]).split(" ")
	return words[0] if not words.is_empty() else "Container"

func destination(game: MVPGameRoot, side: int) -> String:
	var id: String = sides[side]["selected"]
	if id == "all_carried": return "loose"
	if id == "equipped": return game.inventory.default_destination()
	if id == "worn_clothing": return game.inventory.default_destination()
	if id == "nearby_all": return "ground"
	return id

func container_tab_for(game: MVPGameRoot, uid: String) -> String:
	var found := game.inventory.find_unit(uid)
	return "equipped" if not found.is_empty() and found["owner"] == "equipment" else uid

func sources(game: MVPGameRoot, side: int) -> Array[String]:
	var selected: String = sides[side]["selected"]
	var result: Array[String] = []
	if selected == "all_carried":
		result.append("loose")
		if game.inventory.equipped != null:
			result.append(game.inventory.equipped.units[0]["uid"])
		for hand in InventoryGrid.HANDS:
			result.append(hand)
		for slot in InventoryGrid.CLOTHING_SLOTS:
			result.append(slot)
	elif selected == "worn_clothing":
		result.append("equipment")
		result.append_array(InventoryGrid.CLOTHING_SLOTS)
	elif selected in ["ground", "nearby_all"]:
		for point in game.interactions.nearby_containers():
			if selected == "nearby_all" or String(point["id"]).begins_with("dropped_"): result.append(point["id"])
	else:
		var source := destination(game, side)
		if game.interactions.can_access(source): result.append(source)
	return result

func groups(game: MVPGameRoot, side: int) -> Array[Dictionary]:
	var grouped := {}
	var ordered_sources := sources(game, side)
	for source in ordered_sources:
		for stack: ItemStack in game.inventory.contents(source):
			for unit in stack.units:
				var uid: String = unit["uid"]
				var key: String = stack.definition.id + ":" + String(sides[side]["splits"].get(uid, ""))
				if not grouped.has(key):
					grouped[key] = {"key": key, "name": stack.definition.display_name, "entries": [], "weight": 0.0, "volume": 0.0, "acquired": 0.0, "category": category(stack.definition)}
				var group: Dictionary = grouped[key]
				var single := ItemStack.from_unit(stack.definition, unit)
				group["entries"].append({"uid": uid, "source": source, "name": stack.definition.display_name,
					"weight": game.inventory.effective_weight(single), "volume": single.total_volume(),
					"acquired": float(unit.get("acquired", 0.0)), "category": category(stack.definition)})
				group["weight"] += game.inventory.effective_weight(single)
				group["volume"] += single.total_volume()
				group["acquired"] = maxf(group["acquired"], float(unit.get("acquired", 0.0)))
	var result: Array[Dictionary] = []
	for group: Dictionary in grouped.values():
		group["entries"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _less(a, b, side))
		group["ids"] = []
		for entry in group["entries"]: group["ids"].append(entry["uid"])
		var transfers: Array = group["entries"].duplicate()
		transfers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["source"] != b["source"]: return ordered_sources.find(a["source"]) < ordered_sources.find(b["source"])
			return _less(a, b, side))
		group["transfer_ids"] = []
		for entry in transfers: group["transfer_ids"].append(entry["uid"])
		result.append(group)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _less(a, b, side))
	return result

func _less(a: Dictionary, b: Dictionary, side: int) -> bool:
	var key: String = sides[side]["sort"]
	if a[key] == b[key]: return String(a.get("uid", a.get("key", ""))) < String(b.get("uid", b.get("key", "")))
	return a[key] > b[key] if sides[side]["descending"] else a[key] < b[key]

func split(side: int, ids: Array, count: int) -> void:
	if count <= 0 or count >= ids.size(): return
	var group := ItemStack.new_uid()
	for uid in ids.slice(0, count): sides[side]["splits"][uid] = group

static func category(item: ItemDefinition) -> String:
	return item.tags[0].capitalize() if not item.tags.is_empty() else "Misc"

static func acquisition_label(unit: Dictionary) -> String:
	var acquired := float(unit.get("acquired", 0.0))
	var age := maxf(0.0, GameTime.elapsed_game_seconds - acquired)
	if age < 86400.0: return "%d game minutes ago" % int(age / 60.0)
	return "Day %d %02d:%02d" % [int(acquired / 86400.0) + 1, int(acquired / 3600.0) % 24, int(acquired / 60.0) % 60]
