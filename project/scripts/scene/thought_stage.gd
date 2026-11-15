class_name ThoughtStage
extends StageShell

const FIGURE_REFERENCE_WIDTH := 800.0

@export_group("Thoughts")
@export var thoughts_enabled: bool = true
@export var thought_interval_min: float
@export var thought_interval_max: float
@export var thought_hold_to_clear_sec: float

@onready var _thought_layer: Control = $Margin/Body/ThoughtLayer
@onready var _corner: BreathingFigure = $Margin/Body/CornerFigure

var _thought_timer: float = 0.0
var _thought_bubble: ThoughtBubble
var _holding_panel: ThoughtBubble
var _holding_elapsed: float = 0.0
var _thought_layout_queued: bool = false


func _ready() -> void:
	_corner.get_rig().show_chevrons = false
	if thoughts_enabled:
		_thought_timer = randf_range(thought_interval_min, thought_interval_max)
	_thought_layer.resized.connect(_on_thought_layer_resized)
	get_viewport().size_changed.connect(_queue_responsive_figure_layout)
	super._ready()
	_queue_responsive_figure_layout()


func _responsive_figure_control() -> Control:
	return null


func _responsive_figure_pivot(figure: Control) -> Vector2:
	return figure.size * 0.5


func _queue_responsive_figure_layout() -> void:
	_layout_responsive_figures.call_deferred()


func _layout_responsive_figures() -> void:
	var viewport_width := get_viewport().get_visible_rect().size.x
	if viewport_width <= 0.0:
		return
	var scale_factor := clampf(
		viewport_width / FIGURE_REFERENCE_WIDTH,
		float(WindowScale.MIN_WIDTH) / FIGURE_REFERENCE_WIDTH,
		1.0
	)
	if _corner.size != Vector2.ZERO:
		# Keep the corner figure pinned to its bottom-left anchor as it shrinks.
		_corner.pivot_offset = Vector2(0.0, _corner.size.y)
		_corner.scale = Vector2.ONE * scale_factor
	var figure := _responsive_figure_control()
	if figure != null and figure.size != Vector2.ZERO:
		figure.pivot_offset = _responsive_figure_pivot(figure)
		if figure is BodyScan:
			(figure as BodyScan).set_responsive_scale(scale_factor)
		else:
			figure.scale = Vector2.ONE * scale_factor


func _refresh_gameplay_texts() -> void:
	if _thought_bubble != null:
		_thought_bubble.set_subject_text(ThoughtSubjects.text_at(_thought_bubble.subject_index))


func _advance_thoughts(delta: float) -> void:
	if not thoughts_enabled:
		return
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
	_spawn_thought()
	_thought_timer = randf_range(thought_interval_min, thought_interval_max)


func _spawn_thought() -> void:
	var subject_index := ThoughtSubjects.random_index()
	var text := ThoughtSubjects.text_at(subject_index)
	var bubble := ThoughtBubble.new()
	_thought_layer.add_child(bubble)
	var cloud_top_left := _pick_thought_local_position()
	var anchor_layer := ThoughtBubble.to_layer(_thought_layer, _corner.get_head_global_position())
	var zone_center := ThoughtBubble.to_layer(_thought_layer, _thought_spawn_zone().get_center())
	bubble.configure(
		subject_index,
		text,
		cloud_top_left,
		anchor_layer,
		zone_center,
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


func _on_thought_layer_resized() -> void:
	if _thought_layout_queued:
		return
	_thought_layout_queued = true
	_relayout_thoughts.call_deferred()


func _relayout_thoughts() -> void:
	_thought_layout_queued = false
	if _thought_bubble == null or not is_instance_valid(_thought_bubble):
		return
	var zone := _thought_spawn_zone()
	if zone.size.x < 1.0 or zone.size.y < 1.0:
		return
	_thought_bubble.follow_zone(
		ThoughtBubble.to_layer(_thought_layer, zone.get_center()),
		ThoughtBubble.to_layer(_thought_layer, _corner.get_head_global_position()),
		_thought_layer.size
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
