class_name ContainerData
extends RefCounted

## Furniture capacity is volume only; ground piles are unbounded.
const CABINET_DIMENSIONS := Vector3(50, 50, 100)
var capacity := INF
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


func used_volume() -> float:
	var volume := 0.0
	for stack in contents: volume += stack.total_volume()
	return volume


func contents_weight() -> float:
	var weight := 0.0
	for stack in contents: weight += stack.total_weight()
	return weight
