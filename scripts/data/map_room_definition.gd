@tool
class_name MapRoomDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export_enum("residential", "commercial", "storage", "bedroom", "kitchen", "hallway") var room_type := "residential"
@export var floor_level := 0
@export var bounds := Rect2i()
@export var manually_corrected := false
