class_name BuildingOcclusionSystem
extends RefCounted

## Static spatial hash: query only the view corridor when local context changes.
const CELL_SIZE := 8.0
var cells: Dictionary = {}
var active_zones: Array[OcclusionZone] = []
var last_candidate_count := 0


func register_zone(zone: OcclusionZone) -> void:
	# floor division must also work for buildings outside the initial positive map.
	var start := Vector2i((Vector2(zone.bounds.position.x, zone.bounds.position.z) / CELL_SIZE).floor())
	var end := Vector2i((Vector2(zone.bounds.end.x, zone.bounds.end.z) / CELL_SIZE).floor())
	for y in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			var key := Vector2i(x, y)
			if not cells.has(key):
				cells[key] = []
			cells[key].append(zone)


func update_view(interior_id: String, floor_index: int, feet: Vector3,
		direction: Vector3, distance: float, reveal_rect: Vector4, regions: Array[AABB] = []) -> void:
	var end := feet + direction * distance
	var query := Rect2(Vector2(feet.x, feet.z), Vector2.ZERO).expand(Vector2(end.x, end.z)).grow(0.35)
	for region in regions:
		var region_rect := Rect2(Vector2(region.position.x, region.position.z), Vector2(region.size.x, region.size.z))
		query = query.merge(region_rect)
		region_rect.position += Vector2(direction.x, direction.z) * distance
		query = query.merge(region_rect)
	var start_cell := Vector2i((query.position / CELL_SIZE).floor())
	var end_cell := Vector2i((query.end / CELL_SIZE).floor())
	var candidates: Dictionary = {}
	for y in range(start_cell.y, end_cell.y + 1):
		for x in range(start_cell.x, end_cell.x + 1):
			for zone: OcclusionZone in cells.get(Vector2i(x, y), []):
				candidates[zone] = true
	last_candidate_count = candidates.size()
	var next_active: Array[OcclusionZone] = []
	for zone: OcclusionZone in candidates:
		if zone.target is BuildingVisibilityController and zone.target.building_id == interior_id:
			continue
		var blocks := OcclusionZone.blocks_view(zone.bounds, feet, direction, distance)
		if zone.target is BuildingVisibilityController:
			blocks = blocks or OcclusionZone.blocks_regions(zone.bounds, regions, direction, distance)
		if not blocks:
			continue
		next_active.append(zone)
		zone.set_blocked(true)
		if zone.target is BuildingVisibilityController:
			zone.target.update_exterior_view(floor_index, feet, direction, distance, regions)
		elif zone.target is SmallOccluder:
			zone.target.set_occlusion(true, reveal_rect)
	for zone in active_zones:
		if next_active.has(zone):
			continue
		zone.set_blocked(false)
		if zone.target is BuildingVisibilityController:
			if zone.target.building_id != interior_id:
				zone.target.set_cutaway(false)
		elif zone.target is SmallOccluder:
			zone.target.set_occlusion(false)
	active_zones = next_active
