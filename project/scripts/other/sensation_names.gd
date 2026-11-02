class_name SensationNames

const _GROSS_KEY := "SENSATIONS_GROSS"
const _SUBTLE_KEY := "SENSATIONS_SUBTLE"


static func random_label(subtle_chance: float) -> String:
	return label_at(random_pick(subtle_chance))


## x is 0 for a gross name and 1 for a subtle name. y is the line index.
static func random_pick(subtle_chance: float) -> Vector2i:
	var gross := _lines_of(_GROSS_KEY)
	var subtle := _lines_of(_SUBTLE_KEY)
	if gross.is_empty() and subtle.is_empty():
		return Vector2i(-1, -1)
	var use_subtle := false
	if gross.is_empty():
		use_subtle = true
	elif not subtle.is_empty() and randf() < clampf(subtle_chance, 0.0, 1.0):
		use_subtle = true
	var pool := subtle if use_subtle else gross
	return Vector2i(1 if use_subtle else 0, randi() % pool.size())


static func label_at(pick: Vector2i) -> String:
	if pick.x < 0:
		return "!"
	var lines := _lines_of(_SUBTLE_KEY if pick.x == 1 else _GROSS_KEY)
	if lines.is_empty():
		return "!"
	return lines[posmod(pick.y, lines.size())]


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
