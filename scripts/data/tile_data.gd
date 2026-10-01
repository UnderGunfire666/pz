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
## `kind` is the currently visible/walkable surface recipe.  The fields below
## retain the layer information that used to be lost when a road or building
## overwrote a terrain tile during map loading.
var base_kind: String
var base_walkable: bool
var overlay_kind: String
var occupancy_kind: String
var occupancy_id: String


func _init(
		p_kind: String = "grass",
		p_walkable: bool = true,
		p_zombie_pressure: float = 0.1,
		p_building_id: String = "",
		p_room_id: String = "",
		p_is_safehouse: bool = false,
		p_floor_level: int = 0,
		p_base_kind: String = "",
		p_base_walkable: bool = true,
		p_overlay_kind: String = "",
		p_occupancy_kind: String = "",
		p_occupancy_id: String = ""
	) -> void:
	kind = p_kind
	walkable = p_walkable
	zombie_pressure = p_zombie_pressure
	building_id = p_building_id
	room_id = p_room_id
	is_safehouse = p_is_safehouse
	floor_level = p_floor_level
	base_kind = p_base_kind if not p_base_kind.is_empty() else p_kind
	base_walkable = p_base_walkable
	overlay_kind = p_overlay_kind
	occupancy_kind = p_occupancy_kind
	occupancy_id = p_occupancy_id


func is_water() -> bool:
	return base_kind == "water"


func is_occupied() -> bool:
	return not occupancy_id.is_empty()


func set_overlay(p_kind: String, p_walkable: bool, p_occupancy_kind: String,
		p_occupancy_id: String) -> void:
	kind = p_kind
	walkable = p_walkable
	overlay_kind = p_kind
	occupancy_kind = p_occupancy_kind
	occupancy_id = p_occupancy_id
