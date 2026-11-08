class_name ThoughtStage
extends StageShell

@export_group("Thoughts")
@export var thoughts_enabled: bool = true
@export var thought_interval_min: float
@export var thought_interval_max: float
@export var thought_hold_to_clear_sec: float

const _CLOUD_READY_TARGET := 1

@onready var _thought_layer: Control = $Margin/Body/ThoughtLayer
@onready var _corner: BreathingFigure = $Margin/Body/CornerFigure

var _thought_timer: float = 0.0
var _ready_clouds: Array[Image] = []
var _cloud_bakes_pending: int = 0
var _thought_bubble: ThoughtBubble
var _holding_panel: ThoughtBubble
var _holding_elapsed: float = 0.0


func _ready() -> void:
	_corner.get_rig().show_chevrons = false
	if thoughts_enabled:
		_thought_timer = randf_range(thought_interval_min, thought_interval_max)
		ThoughtBubble.prewarm_trail_dots()
		_ensure_cloud_ready()
	super._ready()


func _refresh_gameplay_texts() -> void:
	if _thought_bubble != null:
		_thought_bubble.set_subject_text(ThoughtSubjects.text_at(_thought_bubble.subject_index))


func _advance_thoughts(delta: float) -> void:
	if not thoughts_enabled:
		return
	_ensure_cloud_ready()
	_update_thought_spawning(delta)
	_update_thought_hold(delta)
	_update_thought_visuals()


func _has_revealed_thought() -> bool:
	return _thought_bubble != null and _thought_bubble.is_cloud_revealed()


func _thought_scale() -> float:
	return 1.5


func _thought_spawn_zone() -> Rect2:
	return Rect2()


func _pick_thought_local_position() -> Vector2:
	return ThoughtBubble.random_top_left_in_zone(
		_thought_spawn_zone(),
		_thought_layer,
		0.2,
		ThoughtBubble.CLOUD_SIZE * _thought_scale()
	)


## Called when a thought finishes revealing or is dismissed.
func _on_thoughts_changed() -> void:
	pass


func _update_thought_spawning(delta: float) -> void:
	if _thought_bubble != null:
		return
	_thought_timer -= delta
	if _thought_timer > 0.0:
		return
	if _ready_clouds.is_empty():
		return
	_spawn_thought(_ready_clouds.pop_front())
	_thought_timer = randf_range(thought_interval_min, thought_interval_max)
	_ensure_cloud_ready()


func _ensure_cloud_ready() -> void:
	while _ready_clouds.size() + _cloud_bakes_pending < _CLOUD_READY_TARGET:
		_cloud_bakes_pending += 1
		ThoughtBubble.bake_cloud_texture_async(_on_cloud_bake_finished, _thought_scale())


func _on_cloud_bake_finished(img: Image) -> void:
	_cloud_bakes_pending = maxi(_cloud_bakes_pending - 1, 0)
	if not is_inside_tree():
		return
	_ready_clouds.append(img)


func _spawn_thought(img: Image) -> void:
	var subject_index := ThoughtSubjects.random_index()
	var text := ThoughtSubjects.text_at(subject_index)
	var cloud_tex := ImageTexture.create_from_image(img)
	var bubble := ThoughtBubble.new()
	_thought_layer.add_child(bubble)
	var cloud_top_left := _pick_thought_local_position()
	var anchor_layer := (
		_thought_layer.get_global_transform_with_canvas().affine_inverse()
		* _corner.get_head_global_position()
	)
	bubble.configure(
		subject_index,
		text,
		cloud_top_left,
		anchor_layer,
		cloud_tex,
		_thought_scale()
	)
	bubble.gui_input.connect(_on_thought_input.bind(bubble))
	bubble.reveal_finished.connect(_on_thoughts_changed)
	_thought_bubble = bubble
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 1


func _on_thought_input(event: InputEvent, bubble: ThoughtBubble) -> void:
	if bubble != _thought_bubble:
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_holding_panel = bubble
		_holding_elapsed = 0.0
	else:
		_clear_thought_hold()
	get_viewport().set_input_as_handled()


func _update_thought_hold(delta: float) -> void:
	if _holding_panel == null:
		return
	if _holding_panel != _thought_bubble:
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
	if _thought_bubble == null:
		return
	var target_a := 1.0
	if _holding_panel == _thought_bubble and thought_hold_to_clear_sec > 0.001:
		var t := clampf(_holding_elapsed / thought_hold_to_clear_sec, 0.0, 1.0)
		target_a = lerpf(1.0, 0.1, t)
	_thought_bubble.modulate = Color(1.0, 1.0, 1.0, target_a)
	var interactive := _thought_bubble.is_cloud_revealed()
	_thought_bubble.mouse_filter = (
		Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	)


func _clear_thought_hold() -> void:
	_holding_panel = null
	_holding_elapsed = 0.0


func _dismiss_thought(bubble: ThoughtBubble) -> void:
	if bubble != _thought_bubble:
		return
	_thought_bubble = null
	bubble.queue_free()
	if bubble == _holding_panel:
		_clear_thought_hold()
	_on_thoughts_changed()
	_thought_timer = randf_range(thought_interval_min, thought_interval_max)
