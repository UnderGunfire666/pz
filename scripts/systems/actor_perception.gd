class_name ActorPerception
extends RefCounted

## Simulation-space perception; never consults cameras or streamed meshes.
const EYE_HEIGHT := 1.62
const CHEST_HEIGHT := 1.05

static func point(map: WorldMap, position: Vector2, floor: int, stair: String, height: float) -> Vector3:
	return Vector3(position.x, map.elevation_at(position, floor, stair) + height, position.y)


static func sees_point(map: WorldMap, observer: Node, target: Vector3, distance: float,
		half_angle: float = 72.0, peripheral: float = 1.25) -> bool:
	var eye := point(map, observer.logical_position, observer.floor_level, observer.stair_id, EYE_HEIGHT)
	var offset := target - eye
	if offset.length_squared() > distance * distance: return false
	if offset.length() > peripheral:
		var planar := Vector2(offset.x, offset.z)
		var facing: Vector2 = observer.facing_direction
		if not planar.is_zero_approx() and facing.normalized().dot(planar.normalized()) < cos(deg_to_rad(half_angle)): return false
		if absf(atan2(offset.y, planar.length())) > deg_to_rad(70.0): return false
	return map.has_spatial_line_of_sight(eye, target)


static func sees_actor(map: WorldMap, observer: Node, target: Node, distance: float,
		half_angle: float = 72.0, peripheral: float = 1.25) -> bool:
	for height: float in [EYE_HEIGHT, CHEST_HEIGHT]:
		if sees_point(map, observer, point(map, target.logical_position, target.floor_level,
			target.stair_id, height), distance, half_angle, peripheral): return true
	return false
