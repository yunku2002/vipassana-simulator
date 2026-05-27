extends CanvasLayer

class_name OptionOverlay

const SCENE := preload("res://scenes/options_menu.tscn")
const ICON_SOUND_ON := "🔊"
const ICON_SOUND_OFF := "🔇"

@onready var _title: Label = $Center/Panel/Margin/VBox/Title
@onready var _lang_label: Label = $Center/Panel/Margin/VBox/LangRow/LangLabel
@onready var _lang_en: Button = $Center/Panel/Margin/VBox/LangRow/BtnEn
@onready var _lang_ko: Button = $Center/Panel/Margin/VBox/LangRow/BtnKo
@onready var _vol_label: Label = $Center/Panel/Margin/VBox/VolRow/VolLabel
@onready var _slider: HSlider = $Center/Panel/Margin/VBox/VolRow/VolumeSlider
@onready var _mute: Button = $Center/Panel/Margin/VBox/VolRow/BtnMute
@onready var _close: Button = $Center/Panel/Margin/VBox/BtnClose

## True when this overlay was the one to pause the tree, so we only unpause on close
## if we caused the pause (avoid unpausing a parent's own pause state, e.g. exit confirm).
var _paused_by_self: bool = false


static func open(parent: Node) -> void:
	parent.add_child(SCENE.instantiate())


func _ready() -> void:
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_self = true
	_slider.value_changed.connect(_on_slider_changed)
	_mute.toggled.connect(_on_mute_toggled)
	_lang_en.pressed.connect(func() -> void: _set_lang("en"))
	_lang_ko.pressed.connect(func() -> void: _set_lang("ko"))
	_close.pressed.connect(_on_close_pressed)
	_setup_volume_slider()
	_sync_from_settings()
	_refresh_texts()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


func _setup_volume_slider() -> void:
	_slider.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_slider.custom_minimum_size.y = maxf(_slider.custom_minimum_size.y, 28.0)
	_slider.add_theme_icon_override(&"grabber", _make_grabber_icon(false))
	_slider.add_theme_icon_override(&"grabber_highlight", _make_grabber_icon(true))
	_slider.add_theme_icon_override(&"grabber_disabled", _make_grabber_icon(false))


## Matches [StyleBoxFlat_btn_normal] / [StyleBoxFlat_btn_hover] in main_theme.tres.
const _GRABBER_FILL := Color(0.937, 0.835, 0.541, 1)
const _GRABBER_FILL_HOVER := Color(0.969, 0.886, 0.627, 1)
const _GRABBER_BORDER := Color(0.604, 0.482, 0.18, 1)


static func _rounded_rect_sdf(p: Vector2, half: Vector2, corner_r: float) -> float:
	var q: Vector2 = p.abs() - half + Vector2(corner_r, corner_r)
	return minf(maxf(q.x, q.y), 0.0) + Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() - corner_r


static func _make_grabber_icon(hover: bool) -> ImageTexture:
	const LOGIC_W := 12
	const LOGIC_H := 22
	const SUPERSAMPLE := 3
	const W := LOGIC_W * SUPERSAMPLE
	const H := LOGIC_H * SUPERSAMPLE
	const AA := 1.1 * SUPERSAMPLE
	const BORDER := 1.0 * SUPERSAMPLE
	const CORNER := 5.0 * SUPERSAMPLE
	var fill := _GRABBER_FILL_HOVER if hover else _GRABBER_FILL
	var outline := _GRABBER_BORDER
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var center := Vector2(W * 0.5, H * 0.5)
	var half := Vector2(W * 0.5 - 0.5, H * 0.5 - 0.5)
	for y in H:
		for x in W:
			var pos := Vector2(x + 0.5, y + 0.5) - center
			var d := _rounded_rect_sdf(pos, half, CORNER)
			var alpha := 1.0 - smoothstep(0.0, AA, d)
			if alpha < 0.004:
				continue
			var col: Color
			if d < -BORDER:
				col = fill
			elif d < 0.0:
				var t := smoothstep(-BORDER - AA * 0.5, -BORDER + AA * 0.5, d)
				col = fill.lerp(outline, t)
			else:
				col = outline
			img.set_pixel(x, y, Color(col.r, col.g, col.b, alpha))
	if SUPERSAMPLE > 1:
		img.resize(LOGIC_W, LOGIC_H, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func _sync_from_settings() -> void:
	_slider.set_value_no_signal(GameSettings.master_linear * 100.0)
	_mute.set_pressed_no_signal(GameSettings.muted)
	_update_mute_icon()
	_update_lang_buttons()


func _refresh_texts() -> void:
	_title.text = tr("MENU_OPTIONS")
	_lang_label.text = tr("OPTIONS_LANGUAGE")
	_vol_label.text = tr("OPTIONS_VOLUME")
	_close.text = tr("BTN_CLOSE")


func _update_mute_icon() -> void:
	_mute.text = ICON_SOUND_OFF if _mute.button_pressed else ICON_SOUND_ON


func _update_lang_buttons() -> void:
	var loc := GameSettings.locale
	_apply_lang_active(_lang_en, loc == "en")
	_apply_lang_active(_lang_ko, loc == "ko")


func _apply_lang_active(btn: Button, is_active: bool) -> void:
	btn.disabled = is_active
	btn.theme_type_variation = &"ActiveSelection" if is_active else &""


func _set_lang(code: String) -> void:
	GameSettings.set_locale(code)
	_refresh_texts()
	_update_lang_buttons()


func _on_slider_changed(v: float) -> void:
	GameSettings.set_master_linear(v / 100.0)
	if GameSettings.muted:
		GameSettings.set_muted(false)
		_mute.set_pressed_no_signal(false)
		_update_mute_icon()


func _on_mute_toggled(on: bool) -> void:
	GameSettings.set_muted(on)
	_update_mute_icon()


func _on_close_pressed() -> void:
	if _paused_by_self:
		get_tree().paused = false
	queue_free()
