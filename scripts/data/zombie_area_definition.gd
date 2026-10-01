class_name ZombieAreaDefinition
extends Resource

@export var id := ""
@export var display_name := ""
## Legacy pressure is retained solely to migrate old area resources. Initial
## spawning now reads MapDefinition heat values instead.
@export_range(0.0, 1.0, 0.01) var pressure := 0.1
## A migration-only preference. A negative value falls back to legacy pressure
## so existing .tres files remain valid until explicitly migrated.
@export_range(-1.0, 1.0, 0.01) var migration_attraction := -1.0
## Vector3(x, y, floor). These are authored legal migration destinations.
@export var population_points: PackedVector3Array = []
@export var adjacent_area_ids: PackedStringArray = []


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty(): errors.append("zombie area id is empty")
	if display_name.is_empty(): errors.append("zombie area %s has no display name" % id)
	if pressure < 0.0 or pressure > 1.0: errors.append("zombie area %s pressure is outside 0..1" % id)
	if migration_attraction < -1.0 or migration_attraction > 1.0: errors.append("zombie area %s has invalid migration attraction" % id)
	if population_points.is_empty(): errors.append("zombie area %s has no population points" % id)
	return errors


func migration_weight() -> float:
	return migration_attraction if migration_attraction >= 0.0 else pressure
