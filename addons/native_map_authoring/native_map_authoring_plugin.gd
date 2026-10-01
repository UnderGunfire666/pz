@tool
extends EditorPlugin

const MAP_DOCK = preload("res://addons/native_map_authoring/map_authoring_dock.gd")
var dock: Control


func _enter_tree() -> void:
	dock = MAP_DOCK.new()
	dock.undo_redo = get_undo_redo()
	dock.playtest_requested.connect(_playtest_map)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()


func _playtest_map() -> void:
	EditorInterface.play_main_scene()
