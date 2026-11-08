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

static var _RED: Color = Color.from_hsv(10.0 / 360.0, 0.4, 0.9, 0.55)
static var _GREEN: Color = Color.from_hsv(130.0 / 360.0, 0.3, 0.7, 0.55)
static var _BLUE: Color = Color.from_hsv(220.0 / 360.0, 0.4, 0.8, 0.5)
## Stronger than the gross-sensation red. The feather interpolates toward this color.
const _REJECT_RED := Color(0.96, 0.1, 0.08, 0.75)
const _NAME_OUTLINE := Color(1.0, 0.98, 0.9, 0.95)
const _ANICCA_PATHS: Array[String] = [
	"res://assets/anicca-1.mp3",
	"res://assets/anicca-2.mp3",
	"res://assets/anicca-3.mp3",
]
## Same wash as the Anapana dim masks: black at 75% opacity.
const _DIM := Color(0.0, 0.0, 0.0, 0.75)
## mask_nostrils.svg / mask_philtrum.svg blur the hole by this many design pixels.
const _DIM_BLUR_DESIGN := 1.28
const _FEATHER := 0.28

const _CIRCLE_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform float feather : hint_range(0.0, 1.0) = 0.28;
uniform vec4 reject : source_color = vec4(0.96, 0.1, 0.08, 0.75);
instance uniform float outline_amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float t = smoothstep(1.0 - feather, 1.0, d);
	float shift = smoothstep(0.0, 0.25, t);
	vec3 rgb = mix(COLOR.rgb, reject.rgb, shift * outline_amount);
	float plain = COLOR.a * (1.0 - t);
	float rim = mix(COLOR.a, reject.a, shift) * (1.0 - smoothstep(0.25, 1.0, t));
	COLOR = vec4(rgb, mix(plain, rim, outline_amount));
}
"""

const _DIM_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform vec2 focus_local_px;
uniform vec2 focus_b_local_px;
uniform float dual_focus = 0.0;
uniform vec2 body_size;
uniform float radius_px = 120.0;
uniform float feather_px = 12.0;
uniform vec4 dim_color : source_color = vec4(0.0, 0.0, 0.0, 0.75);
void fragment() {
	float body_a = texture(TEXTURE, UV).a;
	vec2 px = UV * body_size;
	float d = length(px - focus_local_px);
	if (dual_focus > 0.5) {
		d = min(d, length(px - focus_b_local_px));
	}
	float a = smoothstep(radius_px - feather_px, radius_px + feather_px, d);
	COLOR = vec4(dim_color.rgb, dim_color.a * body_a * a);
}
"""

class _Sensation:
	## One copy per view: left (or only) view first, then the right view when symmetric.
	## Each view's pane clips its copy to the side of the body it shows.
	var holders: Array[Control] = []
	var center: Vector2
	var radius: float
	var time_left: float
	var cluster_index: int = -1
	var reject_tween: Tween

class _NameCluster:
	var position: Vector2
	var pick: Vector2i
	## Offset into the equanimity color cycle, in seconds.
	var phase: float

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
var _equanimity: bool = false
var _subtle_chance: float = 0.5
var _press_enabled: bool = false
## When set, each cluster resolves itself at the start and midpoint of its default-color hold.
var _auto_resolve: bool = false
var _default_hold: float = 0.5
var _charged_hold: float = 1.4
var _blend_sec: float = 0.3
var _reject_sec: float = 0.5
var _color_time: float = 0.0
var _coverage_epoch: int = 0
var _anicca_player: AudioStreamPlayer
var _anicca_streams: Array[AudioStream] = []
## Play on every Nth resolution. 1 plays every time.
var _anicca_stride: int = 1
var _anicca_resolves: int = 0

var _pixels_per_design: float = 1.0
var _focus_center: Vector2 = Vector2.ZERO
## Half-gap between the two focus centers when symmetric. Zero means they coincide.
var _focus_offset: float = 0.0
## How far each view is shifted away from the shared pose, in opposite directions.
var _view_shift: float = 0.0
## Design y under the focus centers when symmetric.
var _scan_y: float = 0.0
var _crown: Vector2 = Vector2.ZERO
var _bounds: Rect2 = Rect2()
var _placed: bool = false
var _mask_ready: bool = false
var _symmetric: bool = false
var _overlap_margin: float = 40.0

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
var _drag_last: Vector2 = Vector2.ZERO
var _drag_side_left: bool = true

var _circle_material: ShaderMaterial
var _dim_material: ShaderMaterial
var _dim_material_b: ShaderMaterial
var _left_pane: Control
var _right_pane: Control
var _body: Control
var _body_b: Control
var _coverage: Control
var _coverage_b: Control
var _live: Control
var _live_b: Control
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


## Call before _ready. Two clipped views and two focus holes, mirrored horizontally.
func set_symmetric(enabled: bool, overlap_margin: float = 40.0) -> void:
	_symmetric = enabled
	_overlap_margin = maxf(overlap_margin, 0.0)


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
			created.pick = SensationNames.random_pick(_subtle_chance)
			created.phase = randf() * _cycle_length()
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
	if _equanimity:
		var prev_color_time := _color_time
		_color_time += delta
		if _auto_resolve:
			_resolve_crossed_default_marks(prev_color_time)
		_update_equanimity_colors()
	else:
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
		var spawned := false
		for focus_design in _focus_centers_design():
			if _try_spawn_at(focus_design):
				spawned = true
		if not spawned:
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
	if _symmetric:
		_focus_offset = 0.0
		_view_shift = 0.0
		_scan_y = _head_anchor().y
		_apply_pose()
	else:
		_set_body_position(_focus_center - _head_anchor() * _pixels_per_design)
		_clamp_body()
	_placed = true


func clear_coverage() -> void:
	_coverage_epoch += 1
	for layer in _coverage_layers():
		for child in layer.get_children():
			child.queue_free()
	_covered_px.fill(0)
	_covered_count = 0


func set_equanimity(enabled: bool) -> void:
	_equanimity = enabled


func set_subtle_chance(chance: float) -> void:
	_subtle_chance = clampf(chance, 0.0, 1.0)


## default_sec is the fully-yellow hold. charged_sec is the red or green hold.
## blend_sec is the interpolation between them, and counts as the charged color.
func set_color_holds(default_sec: float, charged_sec: float, blend_sec: float) -> void:
	_default_hold = maxf(default_sec, 0.05)
	_charged_hold = maxf(charged_sec, 0.05)
	_blend_sec = maxf(blend_sec, 0.0)
	_color_time = 0.0


func set_reject_outline_sec(seconds: float) -> void:
	_reject_sec = maxf(seconds, 0.05)


func set_press_enabled(enabled: bool) -> void:
	_press_enabled = enabled


## The cluster still resolves on a manual press. This only adds the unattended marks.
func set_auto_resolve(enabled: bool) -> void:
	_auto_resolve = enabled


## resolutions_per_play is how many cluster resolutions happen for each anicca.
func set_anicca_stride(resolutions_per_play: int) -> void:
	_anicca_stride = maxi(resolutions_per_play, 1)


## Drops sensations that were never resolved. They leave no coverage.
func dismiss_unresolved() -> void:
	for sensation in _sensations:
		_kill_reject(sensation)
		_free_sensation_holders(sensation)
	_sensations.clear()


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
## Symmetric focuses still report the center one, so thoughts land in the same place.
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
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _equanimity and _press_enabled:
		var hit := _sensation_at_local(get_local_mouse_position())
		if hit != null:
			accept_event()
			if _is_default_hold(hit.cluster_index):
				_resolve_cluster(hit)
			else:
				_flash_cluster(hit)
			return
	if not _drag_enabled:
		return
	_dragging = true
	_drag_grab = get_local_mouse_position()
	_drag_last = _drag_grab
	_drag_body_start = _body_scan_pos(_body)
	_drag_side_left = not _symmetric or _drag_grab.x < size.x * 0.5
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
	var mouse := get_local_mouse_position()
	if _symmetric:
		_drag_symmetric(mouse - _drag_last)
		_drag_last = mouse
	else:
		_set_body_position(_drag_body_start + mouse - _drag_grab)
		_clamp_body()


func _build_nodes() -> void:
	if _symmetric:
		_left_pane = _make_pane()
		_right_pane = _make_pane()
		add_child(_left_pane)
		add_child(_right_pane)
		_body = _make_body_tree(_left_pane, false)
		_dim_material_b = _make_dim_material()
		_body_b = _make_body_tree(_right_pane, true)
		_layout_panes()
		return
	_body = _make_body_tree(self, false)


func _make_pane() -> Control:
	var pane := Control.new()
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.clip_contents = true
	return pane


func _make_body_tree(parent: Control, mirror: bool) -> Control:
	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(body)
	var texture := TextureRect.new()
	texture.name = "Figure"
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_SCALE
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(texture)
	var coverage := Control.new()
	coverage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coverage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(coverage)
	var live := Control.new()
	live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(live)
	var dim := TextureRect.new()
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dim.stretch_mode = TextureRect.STRETCH_SCALE
	dim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	dim.material = _dim_material_b if mirror else _dim_material
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(dim)
	if mirror:
		_coverage_b = coverage
		_live_b = live
	else:
		_coverage = coverage
		_live = live
		_cluster_markers = Control.new()
		_cluster_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cluster_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_cluster_markers.draw.connect(_draw_cluster_markers)
		body.add_child(_cluster_markers)
	return body


func _layout_panes() -> void:
	if not _symmetric or _left_pane == null or _right_pane == null:
		return
	var half := size.x * 0.5
	_left_pane.position = Vector2.ZERO
	_left_pane.size = Vector2(half, size.y)
	_right_pane.position = Vector2(half, 0.0)
	_right_pane.size = Vector2(size.x - half, size.y)


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
	var tex := ImageTexture.create_from_image(displayed)
	_apply_figure_texture(_body, tex, displayed.get_size())
	if _body_b != null:
		_apply_figure_texture(_body_b, tex, displayed.get_size())
	_build_mask(svg)


func _apply_figure_texture(body: Control, tex: Texture2D, tex_size: Vector2) -> void:
	body.size = tex_size
	var figure := body.get_node("Figure") as TextureRect
	figure.texture = tex
	for child in body.get_children():
		if child is TextureRect and (child as TextureRect).material != null:
			(child as TextureRect).texture = tex
			break


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
	if _symmetric:
		_focus_center = size * 0.5
		_layout_panes()
		if not _mask_ready:
			return
		if _placed:
			_apply_pose()
		else:
			reset_to_head()
		return
	var kept := Vector2.ZERO
	var keep := _placed and _mask_ready
	if keep:
		kept = (_focus_center - _body_scan_pos(_body)) / _pixels_per_design
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
	_apply_dim_params(_dim_material, _body_scan_pos(_body))
	if _symmetric and _dim_material_b != null and _body_b != null:
		_apply_dim_params(_dim_material_b, _body_scan_pos(_body_b))


func _apply_dim_params(mat: ShaderMaterial, body_scan: Vector2) -> void:
	var feather := 2.0 * _DIM_BLUR_DESIGN * _pixels_per_design
	mat.set_shader_parameter("body_size", _body.size)
	mat.set_shader_parameter("radius_px", _focus_radius)
	mat.set_shader_parameter("feather_px", feather)
	mat.set_shader_parameter("dim_color", _DIM)
	if _symmetric:
		mat.set_shader_parameter("dual_focus", 1.0)
		mat.set_shader_parameter("focus_local_px", _focus_left() - body_scan)
		mat.set_shader_parameter("focus_b_local_px", _focus_right() - body_scan)
	else:
		mat.set_shader_parameter("dual_focus", 0.0)
		mat.set_shader_parameter("focus_local_px", _focus_center - body_scan)
		mat.set_shader_parameter("focus_b_local_px", Vector2.ZERO)


func _head_anchor() -> Vector2:
	var drop := maxf(_focus_radius - _CROWN_INSET_PX, 0.0) / _pixels_per_design
	return _crown + Vector2(0.0, drop)


func _focus_left() -> Vector2:
	return _focus_center - Vector2(_focus_offset, 0.0)


func _focus_right() -> Vector2:
	return _focus_center + Vector2(_focus_offset, 0.0)


## Body position in this control's space, through its clipping pane when symmetric.
func _body_scan_pos(body: Control) -> Vector2:
	var parent := body.get_parent() as Control
	return body.position if parent == self else parent.position + body.position


func _set_body_scan_pos(body: Control, scan_pos: Vector2) -> void:
	var parent := body.get_parent() as Control
	body.position = scan_pos if parent == self else scan_pos - parent.position


func _set_body_position(pos: Vector2) -> void:
	_set_body_scan_pos(_body, pos)
	_update_dim()


func _set_body_positions(pos_l: Vector2, pos_r: Vector2) -> void:
	_set_body_scan_pos(_body, pos_l)
	if _body_b != null:
		_set_body_scan_pos(_body_b, pos_r)
	_update_dim()


## Both views sit here while _view_shift is zero, so they read as one figure.
func _shared_pose() -> Vector2:
	return _focus_center - Vector2(_crown.x, _scan_y) * _pixels_per_design


func _apply_pose() -> void:
	var pos := _shared_pose()
	var shift := Vector2(_view_shift, 0.0)
	_set_body_positions(pos + shift, pos - shift)


func _drag_symmetric(delta: Vector2) -> void:
	if _pixels_per_design <= 0.0 or _bounds.size == Vector2.ZERO:
		return
	_scan_y = clampf(
		_scan_y - delta.y / _pixels_per_design, _bounds.position.y, _bounds.end.y
	)
	_spread_by(delta.x if _drag_side_left else -delta.x)
	_apply_pose()


## amount is how far each scanned point moves outward from the midline, in screen pixels.
## Outward: the focuses separate until they stop overlapping, then the views take over.
## Inward: the views return to the shared pose first, then the focuses close in.
func _spread_by(amount: float) -> void:
	amount = minf(amount, _max_spread() - _focus_offset - _view_shift)
	if amount > 0.0:
		var apart_at := _focus_radius + _overlap_margin * 0.5
		var to_focus := clampf(apart_at - _focus_offset, 0.0, amount)
		_focus_offset += to_focus
		_view_shift += amount - to_focus
	elif amount < 0.0:
		var from_views := minf(-amount, _view_shift)
		_view_shift -= from_views
		_focus_offset = maxf(_focus_offset + amount + from_views, 0.0)


func _max_spread() -> float:
	var half := minf(_crown.x - _bounds.position.x, _bounds.end.x - _crown.x)
	return maxf(half, 0.0) * _pixels_per_design


func _clamp_body() -> void:
	if _bounds.size == Vector2.ZERO:
		return
	var local := (_focus_center - _body_scan_pos(_body)) / _pixels_per_design
	var end := _bounds.end
	local.x = clampf(local.x, _bounds.position.x, end.x)
	local.y = clampf(local.y, _bounds.position.y, end.y)
	_set_body_position(_focus_center - local * _pixels_per_design)


func _focus_centers_design() -> Array[Vector2]:
	var centers: Array[Vector2] = []
	if not _symmetric or _body_b == null:
		centers.append(_focus_center_design())
		return centers
	centers.append((_focus_left() - _body_scan_pos(_body)) / _pixels_per_design)
	centers.append((_focus_right() - _body_scan_pos(_body_b)) / _pixels_per_design)
	return centers


func _try_spawn_at(focus_design: Vector2) -> bool:
	if not _mask_ready:
		return false
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
		if _overlaps_live(center):
			continue
		_add_sensation(center, radius)
		return true
	return false


func _make_sensation_holder(center: Vector2, diameter: float) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(diameter, diameter)
	holder.position = _snap_top_left(center, diameter)
	var circle := ColorRect.new()
	circle.color = HeadFocus._REGION_ACTIVE
	circle.material = _circle_material
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.size = holder.size
	holder.add_child(circle)
	var mark := Label.new()
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.size = holder.size
	holder.add_child(mark)
	return holder


func _add_sensation(center: Vector2, radius: float) -> void:
	var diameter := _snap_diameter(radius)
	var sensation := _Sensation.new()
	sensation.center = center
	sensation.radius = radius
	sensation.cluster_index = _nearest_cluster_index(center)
	for live in _live_layers():
		var holder := _make_sensation_holder(center, diameter)
		live.add_child(holder)
		sensation.holders.append(holder)
		var mark := _label_of(holder)
		if _equanimity:
			_set_name_text(mark, _name_for_cluster(sensation.cluster_index, center), diameter)
			mark.add_theme_color_override(&"font_outline_color", _NAME_OUTLINE)
			mark.add_theme_constant_override(&"outline_size", 4)
			holder.set_meta(&"name_center", center)
			_circle_of(holder).color = _sample_color(sensation.cluster_index)
		else:
			mark.text = "?"
			mark.add_theme_font_size_override(&"font_size", _mark_font_size("?", diameter))
	if not _equanimity:
		sensation.time_left = randf_range(_delay_min, _delay_max)
	_sensations.append(sensation)


func _set_name_text(mark: Label, text: String, diameter: float) -> void:
	mark.text = text
	mark.add_theme_font_size_override(
		&"font_size",
		maxi(int(_mark_font_size(text, diameter) * _NAME_FONT_SCALE), 11)
	)


func _observe(sensation: _Sensation) -> void:
	_sensations.erase(sensation)
	_stamp(sensation.center, sensation.radius)
	var holders := _holders_of(sensation)
	if holders.is_empty():
		return
	var region_name := _name_for_point(sensation.center)
	for holder in holders:
		holder.set_meta(&"name_center", sensation.center)
		_set_name_text(_label_of(holder), region_name, holder.size.x)
	_fade_resolved_mark(sensation)


func _leave_blue_copy(sensation: _Sensation) -> void:
	var layers := _coverage_layers()
	for i in mini(layers.size(), sensation.holders.size()):
		_add_blue_copy(layers[i], sensation.holders[i])


func _add_blue_copy(coverage: Control, holder: Control) -> void:
	if coverage == null or not is_instance_valid(holder):
		return
	var copy := ColorRect.new()
	copy.color = _BLUE
	copy.material = _circle_material
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.position = holder.position
	copy.size = holder.size
	coverage.add_child(copy)


func _free_sensation_holders(sensation: _Sensation) -> void:
	for holder in _holders_of(sensation):
		holder.queue_free()


func _holders_of(sensation: _Sensation) -> Array[Control]:
	var found: Array[Control] = []
	for holder in sensation.holders:
		if is_instance_valid(holder):
			found.append(holder)
	return found


func _circles_of(sensation: _Sensation) -> Array[ColorRect]:
	var found: Array[ColorRect] = []
	for holder in _holders_of(sensation):
		found.append(_circle_of(holder))
	return found


func _circle_of(holder: Control) -> ColorRect:
	return holder.get_child(0) as ColorRect


func _live_layers() -> Array[Control]:
	var layers: Array[Control] = [_live]
	if _live_b != null:
		layers.append(_live_b)
	return layers


func _coverage_layers() -> Array[Control]:
	var layers: Array[Control] = [_coverage]
	if _coverage_b != null:
		layers.append(_coverage_b)
	return layers


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


func _overlaps_live(center: Vector2) -> bool:
	for sensation in _sensations:
		if center.distance_to(sensation.center) < sensation.radius:
			return true
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_sensation_names()


func _refresh_sensation_names() -> void:
	if _live == null:
		return
	for live in _live_layers():
		for child in live.get_children():
			var holder := child as Control
			if holder == null or not holder.has_meta(&"name_center"):
				continue
			var mark := _label_of(holder)
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
	var index := _nearest_cluster_index(point)
	if index < 0:
		return SensationNames.random_label(_subtle_chance)
	return SensationNames.label_at(_name_clusters[index].pick)


func _focus_center_design() -> Vector2:
	return (_focus_center - _body_scan_pos(_body)) / _pixels_per_design


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


func _cycle_length() -> float:
	return _default_hold + _charged_hold + _blend_sec * 2.0


func _nearest_cluster_index(point: Vector2) -> int:
	if _name_clusters.is_empty():
		return -1
	var nearest := 0
	var best := point.distance_squared_to(_name_clusters[0].position)
	for i in range(1, _name_clusters.size()):
		var dist := point.distance_squared_to(_name_clusters[i].position)
		if dist < best:
			best = dist
			nearest = i
	return nearest


func _name_for_cluster(cluster_index: int, point: Vector2) -> String:
	if cluster_index < 0 or cluster_index >= _name_clusters.size():
		return _name_for_point(point)
	return SensationNames.label_at(_name_clusters[cluster_index].pick)


func _charged_color(cluster_index: int) -> Color:
	if cluster_index < 0 or cluster_index >= _name_clusters.size():
		return _RED
	if _name_clusters[cluster_index].pick.x == 1:
		return _GREEN
	return _RED


func _phase_time(cluster_index: int) -> float:
	return _phase_time_at(cluster_index, _color_time)


func _phase_time_at(cluster_index: int, color_time: float) -> float:
	var phase := 0.0
	if cluster_index >= 0 and cluster_index < _name_clusters.size():
		phase = _name_clusters[cluster_index].phase
	return fposmod(color_time + phase, maxf(_cycle_length(), 0.001))


## True when this frame's clock step passed mark, measured from the start of the color cycle.
func _crossed_cycle_mark(cluster_index: int, prev_color_time: float, mark: float) -> bool:
	var cycle := maxf(_cycle_length(), 0.001)
	var phase := 0.0
	if cluster_index >= 0 and cluster_index < _name_clusters.size():
		phase = _name_clusters[cluster_index].phase
	var elapsed := _color_time - prev_color_time
	if elapsed <= 0.0:
		return false
	var dist := fposmod(mark - phase - prev_color_time, cycle)
	if dist == 0.0:
		dist = cycle
	return dist <= elapsed


func _resolve_crossed_default_marks(prev_color_time: float) -> void:
	var seen: Dictionary = {}
	var triggers: Array[_Sensation] = []
	var midpoint := _default_hold * 0.5
	for sensation in _sensations:
		var index := sensation.cluster_index
		if index >= 0:
			if seen.has(index):
				continue
			seen[index] = true
		if (
			_crossed_cycle_mark(index, prev_color_time, 0.0)
			or _crossed_cycle_mark(index, prev_color_time, midpoint)
		):
			triggers.append(sensation)
	for sensation in triggers:
		if sensation in _sensations:
			_resolve_cluster(sensation)


func _is_default_hold(cluster_index: int) -> bool:
	return _phase_time(cluster_index) < _default_hold


func _sample_color(cluster_index: int) -> Color:
	var charged := _charged_color(cluster_index)
	var t := _phase_time(cluster_index)
	var to_charged := _default_hold
	var charged_start := to_charged + _blend_sec
	var charged_end := charged_start + _charged_hold
	if t < to_charged:
		return HeadFocus._REGION_ACTIVE
	if t < charged_start:
		var u := 0.0 if _blend_sec <= 0.0 else (t - to_charged) / _blend_sec
		return HeadFocus._REGION_ACTIVE.lerp(charged, u)
	if t < charged_end:
		return charged
	var back := 0.0 if _blend_sec <= 0.0 else (t - charged_end) / _blend_sec
	return charged.lerp(HeadFocus._REGION_ACTIVE, back)


func _update_equanimity_colors() -> void:
	for sensation in _sensations:
		var color := _sample_color(sensation.cluster_index)
		for circle in _circles_of(sensation):
			circle.color = color


func _sensation_in_focus(sensation: _Sensation) -> bool:
	if _pixels_per_design <= 0.0:
		return false
	var focus_r := _focus_radius / _pixels_per_design
	for focus_design in _focus_centers_design():
		if sensation.center.distance_to(focus_design) <= focus_r:
			return true
	return false


## Only the copy in the pane under the pointer is visible there, so only it is hit-tested.
func _sensation_at_local(local: Vector2) -> _Sensation:
	var on_right := _body_b != null and local.x >= _focus_center.x
	var body := _body_b if on_right else _body
	var view := 1 if on_right else 0
	for i in range(_sensations.size() - 1, -1, -1):
		var sensation := _sensations[i]
		if not _sensation_in_focus(sensation) or view >= sensation.holders.size():
			continue
		var holder := sensation.holders[view]
		if not is_instance_valid(holder):
			continue
		var center_px := _body_scan_pos(body) + holder.position + holder.size * 0.5
		if local.distance_to(center_px) <= holder.size.x * 0.5:
			return sensation
	return null


func _group_of(sensation: _Sensation) -> Array[_Sensation]:
	var found: Array[_Sensation] = []
	if sensation.cluster_index < 0:
		found.append(sensation)
		return found
	for other in _sensations:
		if other.cluster_index == sensation.cluster_index:
			found.append(other)
	return found


func _resolve_cluster(sensation: _Sensation) -> void:
	_play_anicca()
	for member in _group_of(sensation):
		_resolve_sensation(member)


func _play_anicca() -> void:
	_anicca_resolves += 1
	if _anicca_resolves % _anicca_stride != 0:
		return
	if _anicca_player == null:
		_anicca_player = AudioStreamPlayer.new()
		_anicca_player.bus = &"Master"
		add_child(_anicca_player)
		for path in _ANICCA_PATHS:
			var stream := load(path) as AudioStream
			if stream != null:
				_anicca_streams.append(stream)
	if _anicca_streams.is_empty():
		return
	_anicca_player.stream = _anicca_streams[randi() % _anicca_streams.size()]
	_anicca_player.play()


func _resolve_sensation(sensation: _Sensation) -> void:
	_sensations.erase(sensation)
	_kill_reject(sensation)
	for circle in _circles_of(sensation):
		_set_outline_amount(circle, 0.0)
	_stamp(sensation.center, sensation.radius)
	if _holders_of(sensation).is_empty():
		return
	_fade_resolved_mark(sensation)


func _fade_resolved_mark(sensation: _Sensation) -> void:
	var epoch := _coverage_epoch
	var tween := create_tween()
	tween.set_parallel(true)
	for holder in _holders_of(sensation):
		var mark := _label_of(holder)
		mark.pivot_offset = holder.size * 0.5
		tween.tween_property(mark, "scale", Vector2(2.2, 2.2), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(mark, "modulate:a", 0.0, 0.45)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		if epoch == _coverage_epoch:
			_leave_blue_copy(sensation)
		_free_sensation_holders(sensation)
	)


func _flash_cluster(sensation: _Sensation) -> void:
	for member in _group_of(sensation):
		_flash_outline(member)


func _flash_outline(sensation: _Sensation) -> void:
	_kill_reject(sensation)
	var circles := _circles_of(sensation)
	var apply := func(amount: float) -> void:
		for circle in circles:
			_set_outline_amount(circle, amount)
	apply.call(1.0)
	var tween := create_tween()
	sensation.reject_tween = tween
	tween.tween_method(apply, 1.0, 0.0, _reject_sec)


func _set_outline_amount(circle: ColorRect, amount: float) -> void:
	if is_instance_valid(circle):
		circle.set_instance_shader_parameter(&"outline_amount", amount)


func _kill_reject(sensation: _Sensation) -> void:
	if sensation.reject_tween != null and sensation.reject_tween.is_valid():
		sensation.reject_tween.kill()
	sensation.reject_tween = null


func _label_of(holder: Control) -> Label:
	if not is_instance_valid(holder):
		return null
	for child in holder.get_children():
		if child is Label:
			return child as Label
	return null


func _make_circle_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _CIRCLE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("feather", _FEATHER)
	mat.set_shader_parameter("reject", _REJECT_RED)
	return mat


func _make_dim_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _DIM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat
