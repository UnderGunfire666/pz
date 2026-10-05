extends SceneTree

## Run after replacing either source FBX. Bakes gameplay geometry; never sampled
## from a visible instance during combat. Review the preview after rebaking.
func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	for actor_name in ["Player", "Zombie"]:
		var profile := CharacterBodyProfile.new()
		profile.model_path = "res://assets/characters/mixamo/%s/%s.fbx" % [actor_name, actor_name]
		var model := (load(profile.model_path) as PackedScene).instantiate() as Node3D
		root.add_child(model)
		var bounds := AABB()
		var first := true
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = model.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		profile.model_scale = 1.8 / bounds.size.y
		profile.model_offset = Vector3(0, -bounds.position.y * profile.model_scale, 0)
		model.rotation.y = PI
		model.scale = Vector3.ONE * profile.model_scale
		model.position = profile.model_offset
		var skel := MixamoCharacterVisual.find_skeleton(model)
		MixamoCharacterVisual.relax_arms(skel)
		var head := point(skel, "Head")
		var neck := point(skel, "Neck")
		var hips := point(skel, "Hips")
		profile.regions["Head"] = AABB(Vector3(-0.115, neck.y, head.z - 0.13), Vector3(0.23, 1.8 - neck.y, 0.26))
		profile.regions["Torso"] = AABB(Vector3(-0.19, hips.y - 0.12, hips.z - 0.14), Vector3(0.38, neck.y - hips.y + 0.12, 0.28))
		for side in ["Left", "Right"]:
			for joint in ["Arm", "ForeArm", "Hand", "HandMiddle3"]:
				profile.joints[side + joint] = point(skel, side + joint)
			profile.regions[side + " Arm"] = segment(point(skel, side + "Arm"), point(skel, side + "Hand"), 0.065)
			profile.regions[side + " Hand"] = segment(point(skel, side + "Hand"), point(skel, side + "HandMiddle3"), 0.055)
			var leg := segment(point(skel, side + "UpLeg"), point(skel, side + "Foot"), 0.07)
			leg.position.y = 0.16
			leg.size.y = hips.y - 0.16
			profile.regions[side + " Leg"] = leg
			var foot := segment(point(skel, side + "Foot"), point(skel, side + "Toe_End"), 0.065)
			foot.position.y = 0.0
			foot.size.y = 0.16
			profile.regions[side + " Foot"] = foot
		DirAccess.make_dir_recursive_absolute("res://resources/bodies")
		var result := ResourceSaver.save(profile, "res://resources/bodies/%s.tres" % actor_name.to_lower())
		assert(result == OK)
		print(actor_name, " body profile: ", profile.regions)
		model.free()
	quit()

func point(skel: Skeleton3D, suffix: String) -> Vector3:
	var index := MixamoCharacterVisual.bone(skel, suffix)
	assert(index >= 0, "Missing bone: " + suffix)
	return skel.global_transform * skel.get_bone_global_pose(index).origin

func segment(a: Vector3, b: Vector3, radius: float) -> AABB:
	return AABB(a, Vector3.ZERO).expand(b).grow(radius)
