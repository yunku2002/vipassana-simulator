class_name Vipassana2
extends Vipassana1

@export_group("Equanimity")
## First pass: time fully in the default color. Shorter than the charged hold.
@export var default_hold_first: float
## First pass: time fully in red (gross) or green (subtle).
@export var charged_hold_first: float
## Interpolation between the two holds. A press during the blend is rejected.
@export var color_blend_sec: float
@export var reject_outline_sec: float


func _enter_tree() -> void:
	super._enter_tree()
	_apply_fast_pace()
	_scan.set_equanimity(true)
	_scan.set_reject_outline_sec(reject_outline_sec)
	_apply_color_holds()


func _waits_for_sensations() -> bool:
	return false


func _dismiss_before_reset() -> void:
	_scan.dismiss_unresolved()


func _configure_next_pass() -> void:
	_apply_color_holds()


func _apply_color_holds() -> void:
	if _pass == 0:
		_scan.set_color_holds(default_hold_first, charged_hold_first, color_blend_sec)
	else:
		_scan.set_color_holds(charged_hold_first, default_hold_first, color_blend_sec)
