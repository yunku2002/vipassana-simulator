class_name Vipassana1
extends StageShell

enum _Phase { SCAN, ONCE_MORE, DONE }

@export_group("Coverage")
@export_range(10.0, 95.0, 1.0) var coverage_goal: float
@export var once_more_hold: float

@export_group("Body")
@export var body_scale: float
@export var focus_radius: float
## Circle radius in standing.svg design pixels.
@export var region_radius_min: float
@export var region_radius_max: float

@export_group("Sensations")
@export var cluster_count: int
## Minimum distance between name-cluster centers, in standing.svg design pixels.
@export var cluster_separation: float
@export var sensation_interval_min: float
@export var sensation_interval_max: float
@export var sensation_delay_min: float
@export var sensation_delay_max: float
## Second pass divides the interval and delay by this. 2 is twice as fast.
@export var second_pass_pace: float

@export_group("Thoughts")
@export var thought_interval_min: float
@export var thought_interval_max: float
@export var thought_hold_to_clear_sec: float

const _CLOUD_READY_TARGET := 1
const _GOAL_LINE := Color(0.169, 0.141, 0.094, 1.0)
const _THOUGHT_SCALE := 1.5

@onready var _scan: BodyScan = $Margin/Body/Scan
@onready var _gauge_bar: ProgressBar = $Margin/Body/GaugeBox/Gauge
@onready var _gauge_label: Label = $Margin/Body/GaugeBox/GaugeLabel
@onready var _corner: BreathingFigure = $Margin/Body/CornerFigure
@onready var _thought_layer: Control = $Margin/Body/ThoughtLayer
@onready var _once_more: Label = $Margin/Body/OnceMore

var _phase: _Phase = _Phase.SCAN
## 0 = first pass, 1 = second pass.
var _pass: int = 0
var _once_elapsed: float = 0.0

var _thought_timer: float = 0.0
var _ready_clouds: Array[Image] = []
var _cloud_bakes_pending: int = 0
var _thought_bubble: ThoughtBubble
var _holding_panel: ThoughtBubble
var _holding_elapsed: float = 0.0
var _goal_line: ColorRect


func _enter_tree() -> void:
	$Margin/Body/Scan.set_name_clusters(cluster_count, cluster_separation)
	$Margin/Body/Scan.configure(
		body_scale,
		focus_radius,
		region_radius_min,
		region_radius_max,
		sensation_interval_min,
		sensation_interval_max,
		sensation_delay_min,
		sensation_delay_max
	)


## Divides the original interval and delay by second_pass_pace. Calling it again leaves the pace where it is.
func _apply_fast_pace() -> void:
	var pace := maxf(second_pass_pace, 1.0)
	var scan := _scan if _scan != null else $Margin/Body/Scan as BodyScan
	scan.set_sensation_pace(
		sensation_interval_min / pace,
		sensation_interval_max / pace,
		sensation_delay_min / pace,
		sensation_delay_max / pace
	)


func _ready() -> void:
	_goal_line = ColorRect.new()
	_goal_line.color = _GOAL_LINE
	_goal_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_bar.add_child(_goal_line)
	_gauge_bar.resized.connect(_layout_goal_line)
	_gauge_bar.value = 0.0
	_once_more.hide()
	_thought_timer = randf_range(thought_interval_min, thought_interval_max)
	ThoughtBubble.prewarm_trail_dots()
	_ensure_cloud_ready()
	_corner.get_rig().show_chevrons = false
	for chevron_path in ["NostrilChevronA", "NostrilChevronB"]:
		var chevron := _corner.get_rig().get_node_or_null(chevron_path) as CanvasItem
		if chevron:
			chevron.visible = false
	var buttons := $Margin/Body/CornerButtons
	buttons.get_parent().move_child(buttons, -1)
	intro_finished.connect(_on_stage_intro_finished)
	super._ready()
	_layout_goal_line()
	_refresh_gameplay_texts()
	_apply_locks()


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_gameplay_texts()


func _refresh_shell_texts() -> void:
	super._refresh_shell_texts()
	if is_node_ready():
		_refresh_gameplay_texts()


func _refresh_gameplay_texts() -> void:
	_gauge_label.text = tr("GAUGE_COVERAGE")
	_once_more.text = tr("ONCE_MORE")
	if _thought_bubble != null:
		_thought_bubble.set_subject_text(ThoughtSubjects.text_at(_thought_bubble.subject_index))


func _on_stage_intro_finished() -> void:
	_corner.start_breathing()
	_apply_locks()


func _process(delta: float) -> void:
	if is_gameplay_blocked():
		return
	_ensure_cloud_ready()
	_update_thought_spawning(delta)
	_update_thought_hold(delta)
	_update_thought_visuals()
	_apply_locks()
	_scan.advance(delta)
	_update_once_more(delta)
	_gauge_bar.value = _scan.coverage_ratio() * 100.0
	_check_goal()


func _layout_goal_line() -> void:
	if _goal_line == null or _gauge_bar.size.y < 2.0:
		return
	var y := _gauge_bar.size.y * (1.0 - clampf(coverage_goal, 0.0, 100.0) / 100.0)
	_goal_line.position = Vector2(2.0, roundf(y) - 1.0)
	_goal_line.size = Vector2(maxf(_gauge_bar.size.x - 4.0, 0.0), 3.0)


func _check_goal() -> void:
	if _phase != _Phase.SCAN:
		return
	if _scan.coverage_ratio() * 100.0 < coverage_goal:
		return
	if _pass == 0:
		_begin_once_more()
	else:
		_phase = _Phase.DONE
		_apply_locks()
		mark_cleared()


func _begin_once_more() -> void:
	_phase = _Phase.ONCE_MORE
	_once_elapsed = 0.0
	_once_more.show()
	_apply_locks()


func _update_once_more(delta: float) -> void:
	if _phase != _Phase.ONCE_MORE:
		return
	_once_elapsed += delta
	if _once_elapsed < once_more_hold or _waits_for_sensations():
		return
	_end_once_more()


func _waits_for_sensations() -> bool:
	return _scan.has_pending_observation()


func _dismiss_before_reset() -> void:
	pass


func _configure_next_pass() -> void:
	_apply_fast_pace()


func _end_once_more() -> void:
	if not is_inside_tree() or _phase != _Phase.ONCE_MORE:
		return
	_dismiss_before_reset()
	_scan.clear_coverage()
	_scan.reset_to_head()
	_pass = 1
	_configure_next_pass()
	_scan.regenerate_name_clusters()
	_gauge_bar.value = 0.0
	_once_more.hide()
	_phase = _Phase.SCAN
	_apply_locks()


func _apply_locks() -> void:
	var thought := _has_revealed_thought()
	var scanning := _phase == _Phase.SCAN and not is_gameplay_blocked()
	_scan.set_drag_enabled(scanning and not thought)
	_scan.set_spawn_enabled(scanning and not thought)
	_scan.set_timers_paused(thought)


func _has_revealed_thought() -> bool:
	return _thought_bubble != null and _thought_bubble.is_cloud_revealed()


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
		ThoughtBubble.bake_cloud_texture_async(_on_cloud_bake_finished, _THOUGHT_SCALE)


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
	var focus := _scan.get_focus_global_rect()
	var offset := Vector2.from_angle(randf() * TAU) * (focus.size.x * 0.5 * 0.2) * sqrt(randf())
	var top_left_global := focus.get_center() + offset - ThoughtBubble.CLOUD_SIZE * _THOUGHT_SCALE * 0.5
	var cloud_top_left := (
		_thought_layer.get_global_transform_with_canvas().affine_inverse()
		* top_left_global
	)
	var anchor_layer := (
		_thought_layer.get_global_transform_with_canvas().affine_inverse()
		* _corner.get_head_global_position()
	)
	bubble.configure(subject_index, text, cloud_top_left, anchor_layer, cloud_tex, _THOUGHT_SCALE)
	bubble.gui_input.connect(_on_thought_input.bind(bubble))
	bubble.reveal_finished.connect(_apply_locks)
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
	_apply_locks()
	_thought_timer = randf_range(thought_interval_min, thought_interval_max)
