class_name BreathingFigure
extends Control

## Scale of the internal skeleton (0.5 = current full-stage size). Use ~0.2–0.3 for a corner HUD.
@export_range(0.05, 1.0) var rig_display_scale: float = 0.5

@onready var _rig: BreathingRig = $RigRoot
@onready var _bone_neck: Bone2D = $RigRoot/Skeleton/BoneNavel/BoneShoulder/BoneNeck


func _ready() -> void:
	_rig.scale = Vector2.ONE * rig_display_scale


func get_rig() -> BreathingRig:
	return _rig


func get_head_global_position() -> Vector2:
	if _bone_neck == null:
		return global_position
	var tip: Vector2 = Vector2.from_angle(deg_to_rad(_bone_neck.bone_angle)) * _bone_neck.length
	return _bone_neck.to_global(tip)


func start_breathing() -> void:
	_rig.start()


func stop_breathing() -> void:
	_rig.stop()
