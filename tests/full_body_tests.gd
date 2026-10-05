extends RefCounted

static func run(game: MVPGameRoot, check: Callable) -> void:
	var p := game.player
	var view := game.world_3d_view
	var saved_pitch := p.look_pitch
	var saved_heading := p.facing_direction
	view._process(0.0)
	var model: MixamoCharacterVisual = view.actor_visuals[p.get_instance_id()]["character_model"]
	check.call(model.is_visible_in_tree(), "third-person camera renders the imported full body")
	var full := MixamoCharacterVisual.new()
	game.add_child(full)
	full.setup(ActorBody.PLAYER)
	var complete := true
	for index in model.meshes.size():
		var local_mesh := model.meshes[index].mesh
		var original_mesh := full.meshes[index].mesh
		complete = complete and local_mesh == original_mesh
	check.call(complete, "third-person player keeps the complete source mesh including head and neck")
	check.call(ActorBody.PLAYER.regions.has("Head"), "visible player head preserves authoritative head damage")
	for animation in ["walk", "run", "attack"]:
		model.advance_split_animation(0.15, "walk", 1.0, animation, true)
		view.third_person_equipment.advance(0.0, p)
		for side in ["Left", "Right"]:
			var index := MixamoCharacterVisual.bone(model.skeleton, side + "Hand")
			var wrist := model.skeleton.global_transform * model.skeleton.get_bone_global_pose(index).origin
			var grip: Node3D = view.third_person_equipment.hands[0 if side == "Left" else 1]
			check.call(grip.global_position.distance_to(wrist) < 0.002,
				"held item anchor follows the animated %s wrist during %s" % [side, animation])
		var eye := ActorPerception.point(game.world_map, p.logical_position, p.floor_level, p.stair_id, PlayerViewRig.EYE_HEIGHT)
		check.call(view.view_rig.global_position.is_equal_approx(eye), "full body never shifts the authoritative aim origin")
	full.free()
	p.look_pitch = saved_pitch
	p.facing_direction = saved_heading
	view.sync_view_to_player()
	view._process(0.0)
