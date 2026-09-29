class_name OccludableWall
extends RefCounted

## Render-only wall handle; classify against the wall plane, not diagonal depth.
var mesh: MeshInstance3D
var original_visible: bool
var center: Vector2
var normal: Vector2
var bounds: AABB


func _init(p_mesh: MeshInstance3D) -> void:
	mesh = p_mesh
	original_visible = mesh.visible
	bounds = mesh.global_transform * mesh.get_aabb()
	center = Vector2(mesh.global_position.x, mesh.global_position.z)
	var axis := mesh.global_basis.z
	normal = Vector2(axis.x, axis.z).normalized()


func apply_cutaway(enabled: bool, player_position: Vector2, camera_direction: Vector2) -> void:
	var front := false
	if enabled:
		var player_side := (player_position - center).dot(normal)
		var camera_side := camera_direction.dot(normal)
		front = player_side * camera_side < -0.01
	mesh.visible = original_visible and not front


func apply_exterior(feet: Vector3, direction: Vector3, distance: float) -> void:
	mesh.visible = original_visible and not OcclusionZone.blocks_view(bounds, feet, direction, distance)


func cut_visible_regions(regions: Array[AABB], direction: Vector3, distance: float) -> void:
	if not mesh.visible:
		return
	var camera_side := Vector2(direction.x, direction.z).dot(normal)
	for region in regions:
		var point := region.get_center()
		var content_side := (Vector2(point.x, point.z) - center).dot(normal)
		if content_side * camera_side < -0.01 and OcclusionZone.blocks_regions(bounds, [region], direction, distance):
			mesh.visible = false
			return
