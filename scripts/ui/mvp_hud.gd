class_name MVPHud
extends CanvasLayer

var status_label: Label
var objective_label: Label
var help_label: Label
var notification_label: Label
var prompt_label: Label
var floor_label: Label
var detail_label: Label
var details: PanelContainer
var help_panel: PanelContainer
var pack_grid: GridContainer
var world_view: World3DView
var pause_button: Button
var normal_button: Button
var fast_button: Button
var _last_inventory := ""


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := _panel(root)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_top = 10
	top.offset_right = -10
	var rows := VBoxContainer.new()
	top.add_child(rows)
	var bar := HBoxContainer.new()
	rows.add_child(bar)
	floor_label = _label(bar, 15)
	floor_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floor_label.text = "AFTERLIGHT"
	pause_button = _button(bar, "Pause", func() -> void: GameTime.toggle_pause(), true)
	normal_button = _button(bar, "1x", func() -> void: GameTime.set_speed(GameTime.SpeedMode.NORMAL), true)
	fast_button = _button(bar, "3x", func() -> void: GameTime.set_speed(GameTime.SpeedMode.FAST), true)
	_button(bar, "+", func() -> void: adjust_zoom(1.12))
	_button(bar, "−", func() -> void: adjust_zoom(1.0 / 1.12))
	_button(bar, "Pack / health", func() -> void: details.visible = not details.visible)
	_button(bar, "Help", func() -> void: help_panel.visible = not help_panel.visible)
	status_label = _label(rows, 14)

	details = _panel(root)
	details.position = Vector2(10, 90)
	details.custom_minimum_size = Vector2(310, 0)
	details.visible = false
	var content := VBoxContainer.new()
	details.add_child(content)
	detail_label = _label(content, 14)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size.x = 290
	pack_grid = GridContainer.new()
	pack_grid.columns = 6
	content.add_child(pack_grid)

	help_panel = _panel(root)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	help_panel.offset_left = -420
	help_panel.offset_right = -10
	help_panel.offset_top = 90
	help_panel.visible = false
	help_label = _label(help_panel, 14)
	help_label.text = ("WASD move · Shift sprint\nRMB aim · LMB attack · E interact\nF eat · V drink · R sort · Esc cancel action\nMMB drag rotate · Wheel zoom\nSpace pause · 1 normal · 2 fast-forward\nWalk into a stair landing to go up/down.\nF5 quick save · F9 load (paused)\nAfter death: Enter starts a new run.")

	var bottom := _panel(root)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 10
	bottom.offset_right = -10
	bottom.offset_top = -94
	bottom.offset_bottom = -10
	var messages := VBoxContainer.new()
	bottom.add_child(messages)
	objective_label = _label(messages, 14)
	prompt_label = _label(messages, 15)
	notification_label = _label(messages, 14)


func _panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.055, 0.85)
	style.set_content_margin_all(8.0)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable, toggle: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = toggle
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func setup(p_view: World3DView) -> void:
	world_view = p_view


func refresh(game: MVPGameRoot) -> void:
	var tile := game.world_map.get_tile(game.player.logical_position, game.player.floor_level)
	var place := "Outdoors"
	if tile != null and not tile.building_id.is_empty():
		place = game.world_map.buildings[tile.building_id].name
	var stair_text := ""
	if not game.player.stair_id.is_empty():
		var link: StairLink = game.world_map.stairs[game.player.stair_id]
		stair_text = " · Stairs %d↔%d" % [link.from_floor + 1, link.to_floor + 1]
	var display_floor := game.world_map.display_floor_at(game.player.logical_position, game.player.floor_level, game.player.stair_id)
	floor_label.text = "%s · %s · Floor %d%s" % [GameTime.formatted_time(), place, display_floor + 1, stair_text]
	var needs := game.player_state.survival
	status_label.text = "Health %d · Hunger %d · Thirst %d · Fatigue %d · Stamina %d · Stress %d   |   %.1f / %.1f kg" % [
		game.player_state.health, needs.hunger, needs.thirst, needs.fatigue, needs.stamina,
		game.world_map.stress_at(game.player.logical_position, game.local_zombie_count(), game.player.floor_level),
		game.inventory.current_weight(), game.inventory.max_weight]
	detail_label.text = "Wound: %s\n%s\nPack 6 × 4 · F eat · V drink · R sort" % [
		game.player_state.visible_wound_summary(), game.inventory.summary()]
	if details.visible:
		_refresh_pack(game.inventory)
	objective_label.text = game.objective_text()
	prompt_label.text = game.interactions.prompt()
	notification_label.text = game.notification
	if game.player_state.is_dead():
		objective_label.text = "You died · Enter: new run · F9: load quick save"
	pause_button.set_pressed_no_signal(GameTime.speed_mode == GameTime.SpeedMode.PAUSED)
	normal_button.set_pressed_no_signal(GameTime.speed_mode == GameTime.SpeedMode.NORMAL)
	fast_button.set_pressed_no_signal(GameTime.speed_mode == GameTime.SpeedMode.FAST)
	for button in [pause_button, normal_button, fast_button]:
		button.disabled = game.player_state.is_dead()


func _refresh_pack(inventory: InventoryGrid) -> void:
	var signature := inventory.summary() + str(inventory.placements)
	if signature == _last_inventory:
		return
	_last_inventory = signature
	for child in pack_grid.get_children():
		pack_grid.remove_child(child)
		child.queue_free()
	for y in range(inventory.grid_size.y):
		for x in range(inventory.grid_size.x):
			var slot := Vector2i(x, y)
			var label := Label.new()
			label.custom_minimum_size = Vector2(42, 24)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.text = "·"
			for placement in inventory.placements:
				var item: ItemStack = placement["stack"]
				if Rect2i(placement["slot"], item.definition.grid_size).has_point(slot):
					label.text = item.definition.display_name.left(1)
					label.tooltip_text = item.label()
					label.modulate = Color("85cce9")
			pack_grid.add_child(label)


func adjust_zoom(factor: float) -> void:
	if world_view != null:
		world_view.set_zoom_factor(clampf(factor, 0.5, 2.0))
