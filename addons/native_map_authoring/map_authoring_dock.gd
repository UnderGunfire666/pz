@tool
class_name MapAuthoringDock
extends VBoxContainer

signal playtest_requested(map_path: String)
const OPS = preload("res://addons/native_map_authoring/map_edit_operations.gd")
const CANVAS = preload("res://addons/native_map_authoring/map_edit_canvas.gd")
const VALIDATOR = preload("res://scripts/systems/map_validator.gd")
const TERRAINS = [preload("res://resources/maps/terrain/grass.tres"), preload("res://resources/maps/terrain/soil.tres"), preload("res://resources/maps/terrain/water.tres")]
var undo_redo: EditorUndoRedoManager
var map: MapDefinition
var world: WorldMap
var map_picker := EditorResourcePicker.new()
var template_picker := EditorResourcePicker.new()
var tool := OptionButton.new()
var terrain := OptionButton.new()
var level := SpinBox.new()
var heat := SpinBox.new()
var width := SpinBox.new()
var size_x := SpinBox.new()
var size_y := SpinBox.new()
var rotation_picker := OptionButton.new()
var mirror := CheckBox.new()
var heat_overlay := CheckBox.new()
var adjacent := CheckBox.new()
var status := Label.new()
var canvas: Control
var preview: MapAuthoringPreview3D
var confirmation := ConfirmationDialog.new()
var save_dialog := EditorFileDialog.new()
var template_dialog := EditorFileDialog.new()
var selected_house := ""
var selected_rect := Rect2i()
var template: MapBuildingTemplate
var moving_house := ""
var pending: Dictionary = {}
var body := VBoxContainer.new()

func _ready() -> void:
	name = "Map Authoring"
	custom_minimum_size = Vector2(340, 500)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	map_picker.base_type = "MapDefinition"
	map_picker.resource_changed.connect(_set_map)
	body.add_child(map_picker)
	var buttons := HBoxContainer.new()
	body.add_child(buttons)
	_button(buttons, "Open demo", func() -> void: _set_map(load("res://resources/maps/orangeville_prototype.tres")))
	_button(buttons, "New", _new_map)
	_button(buttons, "Save", _save)
	_button(buttons, "Save as", func() -> void: save_dialog.popup_centered_ratio(0.65))
	_button(buttons, "Validate", _validate)
	_spin(size_x, 1, 4096, 64)
	_spin(size_y, 1, 4096, 64)
	var sizes := HBoxContainer.new()
	body.add_child(sizes)
	sizes.add_child(size_x)
	sizes.add_child(size_y)
	_button(sizes, "Resize", _resize)
	_spin(level, 0, 20, 0)
	level.allow_greater = true
	level.value_changed.connect(func(_value: float) -> void: _refresh_visuals())
	_row("Active floor (0 = ground)", level)
	for label in ["Select", "Terrain", "Road", "Indoor floor", "Wall", "Door", "Window", "Erase wall", "Stair", "Erase stair", "Erase floor", "Erase road", "Stamp template"]:
		tool.add_item(label)
	tool.item_selected.connect(func(_index: int) -> void: _refresh_visuals())
	_row("Tool", tool)
	for label in ["Grass", "Soil", "Water"]: terrain.add_item(label)
	_row("Base terrain", terrain)
	_spin(width, 1, 16, 1)
	_row("Road width (whole cells)", width)
	_spin(heat, 0, 1, 0.1)
	heat.step = 0.01
	_row("Heat (0 excludes; 1 highest weight)", heat)
	_button(body, "Apply heat to selection", _apply_selected_heat)
	heat_overlay.text = "Heat overlay: blue 0 → red 1"
	heat_overlay.toggled.connect(func(_on: bool) -> void: _refresh_visuals())
	body.add_child(heat_overlay)
	adjacent.text = "Show adjacent floors as references"
	adjacent.button_pressed = true
	adjacent.toggled.connect(func(_on: bool) -> void: _refresh_visuals())
	body.add_child(adjacent)
	for degrees in [0, 90, 180, 270]: rotation_picker.add_item("%d°" % degrees)
	_row("Template / stair rotation", rotation_picker)
	mirror.text = "Mirror template"
	body.add_child(mirror)
	template_picker.base_type = "MapBuildingTemplate"
	template_picker.resource_changed.connect(func(value: Resource) -> void:
		template = value as MapBuildingTemplate
		if template != null: tool.select(12)
		_refresh_visuals())
	_row("House template", template_picker)
	var house_buttons := HBoxContainer.new()
	body.add_child(house_buttons)
	_button(house_buttons, "Save template", _save_template)
	_button(house_buttons, "Copy house", func() -> void: _copy_house(false))
	_button(house_buttons, "Move house", func() -> void: _copy_house(true))
	_button(house_buttons, "Delete house", _delete_house)
	_button(body, "Toggle selected house roof", _toggle_roof)
	canvas = CANVAS.new()
	canvas.custom_minimum_size = Vector2(320, 420)
	canvas.clip_contents = true
	canvas.gesture.connect(_gesture)
	canvas.hover_changed.connect(_hover)
	body.add_child(canvas)
	preview = MapAuthoringPreview3D.new()
	body.add_child(preview)
	var help := Label.new()
	help.text = "Select a house before editing its floors/walls/stairs. Drag terrain/floor rectangles; draw walls along grid edges. Stairs rise 3 cells toward the selected direction. Wheel zooms; middle-drag pans. Ctrl+Z/Ctrl+Shift+Z undo/redo."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(help)
	_button(body, "Play saved map", _playtest)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	add_child(confirmation)
	confirmation.confirmed.connect(_commit_pending)
	confirmation.canceled.connect(func() -> void:
		pending.clear()
		canvas.cropping = Rect2i()
		canvas.queue_redraw())
	add_child(save_dialog)
	save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	save_dialog.add_filter("*.tres", "Map resource")
	save_dialog.file_selected.connect(_save_path)
	add_child(template_dialog)
	template_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	template_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	template_dialog.add_filter("*.tres", "House template")
	template_dialog.file_selected.connect(func(path: String) -> void:
		if template != null:
			var error := ResourceSaver.save(template, path)
			status.text = "Template saved: " + path if error == OK else error_string(error))
	_set_map(load("res://resources/maps/orangeville_prototype.tres"))

func _exit_tree() -> void:
	if world != null: world.free()

func _button(parent: Node, label: String, action: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	parent.add_child(button)

func _row(label: String, control: Control) -> void:
	var caption := Label.new()
	caption.text = label
	body.add_child(caption)
	body.add_child(control)

func _spin(control: SpinBox, minimum: float, maximum: float, value: float) -> void:
	control.min_value = minimum
	control.max_value = maximum
	control.step = 1.0
	control.value = value

func _set_map(resource: Resource) -> void:
	map = resource as MapDefinition
	selected_house = ""
	selected_rect = Rect2i()
	moving_house = ""
	pending.clear()
	confirmation.hide()
	map_picker.edited_resource = map
	if map == null: return
	var bounds := OPS.bounds(map)
	size_x.value = bounds.size.x
	size_y.value = bounds.size.y
	_refresh()

func _refresh() -> void:
	if world != null: world.free()
	world = OPS.adapter(map)
	canvas.world = world
	canvas.selection = selected_rect
	_refresh_visuals()
	preview.show_map(map)

func _refresh_visuals() -> void:
	if canvas == null: return
	canvas.level = int(level.value)
	canvas.mode = tool.get_item_text(tool.selected)
	canvas.show_heat = heat_overlay.button_pressed
	canvas.show_adjacent = adjacent.button_pressed
	canvas.ghost = Rect2i()
	canvas.queue_redraw()

func _gesture(start: Vector2, finish: Vector2, path: Array[Vector2i]) -> void:
	if map == null or not pending.is_empty(): return
	var rect := Rect2i(Vector2i(start.floor().min(finish.floor())), Vector2i(start.floor().max(finish.floor()) - start.floor().min(finish.floor())) + Vector2i.ONE)
	var mode := tool.get_item_text(tool.selected)
	if mode == "Select":
		selected_rect = rect
		var house := OPS.house_at(map, Vector2i(finish.floor()))
		selected_house = house.id if house != null else ""
		if rect.size == Vector2i.ONE:
			var tile := world.get_tile_at(rect.position, int(level.value))
			if tile != null: heat.value = tile.zombie_pressure
		canvas.selection = selected_rect
		canvas.queue_redraw()
		status.text = "Selected " + (house.effective_display_name() if house != null else str(selected_rect))
		return
	var proposal := OPS.snapshot(map)
	var result: Dictionary
	match mode:
		"Terrain":
			if level.value != 0: status.text = "Base terrain is edited on floor 0."; return
			result = OPS.paint_terrain(proposal, rect, TERRAINS[terrain.selected])
		"Road":
			if level.value != 0: status.text = "Roads are painted on ground level."; return
			result = OPS.brush(proposal, path, int(width.value))
		"Indoor floor": result = OPS.paint_floor(proposal, rect, int(level.value), selected_house)
		"Wall", "Door", "Window", "Erase wall":
			result = OPS.wall(proposal, start.round(), finish.round(), int(level.value), "erase" if mode == "Erase wall" else mode.to_lower(), selected_house)
		"Stair":
			var direction: Vector2 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][rotation_picker.selected]
			result = OPS.place_stair(proposal, finish.floor() + Vector2(0.5, 0.5), direction, int(level.value), selected_house)
		"Erase stair":
			result = _erase_stair(proposal, finish)
		"Erase floor":
			result = _erase_floor(proposal, rect)
		"Erase road":
			for road in proposal.roads.duplicate():
				var remaining := OPS.road_cells(road)
				for point in OPS.cells(rect): remaining.erase(point)
				if remaining.is_empty(): proposal.roads.erase(road)
				else: road.grid_cells = remaining
		"Stamp template":
			if template == null: status.text = "Choose or capture a house template first."; return
			var stamp := OPS.transformed(template, rotation_picker.selected, mirror.button_pressed)
			if not moving_house.is_empty():
				for house in proposal.buildings.duplicate():
					if house.id == moving_house: OPS.remove_house(proposal, house)
			var origin := Vector2i((finish - Vector2(stamp.footprint) * 0.5).round())
			result = OPS.stamp(proposal, stamp, origin)
	_submit(proposal, result, mode)

func _submit(proposal: MapDefinition, result: Dictionary, label: String) -> void:
	if result.has("error"):
		status.text = result.error
		return
	pending = {"target": map, "old": OPS.snapshot(map), "new": proposal, "label": label, "house_id": result.get("house_id", selected_house)}
	var conflicts: Array = result.get("conflicts", [])
	if not conflicts.is_empty() or result.get("shrink", false):
		confirmation.dialog_text = "Confirm replacement/removal (undo is available):\n" + "\n".join(conflicts)
		if result.get("shrink", false): confirmation.dialog_text += "\nAll terrain/heat outside the red boundary will be cropped."
		confirmation.popup_centered(Vector2i(500, 260))
	else: _commit_pending()

func _commit_pending() -> void:
	if pending.is_empty() or undo_redo == null: return
	var target: MapDefinition = pending.target
	undo_redo.create_action(pending.label, UndoRedo.MERGE_DISABLE, target)
	undo_redo.add_do_method(self, "_restore", target, pending.new)
	undo_redo.add_undo_method(self, "_restore", target, pending.old)
	undo_redo.commit_action()
	selected_house = pending.house_id
	if not moving_house.is_empty(): moving_house = ""; tool.select(0)
	status.text = pending.label + " applied. Unsaved changes."
	pending.clear()
	canvas.cropping = Rect2i()
	canvas.queue_redraw()

func _restore(target: MapDefinition, state: MapDefinition) -> void:
	OPS.copy_state(target, OPS.snapshot(state))
	if target == map: _refresh()

func _apply_selected_heat() -> void:
	if map == null or not selected_rect.has_area(): return
	var proposal := OPS.snapshot(map)
	_submit(proposal, OPS.paint_heat(proposal, selected_rect, int(level.value), float(heat.value)), "Edit selected heat")

func _erase_stair(proposal: MapDefinition, point: Vector2) -> Dictionary:
	for house in proposal.buildings:
		if house.id != selected_house: continue
		OPS.normalize_house(proposal, house)
		for stair in house.template.stairs.duplicate():
			if stair.from_floor != int(level.value) and stair.to_floor != int(level.value): continue
			if (point - Vector2(house.origin)).distance_to(Geometry2D.get_closest_point_to_segment(point - Vector2(house.origin), stair.start, stair.end)) < 0.65:
				house.template.stairs.erase(stair)
				return {}
	return {"error": "No stair under pointer in the selected house."}

func _erase_floor(proposal: MapDefinition, rect: Rect2i) -> Dictionary:
	for house in proposal.buildings:
		if house.id != selected_house: continue
		OPS.normalize_house(proposal, house)
		for floor in house.template.indoor_floors.duplicate():
			if floor.level != int(level.value): continue
			var local := Rect2i(rect.position - house.origin, rect.size)
			if not floor.rect.intersects(local): continue
			house.template.indoor_floors.erase(floor)
			for part in OPS.subtract_rect(floor.rect, local):
				var copy := floor.duplicate(true) as MapIndoorFloorDefinition
				copy.id = OPS.uid("floor")
				copy.rect = part
				house.template.indoor_floors.append(copy)
	return {}

func _save_template() -> void:
	if map == null or not selected_rect.has_area(): status.text = "Select a complete house footprint first."; return
	template = OPS.capture(OPS.snapshot(map), selected_rect)
	if template.indoor_floors.is_empty(): status.text = "Selection contains no complete house or indoor floor."; return
	template_picker.edited_resource = template
	template_dialog.popup_centered_ratio(0.65)

func _copy_house(move: bool) -> void:
	for house in map.buildings:
		if house.id != selected_house: continue
		template = OPS.capture(OPS.snapshot(map), house.effective_bounds())
		template_picker.edited_resource = template
		moving_house = house.id if move else ""
		tool.select(12)
		_refresh_visuals()
		status.text = "Click the destination. Original remains until a valid move is committed." if move else "Click repeatedly to place independent copies."
		return
	status.text = "Select a house first."

func _delete_house() -> void:
	if map == null: return
	var proposal := OPS.snapshot(map)
	for house in proposal.buildings.duplicate():
		if house.id != selected_house: continue
		OPS.remove_house(proposal, house)
		_submit(proposal, {"conflicts": ["Entire house: " + house.effective_display_name()], "house_id": ""}, "Delete house")
		return

func _toggle_roof() -> void:
	var proposal := OPS.snapshot(map)
	for house in proposal.buildings:
		if house.id != selected_house: continue
		OPS.normalize_house(proposal, house)
		house.template.has_roof = not house.template.has_roof
		_submit(proposal, {}, "Toggle roof")
		return

func _new_map() -> void:
	_set_map(OPS.create_map(Vector2i(size_x.value, size_y.value)))
	status.text = "New grass map. Use Save as before playtesting."

func _resize() -> void:
	if map == null: return
	var proposal := OPS.snapshot(map)
	var dimensions := Vector2i(size_x.value, size_y.value)
	canvas.cropping = Rect2i(Vector2i.ZERO, dimensions)
	canvas.queue_redraw()
	_submit(proposal, OPS.resize(proposal, dimensions), "Resize map")

func _hover(point: Vector2) -> void:
	if template == null or tool.get_item_text(tool.selected) != "Stamp template": return
	var footprint := template.footprint
	if rotation_picker.selected % 2 == 1: footprint = Vector2i(footprint.y, footprint.x)
	var rect := Rect2i(Vector2i((point - Vector2(footprint) * 0.5).round()), footprint)
	canvas.ghost = rect
	canvas.ghost_valid = OPS.bounds(map).encloses(rect)
	if canvas.ghost_valid:
		for cell in OPS.cells(rect):
			var tile := world.get_tile_at(cell, 0)
			if tile == null or tile.is_water(): canvas.ghost_valid = false; break

func _save() -> void:
	if map == null: return
	if map.resource_path.is_empty(): save_dialog.popup_centered_ratio(0.65)
	else: _save_path(map.resource_path)

func _save_path(path: String) -> bool:
	var issues: Array = VALIDATOR.validate(map)
	if not issues.is_empty(): status.text = "Save blocked:\n" + "\n".join(issues); return false
	var error := ResourceSaver.save(map, path)
	if error == OK: map.take_over_path(path)
	status.text = "Saved " + path if error == OK else error_string(error)
	return error == OK

func _validate() -> void:
	var issues: Array = VALIDATOR.validate(map)
	status.text = "Validation passed." if issues.is_empty() else "\n".join(issues)

func _playtest() -> void:
	if map == null or map.resource_path.is_empty(): status.text = "Save the map first."; return
	if _save_path(map.resource_path): playtest_requested.emit(map.resource_path)
