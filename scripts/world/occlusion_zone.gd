class_name OcclusionZone
extends RefCounted

## Static render bounds, indexed by the local view system; no physics body needed.
signal occlusion_changed(blocked: bool)

var bounds: AABB
var target: Node3D
var blocked := false


func _init(p_bounds: AABB, p_target: Node3D) -> void:
	bounds = p_bounds
	target = p_target


func set_blocked(value: bool) -> void:
	if blocked != value:
		blocked = value
		occlusion_changed.emit(blocked)


static func blocks_view(box: AABB, feet: Vector3, direction: Vector3, distance: float) -> bool:
	# Sweep the complete player envelope along the orthographic view direction.
	# Minkowski expansion catches head/feet/edge occlusion without sparse ray samples.
	var expanded := AABB(box.position - Vector3(0.35, 1.9, 0.35),
		box.size + Vector3(0.7, 1.9, 0.7))
	return expanded.intersects_segment(feet, feet + direction * distance) != null


static func node_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var found := false
	if node is MeshInstance3D:
		result = node.global_transform * (node as MeshInstance3D).get_aabb()
		found = true
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := node_bounds(child)
			if child_bounds.size != Vector3.ZERO:
				result = result.merge(child_bounds) if found else child_bounds
				found = true
	return result


static func blocks_regions(box: AABB, regions: Array[AABB], direction: Vector3, distance: float) -> bool:
	for region in regions:
		var expanded := AABB(box.position - region.size * 0.5, box.size + region.size)
		var origin := region.get_center()
		if expanded.intersects_segment(origin, origin + direction * distance) != null:
			return true
	return false
