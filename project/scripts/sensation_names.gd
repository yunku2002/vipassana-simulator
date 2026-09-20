class_name SensationNames

const _GROSS_KEY := "SENSATIONS_GROSS"
const _SUBTLE_KEY := "SENSATIONS_SUBTLE"


static func random_label() -> String:
	var gross := _lines_of(_GROSS_KEY)
	var subtle := _lines_of(_SUBTLE_KEY)
	if gross.is_empty() and subtle.is_empty():
		return "!"
	var pool := gross
	if gross.is_empty():
		pool = subtle
	elif not subtle.is_empty() and randf() >= 0.5:
		pool = subtle
	return pool[randi() % pool.size()]


static func _lines_of(key: String) -> PackedStringArray:
	var raw := String(TranslationServer.translate(key))
	var out := PackedStringArray()
	if raw.is_empty() or raw == key:
		return out
	for line in raw.split("\n", false):
		var text := line.strip_edges()
		if not text.is_empty():
			out.append(text)
	return out
