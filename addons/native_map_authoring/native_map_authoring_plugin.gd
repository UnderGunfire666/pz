@tool
extends EditorPlugin

const MAP_DOCK = preload("res://addons/native_map_authoring/map_authoring_dock.gd")
var dock: Control
var saved_run_args: Variant
var has_run_override := false


func _enter_tree() -> void:
	dock = MAP_DOCK.new()
	dock.undo_redo = get_undo_redo()
	dock.playtest_requested.connect(_playtest_map)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	_restore_run_args()
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()


func _playtest_map(map_path: String) -> void:
	if EditorInterface.is_playing_scene(): return
	saved_run_args = ProjectSettings.get_setting("editor/run/main_run_args", "")
	has_run_override = true
	ProjectSettings.set_setting("editor/run/main_run_args", '-- "--map=%s"' % map_path.replace('"', '\\"'))
	EditorInterface.play_main_scene()
	# The child receives its launch arguments synchronously. Restore immediately
	# so subsequent F5/F6 launches are not redirected to this editor map.
	_restore_run_args.call_deferred()

func _restore_run_args() -> void:
	if not has_run_override: return
	ProjectSettings.set_setting("editor/run/main_run_args", saved_run_args)
	has_run_override = false
