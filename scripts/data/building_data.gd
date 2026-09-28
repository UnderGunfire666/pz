class_name BuildingData
extends RefCounted

var id: String
var name: String
var bounds: Rect2i
var zone_type: String
var pressure: float
var safehouse: bool
var floor_count := 1
var floor_ids: Array[int] = []
var stair_ids: Array[String] = []
var rooms: Array[RoomData] = []


func _init(
		p_id: String,
		p_name: String,
		p_bounds: Rect2i,
		p_zone_type: String,
		p_pressure: float,
		p_safehouse: bool = false
	) -> void:
	id = p_id
	name = p_name
	bounds = p_bounds
	zone_type = p_zone_type
	pressure = p_pressure
	safehouse = p_safehouse


func add_room(room: RoomData) -> void:
	rooms.append(room)
	if not floor_ids.has(room.floor_level):
		floor_ids.append(room.floor_level)
		floor_count = floor_ids.size()
