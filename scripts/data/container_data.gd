class_name ContainerData
extends RefCounted

## Known contents can be viewed immediately after a container has been searched.
## The first deliberate search takes game time and is handled by InteractionSystem.
var id: String
var display_name: String
var contents: Array[ItemStack] = []
var searched: bool = false
var claimed_by: String = ""
var search_progress_seconds := 0.0


func _init(p_id: String, p_display_name: String, p_contents: Array[ItemStack] = []) -> void:
	id = p_id
	display_name = p_display_name
	contents = p_contents


func is_empty() -> bool:
	return contents.is_empty()
