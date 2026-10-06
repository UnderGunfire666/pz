class_name ActorHearing
extends RefCounted

## Anonymous, finite-lived evidence shared by every AI listener. No actor lookup,
## render meshes, live source tracking, random global state or navigation search.
const MAX_EVENT_AGE := 6.0
const MEMORY_SECONDS := 45.0
const SWITCH_LOCK_SECONDS := 6.0
const DANGER_CATEGORIES := ["struggle", "melee strike", "melee impact", "gunshot", "explosion"]


static func sample(map: WorldMap, listener: Node, stimulus: NoiseStimulus,
		now: float) -> Dictionary:
	if stimulus == null or not is_finite(stimulus.world_time): return {}
	if stimulus.world_time > now or now - stimulus.world_time > MAX_EVENT_AGE: return {}
	if stimulus.emitter_instance_id == listener.get_instance_id(): return {}
	if stimulus.map_instance_id != 0 and stimulus.map_instance_id != map.get_instance_id(): return {}
	var radius := stimulus.audible_range * stimulus.loudness
	if not is_finite(radius) or radius <= 0.0: return {}
	var source := stimulus.spatial_position
	if source == Vector3.INF:
		source = ActorPerception.point(map, stimulus.world_position, stimulus.floor_level, "", ActorPerception.CHEST_HEIGHT)
	if not source.is_finite(): return {}
	var ear := ActorPerception.point(map, listener.logical_position, listener.floor_level,
		listener.stair_id, ActorPerception.EYE_HEIGHT)
	# Broad rejection also applies between floors; remote sounds never scan walls.
	if ear.distance_squared_to(source) >= radius * radius: return {}
	var trace := map.trace_sound(ear, source, radius)
	var strength := radius - float(trace["cost"])
	if strength <= 0.0: return {}
	var clarity := clampf(strength / radius, 0.0, 1.0)
	var uncertainty := clampf(0.25 + (1.0 - clarity) * 1.25 + float(trace["obstacle_loss"]) * 0.08, 0.25, 2.0)
	var floor := stimulus.floor_level
	var anchor := Vector2(source.x, source.z)
	# A stair sound identifies a nearby landing, never the source's direction of
	# travel. Ownership is explicit: merely standing under stairs is not traversal.
	if not stimulus.source_stair_id.is_empty() and map.stairs.has(stimulus.source_stair_id):
		var link: StairLink = map.stairs[stimulus.source_stair_id]
		var lower := ActorPerception.point(map, link.start, link.from_floor, "", ActorPerception.EYE_HEIGHT)
		var upper := ActorPerception.point(map, link.end, link.to_floor, "", ActorPerception.EYE_HEIGHT)
		var use_lower := ear.distance_squared_to(lower) <= ear.distance_squared_to(upper)
		anchor = link.start if use_lower else link.end
		floor = link.from_floor if use_lower else link.to_floor
	var estimate := _estimate(map, anchor, floor, uncertainty)
	return {"position": estimate, "floor": floor, "strength": strength,
		"clarity": clarity, "uncertainty": uncertainty, "world_time": stimulus.world_time,
		"event_type": stimulus.event_type, "danger": stimulus.event_type in DANGER_CATEGORIES,
		"radius": radius, "distance": trace["distance"], "obstacle_loss": trace["obstacle_loss"],
		"obstacles": trace["obstacles"]}


static func _estimate(map: WorldMap, anchor: Vector2, floor: int, uncertainty: float) -> Vector2:
	# Quantization is deterministic, so repeated footsteps do not consume RNG or
	# cause random target jitter. Never fall back to the exact hidden source.
	var grid := uncertainty
	var center := (anchor / grid).floor() * grid + Vector2.ONE * grid * 0.5
	for offset: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT,
		Vector2.UP, Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var candidate := center + offset * grid
		if anchor.distance_to(candidate) <= uncertainty and map.can_stand(candidate, floor): return candidate
	# No navigation query in the event fanout. The existing navigator retries an
	# unreachable clue and the listener eventually abandons its expired memory.
	return center
