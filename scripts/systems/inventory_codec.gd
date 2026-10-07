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
			"switched_on": unit.get("switched_on", false), "freshness": unit.get("freshness", 100.0),
			"temperature": unit.get("temperature", StatusConfig.ambient_temperature_at(GameTime.elapsed_game_seconds)),
			"opened": unit.get("opened", not item.requires_opening), "cooking_state": unit.get("cooking_state", item.default_cooking_state),
			"liquid_ml": unit.get("liquid_ml", item.liquid_capacity_ml),
			"bandage_absorption": unit.get("bandage_absorption", 0.0),
			"bandage_disinfected": unit.get("bandage_disinfected", false),
			"appearance": unit.get("appearance", item.appearance_variants[0] if not item.appearance_variants.is_empty() else "default")})
	return {"id": item.id, "name": item.display_name, "dimensions": item.dimensions,
		"capacity": item.capacity_dimensions, "weight": item.unit_weight, "reduction": item.weight_reduction,
		"tags": item.tags.duplicate(), "two_hands": item.requires_two_hands, "units": units,
		"clothing_slot": item.clothing_slot, "clothing_regions": item.clothing_regions.duplicate(),
		"clothing_gender": item.clothing_gender, "outfit_group": item.outfit_group,
		"clothing_protection": item.clothing_protection.duplicate(true),
		"clothing_warmth": item.clothing_warmth.duplicate(true),
		"clothing_max_durability": item.clothing_max_durability.duplicate(true), "rag_yield": item.rag_yield,
		"weapon_attack_type": item.weapon_attack_type, "weapon_damage": item.weapon_damage,
		"weapon_hitbox_size": item.weapon_hitbox_size,
		"switchable": item.switchable, "hunger_restore": item.hunger_restore,
		"thirst_restore": item.thirst_restore, "happiness_effect": item.happiness_effect,
		"medical_action": item.medical_action, "calories": item.calories,
		"freshness_lifetime_days": item.freshness_lifetime_days, "requires_opening": item.requires_opening,
		"liquid_capacity_ml": item.liquid_capacity_ml, "empty_container_id": item.empty_container_id,
		"cooking_state_supported": item.cooking_state_supported, "default_cooking_state": item.default_cooking_state,
		"edible_frozen": item.edible_frozen, "consumption_rate_per_game_minute": item.consumption_rate_per_game_minute,
		"appearance_variants": item.appearance_variants.duplicate()}

static func valid(data: Variant, depth: int = 0) -> bool:
	if depth > 16 or not data is Dictionary: return false
	if not data.get("id") is String or not data.get("name") is String: return false
	if not data.get("two_hands", false) is bool: return false
	if not data.get("clothing_slot", "") is String or not data.get("clothing_regions", []) is Array: return false
	if data.get("clothing_gender", "") not in ["", "male", "female"] or not data.get("outfit_group", "") is String: return false
	if ClothingCatalog.SOURCES.has(data["id"]) and data.get("clothing_gender", "") != ClothingCatalog.definition(data["id"]).clothing_gender: return false
	for key in ["clothing_protection", "clothing_warmth", "clothing_max_durability"]:
		if not data.get(key, {}) is Dictionary: return false
		for region in data.get(key, {}):
			var value: Variant = data[key][region]
			if not region is String or not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0: return false
	if not data.get("rag_yield", 0) is int or int(data.get("rag_yield", 0)) < 0: return false
	if not data.get("weapon_attack_type", "") is String or not data.get("weapon_damage", 0) is int or int(data.get("weapon_damage", 0)) < 0: return false
	if not data.get("switchable", false) is bool: return false
	if not data.get("weapon_hitbox_size", Vector3.ZERO) is Vector3 or not data.get("weapon_hitbox_size", Vector3.ZERO).is_finite(): return false
	if not data.get("medical_action", "") is String: return false
	if not data.get("empty_container_id", "") is String or not data.get("default_cooking_state", "raw") in ["raw", "cooked", "burnt"]: return false
	if not data.get("requires_opening", false) is bool or not data.get("cooking_state_supported", false) is bool or not data.get("edible_frozen", false) is bool: return false
	if not data.get("appearance_variants", []) is Array: return false
	for key in ["hunger_restore", "thirst_restore", "happiness_effect", "calories", "freshness_lifetime_days", "liquid_capacity_ml", "consumption_rate_per_game_minute"]:
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
		if not unit.get("opened", true) is bool or not unit.get("bandage_disinfected", false) is bool or not unit.get("appearance", "default") is String: return false
		if unit.get("cooking_state", "raw") not in ["raw", "cooked", "burnt"]: return false
		for key in ["freshness", "temperature", "liquid_ml", "bandage_absorption"]:
			var state_value: Variant = unit.get(key, 100.0 if key == "freshness" else 0.0)
			if not (state_value is float or state_value is int) or not is_finite(float(state_value)): return false
		if float(unit.get("freshness", 100.0)) < 0.0 or float(unit.get("freshness", 100.0)) > 100.0 or float(unit.get("liquid_ml", 0.0)) < 0.0 or float(unit.get("bandage_absorption", 0.0)) < 0.0: return false
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
	definition.clothing_gender = data.get("clothing_gender", "")
	definition.outfit_group = data.get("outfit_group", "")
	definition.clothing_regions.assign(data.get("clothing_regions", []))
	definition.clothing_protection = data.get("clothing_protection", {}).duplicate(true)
	definition.clothing_warmth = data.get("clothing_warmth", {}).duplicate(true)
	definition.clothing_max_durability = data.get("clothing_max_durability", {}).duplicate(true)
	definition.rag_yield = data.get("rag_yield", 0)
	definition.weapon_attack_type = data.get("weapon_attack_type", "")
	definition.weapon_damage = data.get("weapon_damage", 0)
	definition.weapon_hitbox_size = data.get("weapon_hitbox_size", Vector3.ZERO)
	definition.switchable = data.get("switchable", false)
	definition.hunger_restore = data.get("hunger_restore", 0.0)
	definition.thirst_restore = data.get("thirst_restore", 0.0)
	definition.happiness_effect = data.get("happiness_effect", 0.0)
	definition.medical_action = data.get("medical_action", "")
	definition.calories = data.get("calories", 0.0)
	definition.freshness_lifetime_days = data.get("freshness_lifetime_days", 0.0)
	definition.requires_opening = data.get("requires_opening", false)
	definition.liquid_capacity_ml = data.get("liquid_capacity_ml", 0.0)
	definition.empty_container_id = data.get("empty_container_id", "")
	definition.cooking_state_supported = data.get("cooking_state_supported", false)
	definition.default_cooking_state = data.get("default_cooking_state", "raw")
	definition.edible_frozen = data.get("edible_frozen", false)
	definition.consumption_rate_per_game_minute = data.get("consumption_rate_per_game_minute", 0.0)
	definition.appearance_variants.assign(data.get("appearance_variants", []))
	var result := ItemStack.new(definition, 0)
	for entry in data["units"]:
		var children: Array = []
		for child in entry["contents"]: children.append(unpack(child))
		result.units.append({"uid": entry["uid"], "flavor": entry["flavor"], "durability": entry["durability"], "contents": children,
			"remaining": entry.get("remaining", 1.0), "acquired": entry.get("acquired", 0.0),
			"clothing_durability": entry.get("clothing_durability", definition.clothing_max_durability).duplicate(true),
			"switched_on": entry.get("switched_on", false), "freshness": entry.get("freshness", 100.0),
			"temperature": entry.get("temperature", StatusConfig.ambient_temperature_at(GameTime.elapsed_game_seconds)),
			"opened": entry.get("opened", not definition.requires_opening), "cooking_state": entry.get("cooking_state", definition.default_cooking_state),
			"liquid_ml": entry.get("liquid_ml", definition.liquid_capacity_ml),
			"bandage_absorption": entry.get("bandage_absorption", 0.0),
			"bandage_disinfected": entry.get("bandage_disinfected", false),
			"appearance": entry.get("appearance", definition.appearance_variants[0] if not definition.appearance_variants.is_empty() else "default")})
	return result
