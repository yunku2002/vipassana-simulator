extends Control

enum Phase { INHALE, EXHALE }

const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"
const STAGE_SCENE := "res://scenes/anapana_1.tscn"

@export var gauge_fill_per_sec: float = 8.0
@export var gauge_drain_per_sec: float = 12.0
@export var inhale_sec_min: float = 2.2
@export var inhale_sec_max: float = 3.8
@export var exhale_sec_min: float = 2.2
@export var exhale_sec_max: float = 3.8

@export_group("Chest motion")
## Rest y of the BoneShoulder; matches the bone's rest pose in the scene.
@export var rest_shoulder_y: float = -250.0
## Rest y of the BoneNeck (local to its parent BoneShoulder); matches the bone's rest pose.
@export var rest_neck_y: float = -50.0
## Chest displacement (in skeleton units) at the shortest possible cycle.
@export var chest_amplitude_min: float = 8.0
## Chest displacement (in skeleton units) at the longest possible cycle.
## Cycles in between scale linearly. Longer breaths = deeper breaths.
@export var chest_amplitude_max: float = 22.0
## How much the neck counter-moves relative to the shoulder. 1.0 = same amount, opposite direction.
@export var neck_counter_ratio: float = 1.0
## Where rest sits inside the chest motion: 0.0 = rest is fully exhaled (chest only rises),
## 0.5 = chest swings equally above and below rest, 1.0 = rest is fully inhaled.
@export_range(0.0, 1.0) var rest_fullness: float = 0.33

@export_group("Nostril chevrons")
## Full inhale↔exhale crossfade time. Blend is 0.5 at each phase change (half before, half after).
@export var breath_crossfade_duration: float = 1.2

@onready var _btn_options: Button = $Margin/Body/CornerButtons/BtnOptions
@onready var _btn_main_menu: Button = $Margin/Body/CornerButtons/BtnMainMenu
@onready var _confirm_layer: CanvasLayer = $ExitConfirmLayer
@onready var _confirm_title: Label = $ExitConfirmLayer/Center/Panel/Margin/VBox/Title
@onready var _btn_confirm_cancel: Button = $ExitConfirmLayer/Center/Panel/Margin/VBox/ButtonsRow/BtnCancel
@onready var _btn_confirm_ok: Button = $ExitConfirmLayer/Center/Panel/Margin/VBox/ButtonsRow/BtnConfirm
@onready var _win_layer: CanvasLayer = $WinLayer
@onready var _win_title: Label = $WinLayer/Center/Panel/Margin/VBox/WinTitle
@onready var _btn_continue: Button = $WinLayer/Center/Panel/Margin/VBox/BtnContinue
@onready var _btn_menu: Button = $WinLayer/Center/Panel/Margin/VBox/BtnMenu
@onready var _btn_in: Button = $Margin/Body/CenterCol/InOutRow/BtnIn
@onready var _btn_out: Button = $Margin/Body/CenterCol/InOutRow/BtnOut
@onready var _gauge_bar: ProgressBar = $Margin/Body/GaugeBox/Gauge
@onready var _gauge_label: Label = $Margin/Body/GaugeBox/GaugeLabel
@onready var _chevron_nostril_a: ChevronScrollIndicator = $Margin/Body/CenterCol/Figure/RigRoot/NostrilChevronA
@onready var _chevron_nostril_b: ChevronScrollIndicator = $Margin/Body/CenterCol/Figure/RigRoot/NostrilChevronB
@onready var _bone_shoulder: Bone2D = $Margin/Body/CenterCol/Figure/RigRoot/Skeleton/BoneNavel/BoneShoulder
@onready var _bone_neck: Bone2D = $Margin/Body/CenterCol/Figure/RigRoot/Skeleton/BoneNavel/BoneShoulder/BoneNeck

var _phase: Phase = Phase.INHALE
var _phase_left: float = 0.0
## Pre-rolled phase durations for the current cycle (chosen at the start of each INHALE).
var _inhale_duration: float = 0.0
var _exhale_duration: float = 0.0
## Chest amplitude in effect for the current cycle, derived from this cycle's total duration.
var _current_amplitude: float = 0.0
## Amplitude from the cycle that just ended; used to ramp from old bottom to new peak across
## the new inhale so consecutive cycles meet seamlessly at empty lungs.
var _prev_amplitude: float = 0.0
var _gauge_value: float = 0.0
var _cleared: bool = false
var _intro_blocking: bool = true


func _ready() -> void:
	_win_layer.hide()
	_confirm_layer.hide()
	GameSettings.set_next_stage(_stage_index())
	_btn_options.pressed.connect(_on_options_pressed)
	_btn_main_menu.pressed.connect(_on_main_menu_pressed)
	_btn_confirm_cancel.pressed.connect(_hide_exit_confirm)
	_btn_confirm_ok.pressed.connect(_go_to_main_menu)
	_btn_continue.pressed.connect(_on_continue_pressed)
	_btn_menu.pressed.connect(_go_to_main_menu)
	_refresh_static_texts()
	var intro := StageIntroOverlay.open(self, "STAGE_ANAPANA_1")
	intro.finished.connect(_on_intro_finished)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_static_texts()


func _refresh_static_texts() -> void:
	_btn_options.text = tr("MENU_OPTIONS")
	_btn_main_menu.text = tr("BTN_MENU")
	_confirm_title.text = tr("CONFIRM_EXIT_TITLE")
	_btn_confirm_cancel.text = tr("BTN_CANCEL")
	_btn_confirm_ok.text = tr("BTN_MENU")
	_win_title.text = tr("STAGE_CLEAR")
	_btn_continue.text = tr("BTN_CONTINUE")
	_btn_menu.text = tr("BTN_MENU")
	_btn_in.text = tr("BTN_IN")
	_btn_out.text = tr("BTN_OUT")
	_gauge_label.text = tr("GAUGE_LABEL")


func _on_intro_finished() -> void:
	_intro_blocking = false
	_start_cycle()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _intro_blocking or _cleared:
		return
	if _confirm_layer.visible:
		_hide_exit_confirm()
	else:
		_show_exit_confirm()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _intro_blocking or _cleared:
		return
	_phase_left -= delta
	if _phase_left <= 0.0:
		_advance_phase()
	_update_visuals()
	_drive_respiration()
	var correct := _is_correct_input_held()
	if correct:
		_gauge_value = minf(100.0, _gauge_value + gauge_fill_per_sec * delta)
	else:
		_gauge_value = maxf(0.0, _gauge_value - gauge_drain_per_sec * delta)
	_gauge_bar.value = _gauge_value
	if _gauge_value >= 100.0:
		_on_cleared_once()


## Start a new full breath cycle: pre-pick both phase durations.
## Chest amplitude is rolled once per cycle from this cycle's total duration:
## the longer the breath, the deeper the chest motion.
func _start_cycle() -> void:
	_prev_amplitude = _current_amplitude
	_inhale_duration = randf_range(inhale_sec_min, inhale_sec_max)
	_exhale_duration = randf_range(exhale_sec_min, exhale_sec_max)
	_phase = Phase.INHALE
	_phase_left = _inhale_duration
	_current_amplitude = _amplitude_for_duration(_inhale_duration + _exhale_duration)


func _advance_phase() -> void:
	if _phase == Phase.INHALE:
		_phase = Phase.EXHALE
		_phase_left = _exhale_duration
	else:
		_start_cycle()


func _is_correct_input_held() -> bool:
	if _phase == Phase.INHALE:
		return _btn_in.button_pressed and not _btn_out.button_pressed
	return _btn_out.button_pressed and not _btn_in.button_pressed


func _update_visuals() -> void:
	var inhaling := _phase == Phase.INHALE
	var blend := _breath_chevron_blend()
	for chevron in [_chevron_nostril_a, _chevron_nostril_b]:
		chevron.set_breath_visual(blend, inhaling)


## Blend 0 = exhale, 1 = inhale. Ramps for half of [member breath_crossfade_duration] before
## each phase change and half after, so 0.5 lands exactly on inhale↔exhale boundaries.
func _breath_chevron_blend() -> float:
	var half := breath_crossfade_duration * 0.5
	var toward_inhale := _phase == Phase.INHALE
	var phase_dur := maxf(_inhale_duration if toward_inhale else _exhale_duration, 0.001)
	var ramp := minf(half, phase_dur * 0.5)
	var elapsed := phase_dur - _phase_left
	var time_left := _phase_left
	var peak := 1.0 if toward_inhale else 0.0
	if elapsed < ramp:
		return lerpf(0.5, peak, elapsed / ramp)
	if time_left < ramp:
		return lerpf(peak, 0.5, 1.0 - time_left / ramp)
	return peak


## Maps a full-cycle duration (inhale + exhale, in seconds) to a chest-motion amplitude.
## The minimum possible cycle (inhale_sec_min + exhale_sec_min) maps to chest_amplitude_min;
## the maximum possible cycle maps to chest_amplitude_max; durations between are interpolated.
func _amplitude_for_duration(total_sec: float) -> float:
	var min_total := inhale_sec_min + exhale_sec_min
	var max_total := inhale_sec_max + exhale_sec_max
	var t := clampf((total_sec - min_total) / maxf(max_total - min_total, 0.001), 0.0, 1.0)
	return lerpf(chest_amplitude_min, chest_amplitude_max, t)


## Drives the rig each frame from per-phase progress, so the peak always lands exactly
## at the inhale→exhale boundary regardless of the two durations.
##
## `rest_fullness` shifts where rest sits inside the chest motion range: at 0.0 the chest
## only rises, at 0.5 it swings symmetrically around rest, at 1.0 it only drops. With any
## non-zero `rest_fullness`, the chest's "empty lungs" position depends on amplitude — so
## a naive switch to a new amplitude at the exhale→inhale boundary would teleport the chest.
##
## To keep the boundary seamless, the inhale ramps amplitude linearly from the previous
## cycle's value (matching where the last exhale ended) up to this cycle's value (the new
## peak). Exhale uses this cycle's amplitude throughout, ending at the same value the next
## inhale starts from, so consecutive cycles meet exactly at empty lungs.
func _drive_respiration() -> void:
	if _bone_shoulder == null or _bone_neck == null:
		return
	var fullness: float
	var amp: float
	if _phase == Phase.INHALE:
		fullness = clampf(1.0 - (_phase_left / maxf(_inhale_duration, 0.001)), 0.0, 1.0)
		amp = lerpf(_prev_amplitude, _current_amplitude, fullness)
	else:
		fullness = clampf(_phase_left / maxf(_exhale_duration, 0.001), 0.0, 1.0)
		amp = _current_amplitude
	var eased := smoothstep(0.0, 1.0, fullness)
	var offset := amp * (eased - rest_fullness)
	_bone_shoulder.position.y = rest_shoulder_y - offset
	_bone_neck.position.y = rest_neck_y + offset * neck_counter_ratio


func _stage_index() -> int:
	return StageRegistry.index_for_scene(STAGE_SCENE)


func _on_cleared_once() -> void:
	if _cleared:
		return
	_cleared = true
	GameSettings.set_next_stage_after(_stage_index())
	_win_layer.show()


func _on_continue_pressed() -> void:
	var next_index := _stage_index() + 1
	if next_index < StageRegistry.stage_count():
		GameSettings.set_next_stage(next_index)
		get_tree().change_scene_to_file(StageRegistry.scene_path(next_index))
		return
	_go_to_main_menu()


func _on_main_menu_pressed() -> void:
	_show_exit_confirm()


func _show_exit_confirm() -> void:
	_confirm_layer.show()
	get_tree().paused = true


func _hide_exit_confirm() -> void:
	_confirm_layer.hide()
	get_tree().paused = false


func _go_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _on_options_pressed() -> void:
	OptionOverlay.open(self)
