class_name CombatFeedback
extends Node

## Presentation-only impact feedback. Combat results remain in the actor systems.
var _impact_player: AudioStreamPlayer
var _impact_stream: AudioStreamWAV


func _ready() -> void:
	_ensure_audio()


func play_bat_impact() -> void:
	_ensure_audio()
	if _impact_player == null:
		return
	_impact_player.stop()
	_impact_player.play()


func _ensure_audio() -> void:
	if _impact_player != null:
		return
	_impact_stream = _build_bat_impact_stream()
	_impact_player = AudioStreamPlayer.new()
	_impact_player.name = "BatImpactAudio"
	_impact_player.stream = _impact_stream
	_impact_player.volume_db = -8.0
	add_child(_impact_player)


func _build_bat_impact_stream() -> AudioStreamWAV:
	# A short generated wooden/body impact keeps the feedback usable without
	# requiring an external placeholder asset. Replace this stream with authored
	# weapon/material sounds when those assets are available.
	const MIX_RATE := 22050
	const DURATION := 0.085
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	var data := PackedByteArray()
	var frame_count := int(MIX_RATE * DURATION)
	for frame in frame_count:
		var time := float(frame) / MIX_RATE
		var envelope := pow(1.0 - time / DURATION, 2.4)
		var thud := sin(TAU * (175.0 - time * 720.0) * time)
		var crack := sin(float(frame) * 19.73) * (1.0 - time / DURATION)
		var sample := int(clampf((thud * 0.72 + crack * 0.28) * envelope, -1.0, 1.0) * 32767.0)
		data.append(sample & 0xff)
		data.append((sample >> 8) & 0xff)
	stream.data = data
	return stream
