class_name Anapana1
extends StageShell

@export var gauge_fill_per_sec: float
@export var gauge_drain_per_sec: float

@onready var _btn_in: Button = $Margin/Body/CenterCol/InOutRow/BtnIn
@onready var _btn_out: Button = $Margin/Body/CenterCol/InOutRow/BtnOut
@onready var _gauge_bar: ProgressBar = $Margin/Body/GaugeBox/Gauge
@onready var _gauge_label: Label = $Margin/Body/GaugeBox/GaugeLabelSlot/GaugeLabel
@onready var _breathing: BreathingFigure = $Margin/Body/CenterCol/BreathingFigure
@onready var _center_col: VBoxContainer = $Margin/Body/CenterCol

const CENTER_COL_REFERENCE_WIDTH := 720.0
const CENTER_COL_MIN_VIEWPORT_WIDTH := 620.0
const CENTER_COL_MAX_BOTTOM_SHIFT := 64.0

var _gauge_value: float = 0.0


func _ready() -> void:
	super._ready()
	_center_col.resized.connect(_layout_center_col)
	get_viewport().size_changed.connect(_queue_center_col_layout)
	_queue_center_col_layout()
	intro_finished.connect(_on_breath_intro_finished)


func _queue_center_col_layout() -> void:
	_layout_center_col.call_deferred()


func _layout_center_col() -> void:
	var viewport_width := get_viewport().get_visible_rect().size.x
	if viewport_width <= 0.0 or _center_col.size == Vector2.ZERO:
		return

	_center_col.pivot_offset = _center_col.size * 0.5
	var min_scale := CENTER_COL_MIN_VIEWPORT_WIDTH / CENTER_COL_REFERENCE_WIDTH
	var scale_factor := clampf(
		viewport_width / CENTER_COL_REFERENCE_WIDTH,
		min_scale,
		1.0
	)
	_center_col.scale = Vector2.ONE * scale_factor
	var shrink_ratio := (1.0 - scale_factor) / (1.0 - min_scale)
	_center_col.position.y = CENTER_COL_MAX_BOTTOM_SHIFT * shrink_ratio


func _refresh_gameplay_texts() -> void:
	_btn_in.text = tr("BTN_IN")
	_btn_out.text = tr("BTN_OUT")
	_gauge_label.text = tr("GAUGE_LABEL")


func _on_breath_intro_finished() -> void:
	_breathing.start_breathing()


func _process(delta: float) -> void:
	if is_gameplay_blocked():
		return
	_on_before_gauge_update(delta)
	_update_breath_gauge(delta)
	if _is_stage_cleared():
		mark_cleared()


func _on_before_gauge_update(_delta: float) -> void:
	pass


func _update_breath_gauge(delta: float) -> void:
	var correct := _is_correct_input_held()
	if correct:
		_gauge_value = minf(100.0, _gauge_value + gauge_fill_per_sec * delta)
	else:
		_gauge_value = maxf(0.0, _gauge_value - gauge_drain_per_sec * delta)
	_gauge_bar.value = _gauge_value


func _is_stage_cleared() -> bool:
	return _gauge_value >= 100.0


func _is_correct_input_held() -> bool:
	if _breathing.get_rig().is_inhaling():
		return _btn_in.button_pressed and not _btn_out.button_pressed
	return _btn_out.button_pressed and not _btn_in.button_pressed
