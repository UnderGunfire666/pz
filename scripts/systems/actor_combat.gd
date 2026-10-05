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


static func turn_toward(actor: Node, target: Vector3, delta: float, turn_speed: float = 4.0) -> void:
	var eye := ActorPerception.point(actor.world_map, actor.logical_position, actor.floor_level, actor.stair_id, ActorPerception.EYE_HEIGHT)
	var offset := target - eye
	var planar := Vector2(offset.x, offset.z)
	if planar.length_squared() > 0.000001:
		var angle := rotate_toward(actor.facing_direction.angle(), planar.angle(), delta * turn_speed)
		actor.facing_direction = Vector2.from_angle(angle)
	actor.look_pitch = move_toward(actor.look_pitch, atan2(offset.y, planar.length()), delta * 3.0)


static func contact(attacker: Node, target: Node, aim: Vector3, reach: float) -> Dictionary:
	if not ActorBody.collision_enabled(attacker) or not ActorBody.collision_enabled(target):
		return {}
	var map: WorldMap = attacker.world_map
	if target.get("world_map") != map: return {}
	var eye := ActorPerception.point(map, attacker.logical_position, attacker.floor_level, attacker.stair_id, ActorPerception.EYE_HEIGHT)
	var feet := ActorPerception.point(map, target.logical_position, target.floor_level, target.stair_id, 0.0)
	# Overlapping proxy boxes must not make a target behind the actor hittable.
	if aim.dot(feet + Vector3.UP * ActorPerception.EYE_HEIGHT - eye) < -0.00001: return {}
	if eye.distance_to(feet + Vector3.UP) > reach + 1.0: return {}
	var volumes := ActorBody.volumes(target)
	var direct := ActorBody.ray_hit(target, eye, aim, reach, volumes)
	if not direct.is_empty() and _clear_contact(map, eye, direct["position"]):
		return direct
	# Sweep body volumes and resolve the first surface on each sampled ray.
	# Far-side limbs cannot be struck through the target's torso.
	var best: Dictionary = {}
	var transform := ActorBody.transform_for(target)
	var samples: Array = []
	for value in volumes.values():
		if value is Array: samples.append_array(value)
		else: samples.append(value)
	for bounds: AABB in samples:
		var offset := transform * bounds.get_center() - eye
		if offset.length_squared() < 0.000001: continue
		var sample_direction := offset.normalized()
		var alignment := aim.dot(sample_direction)
		if alignment < cos(HALF_ANGLE): continue
		var hit := ActorBody.ray_hit(target, eye, sample_direction, reach, volumes)
		if hit.is_empty() or not _clear_contact(map, eye, hit["position"]): continue
		hit["alignment"] = alignment
		if best.is_empty() or alignment > float(best["alignment"]): best = hit
	return best


static func _clear_contact(map: WorldMap, eye: Vector3, point: Vector3) -> bool:
	# Probe just inside the surface. A foot resting exactly on an upper floor
	# must not be hittable from below due to LOS excluding its endpoint plane.
	return map.has_spatial_line_of_sight(eye, point + eye.direction_to(point) * 0.002)


static func select_target(attacker: Node, targets: Array, aim: Vector3, reach: float) -> Node:
	var best: Node = null
	var score := INF
	for target in targets:
		if not is_instance_valid(target) or target == attacker or target.is_queued_for_deletion(): continue
		if not ActorBody.collision_enabled(target) or not ActorBody.collision_enabled(attacker): continue
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


static func weapon_contact(attacker: Node, target: Node, aim: Vector3, hitbox_size: Vector3) -> Dictionary:
	if hitbox_size == Vector3.ZERO or not ActorBody.collision_enabled(attacker) or not ActorBody.collision_enabled(target):
		return {}
	var map: WorldMap = attacker.world_map
	if target.get("world_map") != map: return {}
	var eye := ActorPerception.point(map, attacker.logical_position, attacker.floor_level, attacker.stair_id, ActorPerception.EYE_HEIGHT)
	# The bat begins just forward of the grip and extends along the attack aim.
	# Sampling its narrow cylinder against each AABB is deterministic and remains
	# independent of the visible imported prop.
	var start := eye + aim * 0.32 + Vector3.DOWN * 0.38
	var length := hitbox_size.z
	var radius := maxf(hitbox_size.x, hitbox_size.y) * 0.5
	var transform := ActorBody.transform_for(target)
	var inverse := transform.affine_inverse()
	var best: Dictionary = {}
	for step in range(13):
		var point := start + aim * length * (float(step) / 12.0)
		if not map.has_spatial_line_of_sight(eye, point): continue
		var local := inverse * point
		for region: String in ActorBody.volumes(target):
			var source: Variant = ActorBody.volumes(target)[region]
			var boxes: Array = source if source is Array else [source]
			for box: AABB in boxes:
				if not box.grow(radius).has_point(local): continue
				var distance := eye.distance_to(point)
				if best.is_empty() or distance < float(best["distance"]):
					best = {"region": region, "distance": distance, "position": point, "alignment": aim.dot(eye.direction_to(point))}
	return best


static func select_weapon_target(attacker: Node, targets: Array, aim: Vector3, hitbox_size: Vector3) -> Dictionary:
	var best: Dictionary = {}
	for target in targets:
		if not is_instance_valid(target) or target == attacker or target.is_queued_for_deletion(): continue
		if target is PlayerController:
			if target.state.is_dead(): continue
		elif target.health <= 0:
			continue
		var hit := weapon_contact(attacker, target, aim, hitbox_size)
		if hit.is_empty(): continue
		if best.is_empty() or float(hit["distance"]) < float(best["hit"]["distance"]):
			best = {"target": target, "hit": hit}
	return best


static func apply_hit_recoil(target: Node, away_direction: Vector2, distance: float) -> void:
	# A confirmed contact may move the simulation actor slightly. It never derives
	# gameplay state from animation or a rendered physics prop.
	if target == null or not is_instance_valid(target) or away_direction.length_squared() < 0.00001:
		return
	if target is PlayerController:
		if target.state.is_dead(): return
	elif target.get("health") == null or float(target.health) <= 0.0:
		return
	var map: WorldMap = target.get("world_map")
	if map == null:
		return
	var result := map.move_actor(target.logical_position, target.floor_level, away_direction.normalized() * distance, target.stair_id)
	target.logical_position = result["position"]
	target.floor_level = int(result["floor"])
	target.stair_id = String(result["stair_id"])
