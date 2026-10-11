class_name HeadFocus
extends Control

## Zoomed head crop with a darkened surround and dynamically spawned sensation circles.

const _SvgPath := preload("res://scripts/other/svg_path.gd")

signal region_pressed(region_id: int)

## Square head crop in design pixels (sitting.svg / mouth.svg; mask is 1024²).
const HEAD_SIZE := 256.0
const HEAD_ATLAS := Rect2(512.0 - HEAD_SIZE * 0.5, 345.0 - HEAD_SIZE, HEAD_SIZE, HEAD_SIZE)
## On-screen size of the head crop (1:1 with the cropped raster).
const DISPLAY_SIZE := Vector2(1280, 1280)
## Cancels StageShell's bottom margin so the control is flush with the screen.
const BOTTOM_OVERFLOW := 24.0

const _REGION_ACTIVE := Color(1.0, 0.88, 0.15, 0.55)
## Soft edge as a fraction of the circle radius (0 = hard, ~0.25 = soft).
const _REGION_FEATHER := 0.28
const _SPAWN_ATTEMPTS := 24

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

var _dim_mask_path: String = ""
var _region_radius_min: float
var _region_radius_max: float

var _region_material: ShaderMaterial
var _input_blocked: bool = false
var _next_region_id: int = 1

## Vector outline of the focus hole (smallest closed subpath in the mask SVG).
var _hole_poly: PackedVector2Array = PackedVector2Array()
var _hole_ready: bool = false
var _hole_bounds: Rect2 = Rect2()

## id -> {holder, rect, mark, center: Vector2, radius: float, busy: bool, tween?: Tween}
var _regions: Dictionary = {}


func configure(mask_path: String, radius_min: float, radius_max: float) -> void:
	_dim_mask_path = mask_path
	_region_radius_min = radius_min
	_region_radius_max = radius_max


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = DISPLAY_SIZE
	offset_left = -DISPLAY_SIZE.x / 2.0
	offset_right = DISPLAY_SIZE.x / 2.0
	offset_bottom = BOTTOM_OVERFLOW
	offset_top = BOTTOM_OVERFLOW - DISPLAY_SIZE.y
	_region_material = _make_region_material()
	_setup_textures()
	resized.connect(_layout_focus)
	_layout_focus()


## Cached atlas glyph, centered by texture box in the mark control.
class _GlyphMark extends Control:
	## Vector2i(font_size, code) -> Texture2D
	static var _cache: Dictionary = {}

	var text: String = ""
	var font_size: int = 0
	var _tex: Texture2D

	func refresh() -> void:
		_tex = null
		if text.length() == 1:
			var font := _label_font()
			if font != null:
				_tex = _texture_for(font, font_size, text.unicode_at(0))
		queue_redraw()

	func _draw() -> void:
		var color := get_theme_color("font_color", "Label")
		if text.length() > 1:
			var font := _label_font()
			if font == null:
				return
			var s := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var pos := Vector2((size.x - s.x) * 0.5, (size.y - s.y) * 0.5 + font.get_ascent(font_size))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
			return
		if _tex == null:
			return
		var tex_size := Vector2(_tex.get_width(), _tex.get_height())
		draw_texture_rect(_tex, Rect2((size - tex_size) * 0.5, tex_size), false, color)

	func _label_font() -> Font:
		var font := get_theme_font("font", "Label")
		return font if font != null else ThemeDB.fallback_font

	static func _texture_for(font: Font, p_font_size: int, code: int) -> Texture2D:
		var key := Vector2i(p_font_size, code)
		if _cache.has(key):
			return _cache[key]
		var tex := _bake(font, p_font_size, code)
		if tex != null:
			_cache[key] = tex
		return tex

	static func _bake(font: Font, p_font_size: int, code: int) -> Texture2D:
		font.get_char_size(code, p_font_size)
		var font_file := font as FontFile
		if font_file == null and font is FontVariation:
			font_file = (font as FontVariation).base_font as FontFile
		if font_file == null:
			return null
		var glyph := font_file.get_glyph_index(p_font_size, code, 0)
		var sized := Vector2i(p_font_size, 0)
		var tex_idx := font_file.get_glyph_texture_idx(0, sized, glyph)
		if tex_idx < 0:
			return null
		var uv := font_file.get_glyph_uv_rect(0, sized, glyph)
		var atlas := font_file.get_texture_image(0, sized, tex_idx)
		if atlas == null or uv.size.x < 1.0 or uv.size.y < 1.0:
			return null
		## Don't convert the font's live atlas in place — that breaks its ImageTexture format.
		atlas = atlas.duplicate()
		if atlas.get_format() != Image.FORMAT_RGBA8:
			atlas.convert(Image.FORMAT_RGBA8)
		var x0 := clampi(int(floor(uv.position.x)), 0, atlas.get_width() - 1)
		var y0 := clampi(int(floor(uv.position.y)), 0, atlas.get_height() - 1)
		var x1 := clampi(int(ceil(uv.position.x + uv.size.x)), 0, atlas.get_width())
		var y1 := clampi(int(ceil(uv.position.y + uv.size.y)), 0, atlas.get_height())
		var gw := maxi(x1 - x0, 1)
		var gh := maxi(y1 - y0, 1)
		var glyph_img := Image.create(gw, gh, false, Image.FORMAT_RGBA8)
		glyph_img.fill(Color(0, 0, 0, 0))
		glyph_img.blit_rect(atlas, Rect2i(x0, y0, gw, gh), Vector2i.ZERO)
		return ImageTexture.create_from_image(glyph_img)


func set_input_blocked(blocked: bool) -> void:
	_input_blocked = blocked
	_sync_region_input()


## Spawns a circle inside the mask hole. Returns region id, or -1 on failure.
func spawn_region() -> int:
	var pick := _pick_circle()
	if pick.is_empty():
		return -1
	var id := _next_region_id
	_next_region_id += 1
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := ColorRect.new()
	rect.color = _REGION_ACTIVE
	rect.material = _region_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.gui_input.connect(_on_region_input.bind(id))
	var mark := _GlyphMark.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.text = "?"
	holder.add_child(rect)
	holder.add_child(mark)
	add_child(holder)
	_regions[id] = {
		"holder": holder,
		"rect": rect,
		"mark": mark,
		"center": pick.center,
		"radius": pick.radius,
		"busy": false,
	}
	_layout_region(id)
	_sync_region_input()
	return id


func clear_region(region_id: int) -> void:
	if not _regions.has(region_id):
		return
	var data: Dictionary = _regions[region_id]
	if data.busy:
		# Let the success burst animation complete.
		return
	_free_region(region_id)


func play_success_burst(region_id: int, burst_text: String) -> void:
	if not _regions.has(region_id):
		return
	var data: Dictionary = _regions[region_id]
	if data.busy:
		return
	data.busy = true
	_sync_region_input()
	var mark: _GlyphMark = data.mark
	mark.text = burst_text
	mark.refresh()
	mark.pivot_offset = mark.size * 0.5
	var tween := create_tween()
	data.tween = tween
	tween.set_parallel(true)
	tween.tween_property(mark, "scale", Vector2(2.4, 2.4), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(mark, "modulate:a", 0.0, 0.45)
	tween.set_parallel(false)
	tween.tween_callback(_free_region.bind(region_id))


## Axis-aligned bounds of the focus hole, in global (canvas) space.
func get_regions_global_rect() -> Rect2:
	if not _hole_ready or size.x < 1.0:
		return get_global_rect()
	var min_p := _design_to_view(_hole_bounds.position)
	var max_p := _design_to_view(_hole_bounds.position + _hole_bounds.size)
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


func _free_region(region_id: int) -> void:
	if not _regions.has(region_id):
		return
	var data: Dictionary = _regions[region_id]
	var tween: Tween = data.get("tween") as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	var holder: Control = data.holder
	_regions.erase(region_id)
	if is_instance_valid(holder):
		holder.queue_free()
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
	_build_hole()


func _load_dim_mask() -> Image:
	## Dim mask is 1024² (same space as sitting.svg); crop + scale like the head SVG.
	var full := _load_mask_image(_dim_mask_path)
	if full == null:
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


func _load_mask_image(path: String) -> Image:
	if path.is_empty():
		push_error("HeadFocus mask path is empty")
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("Failed to load dim mask: %s" % path)
		return null
	var full := tex.get_image()
	if full == null:
		push_error("%s has no CPU image data" % path)
		return null
	return full


func _build_hole() -> void:
	_hole_poly = PackedVector2Array()
	_hole_ready = false
	_hole_bounds = Rect2()
	var svg_path := _hole_svg_path()
	if svg_path.is_empty():
		push_error("No SVG mask found for focus hole (from %s)" % _dim_mask_path)
		return
	var svg_text := FileAccess.get_file_as_string(svg_path)
	if svg_text.is_empty():
		push_error("Failed to read focus-hole SVG: %s" % svg_path)
		return
	var d := _SvgPath.first_path_d(svg_text)
	if d.is_empty():
		push_error("No path data in focus-hole SVG: %s" % svg_path)
		return
	var subpaths := _SvgPath.parse_closed_subpaths(d)
	_hole_poly = _smallest_subpath(subpaths)
	if _hole_poly.size() < 3:
		push_error("Could not parse focus-hole subpath in: %s" % svg_path)
		return
	_hole_bounds = _SvgPath.bounds(_hole_poly)
	_hole_ready = true


func _hole_svg_path() -> String:
	if _dim_mask_path.ends_with(".svg"):
		return _dim_mask_path
	if _dim_mask_path.ends_with(".png"):
		var svg_path := "%s.svg" % _dim_mask_path.get_basename()
		if FileAccess.file_exists(svg_path):
			return svg_path
	return ""


static func _smallest_subpath(subpaths: Array[PackedVector2Array]) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := INF
	for poly in subpaths:
		var b := _SvgPath.bounds(poly)
		var area := b.get_area()
		## Skip degenerate / full-canvas dim frames.
		if area < 1.0 or area > 1024.0 * 1024.0 * 0.5:
			continue
		if area < best_area:
			best_area = area
			best = poly
	return best


func _pick_circle() -> Dictionary:
	if not _hole_ready or _hole_bounds.size == Vector2.ZERO:
		return {}
	var bb := _hole_bounds
	for attempt in _SPAWN_ATTEMPTS:
		var r := randf_range(_region_radius_min, _region_radius_max)
		var center := Vector2(
			randf_range(bb.position.x, bb.position.x + bb.size.x),
			randf_range(bb.position.y, bb.position.y + bb.size.y)
		)
		if not _SvgPath.point_in_polygon(center, _hole_poly):
			continue
		if _SvgPath.inward_clearance(center, _hole_poly) < r:
			continue
		var blocked := false
		for data in _regions.values():
			if center.distance_to(data.center) < r + data.radius:
				blocked = true
				break
		if blocked:
			continue
		return {"center": center, "radius": r}
	return {}


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


func _layout_focus() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	_head.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for id in _regions.keys():
		if bool(_regions[id].busy):
			continue
		_layout_region(id)


## Map a point in sitting.svg design space into this control (HEAD_ATLAS crop).
func _design_to_view(design: Vector2) -> Vector2:
	var view_scale := size / Vector2(HEAD_SIZE, HEAD_SIZE)
	return (design - HEAD_ATLAS.position) * view_scale


func _layout_region(region_id: int) -> void:
	if not _regions.has(region_id):
		return
	var data: Dictionary = _regions[region_id]
	var view_scale := size.x / HEAD_SIZE
	## Snap to whole pixels so circle + mark share a stable pixel phase.
	## (Fractional positions make live fonts hinter-shift; texture marks stay put too.)
	var center := _design_to_view(data.center).round()
	var diameter := roundf(float(data.radius) * view_scale * 2.0)
	if int(diameter) % 2 == 1:
		diameter += 1.0
	var radius := diameter * 0.5
	var holder: Control = data.holder
	var mark: _GlyphMark = data.mark
	holder.size = Vector2(diameter, diameter)
	holder.position = center - Vector2(radius, radius)
	mark.font_size = clampi(int(radius * 0.9), 14, 48)
	mark.refresh()


func _sync_region_input() -> void:
	for id in _regions.keys():
		var data: Dictionary = _regions[id]
		var can_press: bool = not _input_blocked and not bool(data.busy)
		var rect: ColorRect = data.rect
		rect.mouse_filter = Control.MOUSE_FILTER_STOP if can_press else Control.MOUSE_FILTER_IGNORE


func _on_region_input(event: InputEvent, region_id: int) -> void:
	if not _regions.has(region_id):
		return
	var data: Dictionary = _regions[region_id]
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var rect: ColorRect = data.rect
	if not _point_in_circle(mb.position, rect.size):
		return
	get_viewport().set_input_as_handled()
	region_pressed.emit(region_id)


static func _point_in_circle(local: Vector2, rect_size: Vector2) -> bool:
	var center := rect_size * 0.5
	var n := (local - center) / center.max(Vector2.ONE * 0.001)
	return n.length() <= 1.0
