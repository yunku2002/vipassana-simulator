class_name Vipassana1
extends ThoughtStage

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

const _GOAL_LINE := Color(0.169, 0.141, 0.094, 1.0)

## Set in _enter_tree rather than @onready: the scan must be configured before its own _ready.
var _scan: BodyScan
@onready var _gauge_bar: ProgressBar = $Margin/Body/GaugeBox/Gauge
@onready var _gauge_label: Label = $Margin/Body/GaugeBox/GaugeLabel
@onready var _once_more: Label = $Margin/Body/OnceMore

var _phase: _Phase = _Phase.SCAN
## 0 = first pass, 1 = second pass.
var _pass: int = 0
var _once_elapsed: float = 0.0
var _goal_line: ColorRect


func _enter_tree() -> void:
	_scan = $Margin/Body/Scan
	_scan.set_name_clusters(cluster_count, cluster_separation)
	_scan.configure(
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
	_scan.set_sensation_pace(
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
	var buttons := $Margin/Body/CornerButtons
	buttons.get_parent().move_child(buttons, -1)
	intro_finished.connect(_on_stage_intro_finished)
	super._ready()
	_layout_goal_line()
	_apply_locks()


func _refresh_gameplay_texts() -> void:
	_gauge_label.text = tr("GAUGE_COVERAGE")
	_once_more.text = tr("ONCE_MORE")
	super._refresh_gameplay_texts()


func _on_stage_intro_finished() -> void:
	_corner.start_breathing()
	_apply_locks()


func _process(delta: float) -> void:
	if is_gameplay_blocked():
		return
	_advance_thoughts(delta)
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
	_scan.set_press_enabled(scanning and not thought)
	_scan.set_timers_paused(thought)


func _on_thoughts_changed() -> void:
	_apply_locks()


func _pick_thought_local_position() -> Vector2:
	var focus := _scan.get_focus_global_rect()
	var thought_scale := _thought_scale()
	var offset := Vector2.from_angle(randf() * TAU) * (focus.size.x * 0.5 * 0.2) * sqrt(randf())
	var top_left_global := focus.get_center() + offset - ThoughtBubble.CLOUD_SIZE * thought_scale * 0.5
	return (
		_thought_layer.get_global_transform_with_canvas().affine_inverse()
		* top_left_global
	)
