class_name StairLink
extends RefCounted

## A traversable surface joining two landings. XY footprint alone never changes
## an actor's elevation: the actor must own this link while traversing it.
var id: String
var building_id: String
var start: Vector2
var end: Vector2
var from_floor: int
var to_floor: int
var width: float
const LANDING_LENGTH := 0.30


func _init(
		p_id: String = "",
		p_building_id: String = "",
		p_start: Vector2 = Vector2.ZERO,
		p_end: Vector2 = Vector2.ONE,
		p_from_floor: int = 0,
		p_to_floor: int = 1,
		p_width: float = 0.8
	) -> void:
	id = p_id
	building_id = p_building_id
	start = p_start
	end = p_end
	from_floor = p_from_floor
	to_floor = p_to_floor
	width = p_width


func direction() -> Vector2:
	return (end - start).normalized()


func length() -> float:
	return start.distance_to(end)


func progress_at(position: Vector2) -> float:
	return clampf((position - start).dot(direction()) / maxf(length(), 0.001), 0.0, 1.0)


func contains(position: Vector2, margin: float = 0.0) -> bool:
	var offset := position - start
	var along := offset.dot(direction())
	var across := absf(offset.cross(direction()))
	return along >= 0.0 and along <= length() and across < width * 0.5 + margin
