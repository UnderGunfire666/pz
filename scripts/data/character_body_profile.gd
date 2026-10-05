class_name CharacterBodyProfile
extends Resource

## Baked in actor space: metres, feet at zero, forward -Z. No render dependency.
@export var model_path: String
@export var model_scale := 1.0
@export var model_offset := Vector3.ZERO
@export var regions: Dictionary = {}
@export var joints: Dictionary = {}

