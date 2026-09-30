class_name GameTimeSystem
extends Node

## One complete in-game day takes one real-time hour at normal speed.
## Systems read simulation_scale instead of Engine.time_scale so the UI remains
## responsive while single-player world time is paused or accelerated.
signal speed_changed(mode_name: String, simulation_scale: float)
signal minute_changed(total_game_minutes: int)

enum SpeedMode { PAUSED, NORMAL, FAST, SLEEP }

const GAME_SECONDS_PER_REAL_SECOND := 24.0
const FAST_SCALE := 3.0

var speed_mode: SpeedMode = SpeedMode.NORMAL
var elapsed_game_seconds := 8.0 * 60.0 * 60.0
var last_advanced_game_seconds := 0.0
var _last_announced_minute := -1


func _process(delta: float) -> void:
	last_advanced_game_seconds = delta * GAME_SECONDS_PER_REAL_SECOND * simulation_scale()
	if is_zero_approx(last_advanced_game_seconds):
		return

	elapsed_game_seconds += last_advanced_game_seconds
	var current_minute := int(elapsed_game_seconds / 60.0)
	if current_minute != _last_announced_minute:
		_last_announced_minute = current_minute
		minute_changed.emit(current_minute)


func simulation_scale() -> float:
	match speed_mode:
		SpeedMode.PAUSED:
			return 0.0
		SpeedMode.FAST:
			return FAST_SCALE
		SpeedMode.SLEEP:
			return StatusConfig.SLEEP_TIME_SCALE
		_:
			return 1.0


func toggle_pause() -> void:
	if speed_mode == SpeedMode.PAUSED:
		set_speed(SpeedMode.NORMAL)
	else:
		set_speed(SpeedMode.PAUSED)


func set_speed(next_mode: SpeedMode) -> void:
	speed_mode = next_mode
	speed_changed.emit(speed_name(), simulation_scale())


func speed_name() -> String:
	match speed_mode:
		SpeedMode.PAUSED:
			return "Paused"
		SpeedMode.FAST:
			return "Fast-forward x%d" % int(FAST_SCALE)
		SpeedMode.SLEEP:
			return "Sleeping x%d" % int(StatusConfig.SLEEP_TIME_SCALE)
		_:
			return "Normal"


func formatted_time() -> String:
	var day_seconds := fmod(elapsed_game_seconds, 24.0 * 60.0 * 60.0)
	var hours := int(day_seconds / 3600.0)
	var minutes := int(day_seconds / 60.0) % 60
	return "Day %d  %02d:%02d" % [int(elapsed_game_seconds / 86400.0) + 1, hours, minutes]
