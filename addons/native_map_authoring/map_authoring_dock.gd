@tool
class_name MapAuthoringDock
extends VBoxContainer

signal playtest_requested

var undo_redo: EditorUndoRedoManager
var map: MapDefinition
var level_selector := OptionButton.new()
var terrain_selector := OptionButton.new()
var status := Label.new()
var canvas: MapAuthoringCanvas
var preview: MapAuthoringPreview3D
var map_picker := EditorResourcePicker.new()
const GRASS: MapTerrainDefinition = preload("res://resources/maps/terrain/grass.tres")
const ASPHALT: MapTerrainDefinition = preload("res://resources/maps/terrain/asphalt.tres")
const MAP_VALIDATOR = preload("res://scripts/systems/map_validator.gd")


func _ready() -> void:
	name = "Map Authoring"
	custom_minimum_size = Vector2(330, 420)
	var title := Label.new()
	title.text = "Native Map Authoring"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)
	map_picker.base_type = "MapDefinition"
	map_picker.resource_changed.connect(_set_map)
	add_child(_labelled("Map", map_picker))
	var controls := HBoxContainer.new()
	var open_default := Button.new()
	open_default.text = "Open Orangeville"
	open_default.pressed.connect(func() -> void: _set_map(load("res://resources/maps/orangeville_prototype.tres")))
	controls.add_child(open_default)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_save)
	controls.add_child(save)
	var validate := Button.new()
	validate.text = "Validate"
	validate.pressed.connect(_validate)
	controls.add_child(validate)
	add_child(controls)
	level_selector.item_selected.connect(func(_index: int) -> void: _refresh_canvas())
	add_child(_labelled("Level", level_selector))
	terrain_selector.add_item("Paint grass", 0)
	terrain_selector.add_item("Paint asphalt", 1)
	add_child(_labelled("Tool", terrain_selector))
	canvas = MapAuthoringCanvas.new()
	canvas.custom_minimum_size = Vector2(300, 300)
	canvas.tile_pressed.connect(_paint_tile)
	add_child(canvas)
	preview = MapAuthoringPreview3D.new()
	add_child(_labelled("3D Preview (runtime map adapter)", preview))
	var help := Label.new()
	help.text = "Click a tile to paint. Resource edits use Godot Undo/Redo.\nThe game test uses the saved map resource."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	var play := Button.new()
	play.text = "Play Main Scene"
	play.pressed.connect(func() -> void: playtest_requested.emit())
	add_child(play)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	_set_map(load("res://resources/maps/orangeville_prototype.tres"))


func _labelled(label: String, control: Control) -> Control:
	var row := VBoxContainer.new()
	var caption := Label.new()
	caption.text = label
	row.add_child(caption)
	row.add_child(control)
	return row


func _set_map(value: Resource) -> void:
	map = value as MapDefinition
	map_picker.edited_resource = map
	level_selector.clear()
	if map == null:
		status.text = "Choose a MapDefinition resource."
		canvas.map = null
		return
	for cell: MapCellDefinition in map.cells:
		for level: MapLevelDefinition in cell.levels:
			if level_selector.get_item_index(level.level) < 0:
				level_selector.add_item("Level %d" % level.level, level.level)
	status.text = "%s · %d × %d logical tiles · saved static content" % [map.display_name, map.cell_size.x, map.cell_size.y]
	_refresh_canvas()


func _selected_level() -> int:
	return level_selector.get_item_id(level_selector.selected) if level_selector.selected >= 0 else 0


func _refresh_canvas() -> void:
	canvas.map = map
	canvas.level = _selected_level()
	canvas.queue_redraw()
	preview.show_map(map)


func _paint_tile(tile: Vector2i) -> void:
	if map == null or undo_redo == null:
		return
	var level := _find_level(_selected_level())
	if level == null:
		return
	var terrain := GRASS if terrain_selector.selected == 0 else ASPHALT
	var old_paints := level.terrain_paints.duplicate()
	var new_paints := level.terrain_paints.duplicate()
	var paint := MapTerrainPaint.new()
	paint.id = "paint_%d_%d_%d" % [level.level, tile.x, tile.y]
	paint.rect = Rect2i(tile, Vector2i.ONE)
	paint.terrain = terrain
	paint.is_override = true
	new_paints.append(paint)
	undo_redo.create_action("Paint map tile")
	undo_redo.add_do_method(self, "_set_level_paints", level, new_paints)
	undo_redo.add_undo_method(self, "_set_level_paints", level, old_paints)
	undo_redo.commit_action()
	status.text = "Painted %s at %d, %d. Unsaved changes." % [terrain.display_name, tile.x, tile.y]
	_refresh_canvas()


func _set_level_paints(level: MapLevelDefinition, paints: Array) -> void:
	level.terrain_paints.assign(paints)
	_refresh_canvas()


func _find_level(target_level: int) -> MapLevelDefinition:
	if map == null:
		return null
	for cell: MapCellDefinition in map.cells:
		for level: MapLevelDefinition in cell.levels:
			if level.level == target_level:
				return level
	return null


func _save() -> void:
	if map == null or map.resource_path.is_empty():
		return
	var result := ResourceSaver.save(map, map.resource_path)
	status.text = "Saved %s." % map.resource_path if result == OK else "Save failed: %s" % error_string(result)


func _validate() -> void:
	var issues: Array = MAP_VALIDATOR.validate(map)
	status.text = "Validation passed." if issues.is_empty() else "Validation:\n" + "\n".join(issues)


class MapAuthoringCanvas:
	extends Control
	signal tile_pressed(tile: Vector2i)
	var map: MapDefinition
	var level := 0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and map != null:
			var logical_size := Vector2(map.cell_size)
			var scale := minf(size.x / logical_size.x, size.y / logical_size.y)
			var tile := Vector2i((event.position / scale).floor())
			if Rect2i(Vector2i.ZERO, map.cell_size).has_point(tile):
				tile_pressed.emit(tile)

	func _draw() -> void:
		if map == null:
			return
		var logical_size := Vector2(map.cell_size)
		var scale := minf(size.x / logical_size.x, size.y / logical_size.y)
		draw_rect(Rect2(Vector2.ZERO, logical_size * scale), Color("242a32"), true)
		for cell: MapCellDefinition in map.cells:
			for authored_level: MapLevelDefinition in cell.levels:
				if authored_level.level != level:
					continue
				for paint: MapTerrainPaint in authored_level.terrain_paints:
					var color := Color("65785a") if paint.terrain == null or paint.terrain.category == "grass" else Color("59606a")
					draw_rect(Rect2(Vector2(paint.rect.position) * scale, Vector2(paint.rect.size) * scale), color, true)
		for road: MapRoadDefinition in map.roads:
			if road.level != level or road.centerline.size() < 2:
				continue
			for point_index in range(road.centerline.size() - 1):
				draw_line(road.centerline[point_index] * scale, road.centerline[point_index + 1] * scale,
					Color("59606a"), maxf(1.0, road.width * scale), true)
		for zone: MapZoneDefinition in map.zones:
			if zone.level == level:
				draw_rect(Rect2(Vector2(zone.rect.position) * scale, Vector2(zone.rect.size) * scale),
					Color("c27443", 0.20), true)
		for building: MapBuildingInstanceDefinition in map.buildings:
			if level < building.effective_floor_count():
				var bounds := building.effective_bounds()
				draw_rect(Rect2(Vector2(bounds.position) * scale, Vector2(bounds.size) * scale), Color("bb8f65"), false, 2.0)
				if building.template != null:
					for edge: MapWallEdgeDefinition in building.template.wall_edges:
						if edge.level == level:
							var origin := Vector2(building.origin)
							draw_line((origin + edge.start) * scale, (origin + edge.end) * scale, Color("eed7aa"), 2.0, true)
		for edge: MapWallEdgeDefinition in map.wall_edges:
			if edge.level == level:
				draw_line(edge.start * scale, edge.end * scale, Color("eed7aa"), 2.0, true)
		for decoration: MapDecorationDefinition in map.decorations:
			if decoration.level == level:
				var color := Color("5f854b") if decoration.kind == "tree" else Color("8eb2ce")
				draw_circle(decoration.position * scale, maxf(2.0, scale * 0.23), color)
		for x in range(map.cell_size.x + 1):
			var p := float(x) * scale
			draw_line(Vector2(p, 0), Vector2(p, logical_size.y * scale), Color(1, 1, 1, 0.08))
		for y in range(map.cell_size.y + 1):
			var p := float(y) * scale
			draw_line(Vector2(0, p), Vector2(logical_size.x * scale, p), Color(1, 1, 1, 0.08))
		draw_circle(map.player_spawn * scale, maxf(3.0, scale * 0.28), Color("d8e7f3"))
