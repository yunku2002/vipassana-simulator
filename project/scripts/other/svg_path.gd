class_name SvgPath
extends RefCounted

## Minimal SVG path helpers for closed cubic/line subpaths in design space.


static func first_path_d(svg_text: String) -> String:
	var re := RegEx.new()
	re.compile("\\bd=\"([^\"]*)\"")
	var m := re.search(svg_text)
	if m == null:
		return ""
	return m.get_string(1)


## Returns each closed subpath as a polyline (cubics flattened).
static func parse_closed_subpaths(d: String) -> Array[PackedVector2Array]:
	var subpaths: Array[PackedVector2Array] = []
	var current := PackedVector2Array()
	var start := Vector2.ZERO
	var pos := Vector2.ZERO
	var i := 0
	var chars := d
	while i < chars.length():
		var ch := chars[i]
		if ch == " " or ch == "," or ch == "\n" or ch == "\t" or ch == "\r":
			i += 1
			continue
		if (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z"):
			var cmd := ch
			i += 1
			var nums := _read_numbers(chars, i)
			i = nums.next_i
			var args: Array[float] = nums.values
			match cmd:
				"M", "m":
					if not current.is_empty():
						subpaths.append(current)
						current = PackedVector2Array()
					if args.size() < 2:
						continue
					var p := Vector2(args[0], args[1])
					if cmd == "m":
						p += pos
					pos = p
					start = p
					current.append(pos)
					## Implicit lineto pairs after moveto.
					var ai := 2
					while ai + 1 < args.size():
						var q := Vector2(args[ai], args[ai + 1])
						if cmd == "m":
							q += pos
						pos = q
						current.append(pos)
						ai += 2
				"L", "l":
					var ai := 0
					while ai + 1 < args.size():
						var p := Vector2(args[ai], args[ai + 1])
						if cmd == "l":
							p += pos
						pos = p
						current.append(pos)
						ai += 2
				"H", "h":
					for x in args:
						pos = Vector2(x if cmd == "H" else pos.x + x, pos.y)
						current.append(pos)
				"V", "v":
					for y in args:
						pos = Vector2(pos.x, y if cmd == "V" else pos.y + y)
						current.append(pos)
				"C", "c":
					var ai := 0
					while ai + 5 < args.size():
						var p1 := Vector2(args[ai], args[ai + 1])
						var p2 := Vector2(args[ai + 2], args[ai + 3])
						var p3 := Vector2(args[ai + 4], args[ai + 5])
						if cmd == "c":
							p1 += pos
							p2 += pos
							p3 += pos
						_append_cubic(current, pos, p1, p2, p3)
						pos = p3
						ai += 6
				"Z", "z":
					if not current.is_empty():
						if current[current.size() - 1].distance_squared_to(start) > 0.01:
							current.append(start)
						subpaths.append(current)
						current = PackedVector2Array()
					pos = start
				_:
					push_warning("SvgPath: unsupported command '%s'" % cmd)
		else:
			i += 1
	if not current.is_empty():
		subpaths.append(current)
	return subpaths


static func bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var min_p := poly[0]
	var max_p := poly[0]
	for p in poly:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	return Rect2(min_p, max_p - min_p)


## Even-odd fill rule.
static func point_in_polygon(point: Vector2, poly: PackedVector2Array) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	var inside := false
	var j := n - 1
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		var intersect := ((a.y > point.y) != (b.y > point.y)) and (
			point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y + 0.0000001) + a.x
		)
		if intersect:
			inside = not inside
		j = i
	return inside


## Distance to the nearest edge. Returns 0 when outside.
static func inward_clearance(point: Vector2, poly: PackedVector2Array) -> float:
	if not point_in_polygon(point, poly):
		return 0.0
	var best := INF
	var n := poly.size()
	if n < 2:
		return 0.0
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		best = minf(best, _dist_point_segment(point, a, b))
	return best if best < INF else 0.0


static func _append_cubic(
	out: PackedVector2Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, steps: int = 16
) -> void:
	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		out.append(_cubic_point(p0, p1, p2, p3, t))


static func _cubic_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return (
		u * u * u * p0
		+ 3.0 * u * u * t * p1
		+ 3.0 * u * t * t * p2
		+ t * t * t * p3
	)


static func _dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _read_numbers(s: String, start: int) -> Dictionary:
	var values: Array[float] = []
	var i := start
	while i < s.length():
		while i < s.length() and (s[i] == " " or s[i] == "," or s[i] == "\n" or s[i] == "\t" or s[i] == "\r"):
			i += 1
		if i >= s.length():
			break
		var ch := s[i]
		if (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z"):
			break
		var begin := i
		if s[i] == "-" or s[i] == "+":
			i += 1
		var saw_digit := false
		while i < s.length() and s[i] >= "0" and s[i] <= "9":
			saw_digit = true
			i += 1
		if i < s.length() and s[i] == ".":
			i += 1
			while i < s.length() and s[i] >= "0" and s[i] <= "9":
				saw_digit = true
				i += 1
		if i < s.length() and (s[i] == "e" or s[i] == "E"):
			i += 1
			if i < s.length() and (s[i] == "-" or s[i] == "+"):
				i += 1
			while i < s.length() and s[i] >= "0" and s[i] <= "9":
				i += 1
		if not saw_digit:
			break
		values.append(float(s.substr(begin, i - begin)))
	return {"values": values, "next_i": i}
