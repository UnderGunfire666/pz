@tool
class_name MapBuildingInstanceDefinition
extends Resource

## Direct values remain a compatibility fallback for older map resources. A
## template instance receives later template edits until a local override exists.
@export var id := ""
@export var display_name := ""
@export var template: MapBuildingTemplate
@export var origin := Vector2i.ZERO
@export var local_footprint_override := Vector2i.ZERO
@export var local_floor_count_override := -1
@export var local_door_override := Vector2i(-1, -1)
@export var bounds := Rect2i()
@export var floor_count := 1
@export var door_cell := Vector2i(-1, -1)
@export_enum("residential", "commercial", "industrial") var zone_type := "residential"
@export_range(0.0, 1.0, 0.01) var zombie_pressure := 0.1
@export var safehouse := false


func effective_bounds() -> Rect2i:
	if template != null:
		var size := local_footprint_override if local_footprint_override.x > 0 and local_footprint_override.y > 0 else template.footprint
		return Rect2i(origin, size)
	return bounds


func effective_floor_count() -> int:
	return local_floor_count_override if local_floor_count_override > 0 else (template.floor_count if template != null else floor_count)


func effective_door_cell() -> Vector2i:
	if local_door_override.x >= 0 and local_door_override.y >= 0:
		return origin + local_door_override
	return origin + template.door_local_cell if template != null else door_cell


func effective_display_name() -> String:
	return display_name if not display_name.is_empty() else (template.display_name if template != null else id)


func effective_zone_type() -> String:
	return template.zone_type if template != null else zone_type
