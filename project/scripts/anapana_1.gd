class_name Anapana1
extends StageShell

@export var gauge_fill_per_sec: float
@export var gauge_drain_per_sec: float

@onready var _btn_in: Button = $Margin/Body/CenterCol/InOutRow/BtnIn
@onready var _btn_out: Button = $Margin/Body/CenterCol/InOutRow/BtnOut
@onready var _gauge_bar: ProgressBar = $Margin/Body/GaugeBox/Gauge
@onready var _gauge_label: Label = $Margin/Body/GaugeBox/GaugeLabel
@onready var _breathing: BreathingFigure = $Margin/Body/CenterCol/BreathingFigure

var _gauge_value: float = 0.0


func _ready() -> void:
	super._ready()
	intro_finished.connect(_on_breath_intro_finished)
	_refresh_gameplay_texts()


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_gameplay_texts()


func _refresh_shell_texts() -> void:
	super._refresh_shell_texts()
	if is_node_ready():
		_refresh_gameplay_texts()


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
