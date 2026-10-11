extends Control

@onready var _title: Label = $Margin/VBox/Title
@onready var _list: VBoxContainer = $Margin/VBox/Stages/List
@onready var _back: Button = $Margin/VBox/BtnBack


func _ready() -> void:
	_back.pressed.connect(_on_back_pressed)
	_populate_list()
	_refresh_texts()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()
		_refresh_list_labels()


func _refresh_texts() -> void:
	_title.text = tr("BTN_STAGE_SELECT")
	_back.text = tr("BTN_BACK")


func _populate_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for i in StageRegistry.stage_count():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(280, 48)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.text = tr(StageRegistry.stage_prefix(i))
		btn.pressed.connect(_on_pick_stage.bind(i))
		_list.add_child(btn)


func _refresh_list_labels() -> void:
	for i in range(mini(StageRegistry.stage_count(), _list.get_child_count())):
		var btn := _list.get_child(i) as Button
		if btn:
			btn.text = tr(StageRegistry.stage_prefix(i))


func _on_pick_stage(stage_index: int) -> void:
	GameSettings.set_next_stage(stage_index)
	get_tree().change_scene_to_file(StageRegistry.scene_path(stage_index))


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
