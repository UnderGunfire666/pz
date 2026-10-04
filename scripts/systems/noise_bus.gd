class_name NoiseEventBus
extends Node

## Central event channel. A stimulus intentionally contains no actor reference, so
## hearing never grants knowledge of an emitter's identity or later movement.
signal noise_emitted(stimulus: NoiseStimulus)

var debug_enabled := false
var debug_samples: Array[Dictionary] = []


func _ready() -> void:
	debug_enabled = "--debug-hearing" in OS.get_cmdline_user_args()


func record_hearing(listener: Node, observation: Dictionary) -> void:
	if not debug_enabled: return
	var record := observation.duplicate(true)
	record["listener_id"] = listener.get_instance_id()
	debug_samples.append(record)
	if debug_samples.size() > 64: debug_samples.pop_front()
	print("[Hearing] %s type=%s radius=%.2f distance=%.2f loss=%.2f received=%.2f clue=%s floor=%d uncertainty=%.2f obstacles=%s" % [
		listener.name, observation["event_type"], observation["radius"], observation["distance"],
		observation["obstacle_loss"], observation["strength"], observation["position"],
		observation["floor"], observation["uncertainty"], observation["obstacles"]])


func emit_noise(world_position: Vector2, radius: float, category: String, floor_level: int = 0,
		loudness: float = 1.0) -> NoiseStimulus:
	var stimulus := NoiseStimulus.new(world_position, radius, category, floor_level,
		loudness, GameTime.elapsed_game_seconds)
	noise_emitted.emit(stimulus)
	return stimulus


func emit_actor_noise(actor: Node, radius: float, category: String,
		loudness: float = 1.0, height: float = ActorPerception.CHEST_HEIGHT) -> NoiseStimulus:
	var map: WorldMap = actor.world_map
	return emit_spatial_noise(map, ActorPerception.point(map, actor.logical_position,
		actor.floor_level, actor.stair_id, height), radius, category, actor.floor_level,
		loudness, actor.stair_id, actor.get_instance_id())


func emit_spatial_noise(map: WorldMap, position: Vector3, radius: float, category: String,
		floor_level: int = 0, loudness: float = 1.0, stair_id: String = "",
		emitter_id: int = 0) -> NoiseStimulus:
	var stimulus := NoiseStimulus.new(Vector2(position.x, position.z), radius, category,
		floor_level, loudness, GameTime.elapsed_game_seconds)
	stimulus.spatial_position = position
	stimulus.source_stair_id = stair_id
	stimulus.emitter_instance_id = emitter_id
	stimulus.map_instance_id = map.get_instance_id()
	noise_emitted.emit(stimulus)
	return stimulus
