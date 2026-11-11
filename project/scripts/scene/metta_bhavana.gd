class_name MettaBhavana
extends StageShell

## Sitting figure, an orange aura, and outward flicks.

const _RING_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float extent_px = 40.0;
uniform float radius_px = 32.0;
uniform float width_px = 8.0;
uniform vec4 ring_color : source_color = vec4(0.95, 0.4, 0.07, 0.8);

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * extent_px;
	float dist = abs(length(p) - radius_px);
	float band = 1.0 - smoothstep(0.0, width_px * 0.5, dist);
	COLOR = vec4(ring_color.rgb, ring_color.a * band);
}
"""

const _SPARK_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_mix;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float core = exp(-dot(p, p) * 8.0);
	float arms = exp(-abs(p.x) * 14.0) * exp(-p.y * p.y * 3.5);
	arms += exp(-abs(p.y) * 14.0) * exp(-p.x * p.x * 3.5);
	float spark = clamp(core + arms * 0.85, 0.0, 1.0);
	float mask = 1.0 - smoothstep(0.72, 1.0, d);
	vec3 col = mix(vec3(0.95, 0.48, 0.1), vec3(1.0, 0.98, 0.93), core);
	COLOR = vec4(col, spark * mask);
}
"""

const _RING_SPEED := 72.0
const _RING_GAP := 0.0
const _RING_WIDTH := 72.0
const _AURA_COLOR := Color(0.95, 0.4, 0.07, 1.0)
const _TRAIL_SEC := 0.32
const _TRAIL_SPACING := 32.0
const _SPEED_WINDOW := 0.1
const _SPARK_SIZE := 48.0
const _TRAIL_COLOR := Color(1.0, 0.62, 0.18, 1.0)
const _OUTWARD_DEGREES := 45.0
## Angle from the spiral's outward ray to its path. About a golden spiral.
const _SPIRAL_BEARING := deg_to_rad(73.0)

@export var aura_start_radius : float
@export var aura_clear_radius : float
@export var releases_required : int
@export var release_speed : float
@export var max_travel_speed : float
@export var drag_radius : float

@onready var _field: Control = $Margin/Body/Field
@onready var _figure: BreathingFigure = $Margin/Body/Field/FigureSlot/BreathingFigure

var _rings_root: Control
var _layer: _SparkLayer
var _spark_material: ShaderMaterial
var _ring_shader: Shader
var _releases := 0
var _radius: float
var _drawn_radius: float
var _held: _Spark
var _copies: Array[_Spark] = []
var _sparks: Array[_Spark] = []
var _samples: Array[Vector2] = []
var _sample_times: Array[float] = []
var _ring_timer := 0.0
var _rings_started := false
var _rings: Array[_Ring] = []


class _Ring:
	var span: float
	var age: float
	var rect: ColorRect


class _Spark:
	var pos: Vector2
	var vel := Vector2.ZERO
	var flying := false
	var fading := false
	var head_life := 0.0
	var head: ColorRect
	var copy_angle := 0.0
	var spiraling := false
	var pole := Vector2.ZERO
	var radius := 0.0
	var radial_angle := 0.0
	var bearing := 0.0
	var points: Array[Vector2] = []
	var ages: Array[float] = []


class _SparkLayer extends Control:
	var stage: MettaBhavana

	func _draw() -> void:
		stage._draw_trails(self)


func _ready() -> void:
	_figure.get_rig().show_chevrons = false
	_radius = aura_start_radius
	_drawn_radius = aura_start_radius
	_build_visuals()
	super._ready()
	intro_finished.connect(_on_stage_intro_finished)


func _on_stage_intro_finished() -> void:
	_figure.start_breathing()
	_start_rings()


func _process(delta: float) -> void:
	_drawn_radius = lerpf(_drawn_radius, _radius, 1.0 - exp(-8.0 * delta))
	_advance_rings(delta)
	if _held != null:
		_sync_copies(_held)
	_advance_sparks(delta)
	_layer.queue_redraw()


func _on_field_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if is_gameplay_blocked() or _held != null:
				return
			if mb.position.distance_to(_field_center()) > drag_radius:
				return
			_begin(_to_layer(mb.position))
			_field.accept_event()
		elif _held != null:
			_release(_to_layer(mb.position))
			_field.accept_event()
	elif event is InputEventMouseMotion and _held != null:
		var motion := event as InputEventMouseMotion
		_follow(_to_layer(motion.position))
		_field.accept_event()


func _build_visuals() -> void:
	_spark_material = _make_material(_SPARK_SHADER)
	_ring_shader = Shader.new()
	_ring_shader.code = _RING_SHADER

	_rings_root = Control.new()
	_rings_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rings_root)
	_rings_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	move_child(_rings_root, $Margin.get_index())

	_layer = _SparkLayer.new()
	_layer.stage = self
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.z_index = 20
	add_child(_layer)
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	move_child(_layer, $Margin.get_index() + 1)
	_field.gui_input.connect(_on_field_input)


func _begin(pos: Vector2) -> void:
	var spark := _Spark.new()
	spark.pos = pos
	_attach_head(spark)
	_sparks.append(spark)
	_held = spark
	_samples.clear()
	_sample_times.clear()
	_note(pos)
	_add_copies()


func _follow(pos: Vector2) -> void:
	if _held == null:
		return
	_held.pos = pos
	_note(pos)


func _release(pos: Vector2) -> void:
	var spark := _held
	if spark == null:
		return
	_held = null
	spark.pos = pos
	_note(pos)
	_sync_copies(spark)
	var vel := _velocity()
	var curvature := _release_curvature()
	_samples.clear()
	_sample_times.clear()
	var offset := pos - _center()
	var outside := offset.length() > drag_radius
	var away := absf(vel.angle_to(offset)) <= deg_to_rad(_OUTWARD_DEGREES)
	var fast := vel.length() >= release_speed
	if outside and away and fast:
		if vel.length() > max_travel_speed:
			vel = vel.normalized() * max_travel_speed
		spark.flying = true
		spark.vel = vel
		_set_spiral(spark, curvature)
		_launch_copies(spark, curvature)
		_grow()
	else:
		_begin_fade(spark)
		for copy in _copies:
			_begin_fade(copy)
		_copies.clear()


func _grow() -> void:
	_releases += 1
	var t := clampf(float(_releases) / float(maxi(releases_required, 1)), 0.0, 1.0)
	_radius = lerpf(aura_start_radius, aura_clear_radius, t)
	if _releases >= releases_required:
		mark_cleared()


func _attach_head(spark: _Spark) -> void:
	var head := ColorRect.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.material = _spark_material
	spark.head = head
	_layer.add_child(head)
	head.size = Vector2(_SPARK_SIZE, _SPARK_SIZE)


func _copy_count() -> int:
	var span := maxf(aura_clear_radius - aura_start_radius, 1.0)
	var t := clampf((_radius - aura_start_radius) / span, 0.0, 1.0)
	if t >= 0.75:
		return 7
	if t >= 0.5:
		return 3
	if t >= 0.25:
		return 1
	return 0


func _add_copies() -> void:
	_copies.clear()
	var count := _copy_count()
	if count == 0:
		return
	var rays := count + 1
	for i in count:
		var spark := _Spark.new()
		spark.copy_angle = TAU * float(i + 1) / float(rays)
		_attach_head(spark)
		_sparks.append(spark)
		_copies.append(spark)


func _sync_copies(origin: _Spark) -> void:
	var center := _center()
	var offset := origin.pos - center
	for spark in _copies:
		spark.pos = center + offset.rotated(spark.copy_angle)


func _launch_copies(origin: _Spark, curvature: float) -> void:
	for spark in _copies:
		spark.vel = origin.vel.rotated(spark.copy_angle)
		spark.flying = true
		_set_spiral(spark, curvature)
	_copies.clear()


func _advance_sparks(delta: float) -> void:
	var view := get_viewport().get_visible_rect().grow(_SPARK_SIZE * 0.5)
	var done: Array[_Spark] = []
	for spark in _sparks:
		if spark.flying:
			if spark.spiraling:
				_advance_spiral(spark, delta)
			else:
				spark.pos += spark.vel * delta
			_stamp(spark, delta)
			_place(spark)
			if not view.has_point(spark.pos):
				_finish_head(spark)
				spark.flying = false
				spark.fading = true
			continue
		if spark.fading:
			_age_points(spark, delta)
			if spark.head != null:
				spark.head_life = maxf(spark.head_life - delta, 0.0)
				spark.head.modulate.a = clampf(spark.head_life / _TRAIL_SEC, 0.0, 1.0)
				_place(spark)
				if spark.head_life <= 0.0:
					_finish_head(spark)
			if spark.head == null and spark.points.is_empty():
				done.append(spark)
			continue
		_stamp(spark, delta)
		_place(spark)
	for spark in done:
		_sparks.erase(spark)


func _stamp(spark: _Spark, delta: float) -> void:
	_age_points(spark, delta)
	if spark.points.is_empty() or spark.points[-1].distance_to(spark.pos) >= _TRAIL_SPACING:
		spark.points.append(spark.pos)
		spark.ages.append(0.0)


func _age_points(spark: _Spark, delta: float) -> void:
	var i := 0
	while i < spark.ages.size():
		spark.ages[i] += delta
		if spark.ages[i] >= _TRAIL_SEC:
			spark.ages.remove_at(i)
			spark.points.remove_at(i)
		else:
			i += 1


func _place(spark: _Spark) -> void:
	if spark.head == null:
		return
	spark.head.position = spark.pos - Vector2(_SPARK_SIZE, _SPARK_SIZE) * 0.5


func _begin_fade(spark: _Spark) -> void:
	spark.fading = true
	spark.flying = false
	spark.head_life = _TRAIL_SEC
	if spark.points.is_empty() or spark.points[-1].distance_to(spark.pos) > 0.5:
		spark.points.append(spark.pos)
		spark.ages.append(0.0)


func _finish_head(spark: _Spark) -> void:
	if is_instance_valid(spark.head):
		spark.head.queue_free()
	spark.head = null


func _draw_trails(layer: Control) -> void:
	for spark in _sparks:
		for i in spark.points.size():
			var life := 1.0 - clampf(spark.ages[i] / _TRAIL_SEC, 0.0, 1.0)
			if life <= 0.0:
				continue
			var color := _TRAIL_COLOR
			color.a = 0.85 * life
			layer.draw_circle(spark.points[i], lerpf(3.0, 8.0, life), color)


func _start_rings() -> void:
	_rings_started = true
	_ring_timer = 0.0


func _advance_rings(delta: float) -> void:
	if not _rings_started:
		return
	var speed := _RING_SPEED
	var i := 0
	while i < _rings.size():
		_rings[i].age += delta
		if _rings[i].age * speed >= _rings[i].span:
			_rings[i].rect.queue_free()
			_rings.remove_at(i)
		else:
			_place_ring(_rings[i], speed)
			i += 1
	_ring_timer -= delta
	var interval := (_RING_GAP + _RING_WIDTH) / speed
	while _ring_timer <= 0.0:
		_ring_timer += interval
		var ring := _Ring.new()
		ring.span = maxf(_drawn_radius, 1.0)
		ring.age = 0.0
		ring.rect = _make_ring_rect()
		_rings.append(ring)
		_place_ring(ring, speed)


func _make_ring_rect() -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _ring_shader
	rect.material = mat
	_rings_root.add_child(rect)
	return rect


func _place_ring(ring: _Ring, speed: float) -> void:
	var phase := clampf(ring.age * speed / maxf(ring.span, 0.001), 0.0, 1.0)
	var fade := smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.4, 1.0, phase))
	var radius := phase * ring.span
	var width := _RING_WIDTH
	var color := _AURA_COLOR
	color.a = fade * 0.8
	var mat := ring.rect.material as ShaderMaterial
	var extent := radius + width
	mat.set_shader_parameter("extent_px", extent)
	mat.set_shader_parameter("radius_px", radius)
	mat.set_shader_parameter("width_px", width)
	mat.set_shader_parameter("ring_color", color)
	ring.rect.size = Vector2(extent, extent) * 2.0
	ring.rect.position = _center() - ring.rect.size * 0.5
	ring.rect.visible = fade > 0.0 and ring.span > 1.0


func _field_center() -> Vector2:
	return _field.make_canvas_position_local(_figure.get_global_rect().get_center())


func _to_layer(field_pos: Vector2) -> Vector2:
	var canvas := _field.get_global_transform() * field_pos
	return _layer.get_global_transform().affine_inverse() * canvas


func _center() -> Vector2:
	var global_center := _figure.get_global_rect().get_center()
	return _layer.get_global_transform().affine_inverse() * global_center


func _note(pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_samples.append(pos)
	_sample_times.append(now)
	var cutoff := now - _SPEED_WINDOW
	while _sample_times.size() > 1 and _sample_times[0] < cutoff:
		_sample_times.remove_at(0)
		_samples.remove_at(0)


func _set_spiral(spark: _Spark, curvature: float) -> void:
	spark.spiraling = false
	if absf(curvature) <= 0.0001 or spark.vel.length_squared() <= 0.0001:
		return
	var bearing := signf(curvature) * _SPIRAL_BEARING
	var radius := sin(_SPIRAL_BEARING) / absf(curvature)
	var outward := spark.vel.normalized().rotated(-bearing)
	spark.pole = spark.pos - outward * radius
	spark.radius = radius
	spark.radial_angle = outward.angle()
	spark.bearing = bearing
	spark.spiraling = true


func _advance_spiral(spark: _Spark, delta: float) -> void:
	var speed := spark.vel.length()
	if speed <= 0.0 or delta <= 0.0:
		return
	if _outward_after(spark, delta):
		_step_spiral(spark, delta)
		return
	var lo := 0.0
	var hi := delta
	for _i in 8:
		var mid := (lo + hi) * 0.5
		if _outward_after(spark, mid):
			lo = mid
		else:
			hi = mid
	_step_spiral(spark, lo)
	spark.spiraling = false
	spark.pos += spark.vel * (delta - lo)


func _step_spiral(spark: _Spark, delta: float) -> void:
	var step := _spiral_after(spark, delta)
	spark.pos = step.pos
	spark.vel = step.vel
	spark.radius = step.radius
	spark.radial_angle = step.radial_angle


func _spiral_after(spark: _Spark, delta: float) -> Dictionary:
	var speed := spark.vel.length()
	var grown := spark.radius + cos(spark.bearing) * speed * delta
	if grown <= spark.radius:
		return {
			"pos": spark.pos,
			"vel": spark.vel,
			"radius": spark.radius,
			"radial_angle": spark.radial_angle,
		}
	var angle := spark.radial_angle + tan(spark.bearing) * log(grown / spark.radius)
	var outward := Vector2.from_angle(angle)
	return {
		"pos": spark.pole + outward * grown,
		"vel": outward.rotated(spark.bearing) * speed,
		"radius": grown,
		"radial_angle": angle,
	}


func _outward_after(spark: _Spark, delta: float) -> bool:
	var step := _spiral_after(spark, delta)
	return (step.pos - _center()).dot(step.vel) > 0.0


func _release_curvature() -> float:
	if _samples.size() < 3:
		return 0.0
	var turn := 0.0
	var length := 0.0
	var prev := _samples[1] - _samples[0]
	for i in range(2, _samples.size()):
		var step := _samples[i] - _samples[i - 1]
		if prev.length_squared() < 1.0 or step.length_squared() < 1.0:
			prev = step
			continue
		turn += prev.angle_to(step)
		length += step.length()
		prev = step
	if length < 1.0:
		return 0.0
	return turn / length


func _velocity() -> Vector2:
	if _samples.size() < 2:
		return Vector2.ZERO
	var dt := _sample_times[-1] - _sample_times[0]
	if dt <= 0.0:
		return Vector2.ZERO
	return (_samples[-1] - _samples[0]) / dt


func _make_material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat
