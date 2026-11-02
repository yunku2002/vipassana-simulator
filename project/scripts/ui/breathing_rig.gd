class_name BreathingRig
extends Node2D

enum Phase { INHALE, EXHALE }

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
@export var chest_amplitude_max: float = 22.0
@export var neck_counter_ratio: float = 1.0
@export_range(0.0, 1.0) var rest_fullness: float = 0.33

@export_group("Nostril chevrons")
@export var show_chevrons: bool = true:
	set(value):
		show_chevrons = value
		_apply_chevron_visibility()
## Full inhale↔exhale crossfade time. Blend is 0.5 at each phase change (half before, half after).
@export var breath_crossfade_duration: float = 1.2

@onready var _bone_shoulder: Bone2D = $Skeleton/BoneNavel/BoneShoulder
@onready var _bone_neck: Bone2D = $Skeleton/BoneNavel/BoneShoulder/BoneNeck
@onready var _chevron_nostril_a: ChevronScrollIndicator = $NostrilChevronA
@onready var _chevron_nostril_b: ChevronScrollIndicator = $NostrilChevronB

var _phase: Phase = Phase.INHALE
var _phase_left: float = 0.0
var _inhale_duration: float = 0.0
var _exhale_duration: float = 0.0
var _current_amplitude: float = 0.0
var _prev_amplitude: float = 0.0
var _running: bool = false


func _ready() -> void:
	set_process(false)
	_apply_chevron_visibility()


func start() -> void:
	if _running:
		return
	_running = true
	_start_cycle()
	set_process(true)


func stop() -> void:
	_running = false
	set_process(false)


func is_inhaling() -> bool:
	return _phase == Phase.INHALE


func _process(delta: float) -> void:
	if not _running:
		return
	_phase_left -= delta
	if _phase_left <= 0.0:
		_advance_phase()
	_update_chevrons()
	_drive_respiration()


func _apply_chevron_visibility() -> void:
	for chevron in [_chevron_nostril_a, _chevron_nostril_b]:
		if chevron:
			chevron.visible = show_chevrons


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


func _update_chevrons() -> void:
	if not show_chevrons:
		return
	var inhaling := is_inhaling()
	var blend := _breath_chevron_blend()
	for chevron in [_chevron_nostril_a, _chevron_nostril_b]:
		chevron.set_breath_visual(blend, inhaling)


func _breath_chevron_blend() -> float:
	var half := breath_crossfade_duration * 0.5
	var toward_inhale := is_inhaling()
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


func _amplitude_for_duration(total_sec: float) -> float:
	var min_total := inhale_sec_min + exhale_sec_min
	var max_total := inhale_sec_max + exhale_sec_max
	var t := clampf((total_sec - min_total) / maxf(max_total - min_total, 0.001), 0.0, 1.0)
	return lerpf(chest_amplitude_min, chest_amplitude_max, t)


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
