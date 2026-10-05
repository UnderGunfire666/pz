class_name FirstPersonTests
extends RefCounted


static func run(game: MVPGameRoot, check: Callable) -> void:
	var view := game.world_3d_view
	var rig := view.view_rig
	var saved_position := game.player.logical_position
	var saved_floor := game.player.floor_level
	var saved_facing := game.player.facing_direction
	var saved_stair := game.player.stair_id
	check.call(view.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "first person uses perspective projection")
	check.call(game.hud.crosshair.get_global_rect().get_center().distance_to(game.get_viewport().get_visible_rect().get_center()) < 1.0,
		"crosshair is anchored at the viewport center")
	for facing in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		game.player.facing_direction = facing
		view.sync_view_to_player()
		check.call(view.input_to_logical(Vector2.UP).is_equal_approx(facing), "W follows the camera heading in every quadrant")
		check.call(absf(view.input_to_logical(Vector2.RIGHT).dot(facing)) < 0.001, "D strafes perpendicular to heading")
		var forward := -view.camera.global_basis.z
		check.call(Vector2(forward.x, forward.z).is_equal_approx(facing), "center camera ray agrees with simulation heading")
	view.orbit_camera(Vector2(5000, -100000))
	check.call(absf(rig.pitch) <= PlayerViewRig.PITCH_LIMIT and game.player.facing_direction.is_equal_approx(rig.facing_direction()),
		"mouse look wraps yaw, clamps pitch and synchronizes actor facing")
	var before := view.camera.global_position
	var fov := view.camera.fov
	view._update_camera(0.1)
	check.call(view.camera.global_position.is_equal_approx(before) and view.camera.fov == fov, "camera updates retain fixed first-person position and FOV")
	for stair: StairLink in game.world_map.stairs.values():
		game.player.logical_position = stair.start.lerp(stair.end, 0.5)
		game.player.floor_level = stair.from_floor
		game.player.stair_id = stair.id
		view._update_camera(0.01)
		var height := game.world_map.elevation_at(game.player.logical_position, stair.from_floor, stair.id)
		check.call(is_equal_approx(view.camera.global_position.y, height + PlayerViewRig.EYE_HEIGHT), "stairs keep the eye at fixed height above the player")
	game.player.logical_position = Vector2(3.5, 3.5)
	game.player.floor_level = 0
	game.player.stair_id = ""
	view.refresh_after_load()
	var opaque := true
	var roof_visible := false
	for entry: Dictionary in view.streamer.resident.values():
		for mesh: MeshInstance3D in (entry["node"] as Node3D).get_children():
			opaque = opaque and (mesh.material_override as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			if mesh.name == "roof": roof_visible = mesh.is_visible_in_tree()
	check.call(opaque and roof_visible, "resident building geometry and roofs remain opaque in first person")
	check.call(not (view.actor_visuals[game.player.get_instance_id()]["root"] as Node3D).visible, "local body is hidden in first person")
	game.mouse_released = false
	game.hud.close_panels()
	game.hud.toggle_inventory()
	check.call(not game.player.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "inventory releases pointer and blocks gameplay input")
	game.hud.toggle_inventory()
	check.call(game.player.controls_enabled and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED), "closing inventory resumes mouse look")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._input(escape)
	check.call(not game.player.controls_enabled, "Escape releases gameplay capture")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game.player._attack_cooldown_left = 0.0
	game._unhandled_input(click)
	check.call(game.player.controls_enabled and game.player._attack_cooldown_left == 0.0, "resume click captures the cursor without attacking")
	game.player.logical_position = saved_position
	game.player.floor_level = saved_floor
	game.player.stair_id = saved_stair
	game.player.look_pitch = 0.0
	game.player.facing_direction = saved_facing
	view.sync_view_to_player()
	view._process(0.0)
