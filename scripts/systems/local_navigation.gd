class_name LocalNavigation
extends RefCounted

## Cached path following shared by NPCs and zombies, including mid-stair restore.
var _path: Array[Dictionary] = []
var _index := 0
var _retry_left := 0.0
var _planned_target := Vector2(INF, INF)
var _planned_floor := -999
var _planned_world_revision := -1
var _path_build_count := 0
const TARGET_REPATH_DISTANCE := 0.35
const UNREACHABLE_RETRY_SECONDS := 0.8
const WAYPOINT_ARRIVAL_DISTANCE := 0.18


func reset() -> void:
	_path.clear()
	_index = 0
	_retry_left = 0.0
	_planned_target = Vector2(INF, INF)
	_planned_floor = -999
	_planned_world_revision = -1


func advance(map: WorldMap, pos: Vector2, floor_level: int, stair_id: String,
		target: Vector2, target_floor: int, speed: float, delta: float) -> Dictionary:
	_retry_left = maxf(0.0, _retry_left - delta)
	if not stair_id.is_empty() and _index >= _path.size():
		# A save never serializes a transient path cache. Resume to a legal landing.
		var link: StairLink = map.stairs.get(stair_id)
		if link != null:
			var go_up := target_floor >= link.to_floor
			_path = [{"position": link.end if go_up else link.start,
				"floor": link.to_floor if go_up else link.from_floor}]
			_index = 0
	if stair_id.is_empty() and _should_repath(map, pos, floor_level, target, target_floor):
		_path = map.find_path(pos, floor_level, target, target_floor)
		_index = 0
		_planned_target = target
		_planned_floor = target_floor
		_planned_world_revision = map.revision
		_path_build_count += 1
		_retry_left = UNREACHABLE_RETRY_SECONDS if _path.is_empty() else 0.0
	while _index < _path.size():
		var waypoint := _path[_index]
		var next: Vector2 = waypoint["position"]
		if floor_level == int(waypoint["floor"]) and pos.distance_to(next) < WAYPOINT_ARRIVAL_DISTANCE and stair_id.is_empty():
			_index += 1
			continue
		var motion := pos.direction_to(next) * minf(speed * delta, pos.distance_to(next))
		return map.move_actor(pos, floor_level, motion, stair_id)
	return {"position": pos, "floor": floor_level, "stair_id": stair_id}


func _should_repath(map: WorldMap, pos: Vector2, floor_level: int,
		target: Vector2, target_floor: int) -> bool:
	if target_floor != _planned_floor or map.revision != _planned_world_revision:
		return true
	if target.distance_squared_to(_planned_target) > TARGET_REPATH_DISTANCE * TARGET_REPATH_DISTANCE:
		return true
	if _index < _path.size():
		return false
	# A finished path is valid only when it ended at the current target. An empty
	# result retries on a bounded cadence so unreachable goals cannot consume a
	# full path search every frame.
	if floor_level == target_floor and pos.distance_to(target) <= 0.10:
		return false
	return _retry_left <= 0.0
