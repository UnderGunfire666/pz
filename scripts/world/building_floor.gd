class_name BuildingFloor
extends Node3D

var floor_index := 0
var walls: Array[OccludableWall] = []
var parts: Array[Dictionary] = []
const CONCEALED_ROOM = preload("res://resources/materials/concealed_room.tres")
var viewer_room := ""
var active_stair := ""


func register_part(node: Node3D, kind: String, room_id: String = "", stair_id: String = "") -> void:
	node.reparent(self, true)
	if kind == "wall":
		walls.append(OccludableWall.new(node as MeshInstance3D))
	else:
		parts.append({"node": node, "visible": node.visible, "bounds": OcclusionZone.node_bounds(node),
			"kind": kind, "room": room_id, "stair": stair_id,
			"material": (node as MeshInstance3D).material_override if node is MeshInstance3D else null})
	apply_room_mask()


func apply_visibility(cutaway: bool, active_floor: int,
		player_position: Vector2, camera_direction: Vector2) -> void:
	visible = not cutaway or floor_index <= active_floor
	for part in parts:
		(part["node"] as Node3D).visible = part["visible"]
	for wall in walls:
		wall.apply_cutaway(cutaway and visible, player_position, camera_direction)
	apply_room_mask()


func apply_exterior(active_floor: int, feet: Vector3, direction: Vector3, distance: float,
		regions: Array[AABB] = []) -> void:
	visible = floor_index <= active_floor
	for wall in walls:
		wall.apply_exterior(feet, direction, distance)
		wall.cut_visible_regions(regions, direction, distance)
	for part in parts:
		(part["node"] as Node3D).visible = bool(part["visible"]) and not (
			OcclusionZone.blocks_view(part["bounds"], feet, direction, distance)
			or OcclusionZone.blocks_regions(part["bounds"], regions, direction, distance))
	apply_room_mask()


func apply_room_mask() -> void:
	for part in parts:
		var revealed: bool = String(part["room"]).is_empty() or String(part["room"]) == viewer_room
		var node := part["node"] as Node3D
		if part["kind"] == "floor":
			(node as MeshInstance3D).material_override = part["material"] if revealed else CONCEALED_ROOM
		elif not revealed and (active_stair.is_empty() or part["stair"] != active_stair):
			node.visible = false
