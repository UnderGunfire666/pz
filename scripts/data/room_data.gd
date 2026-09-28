class_name RoomData
extends RefCounted

var id: String
var name: String
var bounds: Rect2i
var tags: Array[String]
var floor_level: int


func _init(p_id: String, p_name: String, p_bounds: Rect2i, p_tags: Array[String] = [], p_floor_level: int = 0) -> void:
	id = p_id
	name = p_name
	bounds = p_bounds
	tags = p_tags
	floor_level = p_floor_level
