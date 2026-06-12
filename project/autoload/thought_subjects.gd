extends Node

const KEY := "THOUGHT_SUBJECTS"


func random_text() -> String:
	var subjects := get_subjects()
	if subjects.is_empty():
		return ""
	return subjects[randi() % subjects.size()]


func get_subjects() -> PackedStringArray:
	var raw := TranslationServer.translate(KEY)
	if raw.is_empty() or raw == KEY:
		return PackedStringArray()
	return PackedStringArray(raw.split("\n", false))
