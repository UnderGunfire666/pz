class_name PlayerBodyPose
extends RefCounted
const BODY_OFFSET := Vector3(0, 0, 0.25)

## Deterministic two-bone pose in simulation actor space. Both body hit volumes
## and the imported skeleton consume these points, with no render dependency.
static func arms(player: PlayerController, profile: CharacterBodyProfile) -> Dictionary:
	var result := {}
	var pitch_basis := Basis(Vector3.RIGHT, player.look_pitch)
	# The anatomical root sits behind the eye line, like a standing person's
	# heels. Camera/aim remain at the original simulation origin.
	var eye := Vector3.UP * PlayerViewRig.EYE_HEIGHT - BODY_OFFSET
	var world_eye := ActorPerception.point(player.world_map, player.logical_position, player.floor_level, player.stair_id, PlayerViewRig.EYE_HEIGHT)
	var blocked := not player.world_map.has_spatial_line_of_sight(world_eye, world_eye + player.look_direction() * 0.85)
	var strike := sin(clampf(1.0 - player._attack_flash_left / 0.18, 0.0, 1.0) * PI) if player._attack_flash_left > 0.0 else 0.0
	var inventory := player.state.inventory
	var weapon := inventory.held_weapon() if inventory != null else null
	for side in ["Left", "Right"]:
		var sign_x := -1.0 if side == "Left" else 1.0
		var active := weapon == null
		if inventory != null and weapon != null:
			active = weapon in inventory.contents(side.to_lower() + "_hand") or not inventory.contents("two_hands").is_empty()
		var amount := strike if active else 0.0
		var target := eye + pitch_basis * Vector3(sign_x * (0.22 if player.aim_mode else 0.29), -0.29 + amount * 0.08, -0.48 - amount * 0.18 + (0.22 if blocked else 0.0))
		var shoulder: Vector3 = profile.joints[side + "Arm"]
		var upper_length: float = shoulder.distance_to(profile.joints[side + "ForeArm"])
		var lower_length: float = (profile.joints[side + "ForeArm"] as Vector3).distance_to(profile.joints[side + "Hand"])
		var vector := target - shoulder
		var length := clampf(vector.length(), absf(upper_length - lower_length) + 0.005, upper_length + lower_length - 0.005)
		var axis := vector.normalized()
		var along := (upper_length * upper_length - lower_length * lower_length + length * length) / (2.0 * length)
		var height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
		var pole := Vector3(sign_x, -0.7, 0.2)
		var bend := (pole - axis * pole.dot(axis)).normalized()
		var elbow := shoulder + axis * along + bend * height
		var wrist := shoulder + axis * length
		result[side] = {"shoulder": shoulder, "elbow": elbow, "wrist": wrist, "basis": pitch_basis,
			"tip": wrist + pitch_basis * Vector3(0, 0, -0.12)}
	return result

static func volumes(player: PlayerController, profile: CharacterBodyProfile) -> Dictionary:
	var result := profile.regions.duplicate()
	var pose := arms(player, profile)
	for side in ["Left", "Right"]:
		var arm: Dictionary = pose[side]
		# Two segments avoid a large empty diagonal box around bent elbows.
		result[side + " Arm"] = [segment(arm["shoulder"], arm["elbow"], 0.065), segment(arm["elbow"], arm["wrist"], 0.065)]
		result[side + " Hand"] = segment(arm["wrist"], arm["tip"], 0.055)
	return result

static func segment(a: Vector3, b: Vector3, radius: float) -> AABB:
	return AABB(a, Vector3.ZERO).expand(b).grow(radius)
