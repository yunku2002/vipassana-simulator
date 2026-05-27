extends Node

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "game"

var master_linear: float = 0.8
var muted: bool = false
var locale: String = "en"
## Index into [StageRegistry.STAGES] for the next stage to launch from title, or -1 when unset.
var next_stage_index: int = -1


func _ready() -> void:
	load_settings()
	_apply_audio()
	_apply_locale()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	master_linear = clampf(cf.get_value(SECTION, "master_linear", master_linear), 0.0, 1.0)
	muted = bool(cf.get_value(SECTION, "muted", muted))
	locale = str(cf.get_value(SECTION, "locale", locale))
	next_stage_index = clampi(int(cf.get_value(SECTION, "next_stage_index", next_stage_index)), -1, StageRegistry.stage_count() - 1)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value(SECTION, "master_linear", master_linear)
	cf.set_value(SECTION, "muted", muted)
	cf.set_value(SECTION, "locale", locale)
	cf.set_value(SECTION, "next_stage_index", next_stage_index)
	cf.save(SETTINGS_PATH)


func can_continue_from_title() -> bool:
	return next_stage_index >= 0 and next_stage_index < StageRegistry.stage_count()


func title_start_scene_path() -> String:
	if can_continue_from_title():
		return StageRegistry.scene_path(next_stage_index)
	return StageRegistry.scene_path(0)


func set_next_stage(index: int) -> void:
	next_stage_index = clampi(index, -1, StageRegistry.stage_count() - 1)
	save_settings()


func set_next_stage_after(index: int) -> void:
	var current_index := clampi(index, -1, StageRegistry.stage_count() - 1)
	if StageRegistry.is_final(current_index):
		set_next_stage(-1)
		return
	set_next_stage(current_index + 1)


func set_master_linear(v: float) -> void:
	master_linear = clampf(v, 0.0, 1.0)
	_apply_audio()
	save_settings()


func set_muted(m: bool) -> void:
	muted = m
	_apply_audio()
	save_settings()


func set_locale(code: String) -> void:
	locale = code if code in ["en", "ko"] else "en"
	_apply_locale()
	save_settings()


func _apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, muted)
	if muted:
		return
	var db := linear_to_db(master_linear)
	AudioServer.set_bus_volume_db(bus, db)


func _apply_locale() -> void:
	TranslationServer.set_locale(locale)
