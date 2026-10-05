class_name PlayerViewRig
extends Node3D

## Owns presentation pose only. Camera placement never changes movement, LOS,
## targeting, or any actor simulation.
enum Mode { FIRST_PERSON, THIRD_PERSON }
const EYE_HEIGHT := 1.62
const LOOK_SENSITIVITY := 0.0025
const PITCH_LIMIT := deg_to_rad(85.0)
const VIEW_DISTANCE := 64.0
const THIRD_PERSON_DISTANCE := 3.6
const THIRD_PERSON_SHOULDER := Vector3(0.58, 0.16, THIRD_PERSON_DISTANCE)
const CAMERA_COLLISION_STEPS := 10
var mode := Mode.THIRD_PERSON
var yaw := 0.0
var pitch := 0.0
var camera: Camera3D


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = VIEW_DISTANCE
	add_child(camera)


func look_delta(relative: Vector2) -> void:
	yaw = wrapf(yaw - relative.x * LOOK_SENSITIVITY, -PI, PI)
	pitch = clampf(pitch - relative.y * LOOK_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)


func align_to_facing(facing: Vector2) -> void:
	if facing.length_squared() > 0.0001:
		yaw = atan2(-facing.x, -facing.y)
	pitch = 0.0


func facing_direction() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


func movement_direction(input: Vector2) -> Vector2:
	return Vector2(cos(yaw), -sin(yaw)) * input.x - facing_direction() * input.y


func update_pose(feet: Vector3, world_map: WorldMap = null) -> void:
	# The rig remains at the authoritative eye on stairs and after loads. Only the
	# rendered camera moves behind it in third person.
	global_position = feet + Vector3.UP * EYE_HEIGHT
	rotation = Vector3(pitch, yaw, 0.0)
	if mode == Mode.FIRST_PERSON:
		camera.position = Vector3.ZERO
		return
	var desired := THIRD_PERSON_SHOULDER
	if world_map != null:
		desired *= _clear_camera_fraction(world_map, global_position, global_transform * desired)
	camera.position = desired


func _clear_camera_fraction(world_map: WorldMap, pivot: Vector3, desired: Vector3) -> float:
	if world_map.has_spatial_line_of_sight(pivot, desired): return 1.0
	var low := 0.04
	var high := 1.0
	for step in CAMERA_COLLISION_STEPS:
		var middle := (low + high) * 0.5
		if world_map.has_spatial_line_of_sight(pivot, pivot.lerp(desired, middle)):
			low = middle
		else:
			high = middle
	return low


func shows_local_body() -> bool:
	return mode == Mode.THIRD_PERSON
