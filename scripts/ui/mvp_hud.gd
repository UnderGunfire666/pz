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
var pack_panel: BackpackPanel
var character_panel: CharacterStatusPanel
var character_creation_panel: CharacterCreationPanel
var world_view: World3DView
var pause_button: Button
var normal_button: Button
var fast_button: Button
var _last_inventory := ""
var _last_presentation_signature := ""
var _cached_weight := 0.0
var _cached_weight_revision := -1
var _presentation_refresh_count := 0
var action_row: HBoxContainer
var action_bar: ProgressBar
var action_label: Label
var _game: MVPGameRoot
var drop_surface: InventoryDropSurface
var crosshair: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.add_theme_font_size_override("font_size", 24)
	root.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -12
	crosshair.offset_top = -18
	crosshair.offset_right = 12
	crosshair.offset_bottom = 18
	drop_surface = InventoryDropSurface.new()
	drop_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drop_surface.mouse_filter = Control.MOUSE_FILTER_PASS
	drop_surface.hide()
	root.add_child(drop_surface)
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
	_button(bar, "Inventory", toggle_inventory)
	_button(bar, "Character [C]", toggle_character_panel)
	_button(bar, "Help", func() -> void: help_panel.visible = not help_panel.visible)
	status_label = _label(rows, 14)

	details = _panel(root)
	details.position = Vector2(10, 90)
	details.custom_minimum_size = Vector2(800, 0)
	details.visible = false
	var content := VBoxContainer.new()
	details.add_child(content)
	detail_label = _label(content, 14)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size.x = 780
	pack_panel = BackpackPanel.new()
	content.add_child(pack_panel)
	drop_surface.panel = pack_panel
	details.visibility_changed.connect(func() -> void: drop_surface.visible = details.visible)
	character_panel = CharacterStatusPanel.new()
	character_panel.position = Vector2(220, 90)
	character_panel.custom_minimum_size = Vector2(840, 0)
	character_panel.visible = false
	root.add_child(character_panel)
	character_creation_panel = CharacterCreationPanel.new()
	character_creation_panel.hide()
	character_creation_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	character_creation_panel.position = Vector2(-450, -285)
	character_creation_panel.custom_minimum_size = Vector2(900, 570)
	root.add_child(character_creation_panel)

	help_panel = _panel(root)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	help_panel.offset_left = -420
	help_panel.offset_right = -10
	help_panel.offset_top = 90
	help_panel.visible = false
	help_label = _label(help_panel, 14)
	help_label.text = ("Mouse look · WASD move/strafe · Shift sprint\nRMB aim · LMB attack · E interact · Tab inventory · C character\nF eat · V drink · R sort\nEsc close panel / release cursor and cancel action\nClick the world to resume mouse look. No camera zoom.\nSpace pause · 1 normal · 2 fast-forward\nWalk into a stair landing to go up/down.\nF5 quick save · F9 load (paused)\nAfter death: Enter starts a new run.")

	var bottom := _panel(root)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 10
	bottom.offset_right = -10
	bottom.offset_top = -94
	bottom.offset_bottom = -10
	var messages := VBoxContainer.new()
	bottom.add_child(messages)
	action_row = HBoxContainer.new()
	messages.add_child(action_row)
	action_label = _label(action_row, 14)
	action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_bar = ProgressBar.new()
	action_bar.custom_minimum_size = Vector2(160, 18)
	action_row.add_child(action_bar)
	_button(action_row, "×", func() -> void:
		if _game != null: _game.interactions.interrupt_action("Cancelled"))
	action_row.visible = false
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

func _setup_character_creation() -> void:
	if _game != null: character_creation_panel.setup(_game)


func refresh(game: MVPGameRoot) -> void:
	_game = game
	# Aim can change while the cached status/inventory signature stays identical.
	var focus := PlayerTargeting.interaction_target(game.interactions)
	prompt_label.text = game.interactions.prompt(focus)
	crosshair.modulate = Color.WHITE if focus.is_empty() else (Color("86e3a1") if focus["reachable"] else Color("efbc72"))
	if not game.interactions.container_view_requested.is_connected(_view_container):
		game.interactions.container_view_requested.connect(_view_container)
	action_row.visible = not game.interactions.active_action.is_empty()
	if action_row.visible:
		action_label.text = game.interactions.active_action["label"]
		action_bar.value = game.interactions.action_progress() * 100.0
	var weight := _display_weight(game.inventory)
	var player_cell := Vector2i(game.player.logical_position * 4.0)
	var needs := game.player_state.survival
	var signature := str([
		int(GameTime.elapsed_game_seconds / 60.0), player_cell, game.player.floor_level, game.player.stair_id,
		int(round(game.player_state.health)), int(needs.hunger), int(needs.thirst), int(needs.fatigue), int(needs.stamina),
		int(round(game.player_state.pain)), int(round(game.player_state.panic)), int(round(game.player_state.stress)),
		int(round(game.player_state.boredom)), int(round(game.player_state.unhappiness)),
		int(round(game.player_state.core_temperature * 100.0)), game.inventory.revision,
		game.milestones, game.notification, GameTime.speed_mode, game.player_state.is_dead()])
	if signature == _last_presentation_signature:
		return
	_last_presentation_signature = signature
	_presentation_refresh_count += 1
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
	status_label.text = "Health %d · Hunger %d · Thirst %d · Fatigue %d · Stamina %d   |   %.1f / %.1f kg" % [
		game.player_state.health, needs.hunger, needs.thirst, needs.fatigue, needs.stamina,
		weight, game.inventory.absolute_limit]
	status_label.text += " · penalty %.1f kg  %s" % [game.inventory.penalty_limit, _status_icons(game.player_state)]
	status_label.modulate = Color(1, 0.35, 0.3) if weight >= game.inventory.absolute_limit * 0.9 else (Color(1, 0.75, 0.3) if weight > game.inventory.penalty_limit else Color.WHITE)
	detail_label.text = "Wound: %s\n%s\nF eat · V drink · R sort" % [
		game.player_state.visible_wound_summary(), game.inventory.summary()]
	if details.visible:
		pack_panel.refresh(game)
	if character_panel.visible:
		character_panel.refresh(game)
	objective_label.text = game.objective_text()
	notification_label.text = game.notification
	if game.player_state.is_dead():
		objective_label.text = "You died · Enter: new run · F9: load quick save"
	pause_button.set_pressed_no_signal(GameTime.speed_mode == GameTime.SpeedMode.PAUSED)
	normal_button.set_pressed_no_signal(GameTime.speed_mode == GameTime.SpeedMode.NORMAL)
	fast_button.set_pressed_no_signal(GameTime.speed_mode == GameTime.SpeedMode.FAST)
	for button in [pause_button, normal_button, fast_button]:
		button.disabled = game.player_state.is_dead()


func _display_weight(inventory: InventoryGrid) -> float:
	if _cached_weight_revision != inventory.revision:
		_cached_weight = inventory.current_weight()
		_cached_weight_revision = inventory.revision
	return _cached_weight


func has_open_panel() -> bool:
	return details.visible or character_panel.visible or character_creation_panel.visible or help_panel.visible


func close_panels() -> void:
	for panel: Control in [details, character_panel, character_creation_panel, help_panel]:
		panel.hide()


func _status_icons(state: PlayerState) -> String:
	var entries: Array[String] = []
	for data in [
		["🍽", state.survival.hunger, true], ["💧", state.survival.thirst, true],
		["☾", state.survival.fatigue, true], ["⚡", state.survival.stamina, true],
		["✚", state.pain, false], ["!", state.panic, false], ["≈", state.stress, false],
		["…", state.boredom, false], ["☹", state.unhappiness, false]]:
		var tier := StatusConfig.severity_tier(data[1], data[2])
		if tier > 0: entries.append("%s%d" % [data[0], tier])
	var temperature_tier := state.temperature_tier()
	if temperature_tier > 0: entries.append("%s%d" % ["♨" if state.core_temperature > StatusConfig.NORMAL_BODY_TEMPERATURE else "❄", temperature_tier])
	return " ".join(entries)


func toggle_inventory() -> void:
	details.visible = not details.visible
	if details.visible: character_panel.hide()


func toggle_character_panel() -> void:
	character_panel.visible = not character_panel.visible
	if character_panel.visible:
		details.hide()
		help_panel.hide()
		if _game != null: character_panel.refresh(_game)


func pointer_over_page(screen_position: Vector2) -> bool:
	for panel: Control in [details, character_panel, character_creation_panel]:
		if panel.visible and panel.get_global_rect().has_point(screen_position): return true
	return false

func _view_container(id: String) -> void:
	character_panel.hide()
	details.show()
	pack_panel.presentation.sides[1]["selected"] = "ground" if id.begins_with("dropped_") else id
	pack_panel.last_signature = ""
	pack_panel.refresh(_game)
	pack_panel.presentation.save_preferences()
