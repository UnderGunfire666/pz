class_name NoiseStimulus
extends RefCounted

var world_position: Vector2
var loudness: float
var audible_range: float
var floor_level: int
var event_type: String
var world_time: float
# Captured at emission, independent of the emitter's later movement or lifetime.
# INF marks legacy planar events; the listener resolves their floor height.
var spatial_position := Vector3.INF
var source_stair_id := ""
var emitter_instance_id := 0
var map_instance_id := 0


func _init(position := Vector2.ZERO, range := 0.0, type := "", floor := 0,
		strength := 1.0, timestamp := 0.0) -> void:
	world_position = position
	audible_range = maxf(0.0, range)
	event_type = type
	floor_level = floor
	loudness = maxf(0.0, strength)
	world_time = timestamp
