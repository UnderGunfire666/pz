class_name PlayerViewRig
extends Node3D

## Owns presentation pose only. A future third-person mode can supply a shoulder
## offset and collision-resolved position here without changing movement or LOS.
enum Mode { FIRST_PERSON }
const EYE_HEIGHT := 1.62
const LOOK_SENSITIVITY := 0.0025
const PITCH_LIMIT := deg_to_rad(85.0)
const VIEW_DISTANCE := 64.0
var mode := Mode.FIRST_PERSON
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


func update_pose(feet: Vector3) -> void:
	# No height smoothing: the eye must remain above the feet on stairs and loads.
	global_position = feet + Vector3.UP * EYE_HEIGHT
	rotation = Vector3(pitch, yaw, 0.0)


func shows_local_body() -> bool:
	return mode != Mode.FIRST_PERSON
