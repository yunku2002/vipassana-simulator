class_name Anapana3
extends ThoughtStage

@export_group("Gauge")
@export var gauge_fill_on_hit: float
@export var gauge_drain_per_sec: float

@export_group("Sensations")
@export_file("*.png") var dim_mask_path: String = "res://assets/mask_nostrils.png"
@export var sensation_interval_min: float
@export var sensation_interval_max: float
@export var sensation_duration_min: float
@export var sensation_duration_max: float
@export var max_active_sensations: int = 3
## Circle radius in sitting.svg design pixels.
@export var region_radius_min: float
@export var region_radius_max: float

@onready var _gauge_bar: ProgressBar = $Margin/Body/GaugeBox/Gauge
@onready var _gauge_label: Label = $Margin/Body/GaugeBox/GaugeLabel
@onready var _focus: HeadFocus = $Margin/Body/HeadFocus

var _gauge_value: float = 0.0
var _sensation_timer: float = 0.0
## region_id -> time remaining
var _active_sensations: Dictionary = {}


func _enter_tree() -> void:
	$Margin/Body/HeadFocus.configure(dim_mask_path, region_radius_min, region_radius_max)


func _ready() -> void:
	_gauge_bar.value = _gauge_value
	_sensation_timer = randf_range(sensation_interval_min, sensation_interval_max)
	_active_sensations.clear()
	_focus.region_pressed.connect(_on_region_pressed)
	super._ready()
	intro_finished.connect(_on_stage_intro_finished)


func _refresh_gameplay_texts() -> void:
	_gauge_label.text = tr("GAUGE_LABEL")
	super._refresh_gameplay_texts()


func _on_stage_intro_finished() -> void:
	_corner.start_breathing()


func _process(delta: float) -> void:
	if is_gameplay_blocked():
		return
	_advance_thoughts(delta)
	_sync_focus_input_lock()
	_update_sensations(delta)
	if _gauge_value >= 100.0:
		mark_cleared()
		return
	_update_gauge(delta)


func _update_gauge(delta: float) -> void:
	_gauge_value = clampf(_gauge_value - gauge_drain_per_sec * delta, 0.0, 100.0)
	_gauge_bar.value = _gauge_value


func _update_sensations(delta: float) -> void:
	var expired: Array[int] = []
	for region_id in _active_sensations.keys():
		var left: float = float(_active_sensations[region_id]) - delta
		if left <= 0.0:
			expired.append(region_id)
		else:
			_active_sensations[region_id] = left
	for region_id in expired:
		_active_sensations.erase(region_id)
		_focus.clear_region(region_id)

	_sensation_timer -= delta
	while _sensation_timer <= 0.0 and _active_sensations.size() < max_active_sensations:
		var region_id := _focus.spawn_region()
		_sensation_timer = randf_range(sensation_interval_min, sensation_interval_max)
		if region_id < 0:
			break
		_active_sensations[region_id] = randf_range(sensation_duration_min, sensation_duration_max)


func _on_region_pressed(region_id: int) -> void:
	if is_gameplay_blocked():
		return
	if _has_revealed_thought():
		return
	if not _active_sensations.has(region_id):
		return
	_active_sensations.erase(region_id)
	_focus.play_success_burst(region_id, _success_burst_text())
	_gauge_value = minf(100.0, _gauge_value + gauge_fill_on_hit)
	_gauge_bar.value = _gauge_value


func _success_burst_text() -> String:
	return "!"


func _sync_focus_input_lock() -> void:
	_focus.set_input_blocked(_has_revealed_thought())


func _on_thoughts_changed() -> void:
	_sync_focus_input_lock()


func _thought_spawn_zone() -> Rect2:
	return _focus.get_regions_global_rect()
