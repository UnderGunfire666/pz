class_name CharacterProgression
extends RefCounted

signal changed()

const STRENGTH_TRAITS := ["base:weak", "base:feeble", "base:stout", "base:strong"]
const FITNESS_TRAITS := ["base:unfit", "base:out of shape", "base:fit", "base:athletic"]

var catalog: CharacterCatalog
var occupation_id := "base:unemployed"
var selected_trait_ids: Array[String] = []
var granted_trait_ids: Array[String] = []
var skill_xp: Dictionary = {}
var skill_levels: Dictionary = {}
var creation_complete := false


func setup(p_catalog: CharacterCatalog, p_occupation_id: String = "") -> void:
	catalog = p_catalog
	occupation_id = p_occupation_id if not p_occupation_id.is_empty() else catalog.rules.default_occupation_id
	rebuild_starting_state()


func point_balance(trait_ids: Array[String] = selected_trait_ids, profession_id: String = occupation_id) -> int:
	var occupation := catalog.occupation(profession_id)
	var balance := catalog.rules.free_trait_points + (occupation.point_bonus if occupation != null else 0)
	for trait_id in trait_ids:
		var definition := catalog.trait_definition(trait_id)
		if definition != null and definition.selectable: balance -= definition.cost
	return balance


func selection_errors(trait_ids: Array[String] = selected_trait_ids, profession_id: String = occupation_id) -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	var all_ids: Array[String] = []
	var occupation := catalog.occupation(profession_id)
	if occupation == null:
		errors.append("unknown occupation %s" % profession_id)
		return errors
	for trait_id in trait_ids:
		var definition := catalog.trait_definition(trait_id)
		if definition == null or not definition.selectable:
			errors.append("trait %s is not selectable" % trait_id)
		elif seen.has(trait_id):
			errors.append("trait %s was selected twice" % trait_id)
		else:
			seen[trait_id] = true
			all_ids.append(trait_id)
	for granted_id in occupation.granted_trait_ids:
		if not granted_id in all_ids: all_ids.append(granted_id)
	for trait_id in all_ids:
		var definition := catalog.trait_definition(trait_id)
		if definition == null: continue
		for incompatible_id in definition.incompatible_trait_ids:
			if incompatible_id in all_ids and trait_id < incompatible_id:
				errors.append("traits %s and %s are incompatible" % [trait_id, incompatible_id])
	if point_balance(trait_ids, profession_id) < 0: errors.append("trait build overspends available points")
	return errors


func select_build(profession_id: String, trait_ids: Array[String]) -> Array[String]:
	if creation_complete: return ["character creation is already complete"]
	var errors := selection_errors(trait_ids, profession_id)
	if not errors.is_empty(): return errors
	occupation_id = profession_id
	selected_trait_ids = trait_ids.duplicate()
	rebuild_starting_state()
	creation_complete = true
	changed.emit()
	return []


func rebuild_starting_state() -> void:
	granted_trait_ids.clear()
	skill_levels.clear()
	skill_xp.clear()
	var occupation := catalog.occupation(occupation_id)
	if occupation != null:
		for id in occupation.granted_trait_ids:
			if not id in granted_trait_ids: granted_trait_ids.append(id)
	var all_traits := _creation_trait_ids()
	for trait_id in all_traits:
		var trait_definition := catalog.trait_definition(trait_id)
		if trait_definition == null: continue
		for granted_id in trait_definition.granted_trait_ids:
			if not granted_id in granted_trait_ids: granted_trait_ids.append(granted_id)
	var boosts := starting_boosts()
	for skill_id in catalog.skills:
		var definition := catalog.skill(skill_id)
		var base_level := 5 if definition.physical_attribute else 0
		var level := clampi(base_level + int(boosts.get(skill_id, 0)), 0, definition.max_level)
		skill_levels[skill_id] = level
		skill_xp[skill_id] = total_xp_for_level(definition, level)


func active_trait_ids() -> Array[String]:
	var result: Array[String] = []
	for id in selected_trait_ids:
		if not id in STRENGTH_TRAITS and not id in FITNESS_TRAITS: result.append(id)
	for id in granted_trait_ids:
		if not id in STRENGTH_TRAITS and not id in FITNESS_TRAITS and not id in result: result.append(id)
	if not skill_levels.is_empty():
		var strength_trait := _attribute_trait("Strength", STRENGTH_TRAITS)
		var fitness_trait := _attribute_trait("Fitness", FITNESS_TRAITS)
		if not strength_trait.is_empty(): result.append(strength_trait)
		if not fitness_trait.is_empty(): result.append(fitness_trait)
	return result


func has_trait(id: String) -> bool:
	return id in active_trait_ids()


func _attribute_trait(skill_id: String, family: Array) -> String:
	var level := int(skill_levels.get(skill_id, 5))
	if level <= 1: return String(family[0])
	if level <= 4: return String(family[1])
	if level <= 5: return ""
	if level <= 8: return String(family[2])
	return String(family[3])


func _creation_trait_ids() -> Array[String]:
	var result := selected_trait_ids.duplicate()
	for id in granted_trait_ids:
		if not id in result: result.append(id)
	return result


func starting_boosts() -> Dictionary:
	var result := {}
	var occupation := catalog.occupation(occupation_id)
	if occupation != null: _merge_boosts(result, occupation.xp_boosts)
	for trait_id in _creation_trait_ids():
		var trait_definition := catalog.trait_definition(trait_id)
		if trait_definition != null: _merge_boosts(result, trait_definition.xp_boosts)
	return result


func _merge_boosts(target: Dictionary, source: Dictionary) -> void:
	for skill_id in source: target[skill_id] = int(target.get(skill_id, 0)) + int(source[skill_id])


func xp_multiplier(skill_id: String) -> float:
	var definition := catalog.skill(skill_id)
	if definition == null or definition.physical_attribute: return 1.0
	var boost := int(starting_boosts().get(skill_id, 0))
	var multiplier := 0.25 if boost <= 0 else (1.0 if boost == 1 else (1.33 if boost == 2 else 1.66))
	if has_trait("base:fastlearner"): multiplier *= 1.3
	if has_trait("base:slowlearner"): multiplier *= 0.7
	if has_trait("base:pacifist") and definition.category in ["Combat", "Firearms"]: multiplier *= 0.75
	if has_trait("base:crafty") and definition.category == "Crafting": multiplier *= 1.3
	return multiplier


func add_skill_xp(skill_id: String, raw_amount: float) -> float:
	var definition := catalog.skill(skill_id)
	if definition == null or raw_amount <= 0.0: return 0.0
	var amount := raw_amount * xp_multiplier(skill_id)
	var maximum := total_xp_for_level(definition, definition.max_level)
	skill_xp[skill_id] = clampf(float(skill_xp.get(skill_id, 0.0)) + amount, 0.0, maximum)
	skill_levels[skill_id] = level_for_xp(definition, float(skill_xp[skill_id]))
	changed.emit()
	return amount


static func total_xp_for_level(definition: SkillDefinition, level: int) -> float:
	var total := 0.0
	for index in range(clampi(level, 0, definition.max_level)): total += definition.xp_per_level[index]
	return total


static func level_for_xp(definition: SkillDefinition, xp: float) -> int:
	var total := 0.0
	for index in range(definition.max_level):
		total += definition.xp_per_level[index]
		if xp + 0.0001 < total: return index
	return definition.max_level


func to_save_data() -> Dictionary:
	return {"occupation_id": occupation_id, "selected_trait_ids": selected_trait_ids.duplicate(),
		"granted_trait_ids": granted_trait_ids.duplicate(), "skill_xp": skill_xp.duplicate(),
		"skill_levels": skill_levels.duplicate(), "creation_complete": creation_complete}


func load_save_data(data: Dictionary) -> bool:
	if not valid_save_data(data, catalog): return false
	occupation_id = data["occupation_id"]
	selected_trait_ids.assign(data["selected_trait_ids"])
	granted_trait_ids.assign(data["granted_trait_ids"])
	skill_xp = data["skill_xp"].duplicate()
	skill_levels = data["skill_levels"].duplicate()
	creation_complete = data["creation_complete"]
	changed.emit()
	return true


static func valid_save_data(data: Variant, catalog_value: CharacterCatalog) -> bool:
	if not data is Dictionary or not data.has_all(["occupation_id", "selected_trait_ids", "granted_trait_ids", "skill_xp", "skill_levels", "creation_complete"]): return false
	if not data["occupation_id"] is String or catalog_value.occupation(data["occupation_id"]) == null: return false
	if not data["selected_trait_ids"] is Array or not data["granted_trait_ids"] is Array or not data["creation_complete"] is bool: return false
	for value in data["selected_trait_ids"]:
		if not value is String: return false
	var selected: Array[String] = []
	selected.assign(data["selected_trait_ids"])
	var verifier := CharacterProgression.new()
	verifier.setup(catalog_value)
	if not verifier.selection_errors(selected, data["occupation_id"]).is_empty(): return false
	verifier.occupation_id = data["occupation_id"]
	verifier.selected_trait_ids = selected
	verifier.rebuild_starting_state()
	var granted_seen: Dictionary = {}
	for id in data["granted_trait_ids"]:
		if not id is String: return false
		if granted_seen.has(id): return false
		granted_seen[id] = true
		var definition := catalog_value.trait_definition(id)
		if definition == null or (not id in verifier.granted_trait_ids and not definition.can_change_during_play): return false
	if not data["skill_xp"] is Dictionary or not data["skill_levels"] is Dictionary: return false
	for id in catalog_value.skills:
		if not data["skill_xp"].get(id) is float and not data["skill_xp"].get(id) is int: return false
		if not data["skill_levels"].get(id) is int: return false
		var definition := catalog_value.skill(id)
		var xp := float(data["skill_xp"][id])
		var level := int(data["skill_levels"][id])
		if not is_finite(xp) or xp < 0.0 or xp > total_xp_for_level(definition, definition.max_level): return false
		if level != level_for_xp(definition, xp): return false
	return true
