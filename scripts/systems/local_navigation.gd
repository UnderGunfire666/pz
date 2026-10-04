class_name LocalNavigation
extends RefCounted

## Cached path following shared by NPCs and zombies, including mid-stair restore.
var _path: Array[Dictionary] = []
var _index := 0
var _retry_left := 0.0
var _planned_target := Vector2(INF, INF)
var _planned_floor := -999
var _planned_stair := ""
var _planned_world_revision := -1
var _path_build_count := 0
var _repath_left := 0.0
var _blocked_seconds := 0.0
var failure_reason := ""
const TARGET_REPATH_DISTANCE := 0.35
const UNREACHABLE_RETRY_SECONDS := 0.8
const WAYPOINT_ARRIVAL_DISTANCE := 0.02


func reset() -> void:
	_path.clear()
	_index = 0
	_retry_left = 0.0
	_planned_target = Vector2(INF, INF)
	_planned_floor = -999
	_planned_stair = ""
	_planned_world_revision = -1
	_repath_left = 0.0
	_blocked_seconds = 0.0
	failure_reason = ""


func advance(map: WorldMap, pos: Vector2, floor_level: int, stair_id: String,
		target: Vector2, target_floor: int, speed: float, delta: float, target_stair: String = "") -> Dictionary:
	_retry_left = maxf(0.0, _retry_left - delta)
	_repath_left = maxf(0.0, _repath_left - delta)
	if not stair_id.is_empty() and stair_id == target_stair and map.stairs.has(stair_id):
		# Follow the last observed point along this surface, including reversal.
		var link: StairLink = map.stairs[stair_id]
		var rise := (link.to_floor - link.from_floor) * map.floor_height
		var step := speed * delta * link.length() / Vector2(link.length(), rise).length()
		failure_reason = ""
		return map.move_actor(pos, floor_level, pos.direction_to(target) * minf(step, pos.distance_to(target)), stair_id)
	if not stair_id.is_empty() and (_index >= _path.size() or (target_stair.is_empty() and target_floor != _planned_floor)):
		# A save never serializes a transient path cache. Resume to a legal landing.
		var link: StairLink = map.stairs.get(stair_id)
		if link != null:
			var go_up := target_floor >= link.to_floor
			_path = [{"position": link.end if go_up else link.start,
				"floor": link.to_floor if go_up else link.from_floor}]
			_index = 0
			_planned_floor = target_floor
			_planned_world_revision = -1
	if stair_id.is_empty() and (target_stair != _planned_stair or _should_repath(map, pos, floor_level, target, target_floor)):
		_path = map.find_path(pos, floor_level, target, target_floor) if target_stair.is_empty() else map.find_path_to_stair(pos, floor_level, target, target_stair)
		_index = 0
		_planned_target = target
		_planned_floor = target_floor
		_planned_stair = target_stair
		_planned_world_revision = map.revision
		_path_build_count += 1
		_retry_left = UNREACHABLE_RETRY_SECONDS if _path.is_empty() else 0.0
		_repath_left = 0.25
		failure_reason = "unreachable" if _path.is_empty() else ""
	while _index < _path.size():
		var waypoint := _path[_index]
		var next: Vector2 = waypoint["position"]
		# Movement acquires the stair before reaching its exact endpoint. Once
		# acquired, follow its exit instead of steering back to the entry node.
		if not stair_id.is_empty() and _index + 1 < _path.size():
			var link: StairLink = map.stairs.get(stair_id)
			if link != null and (int(waypoint["floor"]) != int(_path[_index + 1]["floor"]) or _path[_index + 1].get("stair", "") == stair_id) \
				and (next.distance_to(link.start) < 0.03 or next.distance_to(link.end) < 0.03):
				_index += 1
				continue
		var arrival := 0.02 if waypoint.get("landing", false) or _index == _path.size() - 1 else WAYPOINT_ARRIVAL_DISTANCE
		if floor_level == int(waypoint["floor"]) and pos.distance_to(next) < arrival and stair_id.is_empty():
			_index += 1
			continue
		var planar_speed := speed
		if not stair_id.is_empty() and map.stairs.has(stair_id):
			var link: StairLink = map.stairs[stair_id]
			var rise := (link.to_floor - link.from_floor) * map.floor_height
			planar_speed *= link.length() / Vector2(link.length(), rise).length()
		var motion := pos.direction_to(next) * minf(planar_speed * delta, pos.distance_to(next))
		var result := map.move_actor(pos, floor_level, motion, stair_id)
		if motion.length_squared() > 0.000001 and pos.distance_squared_to(result["position"]) < motion.length_squared() * 0.01:
			_blocked_seconds += delta
		else:
			_blocked_seconds = 0.0
		if _blocked_seconds >= 0.6 and stair_id.is_empty():
			_path.clear()
			_index = 0
			_retry_left = UNREACHABLE_RETRY_SECONDS
			_blocked_seconds = 0.0
			failure_reason = "blocked"
		return result
	return {"position": pos, "floor": floor_level, "stair_id": stair_id}


func _should_repath(map: WorldMap, pos: Vector2, floor_level: int,
		target: Vector2, target_floor: int) -> bool:
	if target_floor != _planned_floor or map.revision != _planned_world_revision:
		return true
	if target.distance_squared_to(_planned_target) > TARGET_REPATH_DISTANCE * TARGET_REPATH_DISTANCE:
		return _repath_left <= 0.0 and _retry_left <= 0.0
	if _index < _path.size():
		return false
	# A finished path is valid only when it ended at the current target. An empty
	# result retries on a bounded cadence so unreachable goals cannot consume a
	# full path search every frame.
	if floor_level == target_floor and pos.distance_to(target) <= 0.10:
		return false
	return _retry_left <= 0.0
