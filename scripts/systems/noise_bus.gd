class_name NoiseEventBus
extends Node

## Central event channel. A stimulus intentionally contains no actor reference, so
## hearing never grants knowledge of an emitter's identity or later movement.
signal noise_emitted(stimulus: NoiseStimulus)


func emit_noise(world_position: Vector2, radius: float, category: String, floor_level: int = 0,
		loudness: float = 1.0) -> NoiseStimulus:
	var stimulus := NoiseStimulus.new(world_position, radius, category, floor_level,
		loudness, GameTime.elapsed_game_seconds)
	noise_emitted.emit(stimulus)
	return stimulus
