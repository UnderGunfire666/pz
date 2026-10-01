@tool
extends Control

signal gesture(start: Vector2, finish: Vector2, path: Array[Vector2i])
signal hover_changed(point: Vector2)
var world: WorldMap
var level := 0
var show_heat := false
var show_adjacent := true
var selection := Rect2i()
var ghost := Rect2i()
var ghost_valid := true
var cropping := Rect2i()
var mode := "Select"
var zoom := 1.0
var pan := Vector2.ZERO
var dragging := false
var start := Vector2.ZERO
var current := Vector2.ZERO
var path: Array[Vector2i] = []

func scale_factor() -> float:
	if world == null: return 1.0
	return maxf(0.1, minf(size.x / world.width, size.y / world.height) * zoom)

func logical(point: Vector2) -> Vector2:
	return (point - pan) / scale_factor()

func _gui_input(event: InputEvent) -> void:
	if world == null: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var before := logical(event.position)
			zoom = clampf(zoom * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 0.5, 24.0)
			pan = event.position - before * scale_factor()
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			current = logical(event.position)
			if event.pressed:
				start = current
				path = [Vector2i(current.floor())]
				dragging = true
			elif dragging:
				dragging = false
				gesture.emit(start, current, path)
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			pan += event.relative
		current = logical(event.position)
		if dragging:
			var previous := Vector2(path.back()) + Vector2(0.5, 0.5)
			var steps := maxi(1, ceili(previous.distance_to(current) * 2.0))
			for index in range(steps + 1):
				var cell := Vector2i(previous.lerp(current, float(index) / steps).floor())
				if path.back() != cell: path.append(cell)
		hover_changed.emit(current)
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#222932"))
	if world == null: return
	var scale := scale_factor()
	draw_set_transform(pan, 0.0, Vector2.ONE * scale)
	if show_adjacent:
		for adjacent in [level - 1, level + 1]: _draw_floor(adjacent, 0.2)
	_draw_floor(level, 1.0)
	if scale >= 6.0:
		for x in range(world.width + 1):
			draw_line(Vector2(x, 0), Vector2(x, world.height), Color(1, 1, 1, 0.12), 1.0 / scale)
		for y in range(world.height + 1):
			draw_line(Vector2(0, y), Vector2(world.width, y), Color(1, 1, 1, 0.12), 1.0 / scale)
	if selection.has_area(): draw_rect(Rect2(selection), Color("#f5db6a"), false, 2.0 / scale)
	if ghost.has_area():
		var color := Color(0.2, 1, 0.5, 0.4) if ghost_valid else Color(1, 0.2, 0.2, 0.5)
		draw_rect(Rect2(ghost), color)
		draw_rect(Rect2(ghost), color, false, 2.0 / scale)
	if cropping.has_area():
		draw_rect(Rect2(cropping), Color("#ff6655"), false, 3.0 / scale)
	if dragging:
		if mode in ["Wall", "Door", "Window", "Erase wall"]:
			draw_line(start.round(), current.round(), Color("#ffffff"), 2.0 / scale)
		elif mode == "Road":
			for cell in path: draw_rect(Rect2(Vector2(cell), Vector2.ONE), Color(1, 1, 1, 0.4))
		else:
			var a := start.floor().min(current.floor())
			var b := start.floor().max(current.floor()) + Vector2.ONE
			draw_rect(Rect2(a, b - a), Color(1, 1, 1, 0.4), false, 2.0 / scale)
	draw_set_transform(Vector2.ZERO)

func _draw_floor(floor_index: int, opacity: float) -> void:
	if not world.floors.has(floor_index): return
	var data: FloorData = world.floors[floor_index]
	var scale := scale_factor()
	var visible_box := Rect2(-pan / scale, size / scale).grow(1.0)
	for cell: Vector2i in data.tiles:
		if not visible_box.has_point(Vector2(cell)): continue
		var tile: WorldTileData = data.tiles[cell]
		var color := Color("#49694b")
		match tile.kind:
			"floor", "indoor_floor", "wall", "door": color = Color("#89775e")
			"road", "asphalt": color = Color("#55595b")
			"soil", "dirt": color = Color("#785f46")
			"water": color = Color("#315b78")
		color.a = opacity
		draw_rect(Rect2(Vector2(cell), Vector2.ONE), color)
		if show_heat and tile.walkable and not tile.is_water():
			draw_rect(Rect2(Vector2(cell), Vector2.ONE), Color(tile.zombie_pressure, 0.1, 1.0 - tile.zombie_pressure, 0.5 * opacity))
	for face in data.wall_faces + data.visual_edges:
		var color := Color("#eed7aa")
		if face.get("kind", "") == "door": color = Color("#ffb158")
		if face.get("kind", "") == "window": color = Color("#80daf5")
		color.a = opacity
		draw_line(face.start, face.end, color, 2.0 / scale)
	for stair: StairLink in world.stairs.values():
		if stair.from_floor == floor_index or stair.to_floor == floor_index:
			draw_line(stair.start, stair.end, Color(0.9, 0.9, 0.7, opacity), 3.0 / scale)
	for prop in world.definition.decorations:
		if prop.level == floor_index:
			draw_circle(prop.position, 0.3, Color(0.3, 0.9, 0.4, opacity))
