class_name SkillDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export var category := ""
@export var max_level := 10
@export var xp_per_level: PackedFloat32Array = []
@export var passive := false
@export var physical_attribute := false


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty(): errors.append("skill id is empty")
	if display_name.is_empty(): errors.append("skill %s has no display name" % id)
	if max_level <= 0 or xp_per_level.size() != max_level:
		errors.append("skill %s needs one XP threshold per level" % id)
	for value in xp_per_level:
		if value <= 0.0: errors.append("skill %s has a non-positive XP threshold" % id)
	return errors
