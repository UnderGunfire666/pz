class_name CharacterCreationPanel
extends PanelContainer

var occupation_picker: OptionButton
var points_label: Label
var trait_tree: Tree
var confirm_button: Button
var _game: MVPGameRoot
var _occupation_ids: Array[String] = []
var _selected_trait_ids: Array[String] = []


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.028, 0.04, 0.98)
	style.set_content_margin_all(16.0)
	style.set_corner_radius_all(5)
	add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	add_child(content)
	var title := Label.new()
	title.text = "CREATE SURVIVOR · Project Zomboid 42.21 rules"
	title.add_theme_font_size_override("font_size", 20)
	content.add_child(title)
	var occupation_row := HBoxContainer.new()
	content.add_child(occupation_row)
	var occupation_label := Label.new()
	occupation_label.text = "Occupation"
	occupation_row.add_child(occupation_label)
	occupation_picker = OptionButton.new()
	occupation_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	occupation_picker.item_selected.connect(_on_occupation_selected)
	occupation_row.add_child(occupation_picker)
	points_label = Label.new()
	points_label.add_theme_font_size_override("font_size", 16)
	content.add_child(points_label)
	trait_tree = Tree.new()
	trait_tree.columns = 3
	trait_tree.hide_root = true
	trait_tree.column_titles_visible = true
	trait_tree.custom_minimum_size = Vector2(860, 430)
	trait_tree.set_column_title(0, "Trait")
	trait_tree.set_column_title(1, "Cost")
	trait_tree.set_column_title(2, "Description")
	trait_tree.set_column_expand(0, false)
	trait_tree.set_column_custom_minimum_width(0, 230)
	trait_tree.set_column_expand(1, false)
	trait_tree.set_column_custom_minimum_width(1, 60)
	trait_tree.item_edited.connect(_on_trait_edited)
	content.add_child(trait_tree)
	confirm_button = Button.new()
	confirm_button.text = "Start"
	confirm_button.pressed.connect(_confirm)
	content.add_child(confirm_button)


func setup(game: MVPGameRoot) -> void:
	_game = game
	occupation_picker.clear()
	_occupation_ids.clear()
	var occupations: Array = game.character_catalog.occupations.values()
	occupations.sort_custom(func(a: OccupationDefinition, b: OccupationDefinition) -> bool: return a.display_name < b.display_name)
	for occupation: OccupationDefinition in occupations:
		_occupation_ids.append(occupation.id)
		occupation_picker.add_item("%s (%+d)" % [occupation.display_name, occupation.point_bonus])
	var default_index := _occupation_ids.find(game.character_catalog.rules.default_occupation_id)
	occupation_picker.select(maxi(0, default_index))
	_rebuild_traits()
	visible = not game.player_state.character.creation_complete
	if visible: GameTime.set_speed(GameTime.SpeedMode.PAUSED)


func _rebuild_traits() -> void:
	trait_tree.clear()
	var root := trait_tree.create_item()
	var definitions: Array = _game.character_catalog.traits.values().filter(func(value: TraitDefinition) -> bool: return value.selectable)
	definitions.sort_custom(func(a: TraitDefinition, b: TraitDefinition) -> bool:
		return a.cost < b.cost or (a.cost == b.cost and a.display_name < b.display_name))
	for definition: TraitDefinition in definitions:
		var row := trait_tree.create_item(root)
		row.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		row.set_checked(0, definition.id in _selected_trait_ids)
		row.set_editable(0, true)
		row.set_text(0, definition.display_name)
		row.set_text(1, "%+d" % definition.cost)
		row.set_text(2, definition.description.replace("\n", " "))
		row.set_metadata(0, definition.id)
	_update_validity()


func _on_occupation_selected(_index: int) -> void:
	_update_validity()


func _on_trait_edited() -> void:
	var row := trait_tree.get_edited()
	if row == null: return
	var id := String(row.get_metadata(0))
	if row.is_checked(0):
		if not id in _selected_trait_ids: _selected_trait_ids.append(id)
	else:
		_selected_trait_ids.erase(id)
	_update_validity()


func _update_validity() -> void:
	if _game == null or _occupation_ids.is_empty(): return
	var occupation_id := _occupation_ids[occupation_picker.selected]
	var character := _game.player_state.character
	var errors := character.selection_errors(_selected_trait_ids, occupation_id)
	var balance := character.point_balance(_selected_trait_ids, occupation_id)
	points_label.text = "Points remaining: %d%s" % [balance, " · " + errors[0] if not errors.is_empty() else ""]
	points_label.modulate = Color(1.0, 0.45, 0.35) if not errors.is_empty() else Color.WHITE
	confirm_button.disabled = not errors.is_empty()


func _confirm() -> void:
	var errors := _game.player_state.character.select_build(_occupation_ids[occupation_picker.selected], _selected_trait_ids)
	if not errors.is_empty():
		_update_validity()
		return
	visible = false
	GameTime.set_speed(GameTime.SpeedMode.NORMAL)
	_game.show_notification("Survivor created. Character choices are now fixed.")
