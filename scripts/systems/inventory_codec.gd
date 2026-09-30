class_name InventoryCodec
extends RefCounted

static func pack(stack: ItemStack) -> Dictionary:
	var item := stack.definition
	var units: Array = []
	for unit in stack.units:
		var children: Array = []
		for child: ItemStack in unit["contents"]: children.append(pack(child))
		units.append({"uid": unit["uid"], "flavor": unit["flavor"], "durability": unit["durability"], "contents": children,
			"remaining": unit.get("remaining", 1.0), "acquired": unit.get("acquired", 0.0),
			"clothing_durability": unit.get("clothing_durability", {}).duplicate(true),
			"switched_on": unit.get("switched_on", false)})
	return {"id": item.id, "name": item.display_name, "dimensions": item.dimensions,
		"capacity": item.capacity_dimensions, "weight": item.unit_weight, "reduction": item.weight_reduction,
		"tags": item.tags.duplicate(), "two_hands": item.requires_two_hands, "units": units,
		"clothing_slot": item.clothing_slot, "clothing_regions": item.clothing_regions.duplicate(),
		"clothing_protection": item.clothing_protection.duplicate(true),
		"clothing_warmth": item.clothing_warmth.duplicate(true),
		"clothing_max_durability": item.clothing_max_durability.duplicate(true), "rag_yield": item.rag_yield,
		"weapon_attack_type": item.weapon_attack_type, "weapon_damage": item.weapon_damage,
		"switchable": item.switchable, "hunger_restore": item.hunger_restore,
		"thirst_restore": item.thirst_restore, "happiness_effect": item.happiness_effect,
		"medical_action": item.medical_action}

static func valid(data: Variant, depth: int = 0) -> bool:
	if depth > 16 or not data is Dictionary: return false
	if not data.get("id") is String or not data.get("name") is String: return false
	if not data.get("two_hands", false) is bool: return false
	if not data.get("clothing_slot", "") is String or not data.get("clothing_regions", []) is Array: return false
	for key in ["clothing_protection", "clothing_warmth", "clothing_max_durability"]:
		if not data.get(key, {}) is Dictionary: return false
		for region in data.get(key, {}):
			var value: Variant = data[key][region]
			if not region is String or not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0: return false
	if not data.get("rag_yield", 0) is int or int(data.get("rag_yield", 0)) < 0: return false
	if not data.get("weapon_attack_type", "") is String or not data.get("weapon_damage", 0) is int or int(data.get("weapon_damage", 0)) < 0: return false
	if not data.get("switchable", false) is bool: return false
	if not data.get("medical_action", "") is String: return false
	for key in ["hunger_restore", "thirst_restore", "happiness_effect"]:
		var effect: Variant = data.get(key, 0.0)
		if not (effect is float or effect is int) or not is_finite(float(effect)): return false
	for region in data.get("clothing_regions", []):
		if not region is String: return false
	if not data.get("dimensions") is Vector3 or not data.get("capacity") is Vector3: return false
	if not data["dimensions"].is_finite() or not data["capacity"].is_finite(): return false
	if not data.get("tags") is Array or not data.get("units") is Array or data["units"].is_empty() or data["units"].size() > 4096: return false
	for value in [data.get("weight"), data.get("reduction")]:
		if not (value is float or value is int) or not is_finite(float(value)): return false
	for tag in data["tags"]:
		if not tag is String: return false
	for unit in data["units"]:
		if not unit is Dictionary or not unit.get("uid") is String or not unit.get("flavor") is String: return false
		if not (unit.get("durability") is float or unit.get("durability") is int) or not is_finite(float(unit["durability"])): return false
		if not unit.get("contents") is Array: return false
		for key in ["remaining", "acquired"]:
			var value: Variant = unit.get(key, 1.0 if key == "remaining" else 0.0)
			if not (value is float or value is int) or not is_finite(float(value)): return false
		if float(unit.get("remaining", 1.0)) <= 0 or float(unit.get("remaining", 1.0)) > 1 or float(unit.get("acquired", 0.0)) < 0: return false
		if not unit.get("clothing_durability", {}) is Dictionary or not unit.get("switched_on", false) is bool: return false
		for region in unit.get("clothing_durability", {}):
			var value: Variant = unit["clothing_durability"][region]
			if not region is String or not (value is float or value is int) or not is_finite(float(value)): return false
		for child in unit["contents"]:
			if not valid(child, depth + 1): return false
	return true

static func unpack(data: Dictionary) -> ItemStack:
	var tags: Array[String] = []
	tags.assign(data["tags"])
	var definition := ItemDefinition.new(data["id"], data["name"], data["dimensions"], data["weight"], tags)
	definition.capacity_dimensions = data["capacity"]
	definition.weight_reduction = data["reduction"]
	definition.requires_two_hands = data.get("two_hands", false)
	definition.clothing_slot = data.get("clothing_slot", "")
	definition.clothing_regions.assign(data.get("clothing_regions", []))
	definition.clothing_protection = data.get("clothing_protection", {}).duplicate(true)
	definition.clothing_warmth = data.get("clothing_warmth", {}).duplicate(true)
	definition.clothing_max_durability = data.get("clothing_max_durability", {}).duplicate(true)
	definition.rag_yield = data.get("rag_yield", 0)
	definition.weapon_attack_type = data.get("weapon_attack_type", "")
	definition.weapon_damage = data.get("weapon_damage", 0)
	definition.switchable = data.get("switchable", false)
	definition.hunger_restore = data.get("hunger_restore", 0.0)
	definition.thirst_restore = data.get("thirst_restore", 0.0)
	definition.happiness_effect = data.get("happiness_effect", 0.0)
	definition.medical_action = data.get("medical_action", "")
	var result := ItemStack.new(definition, 0)
	for entry in data["units"]:
		var children: Array = []
		for child in entry["contents"]: children.append(unpack(child))
		result.units.append({"uid": entry["uid"], "flavor": entry["flavor"], "durability": entry["durability"], "contents": children,
			"remaining": entry.get("remaining", 1.0), "acquired": entry.get("acquired", 0.0),
			"clothing_durability": entry.get("clothing_durability", definition.clothing_max_durability).duplicate(true),
			"switched_on": entry.get("switched_on", false)})
	return result
