class_name ZombieAreaDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export_range(0.0, 1.0, 0.01) var pressure := 0.1
## Vector3(x, y, floor). These are authored legal stand/migration destinations.
@export var population_points: PackedVector3Array = []
@export var adjacent_area_ids: PackedStringArray = []


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty(): errors.append("zombie area id is empty")
	if display_name.is_empty(): errors.append("zombie area %s has no display name" % id)
	if pressure < 0.0 or pressure > 1.0: errors.append("zombie area %s pressure is outside 0..1" % id)
	if population_points.is_empty(): errors.append("zombie area %s has no population points" % id)
	return errors
