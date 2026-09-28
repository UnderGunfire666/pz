class_name NoiseEventBus
extends Node

## Central event channel so actors react to sounds without knowing their source.
## Occlusion is intentionally basic in the MVP and supplied by WorldMap.
signal noise_emitted(world_position: Vector2, radius: float, category: String)


func emit_noise(world_position: Vector2, radius: float, category: String) -> void:
	noise_emitted.emit(world_position, radius, category)
