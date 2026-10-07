class_name ContainerData
extends RefCounted

## Furniture capacity is volume only; ground piles are unbounded.
const CABINET_DIMENSIONS := Vector3(50, 50, 100)
const CABINET_SIZE := Vector3(0.5, 1.0, 0.5)
const CLOSED_COLOR := Color("a7adb4")
const OPEN_COLOR := Color("70b98b")
var is_open := false
var capacity := INF
var id: String
var display_name: String
var contents: Array[ItemStack] = []
var searched: bool = false
var claimed_by: String = ""
var search_progress_seconds := 0.0
## Simulation seconds; 72 equals 3 real seconds at normal game speed.
var search_duration_game_seconds := 72.0
## Cooling setpoint, not a heater. NaN follows ambient temperature.
var temperature_target := NAN

func effective_temperature(ambient: float) -> float:
	return minf(temperature_target, ambient) if is_finite(temperature_target) else ambient


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
