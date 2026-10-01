class_name MapValidator
extends RefCounted

## Authoring validation only. It never mutates static Resources or save state.
static func validate(map) -> Array[String]:
	var issues: Array[String] = []
	if map == null:
		return ["Map resource is missing."]
	if map.id.strip_edges().is_empty():
		issues.append("Map is missing a stable ID.")
	if map.cell_size.x <= 0 or map.cell_size.y <= 0:
		issues.append("Map %s has an invalid cell size." % map.id)
	var cell_ids: Dictionary = {}
	var cell_positions: Dictionary = {}
	for cell in map.cells:
		if cell.id.strip_edges().is_empty() or cell_ids.has(cell.id):
			issues.append("Cell %s has a missing or duplicate stable ID." % cell.id)
		cell_ids[cell.id] = true
		if cell.size != map.cell_size:
			issues.append("Cell %s size differs from map cell size." % cell.id)
		if cell_positions.has(cell.cell_coordinate):
			issues.append("Cell coordinate %s is authored more than once." % cell.cell_coordinate)
		cell_positions[cell.cell_coordinate] = true
		for level in cell.levels:
			var heat_ids: Dictionary = {}
			for paint in level.terrain_paints:
				if paint.id.strip_edges().is_empty() or paint.terrain == null:
					issues.append("Cell %s level %d has a terrain paint with a missing ID or terrain." % [cell.id, level.level])
				if not Rect2i(Vector2i.ZERO, cell.size).encloses(paint.rect):
					issues.append("Paint %s exceeds cell %s at level %d." % [paint.id, cell.id, level.level])
			for heat in level.heat_paints:
				if heat.id.strip_edges().is_empty() or heat_ids.has(heat.id):
					issues.append("Cell %s level %d has a missing or duplicate heat paint ID." % [cell.id, level.level])
				heat_ids[heat.id] = true
				if heat.pressure < 0.0 or heat.pressure > 1.0 or not Rect2i(Vector2i.ZERO, cell.size).encloses(heat.rect):
					issues.append("Heat paint %s exceeds cell bounds or has invalid pressure." % heat.id)
	var building_ids: Dictionary = {}
	var template_ids: Dictionary = {}
	for building in map.buildings:
		if building.id.strip_edges().is_empty() or building_ids.has(building.id):
			issues.append("Building has a missing or duplicate stable ID: %s." % building.id)
		building_ids[building.id] = true
		var bounds: Rect2i = building.effective_bounds()
		if building.template != null:
			if building.template.id.strip_edges().is_empty() or (template_ids.has(building.template.id)
					and template_ids[building.template.id] != building.template):
				issues.append("Building template has a missing or duplicate stable ID: %s." % building.template.id)
			template_ids[building.template.id] = building.template
			for room in building.template.rooms:
				if room.id.strip_edges().is_empty() or room.floor_level < 0 or not Rect2i(Vector2i.ZERO, building.template.footprint).encloses(room.bounds):
					issues.append("Template %s has an invalid room definition." % building.template.id)
			var wall_ids: Dictionary = {}
			for edge in building.template.wall_edges:
				if edge.id.strip_edges().is_empty() or wall_ids.has(edge.id):
					issues.append("Template %s has a missing or duplicate wall edge ID." % building.template.id)
				wall_ids[edge.id] = true
				if edge.level < 0 or edge.level >= building.template.floor_count or edge.start.distance_to(edge.end) < 0.01:
					issues.append("Template %s has an invalid wall edge %s." % [building.template.id, edge.id])
			for surface in building.template.indoor_floors:
				if surface.id.strip_edges().is_empty() or surface.terrain == null or surface.level < 0 or surface.level >= building.template.floor_count:
					issues.append("Template %s has an invalid indoor floor %s." % [building.template.id, surface.id])
				elif not Rect2i(Vector2i.ZERO, building.template.footprint).encloses(surface.rect):
					issues.append("Template %s indoor floor %s exceeds its footprint." % [building.template.id, surface.id])
			var local_stair_ids: Dictionary = {}
			for stair in building.template.stairs:
				var footprint := Rect2(Vector2.ZERO, Vector2(building.template.footprint))
				if stair.id.is_empty() or local_stair_ids.has(stair.id):
					issues.append("Template %s has missing or duplicate stair ID." % building.template.id)
				local_stair_ids[stair.id] = true
				if stair.from_floor < 0 or stair.to_floor != stair.from_floor + 1 or stair.to_floor >= building.template.floor_count or stair.width <= 0.0 or stair.start.distance_to(stair.end) < 0.1:
					issues.append("Template %s stair %s has invalid levels or geometry." % [building.template.id, stair.id])
				if not footprint.has_point(stair.start) or not footprint.has_point(stair.end):
					issues.append("Template %s stair %s extends outside the house." % [building.template.id, stair.id])
				for opening in stair.opening_cells:
					if not Rect2i(Vector2i.ZERO, building.template.footprint).has_point(opening):
						issues.append("Template %s stair opening exceeds its footprint." % building.template.id)
		if building.effective_floor_count() <= 0 or bounds.size.x <= 0 or bounds.size.y <= 0:
			issues.append("Building %s has invalid bounds or floor count." % building.id)
	var stair_ids: Dictionary = {}
	for stair in map.stairs:
		if stair.id.strip_edges().is_empty() or stair_ids.has(stair.id):
			issues.append("Stair has a missing or duplicate stable ID: %s." % stair.id)
		stair_ids[stair.id] = true
		if not building_ids.has(stair.building_id):
			issues.append("Stair %s references missing building %s." % [stair.id, stair.building_id])
		if stair.from_floor == stair.to_floor or stair.width <= 0.0 or stair.start.distance_to(stair.end) < 0.1:
			issues.append("Stair %s has invalid endpoints, levels or width." % stair.id)
	var road_ids: Dictionary = {}
	for road in map.roads:
		if road.id.strip_edges().is_empty() or road_ids.has(road.id):
			issues.append("Road has a missing or duplicate stable ID: %s." % road.id)
		road_ids[road.id] = true
		if road.terrain == null or (road.centerline.size() < 2 and road.grid_cells.is_empty()) or road.width <= 0.0:
			issues.append("Road %s has missing terrain, width or centerline." % road.id)
		elif not is_equal_approx(road.width, roundf(road.width)):
			issues.append("Road %s width must be a whole number of cells." % road.id)
	var indoor_ids: Dictionary = {}
	for surface in map.indoor_floors:
		if surface.id.strip_edges().is_empty() or indoor_ids.has(surface.id):
			issues.append("Indoor floor has a missing or duplicate stable ID: %s." % surface.id)
		indoor_ids[surface.id] = true
		if surface.terrain == null or surface.level < 0 or surface.rect.size.x <= 0 or surface.rect.size.y <= 0:
			issues.append("Indoor floor %s has invalid terrain, level or bounds." % surface.id)
		elif surface.terrain.category == "water":
			issues.append("Indoor floor %s cannot use water terrain." % surface.id)
	var zone_ids: Dictionary = {}
	for zone in map.zones:
		if zone.id.strip_edges().is_empty() or zone_ids.has(zone.id):
			issues.append("Zone has a missing or duplicate stable ID: %s." % zone.id)
		zone_ids[zone.id] = true
		if zone.rect.size.x <= 0 or zone.rect.size.y <= 0:
			issues.append("Zone %s has invalid bounds." % zone.id)
		for other in map.zones:
			if other == zone:
				continue
			if other.kind == zone.kind and other.level == zone.level and other.priority == zone.priority and other.rect.intersects(zone.rect):
				issues.append("Zones %s and %s overlap at equal priority." % [zone.id, other.id])
	var decoration_ids: Dictionary = {}
	for decoration in map.decorations:
		if decoration.id.strip_edges().is_empty() or decoration_ids.has(decoration.id):
			issues.append("Decoration has a missing or duplicate stable ID: %s." % decoration.id)
		decoration_ids[decoration.id] = true
		if decoration.level < 0 or not _point_in_any_cell(decoration.position, map.cells):
			issues.append("Decoration %s is outside the authored map or has an invalid level." % decoration.id)
	if not _point_in_any_cell(map.player_spawn, map.cells):
		issues.append("Player spawn is outside every authored map cell.")
	if not _point_in_any_cell(map.npc_spawn, map.cells):
		issues.append("NPC spawn is outside every authored map cell.")
	return issues


static func _point_in_any_cell(position: Vector2, cells: Array) -> bool:
	for cell in cells:
		var bounds := Rect2i(cell.cell_coordinate * cell.size, cell.size)
		if bounds.has_point(Vector2i(position.floor())):
			return true
	return false
