class_name Vipassana3
extends Vipassana2

@export_group("Symmetry")
## Extra gap allowed before the two focus circles count as apart.
@export var focus_overlap_margin: float

@export_group("Equanimity")
## Second pass: time fully in the default color. Longer than the first pass.
@export var default_hold_second: float
## Second pass: time fully in red or green. Shorter than the first pass.
@export var charged_hold_second: float
## Chance that a name cluster is subtle (green).
@export_range(0.0, 1.0, 0.05) var subtle_chance: float


func _enter_tree() -> void:
	super._enter_tree()
	_scan.set_symmetric(true, focus_overlap_margin)
	_scan.set_subtle_chance(subtle_chance)


func _apply_color_holds() -> void:
	if _pass == 0:
		# Same timing as Vipassana-2's second pass.
		_scan.set_color_holds(charged_hold_first, default_hold_first, color_blend_sec)
	else:
		_scan.set_color_holds(default_hold_second, charged_hold_second, color_blend_sec)
