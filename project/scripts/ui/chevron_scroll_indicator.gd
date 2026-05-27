@tool
extends Control
class_name ChevronScrollIndicator

## Gap added to chevron_height for scroll pitch (negative = overlap).
@export var chevron_spacing: float = 0.0
## Pixel height of each chevron shape (sets baked texture height).
@export var chevron_height: float = 5.0
## Stroke thickness in logical pixels (same units as [member chevron_height]).
@export_range(0.05, 2.0, 0.05, "or_greater") var chevron_thickness: float = 0.5
## Scroll speed in pixels per second.
@export var scroll_speed: float = 10.0
## Tilt in degrees (positive = clockwise). Rotates around the rect center.
@export_range(-45.0, 45.0) var tilt_degrees: float = 0.0
## Fade band at top/bottom of the box (where chevrons scroll in/out), in pixels.
@export_range(0.0, 16.0, 0.5) var edge_fade_pixels: float = 2.0

const _THICKNESS_STEP := 0.05
const _AA := 0.75
const _COLOR_IN := Color(0.78, 0.25, 0.22)
const _COLOR_OUT := Color(0.22, 0.42, 0.71)
const _EDITOR_FILL := Color(1.0, 0.62, 0.12, 0.1)
const _EDITOR_OUTLINE := Color(1.0, 0.62, 0.12, 0.85)

var _blend: float = 1.0
var _inhaling: bool = true
var _scroll_offset: float = 0.0
var _chevron_tex: ImageTexture
var _built_thickness: float = -1.0
var _built_tex_w: int = -1
var _built_tex_h: int = -1


func _ready() -> void:
	set_process(true)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	modulate = _COLOR_IN


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _edge_alpha_at_y(y: float) -> float:
	if edge_fade_pixels <= 0.0:
		return 1.0
	var fade := edge_fade_pixels
	return minf(smoothstep(0.0, fade, y), smoothstep(0.0, fade, size.y - y))


func _baked_thickness() -> float:
	return snappedf(chevron_thickness, _THICKNESS_STEP)


func _sync_texture_if_needed() -> void:
	var tex_w := maxi(ceili(size.x), 2)
	var tex_h := maxi(ceili(chevron_height), 2)
	var stroke := _baked_thickness()
	if (
		_chevron_tex != null
		and _built_tex_w == tex_w
		and _built_tex_h == tex_h
		and is_equal_approx(_built_thickness, stroke)
	):
		return
	_built_thickness = stroke
	_built_tex_w = tex_w
	_built_tex_h = tex_h
	_chevron_tex = _make_chevron_texture(stroke, tex_w, tex_h)


func set_breath_visual(blend: float, inhaling: bool) -> void:
	_blend = clampf(blend, 0.0, 1.0)
	_inhaling = inhaling


func _process(delta: float) -> void:
	_scroll_offset += (1.0 if _inhaling else -1.0) * maxf(scroll_speed, 0.0) * delta
	if not Engine.is_editor_hint():
		modulate = _COLOR_OUT.lerp(_COLOR_IN, _blend)
	queue_redraw()


func _draw() -> void:
	_sync_texture_if_needed()
	var center := size * 0.5
	var half := size * 0.5
	var angle := deg_to_rad(tilt_degrees)
	if Engine.is_editor_hint():
		var c := PackedVector2Array([
			center + Vector2(-half.x, -half.y).rotated(angle),
			center + Vector2(half.x, -half.y).rotated(angle),
			center + Vector2(half.x, half.y).rotated(angle),
			center + Vector2(-half.x, half.y).rotated(angle),
		])
		draw_colored_polygon(c, _EDITOR_FILL)
		c.append(c[0])
		draw_polyline(c, _EDITOR_OUTLINE, 2.0, true)
	if _chevron_tex == null:
		return
	var tex_size := _chevron_tex.get_size()
	var draw_size := Vector2(maxf(size.x, 1.0), maxf(chevron_height, 1.0))
	var tex_scale := Vector2(draw_size.x / tex_size.x, draw_size.y / tex_size.y)
	var step := maxf(chevron_height + chevron_spacing, 0.5)
	var rot := Transform2D(angle, center)
	var start_i := int(floor(_scroll_offset / step)) - 1
	var end_i := int(ceil((_scroll_offset + size.y) / step)) + 2
	var fade_pad := edge_fade_pixels
	var strips := maxi(ceili(draw_size.y), 1)
	var strip_draw_h := draw_size.y / float(strips)
	var strip_tex_h := tex_size.y / float(strips)
	for i in range(start_i, end_i):
		var y_top := (float(i) * step) - _scroll_offset + (step - draw_size.y) * 0.5
		if y_top + draw_size.y < -fade_pad or y_top > size.y + fade_pad:
			continue
		var pos := Vector2((size.x - draw_size.x) * 0.5 - center.x, y_top - center.y)
		for up: bool in [false, true]:
			var layer_alpha: float = _blend if up else 1.0 - _blend
			if layer_alpha <= 0.004:
				continue
			for s in strips:
				var sy := float(s) * strip_draw_h
				var control_y := y_top + sy + strip_draw_h * 0.5
				var alpha := layer_alpha * _edge_alpha_at_y(control_y)
				if alpha <= 0.004:
					continue
				var tex_y := float(s) * strip_tex_h
				if not up:
					tex_y = tex_size.y - tex_y - strip_tex_h
				var src := Rect2(0.0, tex_y, tex_size.x, strip_tex_h)
				var dst := Rect2(0.0, sy, draw_size.x, strip_draw_h)
				var xf := rot * Transform2D(0.0, pos) * Transform2D().scaled(tex_scale)
				draw_set_transform_matrix(xf)
				draw_texture_rect_region(_chevron_tex, dst, src, Color(1, 1, 1, alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)


static func _segment_sdf(p: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length() - r


static func _chevron_sdf(p: Vector2, half_w: float, arm_half: float, stroke: float) -> float:
	var apex := Vector2(0.0, -arm_half)
	return minf(
		_segment_sdf(p, Vector2(-half_w, arm_half), apex, stroke),
		_segment_sdf(p, Vector2(half_w, arm_half), apex, stroke),
	)


func _make_chevron_texture(stroke: float, logic_w: int, logic_h: int) -> ImageTexture:
	# Bake at texture resolution so each 0.05 thickness step is one logical pixel, not lost in downscale.
	var half_w := maxf(logic_w * 0.5 - stroke * 0.55, stroke)
	var arm_half := maxf(float(logic_h) * 0.5 - stroke * 0.85, stroke * 1.1)
	var img := Image.create(logic_w, logic_h, false, Image.FORMAT_RGBA8)
	for y in logic_h:
		for x in logic_w:
			var pos := Vector2(x + 0.5 - logic_w * 0.5, y + 0.5 - logic_h * 0.5)
			var alpha := 1.0 - smoothstep(0.0, _AA, _chevron_sdf(pos, half_w, arm_half, stroke))
			if alpha < 0.004:
				continue
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(img)
