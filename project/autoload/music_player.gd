extends Node

const MUSIC_PATH := "res://assets/Vipassana Closing Chanting.mp3"

var _player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Master"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	var stream := load(MUSIC_PATH) as AudioStreamMP3
	if stream == null:
		push_warning("Missing music at ", MUSIC_PATH)
		return
	stream.loop = true
	_player.stream = stream
	_player.play()
