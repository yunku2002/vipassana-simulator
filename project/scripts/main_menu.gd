extends Control

@onready var _title: Label = $Margin/Center/VBox/Header/Title
@onready var _credit: Label = $Margin/Center/VBox/Header/Credit
@onready var _btn_start: Button = $Margin/Center/VBox/BtnStart
@onready var _btn_stages: Button = $Margin/Center/VBox/BtnStages
@onready var _btn_options: Button = $Margin/Center/VBox/BtnOptions


func _ready() -> void:
	_refresh_texts()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func _refresh_texts() -> void:
	_title.text = tr("APP_TITLE")
	_credit.text = tr("CREDIT_TEXT")
	_btn_start.text = tr("BTN_CONTINUE") if GameSettings.can_continue_from_title() else tr("BTN_START")
	_btn_stages.text = tr("MENU_STAGE_SELECT")
	_btn_options.text = tr("MENU_OPTIONS")


func _on_start_pressed() -> void:
	var stage_index := GameSettings.next_stage_index if GameSettings.can_continue_from_title() else 0
	GameSettings.set_next_stage(stage_index)
	get_tree().change_scene_to_file(StageRegistry.scene_path(stage_index))


func _on_stages_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/stage_select.tscn")


func _on_options_pressed() -> void:
	OptionOverlay.open(self)
