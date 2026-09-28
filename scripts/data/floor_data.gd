class_name FloorData
extends RefCounted

## Sparse logical tiles: absent cells are unsupported space, not outdoor grass.
var level: int
var tiles: Dictionary = {}
var wall_faces: Array[Dictionary] = []
var rooms: Array[RoomData] = []


func _init(p_level: int = 0) -> void:
	level = p_level


func tile_at(cell: Vector2i) -> WorldTileData:
	return tiles.get(cell) as WorldTileData
