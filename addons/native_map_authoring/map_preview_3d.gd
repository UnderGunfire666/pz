@tool
class_name MapAuthoringPreview3D
extends SubViewportContainer

## Editor-only, static preview. WorldMap remains the sole map-to-runtime
## adapter; this intentionally excludes actors, UI, saves and simulation.
var viewport := SubViewport.new()
var root := Node3D.new()
var content := Node3D.new()
var camera := Camera3D.new()


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(300, 205)
	viewport.size = Vector2i(600, 410)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	viewport.add_child(root)
	root.add_child(content)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("202832")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b7c4d1")
	settings.ambient_light_energy = 0.75
	environment.environment = settings
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 1.1
	root.add_child(light)
	camera.fov = 48.0
	root.add_child(camera)


func show_map(definition: MapDefinition) -> void:
	if not is_node_ready() or definition == null:
		return
	for child in content.get_children():
		child.queue_free()
	var adapter := WorldMap.new()
	# Preview consumes static floors/walls only; building A* here would stall the
	# editor splash without improving the authoring view.
	adapter.load_definition(definition, false)
	for level in adapter.floor_levels():
		_add_floor(adapter, level)
		for face in adapter.wall_faces(level):
			_add_wall(adapter, face, level)
	for building: BuildingData in adapter.buildings.values():
		_add_roof(adapter, building)
	var map_width := adapter.width
	var map_height := adapter.height
	adapter.free()
	var center := Vector3(map_width * 0.5, 0.0, map_height * 0.5)
	var distance := maxf(float(map_width), float(map_height)) * 0.72 + 8.0
	camera.position = center + Vector3(distance, distance, distance)
	camera.look_at(center)


func _add_floor(adapter: WorldMap, level: int) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_tile := false
	for y in range(adapter.height):
		for x in range(adapter.width):
			var tile := adapter.get_tile_at(Vector2i(x, y), level)
			if tile == null:
				continue
			any_tile = true
			var color := _tile_color(tile.kind)
			var base := Vector3(x, float(level) * adapter.floor_height, y)
			_append_quad(surface, base, base + Vector3(1, 0, 0), base + Vector3(1, 0, 1), base + Vector3(0, 0, 1), color)
	if not any_tile:
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "PreviewFloor_%d" % level
	mesh.mesh = surface.commit()
	mesh.material_override = _vertex_material()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	content.add_child(mesh)


func _add_wall(adapter: WorldMap, face: Dictionary, level: int) -> void:
	var start: Vector2 = face["start"]
	var end: Vector2 = face["end"]
	var direction := end - start
	var mesh := MeshInstance3D.new()
	var wall := BoxMesh.new()
	wall.size = Vector3(direction.length(), adapter.floor_height * 0.9, 0.12)
	mesh.mesh = wall
	mesh.material_override = _solid_material(Color("776d64"))
	mesh.position = Vector3((start.x + end.x) * 0.5, float(level) * adapter.floor_height + wall.size.y * 0.5, (start.y + end.y) * 0.5)
	mesh.rotation.y = -atan2(direction.y, direction.x)
	content.add_child(mesh)


func _add_roof(adapter: WorldMap, building: BuildingData) -> void:
	var mesh := MeshInstance3D.new()
	var roof := BoxMesh.new()
	roof.size = Vector3(building.bounds.size.x, 0.08, building.bounds.size.y)
	mesh.mesh = roof
	mesh.material_override = _solid_material(Color(0.23, 0.29, 0.34, 0.55), true)
	mesh.position = Vector3(building.bounds.get_center().x, building.floor_count * adapter.floor_height + 0.04, building.bounds.get_center().y)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	content.add_child(mesh)


func _append_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	for point in [a, c, b, a, d, c]:
		surface.set_color(color)
		surface.set_normal(Vector3.UP)
		surface.add_vertex(point)


func _tile_color(recipe: String) -> Color:
	match recipe:
		"asphalt": return Color("55595b")
		"indoor_floor", "floor": return Color("89775e")
		"door": return Color("936d43")
		_: return Color("49694b")


func _vertex_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _solid_material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
