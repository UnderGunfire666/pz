extends Node

## Offline binding for the supplied unrigged clothing. Keep originals intact.
## Run: Godot --headless --path . res://tools/bake_clothing.tscn
## The source kit uses a 1.68 m A pose. These landmarks describe that pose;
## each output is fitted and weighted against its target body's rest mesh.
const SOURCE := {
	"Hips": [Vector3(0, 0.93, 0.025), Vector3(0, 1.04, 0.025)],
	"Spine": [Vector3(0, 1.04, 0.025), Vector3(0, 1.15, 0.025)],
	"Spine1": [Vector3(0, 1.15, 0.025), Vector3(0, 1.28, 0.025)],
	"Spine2": [Vector3(0, 1.28, 0.025), Vector3(0, 1.43, 0.015)],
	"Neck": [Vector3(0, 1.43, 0.015), Vector3(0, 1.51, 0.025)],
	"Head": [Vector3(0, 1.51, 0.025), Vector3(0, 1.67, 0.025)],
	"LeftArm": [Vector3(0.185, 1.36, 0.025), Vector3(0.34, 1.16, 0.12)],
	"LeftForeArm": [Vector3(0.34, 1.16, 0.12), Vector3(0.455, 1.035, 0.23)],
	"LeftHand": [Vector3(0.455, 1.035, 0.23), Vector3(0.49, 0.925, 0.28)],
	"LeftUpLeg": [Vector3(0.105, 0.93, 0.025), Vector3(0.175, 0.49, 0.04)],
	"LeftLeg": [Vector3(0.175, 0.49, 0.04), Vector3(0.19, 0.085, 0.015)],
	"LeftFoot": [Vector3(0.19, 0.085, 0.015), Vector3(0.19, 0.045, 0.16)],
	"LeftToeBase": [Vector3(0.19, 0.045, 0.16), Vector3(0.19, 0.035, 0.21)],
}
const NEXT := {"Hips": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head", "Arm": "ForeArm", "ForeArm": "Hand", "Hand": "HandMiddle3", "UpLeg": "Leg", "Leg": "Foot", "Foot": "ToeBase"}
var _source: Dictionary
var _models: Dictionary = {}
var _body_points: Array = []
var _body_surfaces: Array = []
var _body_triangles: Array = []
var _triangle_grid: Dictionary = {}
var _skeleton: Skeleton3D
var _maps: Dictionary = {}
var _failed := false
const CELL := 0.08

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	_source = SOURCE.duplicate(true)
	for key: String in SOURCE:
		if key.begins_with("Left"):
			var a: Vector3 = SOURCE[key][0]
			var b: Vector3 = SOURCE[key][1]
			a.x = -a.x
			b.x = -b.x
			_source[key.replace("Left", "Right")] = [a, b]
	for kind: String in ["male", "female", "zombie"]:
		var options := OS.get_cmdline_user_args()
		var selected_body := ""
		var selected_item := ""
		for option: String in options:
			if option.begins_with("--body="): selected_body = option.trim_prefix("--body=")
			if option.begins_with("--item="): selected_item = option.trim_prefix("--item=")
		if not selected_body.is_empty() and selected_body != kind: continue
		var path := CharacterAppearance.MALE if kind == "male" else (CharacterAppearance.FEMALE if kind == "female" else ActorBody.ZOMBIE.model_path)
		var model := (load(path) as PackedScene).instantiate()
		get_tree().root.add_child(model)
		_skeleton = MixamoCharacterVisual.find_skeleton(model)
		_prepare_body(model)
		_prepare_maps()
		DirAccess.make_dir_recursive_absolute(ClothingCatalog.BAKED + kind)
		for id: String in ClothingCatalog.SOURCES:
			if not selected_item.is_empty() and selected_item != id: continue
			var definition := ClothingCatalog.definition(id)
			if not definition.clothing_gender.is_empty() and definition.clothing_gender != ("male" if kind == "zombie" else kind): continue
			_bake(id, kind)
		if kind != "zombie" and selected_item.is_empty():
			for hair: String in CharacterAppearance.HAIR:
				if hair != "original": _bake_hair(hair, kind)
		if selected_item.is_empty() or selected_item == "glasses": _bake_glasses(kind)
		model.free()
	for model in _models.values(): model.free()
	print("CLOTHING_BAKE_COMPLETE failed=", _failed)
	get_tree().quit(1 if _failed else 0)

func _prepare_body(model: Node) -> void:
	_body_points.clear()
	_body_surfaces.clear()
	_body_triangles.clear()
	_triangle_grid.clear()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name) in ["Eyes", "Eyebrows"]: continue
		for s in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var offset := _body_points.size()
			var influences := bones.size() / vertices.size()
			for v in vertices.size():
				var skin_weights := {}
				for influence in influences:
					var w := weights[v * influences + influence]
					if w <= 0.00001: continue
					var bind := bones[v * influences + influence]
					var bone := mesh.skin.get_bind_bone(bind)
					if bone < 0: bone = _skeleton.find_bone(mesh.skin.get_bind_name(bind))
					if bone >= 0: skin_weights[bone] = w
				var p: Vector3 = mesh.global_transform * vertices[v]
				_body_points.append({"p": p, "n": (mesh.global_basis * normals[v]).normalized(), "weights": skin_weights})
			_body_surfaces.append({"key": String(mesh.name) + ":" + str(s), "offset": offset, "indices": arrays[Mesh.ARRAY_INDEX]})
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for t in indices.size() / 3:
				var ia := offset + indices[t * 3]
				var ib := offset + indices[t * 3 + 1]
				var ic := offset + indices[t * 3 + 2]
				_add_triangle(_body_triangles, _triangle_grid, _body_points[ia]["p"], _body_points[ib]["p"], _body_points[ic]["p"], Vector3i(ia, ib, ic))

func _prepare_maps() -> void:
	_maps.clear()
	for name: String in _source:
		var bone := MixamoCharacterVisual.bone(_skeleton, name)
		if bone < 0: continue
		var a: Vector3 = _source[name][0]
		var b: Vector3 = _source[name][1]
		var ta := _skeleton.get_bone_global_rest(bone).origin
		var next_name: String = NEXT.get(name, "")
		if name.begins_with("Left") or name.begins_with("Right"):
			var side := "Left" if name.begins_with("Left") else "Right"
			next_name = side + String(NEXT.get(name.trim_prefix(side), ""))
		var next := MixamoCharacterVisual.bone(_skeleton, next_name)
		var tb := _skeleton.get_bone_global_rest(next).origin if next >= 0 else ta + (b - a) * 1.08
		var from := (b - a).normalized()
		var to := (tb - ta).normalized()
		var rotation := Basis(Quaternion(from, to))
		var radial := 1.08
		var axial := ta.distance_to(tb) / a.distance_to(b)
		var stretch := Basis(Vector3.RIGHT * radial + from * from.x * (axial - radial), Vector3.UP * radial + from * from.y * (axial - radial), Vector3.BACK * radial + from * from.z * (axial - radial))
		var basis := rotation * stretch
		_maps[name] = {"bone": bone, "transform": Transform3D(basis, ta - basis * a)}

func _source_mesh(row: Array) -> MeshInstance3D:
	var path: String = ClothingCatalog.ROOT + row[0]
	if not _models.has(path):
		var packed := load(path) as PackedScene
		if packed == null: return null
		_models[path] = packed.instantiate()
		get_tree().root.add_child(_models[path])
	for mesh: MeshInstance3D in _models[path].find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name) == row[1]: return mesh
	push_error("Missing garment mesh: %s / %s" % [path, row[1]])
	_failed = true
	return null

func _influences(p: Vector3, slot: String) -> Array:
	var candidates: Array = []
	for name: String in _maps:
		var arm := name.contains("Arm") or name.contains("Hand")
		var leg := name.contains("Leg") or name.contains("Foot") or name.contains("Toe")
		if slot in ["hat", "mask", "glasses"] and name != "Head": continue
		if slot in ["outer_bottom", "inner_bottom", "underwear_bottom", "shoes", "socks"] and not leg and name != "Hips": continue
		if slot in ["inner_top", "outer_top", "underwear_top", "belt", "neck", "badge"] and (leg or name == "Head"): continue
		if slot == "gloves" and not (name.contains("Hand") or name.contains("ForeArm")): continue
		if slot == "medical_support" and name != "LeftHand": continue
		if slot in ["neck", "badge"] and name != "Spine2": continue
		if slot == "belt" and name != "Hips": continue
		if (arm or leg) and ((p.x < 0 and name.begins_with("Left")) or (p.x >= 0 and name.begins_with("Right"))): continue
		var a: Vector3 = _source[name][0]
		var b: Vector3 = _source[name][1]
		var nearest := Geometry3D.get_closest_point_to_segment(p, a, b)
		candidates.append({"name": name, "d": p.distance_squared_to(nearest)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])
	if candidates.size() > 3: candidates.resize(3)
	var total := 0.0
	for candidate in candidates:
		candidate["w"] = 1.0 / pow(maxf(0.001, candidate["d"]), 2.0)
		total += candidate["w"]
	for candidate in candidates: candidate["w"] /= total
	return candidates

func _bake(id: String, kind: String) -> void:
	var row: Array = ClothingCatalog.SOURCES[id]
	var source := _source_mesh(row)
	if source == null: return
	if id == "medical_gloves":
		_bake_gloves(source, kind)
		return
	var output := ArrayMesh.new()
	var garment_samples: Array = []
	var garment_grid := {}
	for s in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(s).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(vertices.size() * 4)
		weights.resize(vertices.size() * 4)
		for v in vertices.size():
			var p: Vector3 = source.global_transform * vertices[v]
			# Female underwear variants were laid out side by side in the source.
			if id.begins_with("female_"): p -= source.global_position
			if id == "medical_crutch": p.x -= 0.20
			var normal := (source.global_basis.inverse().transposed() * normals[v]).normalized()
			var fitted := Vector3.ZERO
			var fitted_normal := Vector3.ZERO
			var skin_weights := {}
			for candidate in _influences(p, row[2]):
				var mapping: Dictionary = _maps[candidate["name"]]
				var transform: Transform3D = mapping["transform"]
				fitted += (transform * p) * candidate["w"]
				fitted_normal += (transform.basis.inverse().transposed() * normal) * candidate["w"]
				skin_weights[mapping["bone"]] = candidate["w"]
			if row[2] == "hat": fitted.y += 0.025
			if row[2] not in ["hat", "mask", "neck", "badge", "medical_support", "belt"]:
				var nearest := _nearest_triangle(_body_triangles, _triangle_grid, fitted)
				if not nearest.is_empty():
					var triangle: Dictionary = _body_triangles[nearest["index"]]
					var bary: Vector3 = nearest["bary"]
					var body_normal := Vector3.ZERO
					skin_weights = {}
					for corner in 3:
						var body: Dictionary = _body_points[triangle["indices"][corner]]
						body_normal += body["n"] * bary[corner]
						for bone: int in body["weights"]: skin_weights[bone] = skin_weights.get(bone, 0.0) + body["weights"][bone] * bary[corner]
					body_normal = body_normal.normalized()
					var clearance: float = (fitted - nearest["point"]).dot(body_normal)
					# Preserve loose fabric up to 3 cm, fit gender-neutral garments to
					# this actual body, and interpolate the body's joint weights.
					fitted = nearest["point"] + body_normal * clampf(clearance, 0.018, 0.04)
			vertices[v] = fitted
			normals[v] = fitted_normal.normalized()
			_write_weights(bones, weights, v, skin_weights)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var temporary := ArrayMesh.new()
		temporary.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface := SurfaceTool.new()
		surface.create_from(temporary, 0)
		surface.generate_tangents()
		surface.commit(output)
		var material := source.get_active_material(s).duplicate() as StandardMaterial3D
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if id == "underwear_tshirt":
			material.albedo_texture = load(ClothingCatalog.ROOT + "Underwear 2025/textures/TShirt_TShirt_BaseColor_Utility - sRGB - Texture.png")
		output.surface_set_material(s, material)
		if row[2] not in ["neck", "badge", "medical_support", "belt"]:
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for t in indices.size() / 3:
				var previous_count := garment_samples.size()
				_add_triangle(garment_samples, garment_grid, vertices[indices[t * 3]], vertices[indices[t * 3 + 1]], vertices[indices[t * 3 + 2]])
				if garment_samples.size() > previous_count:
					garment_samples[-1]["uv"] = [uvs[indices[t * 3]], uvs[indices[t * 3 + 1]], uvs[indices[t * 3 + 2]]]
	var masks := _coverage(garment_samples, garment_grid, id)
	if id in ["ranger_shirt", "medical_shirt", "underwear_tshirt", "casual_shoes", "ranger_boots"]:
		_add_lining(output, id, garment_samples, garment_grid, masks)
	output.set_meta("body_masks", masks)
	output.set_meta("source", ClothingCatalog.ROOT + row[0])
	output.set_meta("source_mesh", row[1])
	output.set_meta("body_type", kind)
	var err := ResourceSaver.save(output, ClothingCatalog.mesh_path(id, kind), ResourceSaver.FLAG_COMPRESS)
	if err != OK: _failed = true
	print("BAKED ", kind, " ", id, " surfaces=", output.get_surface_count())

func _add_lining(output: ArrayMesh, id: String, triangles: Array, grid: Dictionary, masks: Dictionary) -> void:
	# A fitted lining closes gaps between differently tessellated shoulders/feet.
	# Transfer UVs from the original garment so its own material is retained.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for entry in _body_surfaces:
		var indices: PackedInt32Array = entry["indices"]
		var hidden: PackedInt32Array = masks.get(entry["key"], PackedInt32Array())
		for t in indices.size() / 3:
			var points: Array = []
			for corner in 3: points.append(_body_points[entry["offset"] + indices[t * 3 + corner]])
			if not _lining_point(id, points[0]["p"]) or not _lining_point(id, points[1]["p"]) or not _lining_point(id, points[2]["p"]): continue
			hidden.append(t)
			for point: Dictionary in points:
				var vertex: Vector3 = point["p"] + point["n"] * 0.01
				var nearest := _nearest_triangle(triangles, grid, vertex)
				var uv := Vector2.ZERO
				if not nearest.is_empty():
					var original_uv: Array = triangles[nearest["index"]]["uv"]
					var bary: Vector3 = nearest["bary"]
					uv = original_uv[0] * bary.x + original_uv[1] * bary.y + original_uv[2] * bary.z
				vertices.append(vertex)
				normals.append(point["n"])
				uvs.append(uv)
				bones.resize(vertices.size() * 4)
				weights.resize(vertices.size() * 4)
				_write_weights(bones, weights, vertices.size() - 1, point["weights"])
		masks[entry["key"]] = hidden
	if vertices.is_empty(): return
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var temporary := ArrayMesh.new()
	temporary.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := SurfaceTool.new()
	surface.create_from(temporary, 0)
	surface.generate_tangents()
	surface.commit(output)
	output.surface_set_material(output.get_surface_count() - 1, output.surface_get_material(0))

func _lining_point(id: String, p: Vector3) -> bool:
	if id in ["casual_shoes", "ranger_boots"]:
		return p.y < (0.18 if id == "ranger_boots" else 0.105)
	var hips := _skeleton.get_bone_global_rest(MixamoCharacterVisual.bone(_skeleton, "Hips")).origin
	var neck := _skeleton.get_bone_global_rest(MixamoCharacterVisual.bone(_skeleton, "Neck")).origin
	for side: String in ["Left", "Right"]:
		var arm := _skeleton.get_bone_global_rest(MixamoCharacterVisual.bone(_skeleton, side + "Arm")).origin
		var elbow := _skeleton.get_bone_global_rest(MixamoCharacterVisual.bone(_skeleton, side + "ForeArm")).origin
		if absf(p.x) > absf(arm.x) - 0.045 and absf(p.x) < lerpf(absf(arm.x), absf(elbow.x), 0.48) and absf(p.y - arm.y) < 0.135: return true
	if absf(p.x) > 0.22 or p.y < hips.y + 0.065 or p.y > neck.y - 0.045: return false
	# Preserve the front neckline instead of closing it with a flat bib.
	if p.z > 0.015 and absf(p.x) < 0.095 and p.y > neck.y - 0.16: return false
	return true

func _write_weights(bones: PackedInt32Array, weights: PackedFloat32Array, vertex: int, values: Dictionary) -> void:
	var keys := values.keys()
	keys.sort_custom(func(a: int, b: int) -> bool: return values[a] > values[b])
	if keys.size() > 4: keys.resize(4)
	var total := 0.0
	for key in keys: total += values[key]
	for i in keys.size():
		bones[vertex * 4 + i] = keys[i]
		weights[vertex * 4 + i] = values[keys[i]] / maxf(total, 0.00001)

func _coverage(points: Array, grid: Dictionary, id: String) -> Dictionary:
	var result := {}
	if points.is_empty(): return result
	var covered := PackedByteArray()
	covered.resize(_body_points.size())
	for i in _body_points.size():
		var p: Vector3 = _body_points[i]["p"]
		var slot: String = ClothingCatalog.SOURCES[id][2]
		if slot in ["inner_top", "outer_top", "underwear_top"]:
			var neck_y := _skeleton.get_bone_global_rest(MixamoCharacterVisual.bone(_skeleton, "Neck")).origin.y
			# Keep the original shoulder/collar silhouette. A projection from a
			# curved shoulder can otherwise hide skin outside the garment's hem.
			if p.y > neck_y - 0.1 or absf(p.x) > 0.15: continue
		var normal: Vector3 = _body_points[i]["n"]
		for triangle_index: int in _near_triangles(grid, p, 1):
			var triangle: Dictionary = points[triangle_index]
			var hit: Variant = Geometry3D.ray_intersects_triangle(p - normal * 0.12, normal, triangle["a"], triangle["b"], triangle["c"])
			if hit is Vector3 and p.distance_to(hit) < 0.12:
				covered[i] = 1
				break
	for entry in _body_surfaces:
		var hidden := PackedInt32Array()
		var indices: PackedInt32Array = entry["indices"]
		for t in indices.size() / 3:
			var ia: int = entry["offset"] + indices[t * 3]
			var ib: int = entry["offset"] + indices[t * 3 + 1]
			var ic: int = entry["offset"] + indices[t * 3 + 2]
			var center: Vector3 = (_body_points[ia]["p"] + _body_points[ib]["p"] + _body_points[ic]["p"]) / 3.0
			if (covered[ia] and covered[ib] and covered[ic]) or _opaque_interior(id, center): hidden.append(t)
		if not hidden.is_empty(): result[entry["key"]] = hidden
	return result

func _opaque_interior(id: String, p: Vector3) -> bool:
	# Guard bands are deliberately inside the hem/collar. They remove the body's
	# interior even when differently tessellated clothing bends across a joint.
	var hips := _skeleton.get_bone_global_rest(MixamoCharacterVisual.bone(_skeleton, "Hips")).origin
	var neck := _skeleton.get_bone_global_rest(MixamoCharacterVisual.bone(_skeleton, "Neck")).origin
	if id in ["casual_jeans", "ranger_pants", "medical_pants"]:
		return p.y > 0.14 and p.y < hips.y + 0.015 and absf(p.x) < 0.31
	if id in ["ranger_shirt", "medical_shirt", "underwear_tshirt"]:
		if absf(p.x) < 0.15 and p.y > hips.y + 0.08 and p.y < neck.y - 0.10: return true
	if id in ["ranger_hat", "medical_cap", "casual_bonnet", "ranger_bonnet"]:
		var head := _skeleton.get_bone_global_rest(MixamoCharacterVisual.bone(_skeleton, "Head")).origin
		return p.y > head.y + 0.14
	return false

func _add_triangle(triangles: Array, grid: Dictionary, a: Vector3, b: Vector3, c: Vector3, indices := Vector3i.ZERO) -> void:
	if (b - a).cross(c - a).length_squared() < 0.000000000001: return
	var index := triangles.size()
	triangles.append({"a": a, "b": b, "c": c, "indices": indices})
	var first := Vector3i((a.min(b).min(c) / CELL).floor())
	var last := Vector3i((a.max(b).max(c) / CELL).floor())
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			for z in range(first.z, last.z + 1):
				var cell := Vector3i(x, y, z)
				if not grid.has(cell): grid[cell] = []
				grid[cell].append(index)

func _near_triangles(grid: Dictionary, p: Vector3, radius: int) -> Array:
	var cell := Vector3i((p / CELL).floor())
	var found := {}
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				for index: int in grid.get(cell + Vector3i(x, y, z), []): found[index] = true
	return found.keys()

func _nearest_triangle(triangles: Array, grid: Dictionary, p: Vector3) -> Dictionary:
	var result := {}
	var distance := INF
	var candidates := _near_triangles(grid, p, 1)
	if candidates.is_empty(): candidates = _near_triangles(grid, p, 3)
	for index: int in candidates:
		var triangle: Dictionary = triangles[index]
		var bary := _closest_barycentric(p, triangle["a"], triangle["b"], triangle["c"])
		var point: Vector3 = triangle["a"] * bary.x + triangle["b"] * bary.y + triangle["c"] * bary.z
		var d := p.distance_squared_to(point)
		if d < distance:
			distance = d
			result = {"point": point, "bary": bary, "index": index}
	return result

func _closest_barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0 and d2 <= 0: return Vector3(1, 0, 0)
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0 and d4 <= d3: return Vector3(0, 1, 0)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0 and d1 >= 0 and d3 <= 0:
		var v := d1 / (d1 - d3)
		return Vector3(1 - v, v, 0)
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0 and d5 <= d6: return Vector3(0, 0, 1)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0 and d2 >= 0 and d6 <= 0:
		var w := d2 / (d2 - d6)
		return Vector3(1 - w, 0, w)
	var va := d3 * d6 - d5 * d4
	if va <= 0 and d4 - d3 >= 0 and d5 - d6 >= 0:
		var w := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return Vector3(0, 1 - w, w)
	var denominator := 1.0 / (va + vb + vc)
	return Vector3(1 - (vb + vc) * denominator, vb * denominator, vc * denominator)

func _bake_hair(hair: String, kind: String) -> void:
	var packed := load(CharacterAppearance.BASE + "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/" + hair + ".gltf") as PackedScene
	var model := packed.instantiate()
	get_tree().root.add_child(model)
	var source_skeleton := MixamoCharacterVisual.find_skeleton(model)
	var source_head := source_skeleton.get_bone_global_rest(MixamoCharacterVisual.bone(source_skeleton, "Head"))
	var target_bone := MixamoCharacterVisual.bone(_skeleton, "Head")
	var offset := _skeleton.get_bone_global_rest(target_bone) * source_head.affine_inverse()
	var output := ArrayMesh.new()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(s).duplicate(true)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bones := PackedInt32Array()
			var weights := PackedFloat32Array()
			bones.resize(vertices.size() * 4)
			weights.resize(vertices.size() * 4)
			for v in vertices.size():
				vertices[v] = offset * mesh.global_transform * vertices[v]
				normals[v] = offset.basis * mesh.global_basis * normals[v]
				bones[v * 4] = target_bone
				weights[v * 4] = 1.0
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = null
			arrays[Mesh.ARRAY_BONES] = bones
			arrays[Mesh.ARRAY_WEIGHTS] = weights
			output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			output.surface_set_material(output.get_surface_count() - 1, mesh.get_active_material(s))
	ResourceSaver.save(output, ClothingCatalog.BAKED + kind + "/" + hair + ".res", ResourceSaver.FLAG_COMPRESS)
	model.free()

func _bake_gloves(source: MeshInstance3D, kind: String) -> void:
	# Surgical gloves conform to the target's individual fingers. Retopologize
	# this close-fitting item on the actual hand surface instead of collapsing
	# an unrelated finger layout onto it, retaining the supplied glove material.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var masks := {}
	for entry in _body_surfaces:
		var hidden := PackedInt32Array()
		var indices: PackedInt32Array = entry["indices"]
		for t in indices.size() / 3:
			var points: Array = []
			for corner in 3: points.append(_body_points[entry["offset"] + indices[t * 3 + corner]])
			if not _on_hand(points[0]) or not _on_hand(points[1]) or not _on_hand(points[2]): continue
			hidden.append(t)
			for point: Dictionary in points:
				vertices.append(point["p"] + point["n"] * 0.004)
				normals.append(point["n"])
				uv.append(Vector2(point["p"].x * 2.0, point["p"].z * 2.0))
				bones.resize(vertices.size() * 4)
				weights.resize(vertices.size() * 4)
				_write_weights(bones, weights, vertices.size() - 1, point["weights"])
		if not hidden.is_empty(): masks[entry["key"]] = hidden
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var output := ArrayMesh.new()
	output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := source.get_active_material(0).duplicate() as StandardMaterial3D
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	output.surface_set_material(0, material)
	output.set_meta("body_masks", masks)
	output.set_meta("source", ClothingCatalog.ROOT + ClothingCatalog.SOURCES["medical_gloves"][0])
	output.set_meta("source_mesh", "Scrub_Gloves")
	output.set_meta("body_type", kind)
	ResourceSaver.save(output, ClothingCatalog.mesh_path("medical_gloves", kind), ResourceSaver.FLAG_COMPRESS)
	print("BAKED ", kind, " medical_gloves surfaces=1")

func _on_hand(point: Dictionary) -> bool:
	var weight := 0.0
	for bone: int in point["weights"]:
		var name := String(_skeleton.get_bone_name(bone)).to_lower()
		if "hand" in name or "thumb" in name or "index" in name or "middle" in name or "ring" in name or "pinky" in name: weight += point["weights"][bone]
	return weight > 0.6

func _bake_glasses(kind: String) -> void:
	var head_index := MixamoCharacterVisual.bone(_skeleton, "Head")
	var head := _skeleton.get_bone_global_rest(head_index).origin
	var eye_height := head.y + (0.09 if kind != "zombie" else 0.095)
	var eye_front := head.z + 0.115
	var parts: Array = []
	for side in [-1.0, 1.0]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.025
		ring.outer_radius = 0.029
		ring.rings = 16
		ring.ring_segments = 6
		parts.append([ring, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(side * 0.033, eye_height, eye_front))])
		var temple := BoxMesh.new()
		temple.size = Vector3(0.005, 0.005, 0.1)
		parts.append([temple, Transform3D(Basis.IDENTITY, Vector3(side * 0.062, eye_height, eye_front - 0.05))])
	var bridge := BoxMesh.new()
	bridge.size = Vector3(0.025, 0.004, 0.005)
	parts.append([bridge, Transform3D(Basis.IDENTITY, Vector3(0, eye_height, eye_front))])
	var output := ArrayMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("343940")
	for part: Array in parts:
		var mesh: Mesh = part[0]
		var transform: Transform3D = part[1]
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(vertices.size() * 4)
		weights.resize(vertices.size() * 4)
		for i in vertices.size():
			vertices[i] = transform * vertices[i]
			normals[i] = transform.basis * normals[i]
			bones[i * 4] = head_index
			weights[i * 4] = 1.0
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		output.surface_set_material(output.get_surface_count() - 1, material)
	ResourceSaver.save(output, ClothingCatalog.mesh_path("glasses", kind), ResourceSaver.FLAG_COMPRESS)
