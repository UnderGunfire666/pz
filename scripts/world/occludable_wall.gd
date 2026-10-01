class_name OccludableWall
extends RefCounted

## Render-only wall handle. Player cutaway uses finite mesh bounds; visible-content
## cutaway also checks the wall plane so rear walls are never removed by depth alone.
var mesh: MeshInstance3D
var original_visible: bool
var center: Vector2
var normal: Vector2
var bounds: AABB
var fade_material: StandardMaterial3D
var base_color := Color.WHITE
var current_alpha := 1.0
var target_alpha := 1.0
var body_cutaway := false
var content_cutaway := false
const CUTAWAY_ALPHA := 0.12
const FADE_PER_SECOND := 5.5


func _init(p_mesh: MeshInstance3D) -> void:
	mesh = p_mesh
	original_visible = mesh.visible
	bounds = mesh.global_transform * mesh.get_aabb()
	center = Vector2(mesh.global_position.x, mesh.global_position.z)
	var axis := mesh.global_basis.z
	normal = Vector2(axis.x, axis.z).normalized()
	var source := mesh.material_override as StandardMaterial3D
	if source == null:
		source = StandardMaterial3D.new()
	fade_material = source.duplicate(true) as StandardMaterial3D
	base_color = fade_material.albedo_color
	fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fade_material.albedo_color = Color(base_color.r, base_color.g, base_color.b, 1.0)
	mesh.material_override = fade_material


func apply_cutaway(enabled: bool, feet: Vector3, direction: Vector3, distance: float) -> void:
	# Plane-side classification hid every collinear segment, including walls that
	# actually terminated the player's FOV. Cut only geometry that overlaps the
	# real camera-to-body corridor; LOS-blocking walls elsewhere remain readable.
	body_cutaway = enabled and OcclusionZone.blocks_view(bounds, feet, direction, distance)
	if not enabled:
		content_cutaway = false
	_refresh_cutaway()


func apply_exterior(feet: Vector3, direction: Vector3, distance: float) -> void:
	body_cutaway = OcclusionZone.blocks_view(bounds, feet, direction, distance)
	_refresh_cutaway()


func cut_visible_regions(regions: Array[AABB], direction: Vector3, distance: float) -> void:
	content_cutaway = false
	var camera_side := Vector2(direction.x, direction.z).dot(normal)
	for region in regions:
		var point := region.get_center()
		var content_side := (Vector2(point.x, point.z) - center).dot(normal)
		if content_side * camera_side < -0.01 and OcclusionZone.blocks_regions(bounds, [region], direction, distance):
			content_cutaway = true
			break
	_refresh_cutaway()


func advance_fade(delta: float) -> void:
	if not original_visible:
		return
	current_alpha = move_toward(current_alpha, target_alpha, FADE_PER_SECOND * delta)
	fade_material.albedo_color = Color(base_color.r, base_color.g, base_color.b, current_alpha)


func is_cutaway() -> bool:
	return body_cutaway or content_cutaway


func _refresh_cutaway() -> void:
	mesh.visible = original_visible
	target_alpha = CUTAWAY_ALPHA if is_cutaway() else 1.0
