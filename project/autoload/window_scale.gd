extends Node

## Design size. A 16:9 window lays out at this size.
const DESIGN_SIZE := Vector2i(1280, 720)
## Narrower than this, the canvas stays this wide and the UI scales down.
const MIN_WIDTH := 880


func _enter_tree() -> void:
	var window := get_window()
	if not window.size_changed.is_connected(_apply):
		window.size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var window := get_window()
	var size := viewport_for(Vector2(window.size))
	if size == Vector2i.ZERO or window.content_scale_size == size:
		return
	window.content_scale_size = size


## Viewport size for a window. Height stays at the design height until the
## width would drop below MIN_WIDTH; only then does the canvas scale down.
static func viewport_for(screen: Vector2) -> Vector2i:
	if screen.x < 1.0 or screen.y < 1.0:
		return Vector2i.ZERO
	var width_at_design_height := screen.x * float(DESIGN_SIZE.y) / screen.y
	if width_at_design_height >= float(MIN_WIDTH):
		return Vector2i(maxi(roundi(width_at_design_height), 1), DESIGN_SIZE.y)
	var height := screen.y * float(MIN_WIDTH) / screen.x
	return Vector2i(MIN_WIDTH, maxi(roundi(height), 1))
