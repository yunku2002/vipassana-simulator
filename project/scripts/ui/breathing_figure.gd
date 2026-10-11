class_name BreathingFigure
extends Control

## Design-space size of sitting.svg (viewBox / mesh).
const DESIGN_SIZE := 1024.0

## Scale of the internal skeleton (0.5 = full-stage size → 512px texture). Use ~0.3 for corner HUD.
@export_range(0.05, 1.0) var rig_display_scale: float = 0.5

@onready var _rig: BreathingRig = $RigRoot
@onready var _body_mesh: Polygon2D = $RigRoot/BodyMesh
@onready var _bone_neck: Bone2D = $RigRoot/Skeleton/BoneNavel/BoneShoulder/BoneNeck

## Mesh UV in design space (from the scene); captured before the first scale.
var _uv_design: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_rig.scale = Vector2.ONE * rig_display_scale
	_uv_design = _body_mesh.uv
	_apply_sitting_texture()


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


func _apply_sitting_texture() -> void:
	# 1:1 with on-screen size: mesh is DESIGN_SIZE units, drawn at rig_display_scale.
	var svg := FileAccess.get_file_as_string("res://assets/sitting.svg")
	var img := SvgRaster.rasterize(svg, rig_display_scale)
	_body_mesh.texture = ImageTexture.create_from_image(img)
	var uv_scale := float(img.get_width()) / DESIGN_SIZE
	var uvs := PackedVector2Array()
	uvs.resize(_uv_design.size())
	for i in _uv_design.size():
		uvs[i] = _uv_design[i] * uv_scale
	_body_mesh.uv = uvs
