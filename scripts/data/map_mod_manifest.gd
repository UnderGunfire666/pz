@tool
class_name MapModManifest
extends Resource

## Data-only package descriptor. Maps remain immutable static content and
## runtime/save data is intentionally excluded from this format.
@export var id := ""
@export var display_name := ""
@export var version := "0.1.0"
@export var required_game_version := "0.1"
@export var dependencies := PackedStringArray()
@export var map_paths := PackedStringArray()
