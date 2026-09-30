class_name CharacterCatalog
extends RefCounted

const SKILL_PATH := "res://resources/character/skills"
const TRAIT_PATH := "res://resources/character/traits"
const OCCUPATION_PATH := "res://resources/character/occupations"
const RULES_PATH := "res://resources/character/world_rules.tres"
const SUPPORTED_EFFECT_IDS := [
	"starting_skill_levels",
	"attribute_level_trait",
	"global_xp_multiplier_1_3",
	"global_xp_multiplier_0_7",
	"combat_xp_multiplier_0_75",
	"crafting_xp_multiplier_1_3",
]

var skills: Dictionary = {}
var traits: Dictionary = {}
var occupations: Dictionary = {}
var rules: CharacterWorldRules
var _load_errors: Array[String] = []


func _init() -> void:
	rules = load(RULES_PATH) as CharacterWorldRules
	_load_directory(SKILL_PATH, SkillDefinition, skills)
	_load_directory(TRAIT_PATH, TraitDefinition, traits)
	_load_directory(OCCUPATION_PATH, OccupationDefinition, occupations)


func _load_directory(path: String, expected_type: Variant, destination: Dictionary) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	var files := directory.get_files()
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".tres"): continue
		var definition: Resource = load(path.path_join(file_name))
		if is_instance_of(definition, expected_type):
			var id := String(definition.get("id"))
			if destination.has(id):
				_load_errors.append("duplicate definition id %s" % id)
			else:
				destination[id] = definition


func validate() -> Array[String]:
	var errors: Array[String] = _load_errors.duplicate()
	if rules == null: errors.append("missing character world rules")
	_validate_definitions(skills, errors)
	_validate_definitions(traits, errors)
	_validate_definitions(occupations, errors)
	for trait_definition: TraitDefinition in traits.values():
		for skill_id in trait_definition.xp_boosts:
			if not skills.has(skill_id): errors.append("trait %s references missing skill %s" % [trait_definition.id, skill_id])
		for other_id in trait_definition.incompatible_trait_ids:
			if not traits.has(other_id): errors.append("trait %s references missing incompatibility %s" % [trait_definition.id, other_id])
		for granted_id in trait_definition.granted_trait_ids:
			if not traits.has(granted_id): errors.append("trait %s grants missing trait %s" % [trait_definition.id, granted_id])
		for effect_id in trait_definition.effect_ids:
			if not effect_id in SUPPORTED_EFFECT_IDS:
				errors.append("trait %s references unsupported active effect %s" % [trait_definition.id, effect_id])
		for pending_id in trait_definition.pending_effect_ids:
			if pending_id.is_empty(): errors.append("trait %s has an empty pending effect" % trait_definition.id)
	for occupation: OccupationDefinition in occupations.values():
		for skill_id in occupation.xp_boosts:
			if not skills.has(skill_id): errors.append("occupation %s references missing skill %s" % [occupation.id, skill_id])
		for trait_id in occupation.granted_trait_ids:
			if not traits.has(trait_id): errors.append("occupation %s grants missing trait %s" % [occupation.id, trait_id])
	return errors


func _validate_definitions(definitions: Dictionary, errors: Array[String]) -> void:
	for id in definitions:
		var definition: Resource = definitions[id]
		if id != definition.get("id"): errors.append("catalog key mismatch for %s" % id)
		errors.append_array(definition.call("validation_errors"))


func skill(id: String) -> SkillDefinition:
	return skills.get(id) as SkillDefinition


func trait_definition(id: String) -> TraitDefinition:
	return traits.get(id) as TraitDefinition


func occupation(id: String) -> OccupationDefinition:
	return occupations.get(id) as OccupationDefinition
