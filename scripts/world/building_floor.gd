class_name BuildingFloor
extends Node3D

var floor_index := 0
var walls: Array[OccludableWall] = []
var parts: Array[Dictionary] = []
var viewer_room := ""
var active_stair := ""
var visible_regions: Array[AABB] = []


func register_part(node: Node3D, kind: String, room_id: String = "", stair_id: String = "") -> void:
	node.reparent(self, true)
	if kind == "wall":
		walls.append(OccludableWall.new(node as MeshInstance3D))
	else:
		parts.append({"node": node, "visible": node.visible, "bounds": OcclusionZone.node_bounds(node),
			"kind": kind, "room": room_id, "stair": stair_id,
			"material": (node as MeshInstance3D).material_override if node is MeshInstance3D else null})
	apply_room_mask()


func unregister_part(node: Node3D) -> bool:
	for wall_index in range(walls.size() - 1, -1, -1):
		if walls[wall_index].mesh == node:
			walls.remove_at(wall_index)
			return true
	for part_index in range(parts.size() - 1, -1, -1):
		if parts[part_index]["node"] == node:
			parts.remove_at(part_index)
			return true
	return false


func apply_visibility(cutaway: bool, active_floor: int,
		feet: Vector3, view_direction: Vector3, view_distance: float) -> void:
	visible = not cutaway or floor_index <= active_floor
	for part in parts:
		(part["node"] as Node3D).visible = part["visible"]
	for wall in walls:
		wall.apply_cutaway(cutaway and visible, feet, view_direction, view_distance)
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
		var revealed: bool = (String(part["room"]).is_empty()
			or String(part["room"]) == viewer_room
			or _intersects_visible_region(part["bounds"]))
		var node := part["node"] as Node3D
		if part["kind"] == "floor":
			# Persistent explored-space memory is drawn by the fog overlay. A separate
			# opaque room material here would turn explored indoor floor back to black.
			(node as MeshInstance3D).material_override = part["material"]
		elif not revealed and (active_stair.is_empty() or part["stair"] != active_stair):
			node.visible = false


func _intersects_visible_region(bounds: AABB) -> bool:
	for region in visible_regions:
		# Plane meshes have zero height; a tiny expansion makes their authored tile
		# bounds participate without leaking into another logical floor.
		if bounds.grow(0.04).intersects(region): return true
	return false
