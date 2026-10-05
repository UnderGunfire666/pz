class_name ActorCombat
extends RefCounted

## Authoritative melee volume: distance and angular sweep follow the actor's aim.
const PLAYER_REACH := 2.0
const WEAPON_REACH := 2.4
const ZOMBIE_REACH := 1.2
const NPC_REACH := 1.8
const HALF_ANGLE := deg_to_rad(24.0)


static func direction(actor: Node) -> Vector3:
	var facing: Vector2 = actor.facing_direction
	var pitch: float = actor.look_pitch
	return Vector3(facing.x * cos(pitch), sin(pitch), facing.y * cos(pitch)).normalized()


static func turn_toward(actor: Node, target: Vector3, delta: float) -> void:
	var eye := ActorPerception.point(actor.world_map, actor.logical_position, actor.floor_level, actor.stair_id, ActorPerception.EYE_HEIGHT)
	var offset := target - eye
	var planar := Vector2(offset.x, offset.z)
	if planar.length_squared() > 0.000001:
		var angle := rotate_toward(actor.facing_direction.angle(), planar.angle(), delta * 4.0)
		actor.facing_direction = Vector2.from_angle(angle)
	actor.look_pitch = move_toward(actor.look_pitch, atan2(offset.y, planar.length()), delta * 3.0)


static func contact(attacker: Node, target: Node, aim: Vector3, reach: float) -> Dictionary:
	var map: WorldMap = attacker.world_map
	if target.get("world_map") != map: return {}
	var eye := ActorPerception.point(map, attacker.logical_position, attacker.floor_level, attacker.stair_id, ActorPerception.EYE_HEIGHT)
	var feet := ActorPerception.point(map, target.logical_position, target.floor_level, target.stair_id, 0.0)
	# Overlapping proxy boxes must not make a target behind the actor hittable.
	if aim.dot(feet + Vector3.UP * ActorPerception.EYE_HEIGHT - eye) < -0.00001: return {}
	if eye.distance_to(feet + Vector3.UP) > reach + 1.0: return {}
	var bounds := AABB(feet + Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.86, 0.6))
	var direct := PlayerTargeting.ray_box(eye, aim, bounds, reach)
	if is_finite(direct) and map.has_spatial_line_of_sight(eye, eye + aim * direct):
		return {"distance": direct, "alignment": 1.0}
	# Sample real body surfaces; cone expansion never permits a hit through walls.
	var best: Dictionary = {}
	for height: float in [0.45, 1.05, 1.62]:
		var center := feet + Vector3.UP * height
		var sample := center + (eye - center).normalized() * 0.24
		var offset := sample - eye
		var distance := offset.length()
		if distance > reach or distance < 0.00001: continue
		var alignment := aim.dot(offset / distance)
		if alignment < cos(HALF_ANGLE) or not map.has_spatial_line_of_sight(eye, sample): continue
		if best.is_empty() or alignment > float(best["alignment"]): best = {"distance": distance, "alignment": alignment}
	return best


static func select_target(attacker: Node, targets: Array, aim: Vector3, reach: float) -> Node:
	var best: Node = null
	var score := INF
	for target in targets:
		if not is_instance_valid(target) or target == attacker or target.is_queued_for_deletion(): continue
		if target is PlayerController:
			if target.state.is_dead(): continue
		elif target.health <= 0: continue
		var hit := contact(attacker, target, aim, reach)
		if hit.is_empty(): continue
		var rank := (1.0 - float(hit["alignment"])) * 10.0 + float(hit["distance"]) * 0.1
		if rank < score:
			score = rank
			best = target
	return best
