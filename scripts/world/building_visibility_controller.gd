class_name BuildingVisibilityController
extends Node3D

## Local presentation only; never changes collision, navigation or actor simulation.
## Exterior zone-driven cutaways can be added without changing floor registration.
enum State { EXTERIOR_FULL, EXTERIOR_CUTAWAY, INTERIOR }

signal state_changed(new_state: int)

var building_id := ""
var state := State.EXTERIOR_FULL
var active_floor := 0
var floors: Dictionary = {}
var roofs: Array[Dictionary] = []
var _player_position := Vector2.ZERO
var _camera_direction := Vector2(1, 1).normalized()
var _feet := Vector3.ZERO
var _view_direction := Vector3.UP
var _view_distance := 20.0
var visible_regions: Array[AABB] = []
var viewer_room := ""
var active_stair := ""


func register_part(part: Dictionary) -> void:
	var node := part["node"] as Node3D
	if part["kind"] == "roof":
		node.reparent(self, true)
		roofs.append({"node": node, "visible": node.visible})
		return
	var index := int(part["floor"])
	if not floors.has(index):
		var floor_node := BuildingFloor.new()
		floor_node.name = "Floor_%02d" % (index + 1)
		floor_node.floor_index = index
		add_child(floor_node)
		floors[index] = floor_node
	(floors[index] as BuildingFloor).register_part(node, String(part["kind"]),
		String(part.get("room", "")), String(part.get("stair", "")))


func set_active_floor(index: int) -> void:
	if active_floor == index:
		return
	active_floor = index
	_apply_visibility()


func configure_content(room: String, stair: String, regions: Array[AABB],
		direction: Vector3, distance: float) -> void:
	viewer_room = room
	active_stair = stair
	visible_regions = regions
	_view_direction = direction
	_view_distance = distance


func set_cutaway(enabled: bool) -> void:
	set_state(State.INTERIOR if enabled else State.EXTERIOR_FULL)


func set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	_apply_visibility()
	state_changed.emit(state)


func update_local_view(index: int, position: Vector2, direction: Vector2) -> void:
	active_floor = index
	_player_position = position
	_camera_direction = direction.normalized()
	var changed := state != State.INTERIOR
	state = State.INTERIOR
	_apply_visibility()
	if changed:
		state_changed.emit(state)


func _apply_visibility() -> void:
	var cutaway := state != State.EXTERIOR_FULL
	for roof in roofs:
		(roof["node"] as Node3D).visible = bool(roof["visible"]) and not cutaway
	for floor_node: BuildingFloor in floors.values():
		floor_node.viewer_room = viewer_room
		floor_node.active_stair = active_stair
		if state == State.EXTERIOR_CUTAWAY:
			floor_node.apply_exterior(active_floor, _feet, _view_direction, _view_distance, visible_regions)
		else:
			floor_node.apply_visibility(cutaway, active_floor, _player_position, _camera_direction)
			if cutaway and floor_node.visible:
				for wall in floor_node.walls:
					wall.cut_visible_regions(visible_regions, _view_direction, _view_distance)


func update_exterior_view(index: int, feet: Vector3, direction: Vector3, distance: float,
		regions: Array[AABB] = []) -> void:
	active_floor = index
	_feet = feet
	_view_direction = direction
	_view_distance = distance
	visible_regions = regions
	viewer_room = ""
	active_stair = ""
	var changed := state != State.EXTERIOR_CUTAWAY
	state = State.EXTERIOR_CUTAWAY
	_apply_visibility()
	if changed:
		state_changed.emit(state)
