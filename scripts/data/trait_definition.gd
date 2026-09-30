class_name TraitDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var cost := 0
@export var selectable := false
@export var profession_trait := false
@export var disabled_in_multiplayer := false
@export var xp_boosts: Dictionary = {}
@export var incompatible_trait_ids: PackedStringArray = []
@export var granted_trait_ids: PackedStringArray = []
@export var granted_recipe_ids: PackedStringArray = []
@export var effect_ids: PackedStringArray = []
@export var pending_effect_ids: PackedStringArray = []
@export var can_change_during_play := false


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty(): errors.append("trait id is empty")
	if display_name.is_empty(): errors.append("trait %s has no display name" % id)
	if selectable and (profession_trait or cost == 0):
		errors.append("selectable trait %s must be non-free and non-profession" % id)
	for skill_id in xp_boosts:
		if not skill_id is String or not xp_boosts[skill_id] is int:
			errors.append("trait %s has an invalid skill boost" % id)
	return errors
