class_name NoiseEventBus
extends Node

## Central event channel. A stimulus intentionally contains no actor reference, so
## hearing never grants knowledge of an emitter's identity or later movement.
signal noise_emitted(stimulus: NoiseStimulus)

var debug_enabled := false
var debug_samples: Array[Dictionary] = []

# Base range is expressed in world units. The propagation sampler subtracts
# distance and structural loss from it, giving each listener a smooth linear
# falloff instead of a binary radius check.
const ACTION_PROFILES := {
	"player_walk": {"range": 8.0, "loudness": 1.0, "event": "footsteps", "height": 0.12},
	"player_sprint": {"range": 18.0, "loudness": 1.0, "event": "sprinting", "height": 0.12},
	"player_melee_swing": {"range": 12.0, "loudness": 1.0, "event": "melee strike", "height": 1.05},
	"player_melee_hit": {"range": 20.0, "loudness": 1.0, "event": "melee impact", "height": 1.05},
	"player_search": {"range": 5.0, "loudness": 1.0, "event": "searching", "height": 1.05},
	"door": {"range": 6.0, "loudness": 1.0, "event": "door"},
	"window": {"range": 8.0, "loudness": 1.0, "event": "window"},
	"zombie_attack": {"range": 9.0, "loudness": 1.0, "event": "struggle", "height": 1.05},
	"npc_attack": {"range": 8.0, "loudness": 1.0, "event": "struggle", "height": 1.05},
}


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


func emit_action_noise(actor: Node, action: String) -> NoiseStimulus:
	var profile: Dictionary = ACTION_PROFILES.get(action, {})
	if profile.is_empty():
		push_warning("Unknown sound action: %s" % action)
		return null
	return emit_actor_noise(actor, float(profile["range"]), String(profile["event"]),
		float(profile["loudness"]), float(profile.get("height", ActorPerception.CHEST_HEIGHT)))


func emit_action_noise_at(map: WorldMap, position: Vector3, action: String,
		floor_level: int, emitter_id: int = 0) -> NoiseStimulus:
	var profile: Dictionary = ACTION_PROFILES.get(action, {})
	if profile.is_empty():
		push_warning("Unknown sound action: %s" % action)
		return null
	return emit_spatial_noise(map, position, float(profile["range"]), String(profile["event"]),
		floor_level, float(profile["loudness"]), "", emitter_id)


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
