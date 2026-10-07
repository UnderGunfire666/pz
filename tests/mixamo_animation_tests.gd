extends RefCounted

const PLAYER_CLIPS := ["idle", "walk", "run", "back_walk", "back_run", "strafe_left", "strafe_right", "jump", "attack", "armed_idle", "armed_run", "equip"]
const ZOMBIE_CLIPS := ["idle", "walk", "run", "attack", "death"]


static func run(game: MVPGameRoot, check: Callable) -> void:
	var view := game.world_3d_view
	view._process(0.0)
	var player_visual: MixamoCharacterVisual = view.actor_visuals[game.player.get_instance_id()]["character_model"]
	_check_library(player_visual, PLAYER_CLIPS, check, "player")
	var npc_visual: MixamoCharacterVisual = view.actor_visuals[game.npc.get_instance_id()]["character_model"]
	_check_library(npc_visual, PLAYER_CLIPS, check, "NPC shared Human")
	var player_walk: Animation = player_visual.animation_player.get_animation("walk")
	var remapped_leg := false
	var lower_owns_upper_body := false
	for track in player_walk.get_track_count():
		var path := String(player_walk.track_get_path(track))
		remapped_leg = remapped_leg or ("Skeleton3D:thigh_l" in path)
	var lower_walk := player_visual.lower_animation_player.get_animation("walk")
	for track in lower_walk.get_track_count():
		if "Skeleton3D:upperarm_l" in String(lower_walk.track_get_path(track)):
			lower_owns_upper_body = lower_walk.track_is_enabled(track)
	check.call(remapped_leg, "player walking clip targets the Player skeleton after Mixamo bone-name retargeting")
	var upper_walk: Animation = player_visual.upper_animation_player.get_animation("walk")
	var upper_owns_arm := false
	for track in upper_walk.get_track_count():
		if "Skeleton3D:upperarm_l" in String(upper_walk.track_get_path(track)):
			upper_owns_arm = upper_walk.track_is_enabled(track)
	check.call(not lower_owns_upper_body and upper_owns_arm, "player locomotion isolates arm tracks into the upper-body layer")
	player_visual.advance_animation(0.1, "run", 1.0)
	check.call(player_visual.animation_player.get_current_animation() == "run", "player visual can switch to running clip")
	check.call(is_zero_approx(MixamoCharacterVisual.animation_interval_for_distance(7.9))
		and is_equal_approx(MixamoCharacterVisual.animation_interval_for_distance(8.0), 1.0 / 30.0)
		and is_equal_approx(MixamoCharacterVisual.animation_interval_for_distance(14.0), 1.0 / 15.0),
		"far-character animation cadence keeps nearby animation at full frequency")
	game.player.aim_mode = false
	game.player.visual_velocity = Vector2.ZERO
	view._update_actors(0.1)
	check.call(player_visual.animation_player.is_playing() and player_visual.animation_player.get_current_animation() == "idle"
		and not player_visual.upper_animation_player.is_playing(), "unprepared player uses one complete idle animation without an upper-body overlay")
	game.player._attack_cooldown_left = 0.0
	var attack_id_before := game.player.visual_attack_id
	game.player.try_attack()
	check.call(game.player.visual_attack_id == attack_id_before, "player cannot start an attack without the right-click ready stance")
	game.player.aim_mode = true
	game.player.try_attack()
	check.call(game.player.visual_attack_id == attack_id_before + 1, "right-click ready stance permits the player attack")
	view._update_actors(0.10)
	check.call(player_visual.upper_animation_player.is_playing() and player_visual.upper_animation_player.get_current_animation() == "attack"
		and player_visual.lower_animation_player.get_current_animation() != "attack"
		and is_equal_approx(player_visual.upper_animation_player.get_playing_speed(), PlayerController.ATTACK_ANIMATION_SPEED),
		"player attack uses only the upper-body attack clip at double speed")
	var prepared_phase := player_visual.upper_animation_player.get_current_animation_position()
	game.player.aim_mode = false
	view._update_actors(0.10)
	var released_phase := player_visual.upper_animation_player.get_current_animation_position()
	check.call(player_visual.upper_animation_player.is_playing() and player_visual.upper_animation_player.get_current_animation() == "attack"
		and not player_visual.animation_player.is_playing() and released_phase > prepared_phase,
		"releasing right-click keeps the original upper-body attack instead of starting a larger full-body replay")
	view._update_actors(0.10)
	check.call(player_visual.upper_animation_player.get_current_animation_position() > released_phase,
		"released attack advances once on its original animation track")
	game.player.visual_attack_remaining = 0.0
	view._update_actors(0.10)
	check.call(player_visual.animation_player.is_playing() and not player_visual.upper_animation_player.is_playing(),
		"complete attack returns to one full-body locomotion animation")
	game.player.interrupt_attack()
	game.player.aim_mode = true
	game.player.visual_attack_remaining = 0.0
	game.player.visual_velocity = Vector2.ZERO
	view._update_actors(0.1)
	player_visual.upper_animation_player.stop()
	view._update_actors(0.1)
	check.call(player_visual.upper_animation_player.get_current_animation() == "armed_idle", "right-click ready state holds the two-hand idle upper-body pose")
	game.player.aim_mode = false
	view._update_actors(0.1)
	check.call(player_visual.animation_player.is_playing() and not player_visual.upper_animation_player.is_playing(),
		"releasing right-click immediately returns the player to one complete body animation")
	game.player.visual_velocity = -game.player.facing_direction * PlayerController.WALK_SPEED * PlayerController.BACKWARD_MOVE_MULTIPLIER
	check.call(view._player_animation() == "back_walk", "backward player movement selects the downloaded backward-walk clip")
	game.player.visual_velocity = -game.player.facing_direction * PlayerController.WALK_SPEED * PlayerController.SPRINT_MULTIPLIER * PlayerController.BACKWARD_MOVE_MULTIPLIER
	check.call(view._player_animation() == "back_run", "backward player sprint selects the downloaded backward-run clip")
	game.player.visual_velocity = Vector2.ZERO

	var zombie_visual := MixamoCharacterVisual.new()
	game.add_child(zombie_visual)
	zombie_visual.setup(ActorBody.ZOMBIE)
	_check_library(zombie_visual, ZOMBIE_CLIPS, check, "zombie")
	var zombie_walk: Animation = zombie_visual.animation_player.get_animation("walk")
	var ignored_root_motion := false
	for track in zombie_walk.get_track_count():
		var path := String(zombie_walk.track_get_path(track))
		if "Hips" in path and zombie_walk.track_get_type(track) == Animation.TYPE_POSITION_3D:
			ignored_root_motion = not zombie_walk.track_is_enabled(track)
	check.call(ignored_root_motion, "zombie root translation is disabled so map simulation remains authoritative")
	zombie_visual.advance_animation(0.1, "attack", 1.0)
	check.call(zombie_visual.animation_player.get_current_animation() == "attack", "zombie visual can switch to attack clip")
	zombie_visual.animation_player.advance(3.0)
	zombie_visual.play_animation("attack", 0.0, 1.0, true)
	zombie_visual.animation_player.advance(0.1)
	check.call(zombie_visual.animation_player.is_playing() and zombie_visual.animation_player.get_current_animation_position() < 0.2,
		"zombie attack clip explicitly restarts after a completed attack")
	zombie_visual.free()
	view._process(0.0)


static func _check_library(visual: MixamoCharacterVisual, clips: Array, check: Callable, name: String) -> void:
	var library := visual.animation_player.get_animation_library("")
	for clip: String in clips:
		check.call(library != null and library.has_animation(clip), "%s Mixamo animation '%s' is imported" % [name, clip])
