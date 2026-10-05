class_name PlayerTargeting
extends RefCounted

## Queries simulation geometry, independently of render residency and animations.
static func ray_box(origin: Vector3, direction: Vector3, bounds: AABB, reach: float) -> float:
	var near := 0.0
	var far := reach
	for axis in 3:
		if absf(direction[axis]) < 0.000001:
			if origin[axis] < bounds.position[axis] or origin[axis] > bounds.end[axis]: return INF
			continue
		var a := (bounds.position[axis] - origin[axis]) / direction[axis]
		var b := (bounds.end[axis] - origin[axis]) / direction[axis]
		near = maxf(near, minf(a, b))
		far = minf(far, maxf(a, b))
		if near > far: return INF
	return near


static func melee_target(player: PlayerController, actors: Array, direction: Vector3, reach: float = ActorCombat.PLAYER_REACH) -> ZombieActor:
	return ActorCombat.select_target(player, actors, direction, reach) as ZombieActor


static func point_bounds(map: WorldMap, point: Dictionary) -> AABB:
	var p: Vector2 = point["position"]
	var furniture: bool = point.get("furniture", false)
	var size := ContainerData.CABINET_SIZE if furniture else Vector3(0.68, 0.46, 0.68)
	return AABB(Vector3(p.x - size.x * 0.5, int(point["floor"]) * map.floor_height, p.y - size.z * 0.5), size)


static func interaction_target(actions: InteractionSystem) -> Dictionary:
	var player := actions.player
	var map := actions.world_map
	var eye := ActorPerception.point(map, player.logical_position, player.floor_level, player.stair_id, ActorPerception.EYE_HEIGHT)
	var direction := player.look_direction()
	var nearest: Dictionary = {}
	var distance := 3.0
	for point: Dictionary in actions.points:
		if point["kind"] == "hazard": continue
		var hit := ray_box(eye, direction, point_bounds(map, point), distance)
		if is_finite(hit):
			distance = hit
			nearest = {"kind": "point", "data": point}
	for barrier: Dictionary in map.barriers.values():
		var start: Vector2 = barrier["start"]
		var end: Vector2 = barrier["end"]
		var axis := (end - start).normalized()
		var side := Vector2(-axis.y, axis.x)
		var relative := Vector2(eye.x, eye.z) - start
		var planar := Vector2(direction.x, direction.z)
		var local_eye := Vector3(relative.dot(axis), eye.y - int(barrier["level"]) * map.floor_height, relative.dot(side))
		var local_direction := Vector3(planar.dot(axis), direction.y, planar.dot(side))
		var hit := ray_box(local_eye, local_direction, AABB(Vector3(0, 0, -0.08), Vector3(start.distance_to(end), map.floor_height, 0.16)), distance)
		if is_finite(hit):
			distance = hit
			nearest = {"kind": "barrier", "data": barrier}
	if nearest.is_empty(): return nearest
	var contact := eye + direction * maxf(0.0, distance - 0.02)
	if not map.has_spatial_line_of_sight(eye, contact):
		return {"kind": "blocked", "reachable": false, "reason": "View blocked"}
	var data: Dictionary = nearest["data"]
	var reachable := false
	if nearest["kind"] == "point":
		reachable = actions._reachable(data)
	else:
		var closest := Geometry2D.get_closest_point_to_segment(player.logical_position, data["start"], data["end"])
		reachable = player.stair_id.is_empty() and player.floor_level == int(data["level"]) and player.logical_position.distance_to(closest) <= 1.0
	nearest["reachable"] = reachable
	nearest["distance"] = distance
	nearest["reason"] = ""
	if not reachable:
		var floor_index := int(data.get("floor", data.get("level", 0)))
		if not player.stair_id.is_empty(): nearest["reason"] = "Finish using the stairs"
		elif player.floor_level != floor_index: nearest["reason"] = "Different floor"
		elif nearest["kind"] == "barrier" or player.logical_position.distance_to(data["position"]) > (actions.CONTAINER_REACH if data.has("container") else float(data["radius"])):
			nearest["reason"] = "Too far away"
		else: nearest["reason"] = "No access from here"
	return nearest
