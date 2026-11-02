class_name StageShell
extends Control

const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"

## Scene file for this stage (used for registry index and continue flow).
@export_file("*.tscn") var stage_scene_path: String = ""
## Translation prefix, e.g. STAGE_ANAPANA_1 (goal/instructions use _GOAL suffix via overlay).
@export var intro_prefix: String = ""

signal intro_finished

@onready var _btn_instructions: Button = $Margin/Body/CornerButtons/BtnInstructions
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

var intro_blocking: bool = true
var cleared: bool = false


func _ready() -> void:
	_win_layer.hide()
	_confirm_layer.hide()
	if not stage_scene_path.is_empty():
		GameSettings.set_next_stage(stage_index())
	_btn_instructions.pressed.connect(_on_instructions_pressed)
	_btn_options.pressed.connect(_on_options_pressed)
	_btn_main_menu.pressed.connect(_on_main_menu_pressed)
	_btn_confirm_cancel.pressed.connect(_hide_exit_confirm)
	_btn_confirm_ok.pressed.connect(_go_to_main_menu)
	_btn_continue.pressed.connect(_on_continue_pressed)
	_btn_menu.pressed.connect(_go_to_main_menu)
	_refresh_shell_texts()
	if not intro_prefix.is_empty():
		var intro := StageIntroOverlay.open(self, intro_prefix)
		intro.finished.connect(_on_intro_finished)
	else:
		_on_intro_finished()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_shell_texts()


func _refresh_shell_texts() -> void:
	_btn_instructions.text = tr("BTN_INSTRUCTIONS")
	_btn_options.text = tr("BTN_OPTIONS")
	_btn_main_menu.text = tr("BTN_MENU")
	_confirm_title.text = tr("CONFIRM_EXIT_TITLE")
	_btn_confirm_cancel.text = tr("BTN_CANCEL")
	_btn_confirm_ok.text = tr("BTN_MENU")
	_win_title.text = tr("STAGE_CLEAR")
	_btn_continue.text = tr("BTN_CONTINUE")
	_btn_menu.text = tr("BTN_MENU")
	_refresh_gameplay_texts()


## Stage-specific labels. Refreshed together with the shell's labels.
func _refresh_gameplay_texts() -> void:
	pass


func _on_intro_finished() -> void:
	intro_blocking = false
	intro_finished.emit()


func is_gameplay_blocked() -> bool:
	return intro_blocking or cleared


func stage_index() -> int:
	return StageRegistry.index_for_scene(stage_scene_path)


func mark_cleared() -> void:
	if cleared:
		return
	cleared = true
	GameSettings.set_next_stage_after(stage_index())
	_win_layer.show()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_gameplay_blocked():
		return
	if _confirm_layer.visible:
		_hide_exit_confirm()
	else:
		_show_exit_confirm()
	get_viewport().set_input_as_handled()


func _on_continue_pressed() -> void:
	var next_index := stage_index() + 1
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


func _on_instructions_pressed() -> void:
	if intro_blocking or intro_prefix.is_empty():
		return
	StageIntroOverlay.open(self, intro_prefix)


func _on_options_pressed() -> void:
	OptionOverlay.open(self)
