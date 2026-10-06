class_name ThoughtBubble
extends Control

signal reveal_finished

const _CELL_SIZE := 16.0
const _MARGIN_CELLS := 2
const _INNER_COLS := 9
const _INNER_ROWS := 3
const CLOUD_SIZE := Vector2(
	(_INNER_COLS + _MARGIN_CELLS * 2) * _CELL_SIZE,
	(_INNER_ROWS + _MARGIN_CELLS * 2) * _CELL_SIZE
)

const _FILL := Color(0.97, 0.96, 0.94, 1.0)
const _STROKE := Color(0.38, 0.38, 0.38, 1.0)
const _AA := 1.0
const _STROKE_W := 2.0
const _TRAIL_RADIUS_NEAR := 12.0
const _TRAIL_RADIUS_FAR := 5.0
const _ARC_BULGE_RATIO := 0.32
const TRAIL_LEAD_TIME := 1.0
const _BAKE_SCALE := 2
const DEBUG_SHOW_CIRCLES := false

static var _dot_tex_cache: Dictionary[float, ImageTexture] = {}
static var _trail_dots_prewarmed: Dictionary = {}

var subject_index: int = -1

var _label: Label
var _cloud_tex: ImageTexture
var _trail_centers: PackedVector2Array = PackedVector2Array()
var _trail_radii: PackedFloat32Array = PackedFloat32Array()
var _trail_reveal_elapsed: float = 0.0


func _init() -> void:
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	custom_minimum_size = CLOUD_SIZE
	size = CLOUD_SIZE

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


## Per-axis half-extent for random cloud centers over a spawn zone.
## small_region_fraction applies when the zone is smaller than the bubble on that axis.
static func spawn_spread(
	zone_size: Vector2,
	small_region_fraction: float,
	bubble_size: Vector2 = CLOUD_SIZE
) -> Vector2:
	return Vector2(
		_spawn_spread_axis(zone_size.x, bubble_size.x, small_region_fraction),
		_spawn_spread_axis(zone_size.y, bubble_size.y, small_region_fraction)
	)


static func _spawn_spread_axis(region: float, bubble: float, small_region_fraction: float) -> float:
	if region < bubble:
		return region * small_region_fraction
	return maxf(0.5 * bubble - 0.2 * region, 0.3 * region - 0.5 * bubble)


## One random top-left in thought_layer coords, using spawn_spread around zone_global.
static func random_top_left_in_zone(
	zone_global: Rect2,
	thought_layer: Control,
	small_region_fraction: float,
	bubble_size: Vector2 = CLOUD_SIZE
) -> Vector2:
	var spread := spawn_spread(zone_global.size, small_region_fraction, bubble_size)
	var center := zone_global.position + zone_global.size * 0.5
	var cloud_center_global := Vector2(
		randf_range(center.x - spread.x, center.x + spread.x),
		randf_range(center.y - spread.y, center.y + spread.y)
	)
	var local_pos := (
		thought_layer.get_global_transform_with_canvas().affine_inverse()
		* (cloud_center_global - bubble_size * 0.5)
	)
	var max_pos := (thought_layer.size - bubble_size).max(Vector2.ZERO)
	return Vector2(
		clampf(local_pos.x, 0.0, max_pos.x),
		clampf(local_pos.y, 0.0, max_pos.y)
	)


static func prewarm_trail_dots() -> void:
	# Prewarm only the minimum trail dot layout; other counts bake on-demand and are cached by radius.
	var key := "2"
	if _trail_dots_prewarmed.get(key, false):
		return
	var count := 2
	for i in count:
		var t := float(i + 1) / float(count + 1)
		_dot_texture(lerpf(_TRAIL_RADIUS_NEAR, _TRAIL_RADIUS_FAR, t))
	_trail_dots_prewarmed[key] = true


static func bake_cloud_texture_async(on_ready: Callable, display_scale: float = 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var cloud_size := CLOUD_SIZE * display_scale
	var circles: Array[Dictionary] = _cloud_layout_random(rng, cloud_size)
	WorkerThreadPool.add_task(func() -> void:
		var img: Image = _bake_cloud_image(circles, cloud_size)
		on_ready.call_deferred(img)
	)


func configure(
	index: int,
	text: String,
	cloud_top_left_layer: Vector2,
	anchor_layer: Vector2,
	cloud_tex: ImageTexture,
	display_scale: float = 1.0
) -> void:
	subject_index = index
	_label.text = text
	var display := CLOUD_SIZE * display_scale
	position = cloud_top_left_layer
	size = display
	custom_minimum_size = display
	_cloud_tex = cloud_tex
	_label.add_theme_font_size_override("font_size", int(round(16.0 * display_scale)))

	var anchor_local := anchor_layer - cloud_top_left_layer
	var attach := _attach_point_toward(anchor_local, display)
	# Larger dots need fewer of them. Always at least 2.
	var trail_count := maxi(floori((attach.distance_to(anchor_local) ** 0.8) * 0.08 / display_scale), 2)
	_trail_centers.clear()
	_trail_radii = PackedFloat32Array()
	for i in trail_count:
		var t := float(i + 1) / float(trail_count + 1)
		_trail_centers.append(_quadratic_bezier(attach, anchor_local, t))
		_trail_radii.append(lerpf(_TRAIL_RADIUS_NEAR, _TRAIL_RADIUS_FAR, t) * display_scale)
	_trail_reveal_elapsed = 0.0
	_label.visible = false
	set_process(true)


func set_subject_text(text: String) -> void:
	_label.text = text


func is_cloud_revealed() -> bool:
	return _trail_reveal_elapsed >= TRAIL_LEAD_TIME


func _reveal_step() -> float:
	return TRAIL_LEAD_TIME / float(_trail_centers.size())


func _process(delta: float) -> void:
	_trail_reveal_elapsed = minf(_trail_reveal_elapsed + delta, TRAIL_LEAD_TIME)
	queue_redraw()
	if not is_cloud_revealed():
		return
	_label.visible = true
	set_process(false)
	reveal_finished.emit()


func _trail_dot_reveal_time(index: int) -> float:
	var count := _trail_centers.size()
	return _reveal_step() * float(count - 1 - index)


func _draw() -> void:
	for i in _trail_centers.size():
		if _trail_reveal_elapsed < _trail_dot_reveal_time(i):
			continue
		_draw_trail_dot(_trail_centers[i], _trail_radii[i])
	if not is_cloud_revealed():
		return
	draw_texture_rect(_cloud_tex, Rect2(Vector2.ZERO, size), false)


func _draw_trail_dot(center: Vector2, radius: float) -> void:
	var tex := _dot_texture(radius)
	var draw_size := Vector2.ONE * (radius + _STROKE_W + _AA) * 2.0
	draw_texture_rect(tex, Rect2(center - draw_size * 0.5, draw_size), false)


static func _dot_texture(radius: float) -> ImageTexture:
	var key := snappedf(radius, 0.05)
	if _dot_tex_cache.has(key):
		return _dot_tex_cache[key]
	var tex := ImageTexture.create_from_image(_bake_dot_image(radius))
	_dot_tex_cache[key] = tex
	return tex


static func _max_circle_radius(pos: Vector2, cloud_size: Vector2) -> float:
	var inset := _STROKE_W * 0.5 + _AA
	var inset_max := cloud_size - Vector2.ONE * inset
	var r := minf(
		minf(pos.x - inset, inset_max.x - pos.x),
		minf(pos.y - inset, inset_max.y - pos.y)
	)
	return maxf(r, 0.0)


static func _append_cell_circle(
	circles: Array[Dictionary],
	rng: RandomNumberGenerator,
	cell_origin: Vector2,
	cell: Vector2,
	cloud_size: Vector2
) -> void:
	var pos := cell_origin + Vector2(
		rng.randf_range(0.0, cell.x),
		rng.randf_range(0.0, cell.y)
	)
	circles.append({"pos": pos, "r": _max_circle_radius(pos, cloud_size)})


static func _cloud_layout_random(rng: RandomNumberGenerator, cloud_size: Vector2) -> Array[Dictionary]:
	var cell_scale := cloud_size.x / CLOUD_SIZE.x
	var cell := Vector2.ONE * _CELL_SIZE * cell_scale
	var inner_origin := Vector2.ONE * float(_MARGIN_CELLS) * cell
	var circles: Array[Dictionary] = []
	for row in _INNER_ROWS:
		if row % 2 != 0:
			continue
		for col in _INNER_COLS:
			if col % 2 != 0:
				continue
			var cell_origin := inner_origin + Vector2(float(col), float(row)) * cell
			_append_cell_circle(circles, rng, cell_origin, cell, cloud_size)
	return circles


func _quadratic_bezier(start: Vector2, end: Vector2, t: float) -> Vector2:
	var chord := end - start
	if chord.length_squared() < 0.001:
		return start.lerp(end, t)
	var mid := start + chord * 0.5
	var perp := Vector2(-chord.y, chord.x).normalized()
	## Vertical trail → bulge from left/right; horizontal trail → from above/below.
	var side: float
	if absf(chord.y) >= absf(chord.x):
		side = 1.0 if start.x < end.x else -1.0
	else:
		side = 1.0 if start.y < end.y else -1.0
	var control := mid + perp * chord.length() * _ARC_BULGE_RATIO * side
	var u := 1.0 - t
	return u * u * start + 2.0 * u * t * control + t * t * end


## Pick the cloud-edge attach point facing the anchor (left / right / top / bottom).
static func _attach_point_toward(anchor_local: Vector2, cloud_size: Vector2) -> Vector2:
	var center := cloud_size * 0.5
	var to_anchor := anchor_local - center
	const EDGE := 0.9
	const INNER := 1.0 - EDGE
	if absf(to_anchor.x) >= absf(to_anchor.y):
		if to_anchor.x >= 0.0:
			return Vector2(cloud_size.x * EDGE, center.y)
		return Vector2(cloud_size.x * INNER, center.y)
	if to_anchor.y >= 0.0:
		return Vector2(center.x, cloud_size.y * EDGE)
	return Vector2(center.x, cloud_size.y * INNER)


static func _circle_sdf(p: Vector2, center: Vector2, radius: float) -> float:
	return p.distance_to(center) - radius


static func _fill_alpha(sdf: float) -> float:
	return 1.0 - smoothstep(-_AA, 0.0, sdf)


static func _stroke_alpha(sdf: float) -> float:
	var half_stroke := _STROKE_W * 0.5
	return 1.0 - smoothstep(half_stroke, half_stroke + _AA, absf(sdf))


static func _layer(tint: Color, alpha: float) -> Color:
	var c := tint
	c.a = alpha
	return c


static func _source_over(src: Color, dst: Color) -> Color:
	if src.a < 0.004:
		return dst
	if dst.a < 0.004:
		return src
	var inv := 1.0 - src.a
	var out_a := src.a + dst.a * inv
	var out := (src * src.a + dst * dst.a * inv) / out_a
	out.a = out_a
	return out


static func _sdf_color(sdf: float) -> Color:
	return _source_over(
		_layer(_STROKE, _stroke_alpha(sdf)),
		_layer(_FILL, _fill_alpha(sdf))
	)


static func _debug_cloud_color(circles: Array, p: Vector2) -> Color:
	var fill := Color(0.0, 0.0, 0.0, 0.0)
	var stroke := Color(0.0, 0.0, 0.0, 0.0)
	for c: Dictionary in circles:
		var sdf: float = _circle_sdf(p, c.pos, c.r)
		fill = _source_over(_layer(_FILL, _fill_alpha(sdf)), fill)
		stroke = _source_over(_layer(_STROKE, _stroke_alpha(sdf)), stroke)
	return _source_over(stroke, fill)


static func _bake_dot_image(radius: float) -> Image:
	var outer := radius + _STROKE_W + _AA
	var logic := maxi(ceili(outer * 2.0 * _BAKE_SCALE), 2)
	var center := Vector2(logic * 0.5, logic * 0.5)
	var img := Image.create(logic, logic, false, Image.FORMAT_RGBA8)
	var inv := 1.0 / float(_BAKE_SCALE)
	for y in logic:
		for x in logic:
			var p := (Vector2(x + 0.5, y + 0.5) - center) * inv
			var col := _sdf_color(_circle_sdf(p, Vector2.ZERO, radius))
			if col.a < 0.004:
				continue
			img.set_pixel(x, y, col)
	return img


static func _bake_cloud_image(circles: Array, cloud_size: Vector2) -> Image:
	var logic_w := maxi(ceili(cloud_size.x * _BAKE_SCALE), 2)
	var logic_h := maxi(ceili(cloud_size.y * _BAKE_SCALE), 2)
	var img := Image.create(logic_w, logic_h, false, Image.FORMAT_RGBA8)
	var inv := 1.0 / float(_BAKE_SCALE)

	for y in logic_h:
		for x in logic_w:
			var p := Vector2(x + 0.5, y + 0.5) * inv
			var col: Color
			if DEBUG_SHOW_CIRCLES:
				col = _debug_cloud_color(circles, p)
			else:
				var sdf := INF
				for c: Dictionary in circles:
					sdf = minf(sdf, _circle_sdf(p, c.pos, c.r))
				col = _sdf_color(sdf)
			if col.a < 0.004:
				continue
			img.set_pixel(x, y, col)

	return img
