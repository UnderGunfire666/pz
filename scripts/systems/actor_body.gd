class_name ActorBody
extends RefCounted

## Authoritative body volumes follow simulation feet/facing, including stairs.
## They exist even when the imported mesh is hidden or unloaded.
const PLAYER: CharacterBodyProfile = preload("res://resources/bodies/player.tres")
const ZOMBIE: CharacterBodyProfile = preload("res://resources/bodies/zombie.tres")

static func profile(actor: Node) -> CharacterBodyProfile:
	return ZOMBIE if actor is ZombieActor else PLAYER

static func transform_for(actor: Node) -> Transform3D:
	var feet := ActorPerception.point(actor.world_map, actor.logical_position, actor.floor_level, actor.stair_id, 0.0)
	var facing: Vector2 = actor.facing_direction
	var basis := Basis(Vector3.UP, atan2(-facing.x, -facing.y))
	if actor is PlayerController: feet += basis * PlayerBodyPose.BODY_OFFSET
	return Transform3D(basis, feet)

static func volumes(actor: Node) -> Dictionary:
	if actor is PlayerController: return PlayerBodyPose.volumes(actor, PLAYER)
	return profile(actor).regions


static func collision_enabled(actor: Node, local_player: PlayerController = null) -> bool:
	# Hurtboxes are simulation data, independent of whether a character mesh is
	# currently rendered. Keep only the player and the local three-tile encounter
	# bubble in the combat broad phase.
	if actor is PlayerController:
		return true
	var player := local_player
	if player == null:
		player = actor.get("player") as PlayerController
	if player == null and actor.is_inside_tree():
		for candidate in actor.get_tree().get_nodes_in_group("zombie_targets"):
			if candidate is PlayerController and candidate.world_map == actor.get("world_map"):
				player = candidate
				break
	if player == null:
		# Detached fixtures have no player encounter to cull.
		return true
	if player.world_map != actor.get("world_map"):
		return false
	return player.floor_level == actor.floor_level and player.stair_id == actor.stair_id \
		and player.logical_position.distance_to(actor.logical_position) <= 3.0

static func ray_hit(actor: Node, origin: Vector3, direction: Vector3, reach: float, body_volumes: Dictionary = {}) -> Dictionary:
	var inverse := transform_for(actor).affine_inverse()
	var local_origin := inverse * origin
	var local_direction := inverse.basis * direction
	var best: Dictionary = {}
	var distance := reach + 0.00001
	var regions := volumes(actor) if body_volumes.is_empty() else body_volumes
	for region: String in regions:
		var boxes: Array = regions[region] if regions[region] is Array else [regions[region]]
		for bounds: AABB in boxes:
			var hit := PlayerTargeting.ray_box(local_origin, local_direction, bounds, reach)
			if is_finite(hit) and hit < distance:
				distance = hit
				best = {"region": region, "distance": hit, "position": origin + direction * hit, "alignment": 1.0}
	return best

static func healthy_regions() -> Dictionary:
	var result := {}
	for region in PlayerState.BODY_REGIONS: result[region] = 100.0
	return result

static func valid_health(value: Variant) -> bool:
	if not value is Dictionary or value.size() != PlayerState.BODY_REGIONS.size(): return false
	for region in PlayerState.BODY_REGIONS:
		var amount: Variant = value.get(region)
		if not (amount is float or amount is int): return false
		if not is_finite(float(amount)) or amount < 0.0 or amount > 100.0: return false
	return true
