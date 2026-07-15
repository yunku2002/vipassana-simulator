extends Node

const KEY := "THOUGHT_SUBJECTS"
const BOOST_PREFIX := "!"
## Fraction of picks taken from entries marked with [constant BOOST_PREFIX].
const BOOST_SHARE := 0.3

var _cache_locale: String = ""
var _subjects: PackedStringArray = PackedStringArray()
var _boosted_indices: PackedInt32Array = PackedInt32Array()
var _normal_indices: PackedInt32Array = PackedInt32Array()


func random_index() -> int:
	_ensure_cache()
	if _subjects.is_empty():
		return -1
	if _boosted_indices.is_empty():
		return _normal_indices[randi() % _normal_indices.size()]
	if _normal_indices.is_empty():
		return _boosted_indices[randi() % _boosted_indices.size()]
	if randf() < BOOST_SHARE:
		return _boosted_indices[randi() % _boosted_indices.size()]
	return _normal_indices[randi() % _normal_indices.size()]


func text_at(index: int) -> String:
	_ensure_cache()
	if index < 0 or index >= _subjects.size():
		return ""
	return _subjects[index]


func random_text() -> String:
	return text_at(random_index())


func get_subjects() -> PackedStringArray:
	_ensure_cache()
	return _subjects.duplicate()


func _ensure_cache() -> void:
	var locale := TranslationServer.get_locale()
	if locale == _cache_locale and not _subjects.is_empty():
		return
	_cache_locale = locale
	_subjects = PackedStringArray()
	_boosted_indices = PackedInt32Array()
	_normal_indices = PackedInt32Array()
	var raw := TranslationServer.translate(KEY)
	if raw.is_empty() or raw == KEY:
		return
	for line in raw.split("\n", false):
		var index := _subjects.size()
		if line.begins_with(BOOST_PREFIX):
			_subjects.append(line.substr(BOOST_PREFIX.length()))
			_boosted_indices.append(index)
		else:
			_subjects.append(line)
			_normal_indices.append(index)
