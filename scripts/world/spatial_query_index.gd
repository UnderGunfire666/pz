extends RefCounted

## Conservative, floor-separated broad phase. Exact collision/LOS rules remain
## in WorldMap. IDs preserve insertion order and deduplicate multi-cell parts.
const CELL_SIZE := 4.0
const EDGE_PADDING := 0.00001
var _values: Dictionary = {}
var _cells: Dictionary = {}


func clear() -> void:
	_values.clear()
	_cells.clear()


func insert(level: int, bounds: Rect2, value: Variant) -> void:
	if not _values.has(level): _values[level] = []
	var values: Array = _values[level]
	var id := values.size()
	values.append(value)
	var rect := bounds.abs().grow(EDGE_PADDING)
	var start := Vector2i((rect.position / CELL_SIZE).floor())
	var end := Vector2i((rect.end / CELL_SIZE).floor())
	for y in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			var key := Vector3i(x, y, level)
			if not _cells.has(key): _cells[key] = []
			_cells[key].append(id)


func all_on_floor(level: int) -> Array:
	return _values.get(level, [])


func query(level: int, bounds: Rect2) -> Array:
	var values: Array = _values.get(level, [])
	if values.is_empty(): return []
	var rect := bounds.abs().grow(EDGE_PADDING)
	var start := Vector2i((rect.position / CELL_SIZE).floor())
	var end := Vector2i((rect.end / CELL_SIZE).floor())
	# A long diagonal must not traverse a city-sized rectangle of empty bins.
	if (end.x - start.x + 1) * (end.y - start.y + 1) > values.size():
		return values
	var found: Dictionary = {}
	for y in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			for id: int in _cells.get(Vector3i(x, y, level), []):
				found[id] = true
	var ids: Array = found.keys()
	ids.sort()
	var result: Array = []
	for id: int in ids: result.append(values[id])
	return result
