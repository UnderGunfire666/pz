extends RefCounted

static func combat(game: MVPGameRoot, check: Callable) -> void:
	var p := game.player
	var position := p.logical_position
	var level := p.floor_level
	var stair := p.stair_id
	var pitch := p.look_pitch
	p.logical_position = Vector2(18.5, 13.5)
	p.floor_level = 0
	p.stair_id = ""
	p.look_pitch = 0.0
	var target := ZombieActor.new()
	target.world_map = game.world_map
	target.logical_position = p.logical_position + Vector2(0, 0.8)
	var side := ZombieActor.new()
	side.world_map = game.world_map
	side.logical_position = p.logical_position + Vector2(0.5, 0.5)
	check.call(PlayerTargeting.melee_target(p, [side, target], p.look_direction(Vector2.DOWN)) == target,
		"melee selects center-ray target rather than closer off-axis actor")
	p.look_pitch = deg_to_rad(80)
	check.call(PlayerTargeting.melee_target(p, [target], p.look_direction(Vector2.DOWN)) == null,
		"looking above nearby zombie misses")
	p.look_pitch = deg_to_rad(-35)
	check.call(PlayerTargeting.melee_target(p, [target], p.look_direction(Vector2.DOWN)) == target,
		"downward melee can hit the torso")
	p.look_pitch = 0
	target.logical_position.y += 2
	check.call(PlayerTargeting.melee_target(p, [target], p.look_direction(Vector2.DOWN)) == null,
		"melee cannot reach distant ray target")
	target.logical_position = p.logical_position - Vector2(0, 0.8)
	check.call(PlayerTargeting.melee_target(p, [target], p.look_direction(Vector2.DOWN)) == null,
		"melee cannot hit behind the player")
	p.logical_position = Vector2(14.5, 4.25)
	p.floor_level = 1
	target.logical_position = Vector2(14.5, 4.95)
	target.floor_level = 1
	check.call(PlayerTargeting.melee_target(p, [target], p.look_direction(Vector2.DOWN)) == null,
		"world wall blocks an in-range target directly on the attack ray")
	target.free()
	side.free()
	p.logical_position = position
	p.floor_level = level
	p.stair_id = stair
	p.look_pitch = pitch


static func aim_at(game: MVPGameRoot, point: Dictionary) -> void:
	var bounds := PlayerTargeting.point_bounds(game.world_map, point)
	var eye := ActorPerception.point(game.world_map, game.player.logical_position, game.player.floor_level, game.player.stair_id, ActorPerception.EYE_HEIGHT)
	var offset := bounds.get_center() - eye
	var horizontal := Vector2(offset.x, offset.z)
	game.player.facing_direction = horizontal.normalized() if horizontal.length() > 0.01 else Vector2.DOWN
	game.player.look_pitch = clampf(atan2(offset.y, horizontal.length()), -PlayerViewRig.PITCH_LIMIT, PlayerViewRig.PITCH_LIMIT)
	game.world_3d_view.sync_view_to_player()


static func interaction(game: MVPGameRoot, check: Callable) -> void:
	var p := game.player
	var position := p.logical_position
	var level := p.floor_level
	var stair := p.stair_id
	var pitch := p.look_pitch
	var facing := p.facing_direction
	var points := game.interactions.points
	p.logical_position = Vector2(18.5, 13.5)
	p.floor_level = 0
	p.stair_id = ""
	var front := {"id": "front", "kind": "bed", "position": p.logical_position + Vector2(0, 0.8), "floor": 0, "radius": 1.2, "furniture": true}
	var behind := front.duplicate()
	behind["id"] = "behind"
	behind["position"] = p.logical_position - Vector2(0, 0.4)
	game.interactions.points = [behind, front]
	aim_at(game, front)
	var focus := PlayerTargeting.interaction_target(game.interactions)
	check.call(focus.get("data", {}).get("id") == "front" and focus["reachable"], "interaction chooses looked-at object instead of closer object behind")
	p.look_pitch = deg_to_rad(80)
	check.call(PlayerTargeting.interaction_target(game.interactions).is_empty(), "looking away clears interaction target")
	front["position"] = p.logical_position + Vector2(0, 2.0)
	aim_at(game, front)
	focus = PlayerTargeting.interaction_target(game.interactions)
	check.call(not focus.is_empty() and not focus["reachable"], "looking at a distant object does not grant interaction reach")
	front["label"] = "Front bed"
	check.call(game.interactions.prompt(focus).contains("Too far away"), "unreachable focus explains the interaction distance limit")
	check.call(game.interactions.prompt({"kind": "blocked", "reachable": false}) == "View blocked", "occluded focus never discloses the hidden object's name")
	game.hud.refresh(game)
	check.call(game.hud.crosshair.modulate == Color("efbc72"), "unreachable focus turns the crosshair amber")
	front["position"] = p.logical_position + Vector2(0, 0.8)
	aim_at(game, front)
	game.hud.refresh(game)
	check.call(game.hud.crosshair.modulate == Color("86e3a1") and game.hud.prompt_label.text.contains("Front bed"), "reachable focus and HUD prompt describe the same selected object: %s" % game.hud.prompt_label.text)
	p.logical_position = Vector2(14.5, 4.25)
	p.floor_level = 1
	front["position"] = Vector2(14.5, 4.95)
	front["floor"] = 1
	aim_at(game, front)
	focus = PlayerTargeting.interaction_target(game.interactions)
	check.call(focus.get("kind") == "blocked" and not focus.has("data"), "wall blocks interaction without exposing the hidden object's identity")
	game.interactions.points = points
	p.logical_position = position
	p.floor_level = level
	p.stair_id = stair
	p.look_pitch = pitch
	p.facing_direction = facing
	game.world_3d_view.sync_view_to_player()


static func equipment(game: MVPGameRoot, check: Callable) -> void:
	var inventory := InventoryGrid.new(false)
	var visual := FirstPersonHands.new()
	game.world_3d_view.camera.add_child(visual)
	visual.setup(inventory)
	check.call(visual.hands.size() == 2 and visual.held_ids == ["", ""], "third-person equipment has two empty hand anchors")
	var hammer := ItemDefinition.new("test_hammer", "Hammer", Vector3(4, 4, 30), 0.8, ["weapon"])
	inventory.contents("right_hand").append(ItemStack.new(hammer))
	inventory.revision += 1
	visual.advance(0, game.player)
	check.call(visual.held_ids[1] == "test_hammer" and visual.hands[1].get_child_count() == 2, "equipped hammer creates only handle and head, with no proxy hand meshes")
	var body: MixamoCharacterVisual = game.world_3d_view.actor_visuals[game.player.get_instance_id()]["character_model"]
	visual.bind_body(body)
	body.play_animation("attack", 0.0, 1.0, true)
	body.animation_player.advance(0.1)
	visual.advance(0, game.player)
	var hand_index := MixamoCharacterVisual.bone(body.skeleton, "RightHand")
	var wrist := body.skeleton.global_transform * body.skeleton.get_bone_global_pose(hand_index).origin
	check.call(visual.hands[1].global_position.distance_to(wrist) < 0.002, "weapon follows the animated wrist during a full-body strike")
	inventory.contents("right_hand").clear()
	inventory.contents("two_hands").append(ItemStack.new(hammer))
	inventory.revision += 1
	visual.refresh()
	check.call(visual.held_ids[1] == "test_hammer", "two-handed slot also supplies a visible held item")
	inventory.contents("two_hands").clear()
	inventory.revision += 1
	visual.refresh()
	check.call(visual.held_ids == ["", ""] and visual.hands[1].get_child_count() == 0, "unequipping leaves empty grip anchors without proxy limbs")
	var jacket: ItemStack = game.inventory.world["wardrobe"].contents[1]
	inventory.contents("outer_top").append(jacket)
	inventory.revision += 1
	visual.refresh()
	check.call(visual.sleeve_color == Color("52616b"), "worn outer clothing updates third-person equipment styling")
	visual.hurt_remaining = 0.3
	var speed := GameTime.speed_mode
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	visual.advance(1, game.player)
	body.set_region_flash("Torso", visual.hurt_remaining)
	check.call(is_equal_approx(visual.hurt_remaining, 0.3) and body._region_flash_meshes["Torso"].visible,
		"injury feedback highlights the hit body part and remains frozen while paused")
	GameTime.set_speed(speed)
	visual.free()


static func save_pitch(game: MVPGameRoot, check: Callable) -> void:
	var original := QuickSave.snapshot(game)
	var speed := GameTime.speed_mode
	game.player.look_pitch = -0.6
	var path := OS.get_temp_dir().path_join("afterlight-first-person-pitch-%d.save" % Time.get_ticks_usec())
	check.call(QuickSave.save_game(game, path), "pitch save is written through normal save validation")
	game.player.look_pitch = 0.5
	check.call(QuickSave.load_game(game, path) and is_equal_approx(game.player.look_pitch, -0.6)
		and is_equal_approx(game.world_3d_view.view_rig.pitch, -0.6), "disk save restores simulation aim and camera pitch together")
	var legacy := QuickSave.snapshot(game)
	legacy.erase("look_pitch")
	check.call(QuickSave.validate(legacy, game), "older v10 saves without pitch remain valid")
	QuickSave.restore(game, legacy)
	check.call(game.player.look_pitch == 0.0 and game.world_3d_view.view_rig.pitch == 0.0, "old saves restore a level view instead of retaining previous pitch")
	for invalid in [NAN, INF, "bad", PI]:
		var broken := original.duplicate(true)
		broken["look_pitch"] = invalid
		check.call(not QuickSave.validate(broken, game), "nonfinite, wrong-type and out-of-range pitch are rejected")
	QuickSave.restore(game, original)
	GameTime.set_speed(speed)
	DirAccess.remove_absolute(path)


static func stair_feedback(game: MVPGameRoot, check: Callable) -> void:
	var player := game.player
	var saved_position := player.logical_position
	var saved_floor := player.floor_level
	var saved_stair := player.stair_id
	var speed := GameTime.speed_mode
	var hands := game.world_3d_view.third_person_equipment
	var link: StairLink = game.world_map.stairs.values()[0]
	player.floor_level = link.from_floor
	player.stair_id = link.id
	player.logical_position = link.start.lerp(link.end, 0.4)
	hands.reset_motion()
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	hands.advance(0.1, player)
	player.logical_position = link.start.lerp(link.end, 0.45)
	hands.advance(0.1, player)
	check.call(hands._walk_blend > 0 and hands._walk_phase > 0, "stair movement drives hand feedback using continuous 3D travel")
	var phase := hands._walk_phase
	player.logical_position = link.start.lerp(link.end, 0.42)
	hands.advance(0.1, player)
	check.call(hands._walk_phase > phase, "reversing on stairs continues the walking rhythm without snapping")
	GameTime.set_speed(GameTime.SpeedMode.PAUSED)
	var pose := hands.hands[0].transform
	hands.advance(1, player)
	check.call(hands.hands[0].transform.is_equal_approx(pose), "pause freezes locomotion feedback")
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	hands.advance(1, player)
	check.call(hands._walk_blend == 0, "stopping on stairs settles hands without continuous bobbing")
	game.world_3d_view._update_camera(0.1)
	var expected := ActorPerception.point(game.world_map, player.logical_position, player.floor_level, player.stair_id, ActorPerception.EYE_HEIGHT)
	check.call(game.world_3d_view.view_rig.global_position.is_equal_approx(expected), "stair feedback preserves exact third-person pivot and simulation eye alignment")
	hands.reset_motion()
	check.call(hands._walk_blend == 0 and hands._walk_phase == 0, "load reset clears previous locomotion feedback")
	player.logical_position = saved_position
	player.floor_level = saved_floor
	player.stair_id = saved_stair
	GameTime.set_speed(speed)
	game.world_3d_view.refresh_after_load()
