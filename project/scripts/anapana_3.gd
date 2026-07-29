extends StageShell

@export_group("Gauge")
@export var gauge_fill_on_hit: float
@export var gauge_drain_per_sec: float

@export_group("Sensations")
@export var sensation_interval_min: float
@export var sensation_interval_max: float
@export var sensation_duration_min: float
@export var sensation_duration_max: float

@export_group("Thoughts")
@export var thought_interval_min: float
@export var thought_interval_max: float
@export var thought_hold_to_clear_sec: float

const _CLOUD_READY_TARGET := 1

@onready var _gauge_bar: ProgressBar = $Margin/Body/GaugeBox/Gauge
@onready var _gauge_label: Label = $Margin/Body/GaugeBox/GaugeLabel
@onready var _corner: BreathingFigure = $Margin/Body/CornerFigure
@onready var _focus: SensationFocus = $Margin/Body/SensationFocus
@onready var _thought_layer: Control = $Margin/Body/ThoughtLayer

var _gauge_value: float = 0.0
var _sensation_timer: float = 0.0
var _active_sensations_left: Array[float] = []

var _thought_timer: float = 0.0
var _ready_clouds: Array[Image] = []
var _cloud_bakes_pending: int = 0
var _thought_bubble: ThoughtBubble
var _holding_panel: ThoughtBubble
var _holding_elapsed: float = 0.0


func _ready() -> void:
	_gauge_bar.value = _gauge_value
	_thought_timer = randf_range(thought_interval_min, thought_interval_max)
	_sensation_timer = randf_range(sensation_interval_min, sensation_interval_max)
	_active_sensations_left.clear()
	for _i in SensationFocus.region_layout.size():
		_active_sensations_left.append(0.0)
	ThoughtBubble.prewarm_trail_dots()
	_ensure_cloud_ready()
	_corner.get_rig().show_chevrons = false
	# Child ready already applied the export; force-hide in case of order quirks.
	for chevron_path in ["NostrilChevronA", "NostrilChevronB"]:
		var chevron := _corner.get_rig().get_node_or_null(chevron_path) as CanvasItem
		if chevron:
			chevron.visible = false
	_focus.region_pressed.connect(_on_region_pressed)
	super._ready()
	intro_finished.connect(_on_stage_intro_finished)
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
	_gauge_label.text = tr("GAUGE_LABEL")
	if _thought_bubble != null:
		_thought_bubble.set_subject_text(ThoughtSubjects.text_at(_thought_bubble.subject_index))


func _on_stage_intro_finished() -> void:
	_corner.start_breathing()


func _process(delta: float) -> void:
	if is_gameplay_blocked():
		return
	_ensure_cloud_ready()
	_update_thought_spawning(delta)
	_update_thought_hold(delta)
	_update_thought_visuals()
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
	# Decrement all active regions independently.
	for i in _active_sensations_left.size():
		var left := _active_sensations_left[i] - delta
		if left <= 0.0:
			_active_sensations_left[i] = 0.0
			_focus.clear_region(i)
		else:
			_active_sensations_left[i] = left

	# Spawn new lit regions on a separate timer (whack-a-mole style).
	_sensation_timer -= delta
	var spawned := 0
	while _sensation_timer <= 0.0 and spawned < 3:
		# Prefer inactive regions to avoid re-lighting the same one.
		var inactive: Array[int] = []
		for i in _active_sensations_left.size():
			if _active_sensations_left[i] <= 0.0:
				inactive.append(i)
		var index := (
			inactive[randi() % inactive.size()] if not inactive.is_empty()
			else randi() % SensationFocus.region_layout.size()
		)
		_focus.activate_region(index)
		_active_sensations_left[index] = randf_range(sensation_duration_min, sensation_duration_max)
		spawned += 1
		_sensation_timer = randf_range(sensation_interval_min, sensation_interval_max)


func _on_region_pressed(region_index: int) -> void:
	if is_gameplay_blocked():
		return
	if _has_revealed_thought():
		return
	if region_index < 0 or region_index >= _active_sensations_left.size():
		return
	if _active_sensations_left[region_index] <= 0.0:
		return
	_active_sensations_left[region_index] = 0.0
	_focus.play_success_burst(region_index)
	_gauge_value = minf(100.0, _gauge_value + gauge_fill_on_hit)
	_gauge_bar.value = _gauge_value


func _sync_focus_input_lock() -> void:
	_focus.set_input_blocked(_has_revealed_thought())


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
		ThoughtBubble.bake_cloud_texture_async(_on_cloud_bake_finished)


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
		cloud_tex
	)
	bubble.gui_input.connect(_on_thought_input.bind(bubble))
	bubble.reveal_finished.connect(_sync_focus_input_lock)
	_thought_bubble = bubble
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 1


func _pick_thought_local_position() -> Vector2:
	return ThoughtBubble.random_top_left_in_zone(
		_focus.get_regions_global_rect(),
		_thought_layer
	)


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
	_sync_focus_input_lock()
	_thought_timer = randf_range(thought_interval_min, thought_interval_max)
