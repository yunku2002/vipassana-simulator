class_name Vipassana2
extends Vipassana1

@export_group("Equanimity")
## First pass: time fully in the default color. Shorter than the charged hold.
@export var default_hold_first: float = 0.5
## First pass: time fully in red (gross) or green (subtle).
@export var charged_hold_first: float = 1.4
## Interpolation between the two holds. A press during the blend is rejected.
@export var color_blend_sec: float = 0.3
@export var reject_outline_sec: float = 0.5


func _enter_tree() -> void:
	super._enter_tree()
	_apply_fast_pace()
	var scan := $Margin/Body/Scan as BodyScan
	scan.set_equanimity(true)
	scan.set_reject_outline_sec(reject_outline_sec)
	_apply_color_holds(scan)


func _apply_locks() -> void:
	super._apply_locks()
	var thought := _has_revealed_thought()
	var scanning := _phase == _Phase.SCAN and not is_gameplay_blocked()
	_scan.set_press_enabled(scanning and not thought)


func _waits_for_sensations() -> bool:
	return false


func _dismiss_before_reset() -> void:
	_scan.dismiss_unresolved()


func _configure_next_pass() -> void:
	_apply_color_holds(_scan)


func _apply_color_holds(scan: BodyScan) -> void:
	if _pass == 0:
		scan.set_color_holds(default_hold_first, charged_hold_first, color_blend_sec)
	else:
		scan.set_color_holds(charged_hold_first, default_hold_first, color_blend_sec)
