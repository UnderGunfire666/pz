class_name SmallOccluder
extends Node3D

## Opt-in for static props with StandardMaterial3D. Buildings never use this shader.
const DITHER_SHADER = preload("res://shaders/local_occluder_dither.gdshader")
var meshes: Array[Dictionary] = []
var occluded := false


func register_mesh(mesh: MeshInstance3D) -> void:
	var source := mesh.get_active_material(0)
	if source != null and not source is StandardMaterial3D:
		push_warning("SmallOccluder requires a StandardMaterial3D prop: " + mesh.name)
		return
	var fade := ShaderMaterial.new()
	fade.shader = DITHER_SHADER
	if source is StandardMaterial3D:
		fade.set_shader_parameter("base_color", source.albedo_color)
		if source.albedo_texture != null:
			fade.set_shader_parameter("base_texture", source.albedo_texture)
	meshes.append({"node": mesh, "original": mesh.material_override,
		"shadow": mesh.cast_shadow, "fade": fade})


func set_occlusion(blocked: bool, reveal_rect: Vector4 = Vector4.ZERO) -> void:
	occluded = blocked
	for entry in meshes:
		var mesh := entry["node"] as MeshInstance3D
		if blocked:
			(entry["fade"] as ShaderMaterial).set_shader_parameter("reveal_rect", reveal_rect)
		mesh.material_override = entry["fade"] if blocked else entry["original"]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if blocked else entry["shadow"]
