extends Anapana1

@export_group("Thoughts")
@export var thought_goal_count: int
@export var thought_interval_start: float
@export var thought_interval_peak: float
@export var thought_peak_erase_count: int
@export var thought_slow_erase_count: int
@export var thought_post_goal_interval_min: float
@export var thought_post_goal_interval_max: float
@export var thought_hold_to_clear_sec: float
@export var thought_min_separation: float

const _THOUGHT_INACTIVE_GRAY := 0.8
const _THOUGHT_PLACEMENT_ATTEMPTS := 8

@onready var _thought_layer: Control = $Margin/Body/ThoughtLayer

var _thought_timer: float = 0.0
var _thoughts_erased: int = 0
var _thought_bubbles: Array[ThoughtBubble] = []
var _holding_panel: ThoughtBubble
var _holding_elapsed: float = 0.0


func _ready() -> void:
	_gauge_value = 100.0
	_gauge_bar.value = 100.0
	_thought_timer = _next_thought_interval()
	super._ready()


func _on_before_gauge_update(delta: float) -> void:
	_update_thought_spawning(delta)
	_update_thought_hold(delta)
	_update_thought_visuals()
	_sync_breath_button_lock()


func _refresh_gameplay_texts() -> void:
	super._refresh_gameplay_texts()
	for bubble in _thought_bubbles:
		bubble.set_subject_text(ThoughtSubjects.text_at(bubble.subject_index))


func _is_stage_cleared() -> bool:
	return _gauge_value >= 100.0 and _thoughts_erased >= thought_goal_count


func _release_breath_buttons() -> void:
	_btn_in.button_pressed = false
	_btn_out.button_pressed = false


func _sync_breath_button_lock() -> void:
	var blocked := _has_revealed_thought()
	if blocked:
		_release_breath_buttons()
	_btn_in.disabled = blocked
	_btn_out.disabled = blocked


func _has_revealed_thought() -> bool:
	for bubble in _thought_bubbles:
		if bubble.is_cloud_revealed():
			return true
	return false


func _update_thought_spawning(delta: float) -> void:
	_thought_timer -= delta
	if _thought_timer > 0.0:
		return
	if _thought_bubbles.size() >= _active_thought_cap():
		return
	_spawn_thought()
	_thought_timer = _next_thought_interval()


func _next_thought_interval() -> float:
	if _thoughts_erased >= thought_slow_erase_count:
		return randf_range(thought_post_goal_interval_min, thought_post_goal_interval_max)
	if _thoughts_erased >= thought_peak_erase_count:
		var span := maxi(thought_slow_erase_count - thought_peak_erase_count, 1)
		var t := float(_thoughts_erased - thought_peak_erase_count) / float(span)
		var low := lerpf(thought_interval_peak, thought_post_goal_interval_min, t)
		var high := lerpf(thought_interval_peak, thought_post_goal_interval_max, t)
		return randf_range(low, high)
	var up := clampf(float(_thoughts_erased) / maxf(1.0, float(thought_peak_erase_count)), 0.0, 1.0)
	return lerpf(thought_interval_start, thought_interval_peak, up)


func _active_thought_cap() -> int:
	return 1 if _thoughts_erased <= 0 else 5


func _spawn_thought() -> void:
	var subject_index := ThoughtSubjects.random_index()
	var text := ThoughtSubjects.text_at(subject_index)
	var bubble := ThoughtBubble.new()
	_thought_layer.add_child(bubble)

	var cloud_top_left := _pick_thought_local_position()
	var anchor_layer := _thought_layer.get_global_transform_with_canvas().affine_inverse() * _breathing.get_head_global_position()
	bubble.configure(subject_index, text, cloud_top_left, anchor_layer)
	bubble.gui_input.connect(_on_thought_input.bind(bubble))
	bubble.reveal_finished.connect(_on_thought_revealed)

	_thought_bubbles.append(bubble)
	_sync_thought_stack_order()
	_update_thought_visuals()


func _on_thought_revealed() -> void:
	_sync_thought_stack_order()
	_sync_breath_button_lock()


func _update_thought_hold(delta: float) -> void:
	if _holding_panel == null:
		return
	if _holding_panel != _oldest_thought_panel():
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
		bubble.z_index = count - i
		var interactive := i == 0 and bubble.is_cloud_revealed()
		bubble.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE


func _clear_thought_hold() -> void:
	_holding_panel = null
	_holding_elapsed = 0.0


func _pick_thought_local_position() -> Vector2:
	var zone := _btn_in.get_global_rect().merge(_btn_out.get_global_rect())
	var best_pos := Vector2.ZERO
	var best_sep := -1.0
	for attempt in _THOUGHT_PLACEMENT_ATTEMPTS:
		var local_pos := ThoughtBubble.random_top_left_in_zone(zone, _thought_layer, 0.4)
		var min_sep := INF
		for bubble in _thought_bubbles:
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
