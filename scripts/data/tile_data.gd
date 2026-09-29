class_name WorldTileData
extends RefCounted

## Runtime metadata for one logical world tile. Rendering is intentionally separate
## from gameplay data so this can later be backed by a TileMap/terrain importer.
var kind: String
var walkable: bool
var zombie_pressure: float
var building_id: String
var room_id: String
var is_safehouse: bool
var floor_level: int


func _init(
		p_kind: String = "grass",
		p_walkable: bool = true,
		p_zombie_pressure: float = 0.1,
		p_building_id: String = "",
		p_room_id: String = "",
		p_is_safehouse: bool = false,
		p_floor_level: int = 0
	) -> void:
	kind = p_kind
	walkable = p_walkable
	zombie_pressure = p_zombie_pressure
	building_id = p_building_id
	room_id = p_room_id
	is_safehouse = p_is_safehouse
	floor_level = p_floor_level
