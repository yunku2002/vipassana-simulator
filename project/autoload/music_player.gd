extends Node

const MUSIC_PATH := "res://assets/Vipassana Closing Chanting.mp3"
const _GAP_SEC := 180.0

var _player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	var stream := load(MUSIC_PATH) as AudioStreamMP3
	if stream == null:
		push_warning("Missing music at ", MUSIC_PATH)
		return
	stream.loop = false
	_player.stream = stream
	var gap := Timer.new()
	gap.wait_time = _GAP_SEC
	gap.one_shot = true
	gap.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(gap)
	_player.finished.connect(gap.start)
	gap.timeout.connect(_player.play)
	_player.play()
