extends Anapana3


func _thought_scale() -> float:
	return 1.2


func _success_burst_text() -> String:
	return SensationNames.random_label()
