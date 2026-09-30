class_name NoiseStimulus
extends RefCounted

var world_position: Vector2
var loudness: float
var audible_range: float
var floor_level: int
var event_type: String
var world_time: float


func _init(position := Vector2.ZERO, range := 0.0, type := "", floor := 0,
		strength := 1.0, timestamp := 0.0) -> void:
	world_position = position
	audible_range = maxf(0.0, range)
	event_type = type
	floor_level = floor
	loudness = maxf(0.0, strength)
	world_time = timestamp
