@tool
class_name MapBuildingTemplate
extends Resource

## Static reusable grid template. Instances inherit these values unless an
## explicit local override is authored on the instance.
@export var id := ""
@export var display_name := ""
@export var footprint := Vector2i(1, 1)
@export var floor_count := 1
@export var door_local_cell := Vector2i(-1, -1)
@export_enum("residential", "commercial", "industrial") var zone_type := "residential"
@export var rooms: Array[MapRoomDefinition] = []
@export var indoor_floors: Array[MapIndoorFloorDefinition] = []
@export var wall_edges: Array[MapWallEdgeDefinition] = []
@export var has_roof := true
@export var explicit_layout := false
@export var stairs: Array[MapStairDefinition] = []
