class_name ZombieAreaCatalog
extends RefCounted

const AREA_PATH := "res://resources/zombie/areas"
const RULES_PATH := "res://resources/zombie/world_rules.tres"

var areas: Dictionary = {}
var rules: ZombieWorldRules
var _load_errors: Array[String] = []


func _init() -> void:
	rules = load(RULES_PATH) as ZombieWorldRules
	var directory := DirAccess.open(AREA_PATH)
	if directory == null:
		_load_errors.append("missing zombie area directory")
		return
	var files := directory.get_files()
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".tres"): continue
		var definition := load(AREA_PATH.path_join(file_name)) as ZombieAreaDefinition
		if definition == null: continue
		if areas.has(definition.id):
			_load_errors.append("duplicate zombie area id %s" % definition.id)
		else:
			areas[definition.id] = definition


func validate(map: WorldMap = null) -> Array[String]:
	var errors := _load_errors.duplicate()
	if rules == null: errors.append("missing zombie world rules")
	for definition: ZombieAreaDefinition in areas.values():
		errors.append_array(definition.validation_errors())
		for adjacent_id in definition.adjacent_area_ids:
			if not areas.has(adjacent_id): errors.append("zombie area %s references missing neighbour %s" % [definition.id, adjacent_id])
		for point in definition.population_points:
			if map != null and not map.can_stand(Vector2(point.x, point.y), int(point.z)):
				errors.append("zombie area %s has invalid population point %s" % [definition.id, point])
	return errors


func area(id: String) -> ZombieAreaDefinition:
	return areas.get(id) as ZombieAreaDefinition
