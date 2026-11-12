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

const _AA := 1.0
const _STROKE_W := 2.0
const _TRAIL_RADIUS_NEAR := 12.0
const _TRAIL_RADIUS_FAR := 5.0
const _ARC_BULGE_RATIO := 0.32
const TRAIL_LEAD_TIME := 1.0

const _SHAPE_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec3 circles[10];
uniform int circle_count;
uniform vec2 shape_size;
uniform vec4 fill_color = vec4(0.97, 0.96, 0.94, 1.0);
uniform vec4 stroke_color = vec4(0.38, 0.38, 0.38, 1.0);
uniform float aa;
uniform float stroke_w;

void fragment() {
	vec4 tint = COLOR;
	vec2 p = UV * shape_size;
	float sdf = 100000.0;
	for (int i = 0; i < 10; i++) {
		if (i < circle_count) {
			sdf = min(sdf, length(p - circles[i].xy) - circles[i].z);
		}
	}
	float fill_a = (1.0 - smoothstep(-aa, 0.0, sdf)) * fill_color.a;
	float half_stroke = stroke_w * 0.5;
	float stroke_a = (1.0 - smoothstep(half_stroke, half_stroke + aa, abs(sdf))) * stroke_color.a;
	float out_a = stroke_a + fill_a * (1.0 - stroke_a);
	vec3 out_rgb = stroke_color.rgb * stroke_a + fill_color.rgb * fill_a * (1.0 - stroke_a);
	if (out_a > 0.004) {
		out_rgb /= out_a;
	}
	COLOR = vec4(out_rgb, out_a) * tint;
}
"""

static var _shape_shader: Shader

var subject_index: int = -1

var _label: Label
var _cloud: ColorRect
var _trail_dots: Array[ColorRect] = []
var _trail_reveal_elapsed: float = 0.0
## Cloud center relative to the spawn-zone center, in layer pixels.
var _zone_offset := Vector2.ZERO
var _trail_anchor := Vector2.ZERO


func _init() -> void:
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_STOP
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


static func to_layer(thought_layer: Control, global_point: Vector2) -> Vector2:
	return thought_layer.get_global_transform_with_canvas().affine_inverse() * global_point


static func _shape_shader_resource() -> Shader:
	if _shape_shader == null:
		_shape_shader = Shader.new()
		_shape_shader.code = _SHAPE_SHADER
	return _shape_shader


func configure(
	index: int,
	text: String,
	cloud_top_left_layer: Vector2,
	anchor_layer: Vector2,
	zone_center_layer: Vector2,
	display_scale: float = 1.0
) -> void:
	subject_index = index
	_label.text = text
	var display := CLOUD_SIZE * display_scale
	position = cloud_top_left_layer
	size = display
	custom_minimum_size = display
	_zone_offset = position + size * 0.5 - zone_center_layer
	_label.add_theme_font_size_override("font_size", int(round(16.0 * display_scale)))
	_build_cloud(display)
	_trail_reveal_elapsed = 0.0
	_label.visible = false
	_trail_anchor = anchor_layer
	_rebuild_trail()
	set_process(true)


func set_subject_text(text: String) -> void:
	_label.text = text


## Move the cloud with the spawn zone and aim the trail at the head's current position.
## The reveal clock is left where it is, so a resize mid-trail does not restart it.
func follow_zone(zone_center_layer: Vector2, anchor_layer: Vector2, layer_size: Vector2) -> void:
	var top_left := zone_center_layer + _zone_offset - size * 0.5
	var max_pos := (layer_size - size).max(Vector2.ZERO)
	top_left = Vector2(
		clampf(top_left.x, 0.0, max_pos.x),
		clampf(top_left.y, 0.0, max_pos.y)
	)
	if top_left.is_equal_approx(position) and anchor_layer.is_equal_approx(_trail_anchor):
		return
	position = top_left
	_trail_anchor = anchor_layer
	_rebuild_trail()


func is_cloud_revealed() -> bool:
	return _trail_reveal_elapsed >= TRAIL_LEAD_TIME


func _process(delta: float) -> void:
	var was_revealed := is_cloud_revealed()
	_trail_reveal_elapsed = minf(_trail_reveal_elapsed + delta, TRAIL_LEAD_TIME)
	_apply_reveal()
	if not is_cloud_revealed():
		return
	set_process(false)
	if not was_revealed:
		reveal_finished.emit()


## Trail grows from the head (t = 1) toward the cloud (t = 0).
## Visibility follows that fraction, so the dot count can change without rewinding.
func _apply_reveal() -> void:
	var count := _trail_dots.size()
	if count == 0:
		return
	var revealed := clampf(_trail_reveal_elapsed / TRAIL_LEAD_TIME, 0.0, 1.0)
	var head_t := float(count) / float(count + 1)
	var threshold := lerpf(head_t, 0.0, revealed)
	for i in count:
		var t := float(i + 1) / float(count + 1)
		_trail_dots[i].visible = t + 0.0001 >= threshold
	if is_cloud_revealed():
		_cloud.visible = true
		_label.visible = true


func _rebuild_trail() -> void:
	var anchor_local := _trail_anchor - position
	var attach := _attach_point_toward(anchor_local, size)
	var display_scale := size.x / CLOUD_SIZE.x
	var reach := attach.distance_to(anchor_local)
	var trail_count := maxi(floori((reach ** 0.8) * 0.08 / display_scale), 2)
	while _trail_dots.size() > trail_count:
		var last := _trail_dots.size() - 1
		var extra: ColorRect = _trail_dots[last]
		_trail_dots.remove_at(last)
		extra.visible = false
		extra.queue_free()
	for i in trail_count:
		var t := float(i + 1) / float(trail_count + 1)
		var center := _quadratic_bezier(attach, anchor_local, t)
		var radius := lerpf(_TRAIL_RADIUS_NEAR, _TRAIL_RADIUS_FAR, t) * display_scale
		if i >= _trail_dots.size():
			_trail_dots.append(_make_dot(center, radius))
		else:
			_sync_dot(_trail_dots[i], center, radius)
	_apply_reveal()
	move_child(_label, get_child_count() - 1)
	move_child(_cloud, get_child_count() - 2)


func _build_cloud(cloud_size: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = cloud_size
	rect.material = _shape_material(_cloud_layout_random(rng, cloud_size), cloud_size)
	rect.visible = false
	_cloud = rect
	add_child(rect)


func _make_dot(center: Vector2, radius: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	add_child(rect)
	_sync_dot(rect, center, radius)
	return rect


func _sync_dot(rect: ColorRect, center: Vector2, radius: float) -> void:
	var draw_size := (radius + _STROKE_W + _AA) * 2.0
	rect.size = Vector2.ONE * draw_size
	rect.position = center - rect.size * 0.5
	var mid := rect.size * 0.5
	var mat := rect.material as ShaderMaterial
	if mat == null:
		rect.material = _shape_material([{"pos": mid, "r": radius}], rect.size)
		return
	var packed := PackedVector3Array()
	packed.resize(10)
	packed[0] = Vector3(mid.x, mid.y, radius)
	mat.set_shader_parameter("circles", packed)
	mat.set_shader_parameter("circle_count", 1)
	mat.set_shader_parameter("shape_size", rect.size)


func _shape_material(circles: Array, shape_size: Vector2) -> ShaderMaterial:
	var packed := PackedVector3Array()
	packed.resize(10)
	for i in mini(circles.size(), 10):
		var circle: Dictionary = circles[i]
		var pos: Vector2 = circle["pos"]
		packed[i] = Vector3(pos.x, pos.y, float(circle["r"]))
	var mat := ShaderMaterial.new()
	mat.shader = _shape_shader_resource()
	mat.set_shader_parameter("circles", packed)
	mat.set_shader_parameter("circle_count", mini(circles.size(), 10))
	mat.set_shader_parameter("shape_size", shape_size)
	mat.set_shader_parameter("aa", _AA)
	mat.set_shader_parameter("stroke_w", _STROKE_W)
	return mat


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
	var offset := perp * chord.length() * _ARC_BULGE_RATIO
	## Bow away from the cloud so the trail leaves the chosen edge
	## instead of sliding along the silhouette into a corner.
	var cloud_center := size * 0.5
	var control := mid + offset
	if control.distance_squared_to(cloud_center) < (mid - offset).distance_squared_to(cloud_center):
		control = mid - offset
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
