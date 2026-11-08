class_name Vipassana4
extends Vipassana3


func _enter_tree() -> void:
	super._enter_tree()
	_scan.set_auto_resolve(true)
	_scan.set_anicca_stride(3)


func _apply_color_holds() -> void:
	_scan.set_color_holds(default_hold_second, charged_hold_second, color_blend_sec)
