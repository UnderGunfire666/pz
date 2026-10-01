@tool
class_name MapIndoorFloorDefinition
extends Resource

## A rectangular indoor surface.  In a MapDefinition coordinates are global;
## when owned by a MapBuildingTemplate they are template-local.
@export var id := ""
@export var rect := Rect2i()
@export var level := 0
@export var room_id := ""
@export var building_id := ""
@export var safehouse := false
@export var terrain: MapTerrainDefinition
@export_range(0.0, 1.0, 0.01) var zombie_pressure := 0.1
