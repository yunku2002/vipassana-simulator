extends Node

## Ordered stage list: title key prefix and scene path.
const STAGES: Array[Dictionary] = [
	{"prefix": "STAGE_ANAPANA_1", "scene": "res://scenes/anapana_1.tscn"},
	{"prefix": "STAGE_ANAPANA_2", "scene": "res://scenes/anapana_2.tscn"},
	{"prefix": "STAGE_ANAPANA_3", "scene": "res://scenes/anapana_3.tscn"},
	{"prefix": "STAGE_ANAPANA_4", "scene": "res://scenes/anapana_4.tscn"},
]


func stage_count() -> int:
	return STAGES.size()


func scene_path(index: int) -> String:
	return STAGES[index]["scene"]


func stage_prefix(index: int) -> String:
	return STAGES[index]["prefix"]


func index_for_scene(path: String) -> int:
	for i in STAGES.size():
		if STAGES[i]["scene"] == path:
			return i
	return -1


func is_final(index: int) -> bool:
	return index >= 0 and index >= STAGES.size() - 1


func has_next_after_cleared(cleared_index: int) -> bool:
	return cleared_index >= 0 and cleared_index < STAGES.size() - 1
