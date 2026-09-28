class_name World3DView
extends Node3D

## The world owns floors, wall faces and stair traversal. This node only draws them.
const WALL_HEIGHT := 2.7
const WALL_THICKNESS := 0.12
const CAMERA_PITCH := deg_to_rad(55.0)
const CAMERA_DISTANCE_MIN := 9.0
const CAMERA_DISTANCE_MAX := 32.0

var world_map: WorldMap
var player: PlayerController
var actor_layer: Node2D
var visibility: VisibilitySystem
var interactions: InteractionSystem
var camera: Camera3D
var camera_yaw := PI * 0.25
var camera_distance := 19.0
var structure_parts: Array[Dictionary] = []
var interaction_markers: Array[Dictionary] = []
var actor_visuals: Dictionary = {}
var fog_overlays: Dictionary = {}
var _floor_openings: Dictionary = {}
var _last_fog_revision := -1
var _last_cutaway_key := ""
var _environment: Environment
var _sun: DirectionalLight3D
var _camera_height := 0.0
var _floor_material := _material(Color("393a34"))
var _wall_material := _material(Color("686057"))
var _grass_material := _material(Color("49694b"))
var _road_material := _material(Color("55595b"))
var _indoor_material := _material(Color("89775e"))
var _stair_material := _material(Color("a58b65"))
var _roof_material := _material(Color("414c52"))
var _door_material := _material(Color("936d43"))
var _player_material := _material(Color("d8e7f3"))
var _player_accent_material := _material(Color("416a92"))
var _zombie_material := _material(Color("a54646"))
var _zombie_flash_material := _material(Color("f06a58"))
var _npc_material := _material(Color("76a878"))
var _health_back_material := _material(Color("261c1a"))
var _health_fill_material := _material(Color("ed655c"))
var _swing_material := _material(Color(1.0, 0.86, 0.53, 0.72), true)


func setup(
		p_world_map: WorldMap,
		p_player: PlayerController,
		p_actor_layer: Node2D,
		p_visibility: VisibilitySystem,
		p_interactions: InteractionSystem
	) -> void:
	world_map = p_world_map
	player = p_player
	actor_layer = p_actor_layer
	visibility = p_visibility
	interactions = p_interactions
	_build_environment()
	_build_map()
	_build_interaction_markers()
	_build_camera()
	player.world_view = self


func _process(delta: float) -> void:
	if player == null:
		return
	_update_camera(delta)
	_update_structure_visibility()
	_update_lighting()
	_update_fog()
	_update_interaction_markers()
	_update_actors()


func orbit_camera(mouse_delta: Vector2) -> void:
	camera_yaw = wrapf(camera_yaw - mouse_delta.x * 0.006, -PI, PI)


func input_to_logical(screen_input: Vector2) -> Vector2:
	var camera_right := Vector2(cos(camera_yaw), -sin(camera_yaw))
	var screen_down := Vector2(sin(camera_yaw), cos(camera_yaw))
	return camera_right * screen_input.x + screen_down * screen_input.y


func mouse_to_logical(mouse_position: Vector2, floor_level: int = 0) -> Vector2:
	if camera == null:
		return player.logical_position + player.facing_direction
	var elevation := float(floor_level) * WorldMap.FLOOR_HEIGHT
	if floor_level == player.floor_level:
		elevation = world_map.elevation_at(player.logical_position, floor_level, player.stair_id)
	var hit: Variant = Plane(Vector3.UP, elevation).intersects_ray(
		camera.project_ray_origin(mouse_position), camera.project_ray_normal(mouse_position)
	)
	if hit == null:
		return player.logical_position + player.facing_direction
	var point: Vector3 = hit
	return Vector2(point.x, point.z)


func set_zoom_factor(factor: float) -> void:
	if factor > 0.0:
		camera_distance = clampf(camera_distance / factor, CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX)


func _build_environment() -> void:
	var environment_node := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("a5b7c7")
	environment_node.environment = _environment
	add_child(environment_node)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	_sun.shadow_enabled = true
	add_child(_sun)
	_update_lighting()


func _update_lighting() -> void:
	var daylight := world_map.ambient_light()
	_environment.ambient_light_energy = lerpf(0.12, 0.65, daylight)
	_environment.background_color = Color("101a28").lerp(Color("424e59"), daylight)
	_sun.light_energy = lerpf(0.08, 1.1, daylight)
	_sun.light_color = Color("8cadd5").lerp(Color("ffe4b8"), daylight)


func _build_map() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "GroundBackdrop"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(WorldMap.WIDTH + 12.0, WorldMap.HEIGHT + 12.0)
	ground.mesh = ground_mesh
	ground.position = Vector3(WorldMap.WIDTH * 0.5, -0.22, WorldMap.HEIGHT * 0.5)
	ground.material_override = _floor_material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	for stair in world_map.stairs.values():
		var direction: Vector2 = (stair.end - stair.start).normalized()
		var side := Vector2(-direction.y, direction.x) * float(stair.width) * 0.5
		var low: Vector2 = stair.start + direction * 0.15
		var high: Vector2 = stair.end - direction * 0.28
		var openings: Array = _floor_openings.get(stair.to_floor, [])
		openings.append(PackedVector2Array([low - side, high - side, high + side, low + side]))
		_floor_openings[stair.to_floor] = openings
	for floor_level in world_map.floor_levels():
		for y in range(WorldMap.HEIGHT):
			for x in range(WorldMap.WIDTH):
				var cell := Vector2i(x, y)
				var tile := world_map.get_tile_at(cell, floor_level)
				if tile != null:
					_add_tile(cell, tile, floor_level)
		for face in world_map.wall_faces(floor_level):
			_add_wall_face(face, floor_level)
		_create_fog_overlay(floor_level)
	for building_value in world_map.buildings.values():
		_add_roof(building_value as BuildingData)
	for stair in world_map.stairs.values():
		_add_stair_mesh(stair)


func _tile_polygons(cell: Vector2i, floor_level: int) -> Array[PackedVector2Array]:
	var corner := Vector2(cell)
	var polygons: Array[PackedVector2Array] = [PackedVector2Array([
		corner, corner + Vector2.RIGHT, corner + Vector2.ONE, corner + Vector2.DOWN,
	])]
	for opening: PackedVector2Array in _floor_openings.get(floor_level, []):
		var remaining: Array[PackedVector2Array] = []
		for polygon in polygons:
			remaining.append_array(Geometry2D.clip_polygons(polygon, opening))
		polygons = remaining
	return polygons


func _add_polygon(surface: SurfaceTool, polygon: PackedVector2Array, height: float, color: Color = Color.WHITE) -> void:
	for index in Geometry2D.triangulate_polygon(polygon):
		var point := polygon[index]
		surface.set_normal(Vector3.UP)
		surface.set_color(color)
		surface.add_vertex(Vector3(point.x, height, point.y))


func _add_tile(cell: Vector2i, tile: WorldTileData, floor_level: int) -> void:
	var polygons := _tile_polygons(cell, floor_level)
	if polygons.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for polygon in polygons:
		_add_polygon(surface, polygon, float(floor_level) * WorldMap.FLOOR_HEIGHT)
	var instance := MeshInstance3D.new()
	instance.name = "Floor_%d_Tile_%d_%d" % [floor_level, cell.x, cell.y]
	instance.mesh = surface.commit()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match tile.kind:
		"road":
			instance.material_override = _road_material
		"floor", "wall", "stairs":
			instance.material_override = _indoor_material
		"door":
			instance.material_override = _door_material
		_:
			instance.material_override = _grass_material
	add_child(instance)
	structure_parts.append({"node": instance, "floor": floor_level, "building": tile.building_id, "kind": "floor"})


func _add_wall_face(face: Dictionary, floor_level: int) -> void:
	var start: Vector2 = face["start"]
	var end: Vector2 = face["end"]
	var midpoint := (start + end) * 0.5
	var direction := end - start
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(direction.length(), WALL_HEIGHT, WALL_THICKNESS)
	instance.mesh = mesh
	instance.position = Vector3(midpoint.x, float(floor_level) * WorldMap.FLOOR_HEIGHT + WALL_HEIGHT * 0.5, midpoint.y)
	instance.rotation.y = -direction.angle()
	instance.material_override = _wall_material
	add_child(instance)
	structure_parts.append({"node": instance, "floor": floor_level, "building": String(face["building_id"]), "kind": "wall"})


func _add_roof(building: BuildingData) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "%s_Roof" % building.id
	var mesh := BoxMesh.new()
	mesh.size = Vector3(building.bounds.size.x + 0.12, 0.16, building.bounds.size.y + 0.12)
	instance.mesh = mesh
	instance.position = Vector3(
		building.bounds.position.x + building.bounds.size.x * 0.5,
		building.floor_count * WorldMap.FLOOR_HEIGHT + 0.04,
		building.bounds.position.y + building.bounds.size.y * 0.5
	)
	instance.material_override = _roof_material
	add_child(instance)
	structure_parts.append({"node": instance, "floor": building.floor_count, "building": building.id, "kind": "roof"})


func _add_stair_mesh(stair: RefCounted) -> void:
	var root := Node3D.new()
	root.name = "%s_Stair" % stair.id
	add_child(root)
	var direction: Vector2 = (stair.end - stair.start).normalized()
	var length: float = stair.start.distance_to(stair.end)
	var base: float = float(stair.from_floor) * WorldMap.FLOOR_HEIGHT
	var rise: float = float(stair.to_floor - stair.from_floor) * WorldMap.FLOOR_HEIGHT
	var steps := maxi(8, int(ceil(rise / 0.22)))
	for step in range(steps):
		var progress := (float(step) + 0.5) / float(steps)
		var point: Vector2 = stair.start.lerp(stair.end, progress)
		var tread := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(length / float(steps) + 0.02, 0.09, float(stair.width))
		tread.mesh = mesh
		tread.position = Vector3(point.x, base + rise * progress - 0.045, point.y)
		tread.rotation.y = -direction.angle()
		tread.material_override = _stair_material
		root.add_child(tread)
	var side := Vector2(-direction.y, direction.x) * float(stair.width) * 0.5
	for side_sign in [-1.0, 1.0]:
		var rail_start: Vector2 = stair.start + side * side_sign
		var rail_end: Vector2 = stair.end + side * side_sign
		_add_beam(root, Vector3(rail_start.x, base + 0.65, rail_start.y), Vector3(rail_end.x, base + rise + 0.65, rail_end.y))
		for progress in [0.0, 0.5, 1.0]:
			var point: Vector2 = rail_start.lerp(rail_end, progress)
			_add_beam(root, Vector3(point.x, base + rise * progress, point.y), Vector3(point.x, base + rise * progress + 0.65, point.y))
	structure_parts.append({"node": root, "floor": int(stair.from_floor), "building": String(stair.building_id), "kind": "stairs"})


func _add_beam(parent: Node3D, start: Vector3, end: Vector3) -> void:
	var beam := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = start.distance_to(end)
	beam.mesh = mesh
	beam.position = (start + end) * 0.5
	beam.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	beam.material_override = _door_material
	parent.add_child(beam)


func _build_interaction_markers() -> void:
	for point in interactions.points:
		var root := Node3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.27
		mesh.outer_radius = 0.34
		var ring := MeshInstance3D.new()
		ring.mesh = mesh
		ring.position.y = 0.045
		root.add_child(ring)
		var beacon := MeshInstance3D.new()
		var beacon_mesh := CylinderMesh.new()
		beacon_mesh.top_radius = 0.045
		beacon_mesh.bottom_radius = 0.08
		beacon_mesh.height = 0.42
		beacon.mesh = beacon_mesh
		beacon.position.y = 0.24
		root.add_child(beacon)
		var color := Color("6dcae8")
		match String(point["kind"]):
			"bed":
				color = Color("baa7ea")
			"hazard":
				color = Color("e37a52")
		var material := _material(color)
		material.emission_enabled = true
		material.emission = color * 0.16
		ring.material_override = material
		beacon.material_override = material
		var logical_position: Vector2 = point["position"]
		var floor_level := int(point.get("floor", 0))
		root.position = Vector3(logical_position.x, float(floor_level) * WorldMap.FLOOR_HEIGHT, logical_position.y)
		add_child(root)
		interaction_markers.append({"node": root, "point": point})


func _update_interaction_markers() -> void:
	for marker in interaction_markers:
		var point: Dictionary = marker["point"]
		(marker["node"] as Node3D).visible = (
			visibility.can_see_position(point["position"], int(point.get("floor", 0)))
			and not (String(point["kind"]) == "hazard" and bool(point.get("triggered", false)))
		)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "OrbitCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 120.0
	add_child(camera)
	camera.make_current()
	_camera_height = world_map.elevation_at(player.logical_position, player.floor_level, player.stair_id)
	_update_camera(0.0)


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	camera.size = camera_distance * 0.84
	var target_height := world_map.elevation_at(player.logical_position, player.floor_level, player.stair_id)
	_camera_height = lerpf(_camera_height, target_height, 1.0 - exp(-12.0 * delta)) if delta > 0.0 else target_height
	var focus := Vector3(player.logical_position.x, _camera_height + 0.6, player.logical_position.y)
	var horizontal_distance := camera_distance * cos(CAMERA_PITCH)
	camera.global_position = focus + Vector3(
		sin(camera_yaw) * horizontal_distance,
		camera_distance * sin(CAMERA_PITCH),
		cos(camera_yaw) * horizontal_distance
	)
	camera.look_at(focus, Vector3.UP)


func _update_structure_visibility() -> void:
	var tile := world_map.get_tile_at(Vector2i(player.logical_position.floor()), player.floor_level)
	var player_building := tile.building_id if tile != null else ""
	var highest_visible_floor := player.floor_level
	if not player.stair_id.is_empty() and world_map.stairs.has(player.stair_id):
		var stair: RefCounted = world_map.stairs[player.stair_id]
		player_building = stair.building_id
		highest_visible_floor = maxi(highest_visible_floor, int(stair.to_floor))
	var key := "%s:%d" % [player_building, highest_visible_floor]
	if key == _last_cutaway_key:
		return
	_last_cutaway_key = key
	for part in structure_parts:
		var in_player_building := not player_building.is_empty() and String(part["building"]) == player_building
		var show_part := true
		if in_player_building:
			show_part = String(part["kind"]) != "roof" and int(part["floor"]) <= highest_visible_floor
		(part["node"] as Node3D).visible = show_part
	for floor_level in fog_overlays:
		(fog_overlays[floor_level] as MeshInstance3D).visible = int(floor_level) <= highest_visible_floor
	_last_fog_revision = -1


func _create_fog_overlay(floor_level: int) -> void:
	var fog := MeshInstance3D.new()
	fog.name = "Floor_%d_VisionFog" % floor_level
	var material := _material(Color.WHITE, true)
	material.vertex_color_use_as_albedo = true
	material.render_priority = 2
	fog.material_override = material
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fog)
	fog_overlays[floor_level] = fog


func _update_fog() -> void:
	if visibility.revision == _last_fog_revision:
		return
	_last_fog_revision = visibility.revision
	for floor_level in world_map.floor_levels():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var has_vertices := false
		for y in range(WorldMap.HEIGHT):
			for x in range(WorldMap.WIDTH):
				var cell := Vector2i(x, y)
				if world_map.get_tile_at(cell, floor_level) == null:
					continue
				var seen := visibility.was_tile_seen(cell, floor_level)
				var fog_color := Color(0.025, 0.045, 0.07, 0.46 if seen else 0.9)
				for tile_polygon in _tile_polygons(cell, floor_level):
					var obscured: Array[PackedVector2Array] = [tile_polygon]
					if floor_level == player.floor_level and visibility.visible_world_polygon.size() >= 3:
						obscured = Geometry2D.clip_polygons(tile_polygon, visibility.visible_world_polygon)
					for polygon in obscured:
						if polygon.size() >= 3:
							_add_polygon(surface, polygon, float(floor_level) * WorldMap.FLOOR_HEIGHT + 0.018, fog_color)
							has_vertices = true
		var fog: MeshInstance3D = fog_overlays[floor_level]
		fog.mesh = surface.commit() if has_vertices else null


func _update_actors() -> void:
	var alive_ids: Dictionary = {}
	for actor in actor_layer.get_children():
		if not actor is PlayerController and not actor is ZombieActor and not actor is SurvivorNPC:
			continue
		var node := actor as Node2D
		var actor_id := node.get_instance_id()
		if node.is_queued_for_deletion():
			continue
		alive_ids[actor_id] = true
		var logical_position: Vector2 = node.get("logical_position")
		var actor_floor := int(node.get("floor_level"))
		var visible := node == player or visibility.can_see_position(logical_position, actor_floor)
		var visual: Dictionary = actor_visuals.get(actor_id, {})
		if visual.is_empty():
			visual = _create_actor_visual(node)
			actor_visuals[actor_id] = visual
		var model: Node3D = visual["root"]
		model.visible = visible
		if bool(visual["has_health"]):
			(visual["health_bar"] as Node3D).visible = visible
		if not visible:
			continue
		var stair_id := String(node.get("stair_id"))
		model.position = Vector3(logical_position.x, world_map.elevation_at(logical_position, actor_floor, stair_id), logical_position.y)
		if node == player:
			model.rotation.y = atan2(-player.facing_direction.x, -player.facing_direction.y)
			var swing: Node3D = visual["swing"]
			swing.visible = player._attack_flash_left > 0.0
			swing.rotation.y = lerpf(-0.9, 0.9, 1.0 - clampf(player._attack_flash_left / 0.18, 0.0, 1.0))
		elif node is ZombieActor:
			var zombie := node as ZombieActor
			var direction := zombie.target_position - zombie.logical_position
			if direction.length_squared() > 0.001:
				model.rotation.y = atan2(-direction.x, -direction.y)
			_update_health_bar(visual, zombie.health, ZombieActor.MAX_HEALTH)
			var flash := _zombie_flash_material if zombie._damage_flash_left > 0.0 else _zombie_material
			(visual["body"] as MeshInstance3D).material_override = flash
			(visual["head"] as MeshInstance3D).material_override = flash
		if bool(visual["has_health"]):
			var bar: Node3D = visual["health_bar"]
			bar.global_position = model.global_position + Vector3(0.0, 2.05, 0.0)
			bar.look_at(camera.global_position, Vector3.UP)
	for actor_id in actor_visuals.keys():
		if not alive_ids.has(actor_id):
			_remove_actor_visual(actor_id, actor_visuals[actor_id])


func _create_actor_visual(actor: Node2D) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.26
	capsule.height = 1.42
	var body := MeshInstance3D.new()
	body.mesh = capsule
	body.position.y = 0.76
	root.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.23
	head_mesh.height = 0.46
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.62, -0.04)
	root.add_child(head)
	var has_health := actor is ZombieActor
	var material := _zombie_material if has_health else (_npc_material if actor is SurvivorNPC else _player_material)
	body.material_override = material
	head.material_override = _player_accent_material if actor == player else material
	if has_health:
		head.position.z = -0.2
	var direction_marker := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.07, 0.07, 0.42)
	direction_marker.mesh = marker_mesh
	direction_marker.position = Vector3(0.0, 0.85, -0.42)
	direction_marker.material_override = _door_material
	root.add_child(direction_marker)
	var visual := {"root": root, "body": body, "head": head, "has_health": has_health}
	if actor == player:
		visual["swing"] = _create_swing_visual(root)
	if has_health:
		visual["health_bar"] = _create_health_bar()
		var actor_id := actor.get_instance_id()
		(actor as ZombieActor).died.connect(
			func(_zombie: ZombieActor) -> void: _remove_actor_visual(actor_id, visual),
			CONNECT_ONE_SHOT
		)
	return visual


func _create_swing_visual(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(12):
		var a := lerpf(-0.45, 0.45, float(index) / 12.0)
		var b := lerpf(-0.45, 0.45, float(index + 1) / 12.0)
		for point in [Vector2(sin(a), -cos(a)) * 0.72, Vector2(sin(a), -cos(a)) * 1.22, Vector2(sin(b), -cos(b)) * 1.22,
			Vector2(sin(a), -cos(a)) * 0.72, Vector2(sin(b), -cos(b)) * 1.22, Vector2(sin(b), -cos(b)) * 0.72]:
			surface.add_vertex(Vector3(point.x, 0.85, point.y))
	var arc := MeshInstance3D.new()
	arc.mesh = surface.commit()
	arc.material_override = _swing_material
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(arc)
	root.visible = false
	return root


func _remove_actor_visual(actor_id: int, visual: Dictionary) -> void:
	for key in ["root", "health_bar"]:
		var node := visual.get(key) as Node3D
		if is_instance_valid(node):
			node.visible = false
			node.queue_free()
	actor_visuals.erase(actor_id)


func _create_health_bar() -> Node3D:
	var bar := Node3D.new()
	add_child(bar)
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(0.8, 0.1, 0.04)
	back.mesh = back_mesh
	back.material_override = _health_back_material
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(back)
	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.72, 0.055, 0.06)
	fill.mesh = fill_mesh
	fill.position.z = -0.035
	fill.material_override = _health_fill_material
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.add_child(fill)
	bar.visible = false
	return bar


func _update_health_bar(visual: Dictionary, health: int, max_health: int) -> void:
	var bar: Node3D = visual["health_bar"]
	var fill := bar.get_child(1) as MeshInstance3D
	var ratio := clampf(float(health) / float(maxi(1, max_health)), 0.0, 1.0)
	fill.scale.x = maxf(0.001, ratio)
	fill.position.x = -0.36 * (1.0 - ratio)


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
