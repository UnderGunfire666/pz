class_name OccupationDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var point_bonus := 0
@export var xp_boosts: Dictionary = {}
@export var granted_trait_ids: PackedStringArray = []
@export var granted_recipe_ids: PackedStringArray = []
@export var pending_effect_ids: PackedStringArray = []


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty(): errors.append("occupation id is empty")
	if display_name.is_empty(): errors.append("occupation %s has no display name" % id)
	for skill_id in xp_boosts:
		if not skill_id is String or not xp_boosts[skill_id] is int:
			errors.append("occupation %s has an invalid skill boost" % id)
	return errors
