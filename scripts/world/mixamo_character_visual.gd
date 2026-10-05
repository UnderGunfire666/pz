class_name MixamoCharacterVisual
extends Node3D

## Static relaxed pose until animation assets are supplied. Calibration is baked
## alongside authoritative body volumes by tools/bake_character_bodies.gd.
var skeleton: Skeleton3D
var meshes: Array[MeshInstance3D] = []
# Full-body player used outside the ready stance.
var animation_player: AnimationPlayer
# Lower-body layer used only while the ready stance is active.
var lower_animation_player: AnimationPlayer
var upper_animation_player: AnimationPlayer
var _flashing := false
var _bone_indices: Dictionary = {}
var _profile: CharacterBodyProfile
var _animation_name := ""
var _upper_animation_name := ""
var _split_human_layers := false
var _model_root: Node3D
var _region_flash_meshes: Dictionary = {}
static var _scenes: Dictionary = {}
static var _flash: StandardMaterial3D
static var _animation_libraries: Dictionary = {}

const PLAYER_ANIMATIONS := {
	"idle": "res://assets/characters/mixamo/Human/idle.fbx",
	"walk": "res://assets/characters/mixamo/Human/walking.fbx",
	"run": "res://assets/characters/mixamo/Human/running.fbx",
	"back_walk": "res://assets/characters/mixamo/Human/Walking Backwards.fbx",
	"back_run": "res://assets/characters/mixamo/Human/Run Backward.fbx",
	"strafe_left": "res://assets/characters/mixamo/Human/left strafe walking.fbx",
	"strafe_right": "res://assets/characters/mixamo/Human/right strafe walking.fbx",
	"jump": "res://assets/characters/mixamo/Human/jump.fbx",
	"attack": "res://assets/characters/mixamo/Human/Attack Downward.fbx",
	"armed_idle": "res://assets/characters/mixamo/Human/2hand Idle.fbx",
	"armed_run": "res://assets/characters/mixamo/Human/Run With Sword.fbx",
	"equip": "res://assets/characters/mixamo/Human/Unarmed Equip Underarm.fbx",
}
const ZOMBIE_ANIMATIONS := {
	"idle": "res://assets/characters/mixamo/Zombie/zombie idle.fbx",
	"walk": "res://assets/characters/mixamo/Zombie/zombie walk.fbx",
	"run": "res://assets/characters/mixamo/Zombie/zombie run.fbx",
	"attack": "res://assets/characters/mixamo/Zombie/zombie attack.fbx",
	"death": "res://assets/characters/mixamo/Zombie/zombie death.fbx",
}
const LOOPING_ANIMATIONS := ["idle", "walk", "run", "back_walk", "back_run", "strafe_left", "strafe_right", "armed_idle", "armed_run"]

func setup(profile: CharacterBodyProfile, split_human_layers: bool = false) -> void:
	_profile = profile
	_split_human_layers = split_human_layers and profile.model_path.contains("/Human/")
	if not _scenes.has(profile.model_path):
		_scenes[profile.model_path] = load(profile.model_path)
	var model := (_scenes[profile.model_path] as PackedScene).instantiate() as Node3D
	_model_root = model
	model.name = "ImportedModel"
	model.rotation.y = PI
	model.scale = Vector3.ONE * profile.model_scale
	model.position = profile.model_offset
	add_child(model)
	skeleton = find_skeleton(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	# Conservative bound includes the posed arms, independent of rest-pose AABB.
	for mesh in meshes: mesh.extra_cull_margin = 0.5
	_setup_animations()


func _setup_animations() -> void:
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	animation_player.root_node = NodePath("..")
	animation_player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	var key := _profile.model_path
	if not _animation_libraries.has(key):
		var library := AnimationLibrary.new()
		var source_paths: Dictionary = PLAYER_ANIMATIONS if key.contains("/Human/") else ZOMBIE_ANIMATIONS
		for animation_name: String in source_paths:
			var clip := _load_clip(source_paths[animation_name])
			if clip == null: continue
			clip.loop_mode = Animation.LOOP_LINEAR if animation_name in LOOPING_ANIMATIONS else Animation.LOOP_NONE
			library.add_animation(animation_name, _retarget_clip(clip))
		_animation_libraries[key] = library
	animation_player.add_animation_library("", _animation_libraries[key])
	add_child(animation_player)
	if _split_human_layers:
		var source_library := animation_player.get_animation_library("")
		lower_animation_player = AnimationPlayer.new()
		lower_animation_player.name = "LowerBodyAnimationPlayer"
		lower_animation_player.root_node = NodePath("..")
		lower_animation_player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
		lower_animation_player.add_animation_library("", _layer_library(source_library, false))
		add_child(lower_animation_player)
		upper_animation_player = AnimationPlayer.new()
		upper_animation_player.name = "UpperBodyAnimationPlayer"
		upper_animation_player.root_node = NodePath("..")
		upper_animation_player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
		upper_animation_player.add_animation_library("", _layer_library(source_library, true))
		add_child(upper_animation_player)
	play_animation("idle", 0.0, 1.0)


func _load_clip(path: String) -> Animation:
	var scene := load(path) as PackedScene
	if scene == null: return null
	var source := scene.instantiate()
	var source_player: AnimationPlayer = null
	for node in source.find_children("*", "AnimationPlayer", true, false):
		source_player = node as AnimationPlayer
		break
	var clip: Animation = source_player.get_animation("mixamo_com") if source_player != null else null
	source.free()
	return clip.duplicate(true) if clip != null else null


func _retarget_clip(source: Animation) -> Animation:
	var result := source.duplicate(true) as Animation
	var skeleton_path := get_path_to(skeleton)
	for track in result.get_track_count():
		var source_path := String(result.track_get_path(track))
		var colon := source_path.find(":")
		if colon < 0:
			result.track_set_enabled(track, false)
			continue
		var source_bone := source_path.substr(colon + 1)
		var divider := source_bone.find("_")
		var suffix := source_bone.substr(divider + 1) if divider >= 0 else source_bone
		var target_index := _bone(suffix)
		if target_index < 0:
			result.track_set_enabled(track, false)
			continue
		result.track_set_path(track, NodePath("%s:%s" % [skeleton_path, skeleton.get_bone_name(target_index)]))
		# Movement uses authoritative map coordinates. Ignore downloaded root motion.
		if suffix == "Hips" and result.track_get_type(track) == Animation.TYPE_POSITION_3D:
			result.track_set_enabled(track, false)
	return result


func _layer_library(source: AnimationLibrary, upper: bool) -> AnimationLibrary:
	var result := AnimationLibrary.new()
	for name: String in source.get_animation_list():
		var clip := source.get_animation(name).duplicate(true) as Animation
		for track in clip.get_track_count():
			var path := String(clip.track_get_path(track))
			var colon := path.find(":")
			if colon < 0: continue
			var bone_name := path.substr(colon + 1)
			var lower := bone_name.contains("Hips") or bone_name.contains("UpLeg") or bone_name.contains("Leg") or bone_name.contains("Foot") or bone_name.contains("ToeBase")
			if lower == upper: clip.track_set_enabled(track, false)
		result.add_animation(name, clip)
	return result


func play_animation(next: String, blend: float = 0.12, speed: float = 1.0, restart: bool = false) -> void:
	_play_on(animation_player, next, blend, speed, restart, false)


func advance_animation(delta: float, next: String, speed: float = 1.0) -> void:
	# The full clip owns every bone whenever the character is not preparing.
	# Stopping both layer players resets their track influence before playback.
	if lower_animation_player != null and lower_animation_player.is_playing(): lower_animation_player.stop()
	if upper_animation_player != null and upper_animation_player.is_playing(): upper_animation_player.stop()
	play_animation(next, 0.12, speed)
	if animation_player != null: animation_player.advance(delta)


func advance_split_animation(delta: float, lower: String, lower_speed: float, upper: String, upper_restart: bool = false, upper_speed: float = 1.0) -> void:
	# The two partial clips own the pose only during the right-click ready stance.
	if animation_player != null and animation_player.is_playing(): animation_player.stop()
	_play_on(lower_animation_player, lower, 0.12, lower_speed, false, false)
	_play_on(upper_animation_player, upper, 0.08, upper_speed, upper_restart, true)
	if lower_animation_player != null: lower_animation_player.advance(delta)
	if upper_animation_player != null: upper_animation_player.advance(delta)


func _play_on(player: AnimationPlayer, next: String, blend: float, speed: float, restart: bool, upper: bool) -> void:
	if player == null or not player.has_animation(next): return
	var current := _upper_animation_name if upper else _animation_name
	if current != next or restart or not player.is_playing():
		if restart: player.stop()
		player.play(next, blend, speed)
		if upper: _upper_animation_name = next
		else: _animation_name = next
	else:
		player.speed_scale = speed

func set_damage_flash(enabled: bool) -> void:
	if _flashing == enabled: return
	_flashing = enabled
	if _flash == null:
		_flash = StandardMaterial3D.new()
		_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash.albedo_color = Color(1.0, 0.15, 0.08, 0.35)
		_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mesh in meshes: mesh.material_overlay = _flash if enabled else null


func set_region_flash(region: String, seconds: float) -> void:
	if region.is_empty() or not _profile.regions.has(region):
		for marker in _region_flash_meshes.values(): marker.visible = false
		return
	if not _region_flash_meshes.has(region):
		var marker := MeshInstance3D.new()
		marker.name = "%sHitFlash" % region.replace(" ", "")
		var bounds: AABB = _profile.regions[region]
		var box := BoxMesh.new()
		box.size = bounds.size + Vector3.ONE * 0.018
		marker.mesh = box
		marker.position = bounds.get_center()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.02, 0.02, 0.72)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		marker.material_override = material
		_model_root.add_child(marker)
		_region_flash_meshes[region] = marker
	for name in _region_flash_meshes:
		_region_flash_meshes[name].visible = name == region and seconds > 0.0

func _bone(suffix: String) -> int:
	if not _bone_indices.has(suffix): _bone_indices[suffix] = bone(skeleton, suffix)
	return int(_bone_indices[suffix])

static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found := find_skeleton(child)
		if found != null: return found
	return null

static func bone(skel: Skeleton3D, suffix: String) -> int:
	for index in skel.get_bone_count():
		if skel.get_bone_name(index).ends_with("_" + suffix) or skel.get_bone_name(index).ends_with(":" + suffix):
			return index
	return -1


