@tool
class_name MapDefinition
extends Resource

## Canonical immutable static map source. Runtime mutations belong in saves.
@export var id := ""
@export var display_name := ""
@export var format_version := 2
@export var cell_size := Vector2i(64, 64)
@export_range(0.1, 20.0, 0.01) var default_floor_spacing := 3.0
@export var cells: Array[MapCellDefinition] = []
@export var buildings: Array[MapBuildingInstanceDefinition] = []
@export var wall_edges: Array[MapWallEdgeDefinition] = []
@export var roads: Array[MapRoadDefinition] = []
@export var indoor_floors: Array[MapIndoorFloorDefinition] = []
@export var zones: Array[MapZoneDefinition] = []
@export var stairs: Array[MapStairDefinition] = []
@export var decorations: Array[MapDecorationDefinition] = []
@export var player_spawn := Vector2(4.45, 6.65)
@export var npc_spawn := Vector2(4.4, 10.3)


func logical_to_world(position: Vector2, level: int = 0) -> Vector3:
	return Vector3(position.x, float(level) * default_floor_spacing, position.y)


func world_to_logical(position: Vector3) -> Vector2:
	return Vector2(position.x, position.z)
