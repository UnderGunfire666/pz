class_name MVPHud
extends CanvasLayer

var status_label: Label
var objective_label: Label
var help_label: Label
var notification_label: Label
var world_view: World3DView
var pause_button: Button
var normal_button: Button
var fast_button: Button


func _ready() -> void:
	var top_panel := ColorRect.new()
	top_panel.color = Color(0.025, 0.04, 0.055, 0.76)
	top_panel.position = Vector2(14.0, 14.0)
	top_panel.size = Vector2(310.0, 158.0)
	add_child(top_panel)

	status_label = Label.new()
	status_label.position = Vector2(12.0, 9.0)
	status_label.size = Vector2(286.0, 140.0)
	status_label.add_theme_font_size_override("font_size", 14)
	top_panel.add_child(status_label)

	var objective_panel := ColorRect.new()
	objective_panel.color = Color(0.025, 0.04, 0.055, 0.76)
	objective_panel.anchor_left = 0.5
	objective_panel.anchor_right = 0.5
	objective_panel.offset_left = -280.0
	objective_panel.offset_top = 14.0
	objective_panel.offset_right = 280.0
	objective_panel.offset_bottom = 76.0
	add_child(objective_panel)

	objective_label = Label.new()
	objective_label.position = Vector2(12.0, 7.0)
	objective_label.size = Vector2(536.0, 48.0)
	objective_label.add_theme_font_size_override("font_size", 14)
	objective_panel.add_child(objective_label)

	var time_panel := ColorRect.new()
	time_panel.color = Color(0.025, 0.04, 0.055, 0.82)
	time_panel.anchor_left = 1.0
	time_panel.anchor_right = 1.0
	time_panel.offset_left = -356.0
	time_panel.offset_top = 14.0
	time_panel.offset_right = -14.0
	time_panel.offset_bottom = 60.0
	add_child(time_panel)

	var controls := HBoxContainer.new()
	controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls.offset_left = 6.0
	controls.offset_top = 4.0
	controls.offset_right = -6.0
	controls.offset_bottom = -4.0
	controls.add_theme_constant_override("separation", 4)
	time_panel.add_child(controls)

	pause_button = _add_time_button(controls, "Pause")
	pause_button.pressed.connect(_toggle_pause)
	normal_button = _add_time_button(controls, "1x")
	normal_button.pressed.connect(_set_normal_speed)
	fast_button = _add_time_button(controls, "3x")
	fast_button.pressed.connect(_set_fast_speed)
	_add_time_button(controls, "+").pressed.connect(func() -> void: adjust_zoom(1.12))
	_add_time_button(controls, "-").pressed.connect(func() -> void: adjust_zoom(1.0 / 1.12))

	var help_panel := ColorRect.new()
	help_panel.color = Color(0.025, 0.04, 0.055, 0.78)
	help_panel.anchor_top = 1.0
	help_panel.anchor_bottom = 1.0
	help_panel.offset_left = 14.0
	help_panel.offset_top = -82.0
	help_panel.offset_right = 900.0
	help_panel.offset_bottom = -14.0
	add_child(help_panel)

	help_label = Label.new()
	help_label.position = Vector2(12.0, 7.0)
	help_label.size = Vector2(876.0, 56.0)
	help_label.add_theme_font_size_override("font_size", 13)
	help_panel.add_child(help_label)

	notification_label = Label.new()
	notification_label.anchor_left = 0.5
	notification_label.anchor_right = 0.5
	notification_label.position = Vector2(-270.0, 82.0)
	notification_label.size = Vector2(540.0, 32.0)
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label.add_theme_font_size_override("font_size", 16)
	add_child(notification_label)


func setup(p_world_view: World3DView) -> void:
	world_view = p_world_view


func refresh(game: MVPGameRoot) -> void:
	if status_label == null:
		return
	var survival := game.player_state.survival
	status_label.text = (
		"AFTERLIGHT — ORANGEVILLE\n"
		+ "%s  •  %s\n\n" % [GameTime.formatted_time(), GameTime.speed_name()]
		+ "Hunger %3d  Thirst %3d\n" % [survival.hunger, survival.thirst]
		+ "Fatigue %3d  Stamina %3d\n" % [survival.fatigue, survival.stamina]
		+ "Wound: %s\n" % game.player_state.visible_wound_summary()
		+ "Floor %d  |  Stress %3d  |  Pack %.1f/%.1f kg"
		% [
			game.player.floor_level + 1,
			game.world_map.stress_at(game.player.logical_position, game.local_zombie_count()),
			game.inventory.current_weight(),
			game.inventory.max_weight,
		]
	)
	objective_label.text = (
		game.objective_text() + "\n" + game.milestone_summary()
	)
	help_label.text = (
		"WASD move  Shift sprint  RMB aim  LMB attack  E interact  F eat  V drink  R sort\n"
		+ "MMB drag rotate  Wheel / +/- zoom  Walk up/down the ramp to change floors  Space pause\n"
		+ "Time buttons: pause / 1x / 3x\n"
		+ game.interactions.prompt()
	)
	notification_label.text = game.notification
	pause_button.button_pressed = GameTime.speed_mode == GameTime.SpeedMode.PAUSED
	normal_button.button_pressed = GameTime.speed_mode == GameTime.SpeedMode.NORMAL
	fast_button.button_pressed = GameTime.speed_mode == GameTime.SpeedMode.FAST


func adjust_zoom(factor: float) -> void:
	if world_view == null:
		return
	var zoom_factor := clampf(factor, 0.5, 2.0)
	world_view.set_zoom_factor(zoom_factor)


func _add_time_button(parent: HBoxContainer, label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.toggle_mode = label in ["Pause", "1x", "3x"]
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 13)
	parent.add_child(button)
	return button


func _toggle_pause() -> void:
	GameTime.toggle_pause()


func _set_normal_speed() -> void:
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)


func _set_fast_speed() -> void:
	GameTime.set_speed(GameTime.SpeedMode.FAST)
