extends Anapana1

@export_group("Thoughts")
@export var thought_goal_count: int
@export var thought_interval_start: float
@export var thought_interval_peak: float
@export var thought_interval_end: float
@export var thought_peak_progress: float
@export var thought_post_goal_interval_min: float
@export var thought_post_goal_interval_max: float
@export var thought_hold_to_clear_sec: float
@export var thought_min_separation: float = 96.0

const _THOUGHT_INACTIVE_GRAY := 0.8
const _THOUGHT_PLACEMENT_ATTEMPTS := 8

@onready var _thought_layer: Control = $Margin/Body/ThoughtLayer

var _thought_timer: float = 0.0
var _thoughts_erased: int = 0
var _thought_bakes_pending: int = 0
var _thought_bubbles: Array[ThoughtBubble] = []
var _holding_panel: ThoughtBubble
var _holding_elapsed: float = 0.0


func _ready() -> void:
	_gauge_value = 100.0
	_gauge_bar.value = 100.0
	_thought_timer = _next_thought_interval()
	ThoughtBubble.prewarm_trail_dots()
	super._ready()


func _on_before_gauge_update(delta: float) -> void:
	_update_thought_spawning(delta)
	_update_thought_hold(delta)
	_update_thought_visuals()
	_sync_breath_button_lock()


func _is_stage_cleared() -> bool:
	return _gauge_value >= 100.0 and _thoughts_erased >= thought_goal_count


func _release_breath_buttons() -> void:
	_btn_in.button_pressed = false
	_btn_out.button_pressed = false


func _sync_breath_button_lock() -> void:
	var blocked := _thought_bubbles.size() > 0
	if blocked:
		_release_breath_buttons()
	_btn_in.disabled = blocked
	_btn_out.disabled = blocked


func _update_thought_spawning(delta: float) -> void:
	_thought_timer -= delta
	if _thought_timer > 0.0:
		return
	if _thought_bakes_pending > 0:
		return
	if _thought_bubbles.size() >= _active_thought_cap():
		return
	_begin_thought_spawn()
	_thought_timer = _next_thought_interval()


func _next_thought_interval() -> float:
	if _thoughts_erased >= thought_goal_count:
		return randf_range(thought_post_goal_interval_min, thought_post_goal_interval_max)
	var p := clampf(float(_thoughts_erased) / maxf(1.0, float(thought_goal_count)), 0.0, 1.0)
	if p < thought_peak_progress:
		var up := p / maxf(thought_peak_progress, 0.001)
		return lerpf(thought_interval_start, thought_interval_peak, up)
	var down := (p - thought_peak_progress) / maxf(1.0 - thought_peak_progress, 0.001)
	return lerpf(thought_interval_peak, thought_interval_end, down)


func _active_thought_cap() -> int:
	return 1 if _thoughts_erased <= 0 else 5


func _begin_thought_spawn() -> void:
	_thought_bakes_pending += 1
	ThoughtBubble.bake_cloud_texture_async(_on_thought_cloud_baked)


func _on_thought_cloud_baked(img: Image) -> void:
	_thought_bakes_pending = maxi(_thought_bakes_pending - 1, 0)
	if not is_inside_tree():
		return
	if _thought_bubbles.size() >= _active_thought_cap():
		return

	var text := ThoughtSubjects.random_text()
	var cloud_tex := ImageTexture.create_from_image(img)
	var bubble := ThoughtBubble.new()
	_thought_layer.add_child(bubble)

	var cloud_top_left := _pick_thought_local_position()
	var anchor_layer := _thought_layer.get_global_transform_with_canvas().affine_inverse() * _breathing.get_head_global_position()
	bubble.configure(text, cloud_top_left, anchor_layer, cloud_tex)
	bubble.gui_input.connect(_on_thought_input.bind(bubble))
	bubble.mouse_exited.connect(_on_thought_mouse_exited.bind(bubble))

	_thought_bubbles.append(bubble)
	_sync_thought_stack_order()
	_sync_breath_button_lock()


func _update_thought_hold(delta: float) -> void:
	if _holding_panel == null:
		return
	if not is_instance_valid(_holding_panel) or _holding_panel != _oldest_thought_panel():
		_clear_thought_hold()
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_clear_thought_hold()
		return
	_holding_elapsed += delta
	if _holding_elapsed >= thought_hold_to_clear_sec:
		_dismiss_thought(_holding_panel)
		_clear_thought_hold()


func _update_thought_visuals() -> void:
	var oldest := _oldest_thought_panel()
	for bubble in _thought_bubbles:
		if bubble == null or not is_instance_valid(bubble):
			continue
		var rgb := 1.0 if bubble == oldest else _THOUGHT_INACTIVE_GRAY
		var target_a := 1.0
		if bubble == _holding_panel and thought_hold_to_clear_sec > 0.001:
			var t := clampf(_holding_elapsed / thought_hold_to_clear_sec, 0.0, 1.0)
			target_a = lerpf(1.0, 0.1, t)
		bubble.modulate = Color(rgb, rgb, rgb, target_a)


func _oldest_thought_panel() -> ThoughtBubble:
	if _thought_bubbles.is_empty():
		return null
	return _thought_bubbles[0]


func _sync_thought_stack_order() -> void:
	var count := _thought_bubbles.size()
	for i in count:
		var bubble := _thought_bubbles[i]
		if bubble == null or not is_instance_valid(bubble):
			continue
		bubble.z_index = count - i
		bubble.mouse_filter = Control.MOUSE_FILTER_STOP if i == 0 else Control.MOUSE_FILTER_IGNORE


func _clear_thought_hold() -> void:
	_holding_panel = null
	_holding_elapsed = 0.0


func _pick_thought_local_position() -> Vector2:
	var bubble_size := ThoughtBubble.CLOUD_SIZE
	var button_zone := _btn_in.get_global_rect().merge(_btn_out.get_global_rect())
	var spread_x := (button_zone.size.x - bubble_size.x) * 0.5
	var spread_y := button_zone.size.y * 0.4
	var center := button_zone.position + button_zone.size * 0.5
	var layer_from_global := _thought_layer.get_global_transform_with_canvas().affine_inverse()
	var max_pos := (_thought_layer.size - bubble_size).max(Vector2.ZERO)
	var best_pos := Vector2.ZERO
	var best_sep := -1.0
	for attempt in _THOUGHT_PLACEMENT_ATTEMPTS:
		var cloud_center_global := Vector2(
			randf_range(center.x - spread_x, center.x + spread_x),
			randf_range(center.y - spread_y, center.y + spread_y)
		)
		var local_pos := layer_from_global * (cloud_center_global - bubble_size * 0.5)
		local_pos = Vector2(
			clampf(local_pos.x, 0.0, max_pos.x),
			clampf(local_pos.y, 0.0, max_pos.y)
		)
		var min_sep := INF
		for bubble in _thought_bubbles:
			if bubble == null or not is_instance_valid(bubble):
				continue
			min_sep = minf(min_sep, local_pos.distance_to(bubble.position))
		if min_sep >= thought_min_separation:
			return local_pos
		if min_sep > best_sep:
			best_sep = min_sep
			best_pos = local_pos
	return best_pos


func _on_thought_input(event: InputEvent, bubble: ThoughtBubble) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if bubble != _oldest_thought_panel():
			return
		_holding_panel = bubble
		_holding_elapsed = 0.0
	else:
		_clear_thought_hold()
	get_viewport().set_input_as_handled()


func _on_thought_mouse_exited(bubble: ThoughtBubble) -> void:
	if bubble == _holding_panel:
		_clear_thought_hold()


func _dismiss_thought(bubble: ThoughtBubble) -> void:
	if bubble != _oldest_thought_panel():
		return
	_thought_bubbles.remove_at(0)
	bubble.queue_free()
	_thoughts_erased += 1
	if bubble == _holding_panel:
		_clear_thought_hold()
	_sync_thought_stack_order()
	_sync_breath_button_lock()
