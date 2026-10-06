class_name BodyScan
extends Control

## Draggable standing body under a fixed circular focus.
## Coverage is the union of observed sensation circles on the body silhouette,
## kept as a pixel mask.

const DESIGN_SIZE := Vector2(1024, 1536)
## Coverage mask pixels per design pixel. Independent of the on-screen scale.
const MASK_SCALE := 0.5
const _CLUSTER_SPAWN_ATTEMPTS := 40
const _SENSATION_SPAWN_ATTEMPTS := 24
const _DEBUG_CLUSTERS := false
const _NAME_FONT_SCALE := 0.6
## How far inside the top of the focus circle the crown sits at the start of a pass.
const _CROWN_INSET_PX := 36.0

const _YELLOW := Color(1.0, 0.88, 0.15, 0.55)
const _BLUE := Color(0.29, 0.47, 0.78, 0.5)
## Same wash as the Anapana dim masks: black at 75% opacity.
const _DIM := Color(0.0, 0.0, 0.0, 0.75)
## mask_nostrils.svg / mask_philtrum.svg blur the hole by this many design pixels.
const _DIM_BLUR_DESIGN := 1.28
const _FEATHER := 0.28

const _CIRCLE_SHADER := """
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

const _DIM_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform vec2 focus_local_px;
uniform vec2 body_size;
uniform float radius_px = 120.0;
uniform float feather_px = 12.0;
uniform vec4 dim_color : source_color = vec4(0.0, 0.0, 0.0, 0.75);
void fragment() {
	float body_a = texture(TEXTURE, UV).a;
	vec2 px = UV * body_size;
	float d = length(px - focus_local_px);
	float a = smoothstep(radius_px - feather_px, radius_px + feather_px, d);
	COLOR = vec4(dim_color.rgb, dim_color.a * body_a * a);
}
"""

class _Sensation:
	var holder: Control
	var center: Vector2
	var radius: float
	var time_left: float

class _NameCluster:
	var position: Vector2
	var pick: Vector2i

var _body_scale: float
var _focus_radius: float
var _radius_min: float
var _radius_max: float
var _interval_min: float
var _interval_max: float
var _delay_min: float
var _delay_max: float

var _drag_enabled: bool = false
var _timers_paused: bool = false
var _spawn_enabled: bool = false

var _pixels_per_design: float = 1.0
var _focus_center: Vector2 = Vector2.ZERO
var _crown: Vector2 = Vector2.ZERO
var _bounds: Rect2 = Rect2()
var _placed: bool = false
var _mask_ready: bool = false

var _mask_w: int = 0
var _mask_h: int = 0
var _body_px: PackedByteArray = PackedByteArray()
var _covered_px: PackedByteArray = PackedByteArray()
var _body_count: int = 0
var _covered_count: int = 0

var _spawn_timer: float = 0.0
var _dragging: bool = false
var _drag_grab: Vector2 = Vector2.ZERO
var _drag_body_start: Vector2 = Vector2.ZERO

var _circle_material: ShaderMaterial
var _dim_material: ShaderMaterial
var _body: Control
var _coverage: Control
var _dim: TextureRect
var _live: Control
var _cluster_markers: Control
var _sensations: Array[_Sensation] = []
var _name_clusters: Array[_NameCluster] = []
var _cluster_count: int = 0
var _cluster_separation: float = 0.0


func configure(
	body_scale: float,
	focus_radius: float,
	radius_min: float,
	radius_max: float,
	interval_min: float,
	interval_max: float,
	delay_min: float,
	delay_max: float
) -> void:
	_body_scale = body_scale
	_focus_radius = focus_radius
	_radius_min = radius_min
	_radius_max = radius_max
	_interval_min = interval_min
	_interval_max = interval_max
	_delay_min = delay_min
	_delay_max = delay_max


## separation is the minimum distance between centers, in design pixels.
## Centers may also land that far outside the figure's bounding box.
func set_name_clusters(count: int, separation: float) -> void:
	_cluster_count = count
	_cluster_separation = separation


func regenerate_name_clusters() -> void:
	_name_clusters.clear()
	if not _mask_ready or _cluster_count <= 0 or _bounds.size == Vector2.ZERO:
		return
	var area := _bounds.grow(_cluster_separation)
	var min_d2 := _cluster_separation * _cluster_separation
	for _i in _cluster_count:
		var placed := false
		for _attempt in _CLUSTER_SPAWN_ATTEMPTS:
			var point := Vector2(
				randf_range(area.position.x, area.end.x),
				randf_range(area.position.y, area.end.y)
			)
			var too_close := false
			for cluster in _name_clusters:
				if point.distance_squared_to(cluster.position) < min_d2:
					too_close = true
					break
			if too_close:
				continue
			var created := _NameCluster.new()
			created.position = point
			created.pick = SensationNames.random_pick()
			_name_clusters.append(created)
			placed = true
			break
		if not placed:
			break
	if _cluster_markers != null:
		_cluster_markers.queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_circle_material = _make_circle_material()
	_dim_material = _make_dim_material()
	_build_nodes()
	_build_figure()
	_spawn_timer = randf_range(_interval_min, _interval_max)
	resized.connect(_on_resized)
	_on_resized()


func advance(delta: float) -> void:
	if _timers_paused or not _mask_ready:
		return
	var finished: Array[_Sensation] = []
	for sensation in _sensations:
		sensation.time_left -= delta
		if sensation.time_left <= 0.0:
			finished.append(sensation)
	for sensation in finished:
		_observe(sensation)
	if not _spawn_enabled:
		return
	_spawn_timer -= delta
	while _spawn_timer <= 0.0:
		if not _try_spawn():
			break
		_spawn_timer = randf_range(_interval_min, _interval_max)


func coverage_ratio() -> float:
	if _body_count <= 0:
		return 0.0
	return float(_covered_count) / float(_body_count)


func has_pending_observation() -> bool:
	return not _sensations.is_empty()


func reset_to_head() -> void:
	_dragging = false
	if not _mask_ready:
		return
	_set_body_position(_focus_center - _head_anchor() * _pixels_per_design)
	_clamp_body()
	_placed = true


func clear_coverage() -> void:
	for child in _coverage.get_children():
		child.queue_free()
	_covered_px.fill(0)
	_covered_count = 0


func set_drag_enabled(enabled: bool) -> void:
	_drag_enabled = enabled
	if not enabled:
		_dragging = false


func set_timers_paused(paused: bool) -> void:
	_timers_paused = paused


func set_sensation_pace(interval_min: float, interval_max: float, delay_min: float, delay_max: float) -> void:
	_interval_min = interval_min
	_interval_max = interval_max
	_delay_min = delay_min
	_delay_max = delay_max


func set_spawn_enabled(enabled: bool) -> void:
	if enabled and not _spawn_enabled:
		_spawn_timer = randf_range(_interval_min, _interval_max)
	_spawn_enabled = enabled


## Axis-aligned bounds of the focus circle, in canvas space. Used to place thoughts.
func get_focus_global_rect() -> Rect2:
	var xform := get_global_transform_with_canvas()
	var c := _focus_center
	var r := _focus_radius
	var corners: Array[Vector2] = [
		xform * (c + Vector2(-r, -r)),
		xform * (c + Vector2(r, -r)),
		xform * (c + Vector2(r, r)),
		xform * (c + Vector2(-r, r)),
	]
	var g_min := corners[0]
	var g_max := corners[0]
	for corner in corners:
		g_min = g_min.min(corner)
		g_max = g_max.max(corner)
	return Rect2(g_min, g_max - g_min)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed or not _drag_enabled:
		return
	_dragging = true
	_drag_grab = get_local_mouse_position()
	_drag_body_start = _body.position
	accept_event()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_dragging = false
		return
	if not event is InputEventMouseMotion or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
		return
	_set_body_position(_drag_body_start + get_local_mouse_position() - _drag_grab)
	_clamp_body()


func _build_nodes() -> void:
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_body)
	var texture := TextureRect.new()
	texture.name = "Figure"
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_SCALE
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_child(texture)
	_coverage = Control.new()
	_coverage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coverage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_child(_coverage)
	_dim = TextureRect.new()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dim.stretch_mode = TextureRect.STRETCH_SCALE
	_dim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_dim.material = _dim_material
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_child(_dim)
	_cluster_markers = Control.new()
	_cluster_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cluster_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cluster_markers.draw.connect(_draw_cluster_markers)
	_body.add_child(_cluster_markers)
	_live = Control.new()
	_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_live)


func _build_figure() -> void:
	var svg := FileAccess.get_file_as_string("res://assets/standing.svg")
	if svg.is_empty():
		push_error("Failed to read standing.svg")
		return
	var displayed := SvgRaster.rasterize(svg, _body_scale)
	if displayed == null or displayed.get_width() < 2:
		push_error("Failed to rasterize standing.svg")
		return
	_pixels_per_design = float(displayed.get_width()) / DESIGN_SIZE.x
	_body.size = displayed.get_size()
	var figure := _body.get_node("Figure") as TextureRect
	figure.texture = ImageTexture.create_from_image(displayed)
	_dim.texture = figure.texture
	_build_mask(svg)


func _build_mask(svg: String) -> void:
	var mask := SvgRaster.rasterize(svg, MASK_SCALE)
	if mask == null or mask.get_width() < 2:
		push_error("Failed to rasterize the coverage mask")
		return
	if mask.get_format() != Image.FORMAT_RGBA8:
		mask.convert(Image.FORMAT_RGBA8)
	_mask_w = mask.get_width()
	_mask_h = mask.get_height()
	var data := mask.get_data()
	var count := _mask_w * _mask_h
	_body_px.resize(count)
	_body_px.fill(0)
	_covered_px.resize(count)
	_covered_px.fill(0)
	_body_count = 0
	_covered_count = 0
	var min_p := Vector2i(_mask_w, _mask_h)
	var max_p := Vector2i.ZERO
	for y in _mask_h:
		var row := y * _mask_w
		for x in _mask_w:
			var alpha: int = data[(row + x) * 4 + 3]
			if alpha < 128:
				continue
			_body_px[row + x] = 1
			_body_count += 1
			min_p.x = mini(min_p.x, x)
			min_p.y = mini(min_p.y, y)
			max_p.x = maxi(max_p.x, x)
			max_p.y = maxi(max_p.y, y)
	if _body_count == 0:
		push_error("Standing figure mask has no opaque pixels")
		return
	_bounds = Rect2(
		Vector2(min_p) / MASK_SCALE,
		Vector2(max_p - min_p + Vector2i.ONE) / MASK_SCALE
	)
	_crown = _crown_design(min_p.y)
	_mask_ready = true
	regenerate_name_clusters()


func _crown_design(top_y: int) -> Vector2:
	var left := _mask_w
	var right := 0
	var y_end := mini(top_y + 2, _mask_h - 1)
	for y in range(top_y, y_end + 1):
		var row := y * _mask_w
		for x in _mask_w:
			if _body_px[row + x] == 0:
				continue
			left = mini(left, x)
			right = maxi(right, x)
	return Vector2((left + right) * 0.5, top_y) / MASK_SCALE


func _on_resized() -> void:
	if size.x < 2.0 or size.y < 2.0 or _pixels_per_design <= 0.0:
		return
	var kept := Vector2.ZERO
	var keep := _placed and _mask_ready
	if keep:
		kept = (_focus_center - _body.position) / _pixels_per_design
	_focus_center = size * 0.5
	_update_dim()
	if not _mask_ready:
		return
	if not _placed:
		reset_to_head()
	else:
		_set_body_position(_focus_center - kept * _pixels_per_design)
		_clamp_body()


func _update_dim() -> void:
	if _dim_material == null or _body == null or _pixels_per_design <= 0.0:
		return
	_dim_material.set_shader_parameter("focus_local_px", _focus_center - _body.position)
	_dim_material.set_shader_parameter("body_size", _body.size)
	_dim_material.set_shader_parameter("radius_px", _focus_radius)
	_dim_material.set_shader_parameter("feather_px", 2.0 * _DIM_BLUR_DESIGN * _pixels_per_design)
	_dim_material.set_shader_parameter("dim_color", _DIM)


func _head_anchor() -> Vector2:
	var drop := maxf(_focus_radius - _CROWN_INSET_PX, 0.0) / _pixels_per_design
	return _crown + Vector2(0.0, drop)


func _set_body_position(pos: Vector2) -> void:
	_body.position = pos
	_live.position = pos
	_update_dim()


func _clamp_body() -> void:
	if _bounds.size == Vector2.ZERO:
		return
	var local := (_focus_center - _body.position) / _pixels_per_design
	var end := _bounds.end
	local.x = clampf(local.x, _bounds.position.x, end.x)
	local.y = clampf(local.y, _bounds.position.y, end.y)
	_set_body_position(_focus_center - local * _pixels_per_design)


func _try_spawn() -> bool:
	if not _mask_ready:
		return false
	var focus_design := _focus_center_design()
	var focus_r := _focus_radius / _pixels_per_design
	for _attempt in _SENSATION_SPAWN_ATTEMPTS:
		var radius := randf_range(_radius_min, _radius_max)
		var reach := focus_r - radius
		if reach <= 1.0:
			return false
		var angle := randf() * TAU
		var dist := sqrt(randf()) * reach
		var center := focus_design + Vector2.from_angle(angle) * dist
		if not _circle_inside_body(center, radius):
			continue
		if _center_is_covered(center):
			continue
		if _overlaps_live(center, radius):
			continue
		_add_sensation(center, radius)
		return true
	return false


func _add_sensation(center: Vector2, radius: float) -> void:
	var diameter := _snap_diameter(radius)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(diameter, diameter)
	holder.position = _snap_top_left(center, diameter)
	var circle := ColorRect.new()
	circle.color = _YELLOW
	circle.material = _circle_material
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.size = holder.size
	holder.add_child(circle)
	var mark := Label.new()
	mark.text = "?"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.size = holder.size
	mark.add_theme_font_size_override(&"font_size", _mark_font_size("?", diameter))
	holder.add_child(mark)
	_live.add_child(holder)
	var sensation := _Sensation.new()
	sensation.holder = holder
	sensation.center = center
	sensation.radius = radius
	sensation.time_left = randf_range(_delay_min, _delay_max)
	_sensations.append(sensation)


func _observe(sensation: _Sensation) -> void:
	_sensations.erase(sensation)
	_stamp(sensation.center, sensation.radius)
	var holder := sensation.holder
	if not is_instance_valid(holder) or holder.get_child_count() < 2:
		_leave_blue_copy(sensation)
		return
	var mark := holder.get_child(1) as Label
	holder.set_meta(&"name_center", sensation.center)
	var name := _name_for_point(sensation.center)
	mark.text = name
	mark.add_theme_font_size_override(
		&"font_size",
		maxi(int(_mark_font_size(name, holder.size.x) * _NAME_FONT_SCALE), 11)
	)
	mark.pivot_offset = holder.size * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mark, "scale", Vector2(2.2, 2.2), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(mark, "modulate:a", 0.0, 0.45)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		_leave_blue_copy(sensation)
		if is_instance_valid(holder):
			holder.queue_free()
	)


func _leave_blue_copy(sensation: _Sensation) -> void:
	var holder := sensation.holder
	if not is_instance_valid(holder):
		return
	var copy := ColorRect.new()
	copy.color = _BLUE
	copy.material = _circle_material
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.position = holder.position
	copy.size = holder.size
	_coverage.add_child(copy)


func _stamp(center: Vector2, radius: float) -> void:
	_visit_circle(center, radius, true)


func _circle_inside_body(center: Vector2, radius: float) -> bool:
	return _visit_circle(center, radius, false)


## When stamping, marks newly covered body pixels. Otherwise returns false if any
## circle pixel falls outside the silhouette.
func _visit_circle(center: Vector2, radius: float, stamp: bool) -> bool:
	var c := center * MASK_SCALE
	var r := radius * MASK_SCALE
	var r2 := r * r
	var x0 := maxi(int(floor(c.x - r)), 0)
	var y0 := maxi(int(floor(c.y - r)), 0)
	var x1 := mini(int(ceil(c.x + r)), _mask_w - 1)
	var y1 := mini(int(ceil(c.y + r)), _mask_h - 1)
	if x0 > x1 or y0 > y1:
		return false
	for y in range(y0, y1 + 1):
		var row := y * _mask_w
		var dy := float(y) + 0.5 - c.y
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - c.x
			if dx * dx + dy * dy > r2:
				continue
			var i := row + x
			if _body_px[i] == 0:
				if stamp:
					continue
				return false
			if stamp and _covered_px[i] == 0:
				_covered_px[i] = 1
				_covered_count += 1
	return true


func _center_is_covered(center: Vector2) -> bool:
	var p := center * MASK_SCALE
	var x := int(floor(p.x))
	var y := int(floor(p.y))
	if x < 0 or y < 0 or x >= _mask_w or y >= _mask_h:
		return true
	return _covered_px[y * _mask_w + x] != 0


func _overlaps_live(center: Vector2, radius: float) -> bool:
	for sensation in _sensations:
		if center.distance_to(sensation.center) < radius + sensation.radius:
			return true
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_sensation_names()


func _refresh_sensation_names() -> void:
	if _live == null:
		return
	for child in _live.get_children():
		var holder := child as Control
		if holder == null or not holder.has_meta(&"name_center") or holder.get_child_count() < 2:
			continue
		var mark := holder.get_child(1) as Label
		if mark == null:
			continue
		mark.text = _name_for_point(holder.get_meta(&"name_center"))


func _draw_cluster_markers() -> void:
	if not _DEBUG_CLUSTERS:
		return
	var color := Color(0.9, 0.15, 0.45, 0.95)
	for cluster in _name_clusters:
		_cluster_markers.draw_circle(cluster.position * _pixels_per_design, 14.0, color)


func _name_for_point(point: Vector2) -> String:
	if _name_clusters.is_empty():
		return SensationNames.random_label()
	var nearest := _name_clusters[0]
	var best := point.distance_squared_to(nearest.position)
	for cluster in _name_clusters:
		var dist := point.distance_squared_to(cluster.position)
		if dist < best:
			best = dist
			nearest = cluster
	return SensationNames.label_at(nearest.pick)


func _focus_center_design() -> Vector2:
	return (_focus_center - _body.position) / _pixels_per_design


func _snap_diameter(radius_design: float) -> float:
	var diameter := roundf(radius_design * _pixels_per_design * 2.0)
	if int(diameter) % 2 == 1:
		diameter += 1.0
	return maxf(diameter, 2.0)


func _snap_top_left(center_design: Vector2, diameter: float) -> Vector2:
	var center := (center_design * _pixels_per_design).round()
	return center - Vector2(diameter, diameter) * 0.5


func _mark_font_size(text: String, diameter: float) -> int:
	var ratio := 0.48
	if text.length() > 1:
		ratio = 0.34 if text.length() <= 4 else 0.24
	if text.length() >= 8:
		ratio = 0.18
	return clampi(int(diameter * ratio), 13, 36)


func _make_circle_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _CIRCLE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("feather", _FEATHER)
	return mat


func _make_dim_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _DIM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat
