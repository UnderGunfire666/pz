class_name LocalNavigation
extends RefCounted

## Cached path following shared by NPCs and zombies, including mid-stair restore.
var _path: Array[Dictionary] = []
var _index := 0
var _repath_left := 0.0


func reset() -> void:
	_path.clear()
	_index = 0
	_repath_left = 0.0


func advance(map: WorldMap, pos: Vector2, floor_level: int, stair_id: String,
		target: Vector2, target_floor: int, speed: float, delta: float) -> Dictionary:
	_repath_left -= delta
	if not stair_id.is_empty() and _index >= _path.size():
		# A save never serializes a transient path cache. Resume to a legal landing.
		var link: StairLink = map.stairs.get(stair_id)
		if link != null:
			var go_up := target_floor >= link.to_floor
			_path = [{"position": link.end if go_up else link.start,
				"floor": link.to_floor if go_up else link.from_floor}]
			_index = 0
	if _repath_left <= 0.0 and stair_id.is_empty():
		_path = map.find_path(pos, floor_level, target, target_floor)
		_index = 0
		_repath_left = 0.8
	while _index < _path.size():
		var waypoint := _path[_index]
		var next: Vector2 = waypoint["position"]
		if floor_level == int(waypoint["floor"]) and pos.distance_to(next) < 0.10 and stair_id.is_empty():
			_index += 1
			continue
		var motion := pos.direction_to(next) * minf(speed * delta, pos.distance_to(next))
		return map.move_actor(pos, floor_level, motion, stair_id)
	return {"position": pos, "floor": floor_level, "stair_id": stair_id}
