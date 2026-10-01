@tool
class_name MapHeatPaint
extends Resource

## A rectangular authored override of the spawn-distribution heatmap.  Heat is
## stored separately from terrain so changing a base terrain never silently
## changes a building or road's intended spawn distribution.
@export var id := ""
@export var rect := Rect2i()
@export_range(0.0, 1.0, 0.01) var pressure := 0.1
