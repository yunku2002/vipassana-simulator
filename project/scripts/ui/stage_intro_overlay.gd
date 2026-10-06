extends CanvasLayer

class_name StageIntroOverlay

signal finished

const SCENE := preload("res://scenes/stage_intro_overlay.tscn")

@onready var _stage_title: Label = $Center/Panel/Margin/VBox/StageTitle
@onready var _goal: Label = $Center/Panel/Margin/VBox/Goal
@onready var _instructions_block: VBoxContainer = $Center/Panel/Margin/VBox/InstructionsBlock
@onready var _btn_learn_more: Button = $Center/Panel/Margin/VBox/ActionsRow/BtnLearnMore
@onready var _btn_continue: Button = $Center/Panel/Margin/VBox/ActionsRow/BtnContinue
@onready var _intro_root: Control = $Center
@onready var _background_root: CenterContainer = $BackgroundView
@onready var _background_title: Label = $BackgroundView/Panel/Margin/VBox/BackgroundTitle
@onready var _background_block: VBoxContainer = $BackgroundView/Panel/Margin/VBox/Scroll/BackgroundBlock
@onready var _btn_background_back: Button = $BackgroundView/Panel/Margin/VBox/BtnBackgroundBack
@onready var _body_label_template: Label = $BodyLabelTemplate

var _stage_prefix: String = ""
var _paused_by_self: bool = false


static func open(parent: Node, stage_prefix: String) -> StageIntroOverlay:
	var overlay: StageIntroOverlay = SCENE.instantiate()
	overlay._stage_prefix = stage_prefix
	parent.add_child(overlay)
	return overlay


func _ready() -> void:
	_body_label_template.visible = false
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_self = true
	_btn_learn_more.pressed.connect(_on_learn_more_pressed)
	_btn_continue.pressed.connect(_on_continue_pressed)
	_btn_background_back.pressed.connect(_hide_background)
	_background_root.hide()
	_apply_content()
	_refresh_texts()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_content()
		_refresh_texts()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _background_root.visible:
		_hide_background()
	else:
		_on_continue_pressed()
	get_viewport().set_input_as_handled()


func _apply_content() -> void:
	_stage_title.text = tr(_stage_prefix)
	_goal.text = _keep_korean_words(tr(_goal_key()))

	var instructions := _translate_optional(_instructions_key())
	_fill_paragraphs(_instructions_block, instructions)
	_instructions_block.visible = not instructions.is_empty()

	var has_background := not _translate_optional(_background_key()).is_empty()
	_btn_learn_more.visible = has_background


func _refresh_texts() -> void:
	_btn_learn_more.text = tr("BTN_LEARN_MORE")
	_btn_continue.text = tr("BTN_CONTINUE")
	_background_title.text = tr("STAGE_INTRO_BACKGROUND_TITLE")
	_btn_background_back.text = tr("BTN_BACK")


## Hangul syllables are legal line breaks, so a Korean word can split even in word
## wrap. A word joiner between syllables leaves the spaces as the only breaks.
func _keep_korean_words(text: String) -> String:
	if not TranslationServer.get_locale().begins_with("ko"):
		return text
	var out := ""
	var prev_hangul := false
	for i in text.length():
		var ch := text[i]
		var hangul := _is_hangul(ch)
		if hangul and prev_hangul:
			out += "\u2060"
		out += ch
		prev_hangul = hangul
	return out


func _is_hangul(ch: String) -> bool:
	var code := ch.unicode_at(0)
	return code >= 0xAC00 and code <= 0xD7A3


func _goal_key() -> String:
	return "%s_GOAL" % _stage_prefix


func _instructions_key() -> String:
	return "%s_INSTRUCTIONS" % _stage_prefix


func _background_key() -> String:
	return "%s_BACKGROUND" % _stage_prefix


func _translate_optional(key: String) -> String:
	var text := tr(key)
	if text == key:
		return ""
	return text


func _fill_paragraphs(container: VBoxContainer, text: String) -> void:
	for child in container.get_children():
		child.queue_free()
	for paragraph in _split_paragraphs(text):
		var label: Label = _body_label_template.duplicate() as Label
		label.visible = true
		label.text = paragraph
		container.add_child(label)


func _split_paragraphs(text: String) -> Array[String]:
	# Paragraph breaks are represented by an empty line in the runtime string,
	# which corresponds to `\n\n` in PO strings.
	#
	# Single `\n` stays inside the same paragraph (same label), so only `\n\n`
	# produces vertical spacing (because we create a new Label per paragraph).
	var normalized := text.replace("\r\n", "\n")
	# allow_empty = true so blank lines (from \n\n) are preserved for paragraph detection
	var lines := normalized.split("\n", true)

	var out: Array[String] = []
	var buf: Array[String] = []
	for line in lines:
		if line.strip_edges().is_empty():
			if not buf.is_empty():
				out.append("\n".join(buf))
				buf.clear()
		else:
			buf.append(line)

	if not buf.is_empty():
		out.append("\n".join(buf))

	return out


func _on_learn_more_pressed() -> void:
	_fill_paragraphs(_background_block, tr(_background_key()))
	_intro_root.hide()
	_background_root.show()


func _hide_background() -> void:
	_background_root.hide()
	_intro_root.show()


func _on_continue_pressed() -> void:
	if _paused_by_self:
		get_tree().paused = false
	finished.emit()
	queue_free()
