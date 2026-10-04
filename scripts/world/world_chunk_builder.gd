class_name WorldChunkBuilder
extends RefCounted

## Sparse render index built once per loaded map. Each X/Z chunk owns all its
## storeys. Long walls and roofs are split spatially, never owned by midpoint.
const WALL_THICKNESS := 0.12
var world_map: WorldMap
var chunks: Dictionary = {}
var barrier_chunks: Dictionary = {}
var materials: Dictionary = {}
var _openings: Dictionary = {}
var _geometry: Dictionary = {}
var _box_mesh: BoxMesh


func setup(map: WorldMap) -> void:
	world_map = map
	chunks.clear()
	barrier_chunks.clear()
	_openings.clear()
	_prepare_geometry()
	for entry in [["floor", "393a34"], ["grass", "49694b"], ["soil", "785f46"],
		["water", "315b78"], ["road", "55595b"], ["indoor", "89775e"],
		["wall", "686057"], ["door", "936d43"], ["roof", "414c52"],
		["stair", "a58b65"], ["sign", "526e8a"]]:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(entry[1])
		material.roughness = 0.92
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials[entry[0]] = material
	for stair: StairLink in map.stairs.values():
		var direction := stair.direction()
		var side := Vector2(-direction.y, direction.x) * stair.width * 0.5
		var low := stair.start + direction * 0.15
		var high := stair.end - direction * 0.28
		var opening := PackedVector2Array([low - side, high - side, high + side, low + side])
		var bounds := Rect2(opening[0], Vector2.ZERO)
		for point in opening: bounds = bounds.expand(point)
		for key in _keys_in(bounds):
			var floor_key := Vector3i(stair.to_floor, key.x, key.y)
			if not _openings.has(floor_key): _openings[floor_key] = []
			_openings[floor_key].append(opening)
		_index_stair(stair)
	for level: int in map.floor_levels():
		var floor_data := map.floors[level] as FloorData
		for cell: Vector2i in floor_data.tiles:
			_entry(WorldChunkStreamer.cell_at(Vector2(cell)))["tiles"].append({"cell": cell, "level": level})
		for face: Dictionary in floor_data.wall_faces:
			if face.get("render", true): _index_wall(face, level)
		for face: Dictionary in floor_data.visual_edges:
			_index_wall(face, level)
	for building: BuildingData in map.buildings.values():
		if not building.has_roof: continue
		var roof_bounds := Rect2(building.bounds).grow(0.06)
		for key in _keys_in(roof_bounds):
			var clipped := roof_bounds.intersection(WorldChunkStreamer.bounds_at(key))
			if not clipped.has_area(): continue
			_entry(key)["boxes"].append({"size": Vector3(clipped.size.x, 0.16, clipped.size.y),
				"position": Vector3(clipped.get_center().x, building.floor_count * map.floor_height + 0.04, clipped.get_center().y),
				"material": "roof", "yaw": 0.0})
	for decoration: MapDecorationDefinition in map.definition.decorations:
		_entry(WorldChunkStreamer.cell_at(decoration.position))["props"].append(decoration)


func _entry(key: Vector2i) -> Dictionary:
	if not chunks.has(key): chunks[key] = {"tiles": [], "walls": [], "boxes": [], "beams": [], "props": []}
	return chunks[key]


func _keys_in(bounds: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var first := WorldChunkStreamer.cell_at(bounds.position)
	var last := WorldChunkStreamer.cell_at(bounds.end)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1): result.append(Vector2i(x, y))
	return result


static func clip_segment(start: Vector2, end: Vector2, bounds: Rect2) -> PackedVector2Array:
	var delta := end - start
	var low := 0.0
	var high := 1.0
	for axis in range(2):
		if absf(delta[axis]) < 0.000001:
			# Half-open ownership prevents duplicate faces along chunk boundaries.
			if start[axis] < bounds.position[axis] or start[axis] >= bounds.end[axis]: return []
		else:
			var a := (bounds.position[axis] - start[axis]) / delta[axis]
			var b := (bounds.end[axis] - start[axis]) / delta[axis]
			low = maxf(low, minf(a, b))
			high = minf(high, maxf(a, b))
	if high - low < 0.000001: return []
	return PackedVector2Array([start + delta * low, start + delta * high])


func _index_wall(face: Dictionary, level: int) -> void:
	var start: Vector2 = face["start"]
	var end: Vector2 = face["end"]
	var direction := end - start
	# Preserve the existing corner ownership: horizontal walls stop at the inner
	# face of perpendicular walls, preventing coplanar overlap at joins.
	if absf(direction.x) > absf(direction.y):
		if _has_perpendicular_join(face, start, level): start += direction.normalized() * WALL_THICKNESS * 0.5
		if _has_perpendicular_join(face, end, level): end -= direction.normalized() * WALL_THICKNESS * 0.5
	var id := String(face.get("barrier_id", ""))
	for key in _keys_in(Rect2(start, Vector2.ZERO).expand(end)):
		var clipped := clip_segment(start, end, WorldChunkStreamer.bounds_at(key))
		if clipped.is_empty(): continue
		_entry(key)["walls"].append({"start": clipped[0], "end": clipped[1], "level": level,
			"kind": String(face.get("kind", "wall")), "barrier": id})
		if not id.is_empty():
			if not barrier_chunks.has(id): barrier_chunks[id] = []
			if not barrier_chunks[id].has(key): barrier_chunks[id].append(key)


func _has_perpendicular_join(face: Dictionary, endpoint: Vector2, level: int) -> bool:
	var unit := ((face["end"] as Vector2) - (face["start"] as Vector2)).normalized()
	for candidate: Dictionary in world_map.query_walls(level, Rect2(endpoint, Vector2.ZERO).grow(0.02)):
		var start: Vector2 = candidate["start"]
		var end: Vector2 = candidate["end"]
		if endpoint.distance_squared_to(start) > 0.0004 and endpoint.distance_squared_to(end) > 0.0004: continue
		if start.distance_squared_to(end) > 0.0001 and absf(unit.dot(start.direction_to(end))) < 0.01: return true
	return false


func _index_stair(stair: StairLink) -> void:
	var direction := stair.direction()
	var length := stair.start.distance_to(stair.end)
	var base := stair.from_floor * world_map.floor_height
	var rise := (stair.to_floor - stair.from_floor) * world_map.floor_height
	var steps := maxi(maxi(8, ceili(rise / 0.22)), ceili(length))
	for step in steps:
		var progress := (float(step) + 0.5) / steps
		var point := stair.start.lerp(stair.end, progress)
		_entry(WorldChunkStreamer.cell_at(point))["boxes"].append({
			"size": Vector3(length / steps + 0.02, 0.09, stair.width),
			"position": Vector3(point.x, base + rise * progress - 0.045, point.y),
			"material": "stair", "yaw": -direction.angle()})
	var side := Vector2(-direction.y, direction.x) * stair.width * 0.5
	for sign: float in [-1.0, 1.0]:
		var start := stair.start + side * sign
		var end := stair.end + side * sign
		_index_beam(Vector3(start.x, base + 0.65, start.y), Vector3(end.x, base + rise + 0.65, end.y))
		for progress in [0.0, 0.5, 1.0]:
			var point := start.lerp(end, progress)
			_index_beam(Vector3(point.x, base + rise * progress, point.y), Vector3(point.x, base + rise * progress + 0.65, point.y))


func _index_beam(start: Vector3, end: Vector3) -> void:
	# Short segments have bounded overhang into adjacent chunks.
	var count := maxi(1, ceili(start.distance_to(end)))
	for index in count:
		var a := start.lerp(end, float(index) / count)
		var b := start.lerp(end, float(index + 1) / count)
		var center := (a + b) * 0.5
		_entry(WorldChunkStreamer.cell_at(Vector2(center.x, center.z)))["beams"].append([a, b])


func begin_chunk(key: Vector2i) -> Dictionary:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [key.x, key.y]
	return {"root": root, "data": chunks[key], "batches": {}, "barriers": {}, "stage": 0, "index": 0}


func build_chunk(key: Vector2i) -> Node3D:
	var job := begin_chunk(key)
	advance_chunk(job, 0)
	return job["root"]


func advance_chunk(job: Dictionary, budget_usec: int) -> bool:
	var started := Time.get_ticks_usec()
	while int(job["stage"]) < 7:
		_step_chunk(job)
		if budget_usec > 0 and Time.get_ticks_usec() - started >= budget_usec:
			return false
	(job["root"] as Node3D).set_meta("barriers", job["barriers"])
	return true


func _step_chunk(job: Dictionary) -> void:
	var batches: Dictionary = job["batches"]
	var stage := int(job["stage"])
	var fields := ["tiles", "", "walls", "boxes", "beams", "props", ""]
	var items: Array = batches.keys() if stage in [1, 6] else job["data"][fields[stage]]
	var index := int(job["index"])
	if index >= items.size():
		job["stage"] = stage + 1
		job["index"] = 0
		return
	job["index"] = index + 1
	match stage:
		0:
			_append_tile(batches, items[index])
		1:
			pass
		2:
			_append_wall(job, items[index])
		3:
			var box: Dictionary = items[index]
			_append_geometry(_surface(batches, box["material"]), "box", Transform3D(Basis(Vector3.UP, box["yaw"]) * Basis.from_scale(box["size"]), box["position"]))
		4:
			var beam: Array = items[index]
			var height := (beam[0] as Vector3).distance_to(beam[1])
			var basis := Basis(Quaternion(Vector3.UP, (beam[1] - beam[0]).normalized())) * Basis.from_scale(Vector3(0.035, height, 0.035))
			_append_geometry(_surface(batches, "door"), "cylinder", Transform3D(basis, (beam[0] + beam[1]) * 0.5))
		5:
			_add_prop(batches, items[index])
		6:
			var material := String(items[index])
			var instance := MeshInstance3D.new()
			instance.name = material
			(batches[material] as SurfaceTool).index()
			instance.mesh = (batches[material] as SurfaceTool).commit()
			instance.material_override = materials[material]
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(job["root"] as Node3D).add_child(instance)


func _append_tile(batches: Dictionary, tile_data: Dictionary) -> void:
	var cell: Vector2i = tile_data["cell"]
	var level := int(tile_data["level"])
	var tile := world_map.get_tile_at(cell, level)
	var surface := _surface(batches, _floor_kind(tile.kind))
	for polygon in tile_polygons(cell, level):
		for index in Geometry2D.triangulate_polygon(polygon):
			var point: Vector2 = polygon[index]
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(point.x, level * world_map.floor_height, point.y))


func _append_wall(job: Dictionary, wall: Dictionary) -> void:
	var direction: Vector2 = wall["end"] - wall["start"]
	var center: Vector2 = (wall["start"] + wall["end"]) * 0.5
	var size := Vector3(direction.length(), world_map.floor_height, WALL_THICKNESS)
	var pose := Transform3D(Basis(Vector3.UP, -direction.angle()) * Basis.from_scale(size), Vector3(center.x, (float(wall["level"]) + 0.5) * world_map.floor_height, center.y))
	var material := "door" if wall["kind"] == "door" else ("water" if wall["kind"] == "window" else "wall")
	var id := String(wall["barrier"])
	if id.is_empty():
		_append_geometry(_surface(job["batches"], material), "box", pose)
	else:
		var instance := MeshInstance3D.new()
		instance.mesh = _box_mesh
		instance.transform = pose
		instance.material_override = materials[material]
		instance.visible = not world_map.is_barrier_open(id)
		(job["root"] as Node3D).add_child(instance)
		if not job["barriers"].has(id): job["barriers"][id] = []
		job["barriers"][id].append(instance)

func _surface(batches: Dictionary, material: String) -> SurfaceTool:
	if not batches.has(material):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[material] = surface
	return batches[material]


func _prepare_geometry() -> void:
	# Read reusable primitive arrays once. Constructing a fresh PrimitiveMesh and
	# calling append_from during streaming can synchronize with the render thread.
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_geometry["box"] = _box_mesh.surface_get_arrays(0)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	_geometry["cylinder"] = cylinder.surface_get_arrays(0)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 2.0 / 3.0
	trunk.bottom_radius = 1.0
	trunk.height = 1.0
	trunk.radial_segments = 8
	_geometry["trunk"] = trunk.surface_get_arrays(0)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_geometry["sphere"] = sphere.surface_get_arrays(0)


func _append_geometry(surface: SurfaceTool, shape: String, pose: Transform3D) -> void:
	var arrays: Array = _geometry[shape]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis := pose.basis.inverse().transposed()
	for index in indices:
		surface.set_normal((normal_basis * normals[index]).normalized())
		surface.add_vertex(pose * vertices[index])


func _add_prop(batches: Dictionary, prop: MapDecorationDefinition) -> void:
	var base := world_map.definition.logical_to_world(prop.position, prop.level)
	if prop.kind == "tree":
		_append_geometry(_surface(batches, "stair"), "trunk", Transform3D(Basis.from_scale(Vector3(0.18, 2.8, 0.18)), base + Vector3.UP * 1.4))
		_append_geometry(_surface(batches, "grass"), "sphere", Transform3D(Basis.from_scale(Vector3.ONE * 0.9), base + Vector3.UP * 3.0))
	else:
		_append_geometry(_surface(batches, "wall"), "cylinder", Transform3D(Basis.from_scale(Vector3(0.05, 2.6, 0.05)), base + Vector3.UP * 1.3))
		_append_geometry(_surface(batches, "sign"), "box", Transform3D(Basis.from_scale(Vector3(1.1, 0.75, 0.08)), base + Vector3.UP * 2.3))

func tile_polygons(cell: Vector2i, level: int) -> Array[PackedVector2Array]:
	var corner := Vector2(cell)
	var polygons: Array[PackedVector2Array] = [PackedVector2Array([corner, corner + Vector2.RIGHT, corner + Vector2.ONE, corner + Vector2.DOWN])]
	var key := WorldChunkStreamer.cell_at(Vector2(cell))
	for opening: PackedVector2Array in _openings.get(Vector3i(level, key.x, key.y), []):
		var remaining: Array[PackedVector2Array] = []
		for polygon in polygons: remaining.append_array(Geometry2D.clip_polygons(polygon, opening))
		polygons = remaining
	return polygons


func _floor_kind(kind: String) -> String:
	match kind:
		"road", "asphalt", "concrete": return "road"
		"floor", "wall", "stairs", "indoor_floor": return "indoor"
		"door": return "door"
		"soil", "dirt": return "soil"
		"water": return "water"
	return "grass"
