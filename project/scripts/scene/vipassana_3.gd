class_name Vipassana3
extends Vipassana2

@export_group("Symmetry")
## Extra gap allowed before the two focus circles count as apart.
@export var focus_overlap_margin: float

@export_group("Equanimity")
## Chance that a name cluster is subtle (green).
@export_range(0.0, 1.0, 0.05) var subtle_chance: float


func _enter_tree() -> void:
	super._enter_tree()
	_scan.set_symmetric(true, focus_overlap_margin)
	_scan.set_subtle_chance(subtle_chance)


func _apply_color_holds() -> void:
	# The single pass keeps Vipassana-2's second-pass timing.
	_scan.set_color_holds(charged_hold_first, default_hold_first, color_blend_sec)


func _pass_count() -> int:
	return 1
