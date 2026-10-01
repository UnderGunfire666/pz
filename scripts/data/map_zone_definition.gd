@tool
class_name MapZoneDefinition
extends Resource

## Rectangular grid overlay. Runtime systems consume only the kinds they own.
@export var id := ""
@export_enum("zombie_pressure", "loot", "migration") var kind := "zombie_pressure"
@export var level := 0
@export var rect := Rect2i()
@export_range(0, 100, 1) var priority := 0
@export_range(0.0, 1.0, 0.01) var pressure := 0.1
