class_name SensationFocus
extends Control

## Zoomed head crop with a darkened surround and interactive sensation regions.

signal region_activated(region_index: int)
signal region_expired(region_index: int)
signal region_pressed(region_index: int)

## Square head crop in design pixels (sitting.svg / mouth.svg; mask is 1024² PNG).
const HEAD_SIZE := 256.0
const HEAD_ATLAS := Rect2(512.0 - HEAD_SIZE * 0.5, 345.0 - HEAD_SIZE, HEAD_SIZE, HEAD_SIZE)
## On-screen size of the head crop (1:1 with the cropped raster).
const DISPLAY_SIZE := Vector2(1280, 1280)
## Cancels StageShell's bottom margin so the control is flush with the screen.
const BOTTOM_OVERFLOW := 24.0

const _REGION_IDLE := Color(1.0, 1.0, 1.0, 0.0)
const _REGION_ACTIVE := Color(1.0, 0.88, 0.15, 0.55)
## Soft edge as a fraction of the ellipse radius (0 = hard, ~0.25 = soft).
const _REGION_FEATHER := 0.28
const _MARK_FONT_SIZE := 36

const _REGION_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform float feather : hint_range(0.0, 1.0) = 0.28;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = 1.0 - smoothstep(1.0 - feather, 1.0, d);
	COLOR = vec4(COLOR.rgb, COLOR.a * a);
}
"""

@onready var _head: TextureRect = $HeadTexture
@onready var _dim: TextureRect = $DimOverlay

var _regions: Array[ColorRect] = []
var _region_material: ShaderMaterial
var _region_active: Array[bool] = []
var _region_busy: Array[bool] = []
var _marks: Array[Label] = []
var _input_blocked: bool = false

## Rotated ellipses in sitting.svg design space (1024²). Add/remove entries freely.
## Inkscape: radii/center from Object Properties; deg from Select tool R (or Transform).
##   cx, cy = center; rx, ry = radii; deg = rotation degrees
static var region_layout: Array[Dictionary] = [
	{"cx": 505.25, "cy": 259.50, "rx": 8.00, "ry": 7.50, "deg": -20},
	{"cx": 518.75, "cy": 259.50, "rx": 8.00, "ry": 7.50, "deg": 20},
	{"cx": 498.00, "cy": 269.75, "rx": 8.75, "ry": 7.25, "deg": 20},
	{"cx": 512.00, "cy": 270.25, "rx": 8.25, "ry": 7.75, "deg": 0},
	{"cx": 526.00, "cy": 269.75, "rx": 8.75, "ry": 7.25, "deg": -20},
	{"cx": 494.50, "cy": 279.50, "rx": 6.75, "ry": 6.25, "deg": 15},
	{"cx": 506.00, "cy": 280.25, "rx": 7.00, "ry": 6.25, "deg": 0},
	{"cx": 518.00, "cy": 280.25, "rx": 7.00, "ry": 6.25, "deg": 0},
	{"cx": 529.50, "cy": 279.50, "rx": 6.75, "ry": 6.25, "deg": -15},
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = DISPLAY_SIZE
	offset_left = -DISPLAY_SIZE.x / 2.0
	offset_right = DISPLAY_SIZE.x / 2.0
	offset_bottom = BOTTOM_OVERFLOW
	offset_top = BOTTOM_OVERFLOW - DISPLAY_SIZE.y
	_region_material = _make_region_material()
	_setup_textures()
	_build_regions()
	resized.connect(_layout_focus)
	_layout_focus()


func is_awaiting_press() -> bool:
	for i in _regions.size():
		if i >= _region_active.size():
			break
		if _region_active[i] and not _region_busy[i]:
			return true
	return false


func is_resolving() -> bool:
	for i in _regions.size():
		if i >= _region_busy.size():
			break
		if _region_busy[i]:
			return true
	return false


func set_input_blocked(blocked: bool) -> void:
	_input_blocked = blocked
	_sync_region_input()


func activate_region(index: int) -> void:
	if index < 0 or index >= _regions.size():
		return
	_region_active[index] = true
	_region_busy[index] = false
	_regions[index].color = _REGION_ACTIVE
	var mark := _marks[index]
	mark.text = "?"
	mark.modulate = Color.WHITE
	mark.scale = Vector2.ONE
	mark.visible = true
	# Keep the mark centered on the ellipse pivot without rotating it with the ellipse.
	var region := _regions[index]
	mark.size = region.size
	mark.pivot_offset = region.pivot_offset
	mark.position = region.position
	_sync_region_input()
	region_activated.emit(index)


func clear_region(index: int) -> void:
	if index < 0 or index >= _regions.size():
		return
	if _region_busy.size() > 0 and _region_busy[index]:
		# Let the success burst animation complete.
		return
	if not _region_active[index]:
		return
	_region_active[index] = false
	_regions[index].color = _REGION_IDLE
	var mark := _marks[index]
	mark.visible = false
	mark.scale = Vector2.ONE
	mark.modulate = Color.WHITE
	mark.text = "?"
	_sync_region_input()
	region_expired.emit(index)


func play_success_burst(index: int) -> void:
	if index < 0 or index >= _regions.size():
		return
	if not _region_active[index] or _region_busy[index]:
		return
	_region_busy[index] = true
	_sync_region_input()
	var mark := _marks[index]
	mark.text = "!"
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mark, "scale", Vector2(2.4, 2.4), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(mark, "modulate:a", 0.0, 0.45)
	tween.set_parallel(false)
	tween.tween_callback(_finish_success_burst.bind(index))


func _finish_success_burst(index: int) -> void:
	if index < 0 or index >= _regions.size():
		return
	_region_active[index] = false
	_region_busy[index] = false
	_regions[index].color = _REGION_IDLE
	var mark := _marks[index]
	mark.visible = false
	mark.scale = Vector2.ONE
	mark.modulate = Color.WHITE
	mark.text = "?"
	_sync_region_input()


func _setup_textures() -> void:
	var svg_scale := DISPLAY_SIZE.x / HEAD_SIZE
	var sitting := FileAccess.get_file_as_string("res://assets/sitting.svg")
	var mouth := FileAccess.get_file_as_string("res://assets/mouth.svg")
	var head := SvgRaster.rasterize_crop(sitting, HEAD_ATLAS, svg_scale)
	var mouth_img := SvgRaster.rasterize_crop(mouth, HEAD_ATLAS, svg_scale)
	head.blend_rect(mouth_img, Rect2i(Vector2i.ZERO, mouth_img.get_size()), Vector2i.ZERO)
	var dim := _load_dim_mask()
	_clip_dim_to_head(dim, head)
	_configure_texture_rect(_head, ImageTexture.create_from_image(head))
	_configure_texture_rect(_dim, ImageTexture.create_from_image(dim))


func _load_dim_mask() -> Image:
	## mask_nostrils.png is 1024² (same space as sitting.svg); crop + scale like the head SVG.
	var tex := load("res://assets/mask_nostrils.png") as Texture2D
	if tex == null:
		push_error("Failed to load mask_nostrils.png")
		return Image.create(int(DISPLAY_SIZE.x), int(DISPLAY_SIZE.y), false, Image.FORMAT_RGBA8)
	var full := tex.get_image()
	if full == null:
		push_error("mask_nostrils.png has no CPU image data")
		return Image.create(int(DISPLAY_SIZE.x), int(DISPLAY_SIZE.y), false, Image.FORMAT_RGBA8)
	var crop := Rect2i(
		int(HEAD_ATLAS.position.x),
		int(HEAD_ATLAS.position.y),
		int(HEAD_ATLAS.size.x),
		int(HEAD_ATLAS.size.y)
	)
	var dim := full.get_region(crop)
	dim.resize(int(DISPLAY_SIZE.x), int(DISPLAY_SIZE.y), Image.INTERPOLATE_TRILINEAR)
	return dim


func _configure_texture_rect(rect: TextureRect, texture: Texture) -> void:
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Keep dim only where the head has coverage (avoids a dark square around the silhouette).
static func _clip_dim_to_head(dim: Image, head: Image) -> void:
	if dim.get_size() != head.get_size():
		return
	if dim.get_format() != Image.FORMAT_RGBA8:
		dim.convert(Image.FORMAT_RGBA8)
	if head.get_format() != Image.FORMAT_RGBA8:
		head.convert(Image.FORMAT_RGBA8)
	var d := dim.get_data()
	var h := head.get_data()
	for i in range(3, d.size(), 4):
		d[i] = int(float(d[i]) * float(h[i]) / 255.0)
	dim.set_data(dim.get_width(), dim.get_height(), false, Image.FORMAT_RGBA8, d)


func _make_region_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _REGION_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("feather", _REGION_FEATHER)
	return mat


func _build_regions() -> void:
	for rect in _regions:
		rect.queue_free()
	_regions.clear()
	for i in region_layout.size():
		var rect := ColorRect.new()
		rect.color = _REGION_IDLE
		rect.material = _region_material
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.gui_input.connect(_on_region_input.bind(i))
		add_child(rect)
		_regions.append(rect)
	# Prepare per-region state and per-region non-rotating marks.
	_region_active.clear()
	_region_busy.clear()
	for _i in _regions.size():
		_region_active.append(false)
		_region_busy.append(false)

	for mark in _marks:
		mark.queue_free()
	_marks.clear()
	for _i in _regions.size():
		var mark := Label.new()
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.add_theme_font_size_override("font_size", _MARK_FONT_SIZE)
		mark.text = "?"
		mark.modulate = Color.WHITE
		mark.scale = Vector2.ONE
		mark.visible = false
		add_child(mark)
		_marks.append(mark)


func _layout_focus() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	_head.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout_regions()
	_layout_marks()


## Map a point in sitting.svg design space into this control (HEAD_ATLAS crop).
func _design_to_view(design: Vector2) -> Vector2:
	var view_scale := size / Vector2(HEAD_SIZE, HEAD_SIZE)
	return (design - HEAD_ATLAS.position) * view_scale


func _layout_regions() -> void:
	var view_scale := size.x / HEAD_SIZE
	for i in _regions.size():
		if i >= region_layout.size():
			return
		var e: Dictionary = region_layout[i]
		var center := _design_to_view(Vector2(float(e.cx), float(e.cy)))
		var radii := Vector2(float(e.rx), float(e.ry)) * view_scale
		var rect := _regions[i]
		rect.size = radii * 2.0
		rect.pivot_offset = radii
		rect.position = center - radii
		rect.rotation = deg_to_rad(float(e.get("deg", 0.0)))


## Axis-aligned bounds of the sensation-region cluster, in global (canvas) space.
func get_regions_global_rect() -> Rect2:
	if region_layout.is_empty() or size.x < 1.0:
		return get_global_rect()
	var view_scale := size.x / HEAD_SIZE
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for e in region_layout:
		var center := _design_to_view(Vector2(float(e.cx), float(e.cy)))
		## Max radius covers rotated ellipses without needing full OBB math.
		var pad := maxf(float(e.rx), float(e.ry)) * view_scale
		min_p = min_p.min(center - Vector2(pad, pad))
		max_p = max_p.max(center + Vector2(pad, pad))
	var xform := get_global_transform_with_canvas()
	var corners: Array[Vector2] = [
		xform * min_p,
		xform * Vector2(max_p.x, min_p.y),
		xform * max_p,
		xform * Vector2(min_p.x, max_p.y),
	]
	var g_min := corners[0]
	var g_max := corners[0]
	for c in corners:
		g_min = g_min.min(c)
		g_max = g_max.max(c)
	return Rect2(g_min, g_max - g_min)


func _layout_marks() -> void:
	var n: int = mini(_regions.size(), _marks.size())
	for i in n:
		var region := _regions[i]
		var mark := _marks[i]
		mark.size = region.size
		mark.pivot_offset = region.pivot_offset
		mark.position = region.position


func _sync_region_input() -> void:
	for i in _regions.size():
		var can_press := not _input_blocked and _region_active[i] and not _region_busy[i]
		_regions[i].mouse_filter = Control.MOUSE_FILTER_STOP if can_press else Control.MOUSE_FILTER_IGNORE


func _on_region_input(event: InputEvent, index: int) -> void:
	if _input_blocked:
		return
	if index < 0 or index >= _regions.size():
		return
	if not _region_active[index] or _region_busy[index]:
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if not _point_in_ellipse(mb.position, _regions[index].size):
		return
	get_viewport().set_input_as_handled()
	region_pressed.emit(index)


static func _point_in_ellipse(local: Vector2, rect_size: Vector2) -> bool:
	var center := rect_size * 0.5
	var n := (local - center) / center.max(Vector2.ONE * 0.001)
	return n.length() <= 1.0
