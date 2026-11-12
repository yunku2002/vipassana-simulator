extends SceneTree

## Grow the figure strokes in res://assets/icon.png to _TARGET_PX and rebuild icon.ico.
## Godot --headless --path project --script tools/generate_icon.gd

const _STROKE := Color8(96, 96, 96, 255)
const _LUMA_MAX := 175
const _TARGET_PX := 12.0


func _init() -> void:
	var img := Image.new()
	var err := img.load("res://assets/icon.png")
	if err != OK:
		push_error("load icon: %s" % error_string(err))
		quit(1)
		return
	var w := img.get_width()
	var h := img.get_height()
	var src := img.get_data()
	var stroke := PackedByteArray()
	stroke.resize(w * h)
	for y in h:
		for x in w:
			var i := (y * w + x) * 4
			if src[i + 3] < 200:
				continue
			var luma := int(0.2126 * src[i] + 0.7152 * src[i + 1] + 0.0722 * src[i + 2])
			if luma < _LUMA_MAX:
				stroke[y * w + x] = 1
	var samples: Array[int] = []
	var step := maxi(1, int(sqrt(float(w * h) / 8000.0)))
	for y in range(0, h, step):
		for x in range(0, w, step):
			if stroke[y * w + x] == 0:
				continue
			samples.append(mini(_run(stroke, w, h, x, y, 1, 0), _run(stroke, w, h, x, y, 0, 1)))
	samples.sort()
	var median := samples[samples.size() / 2] if samples.size() else 1
	var radius := maxi(0, int(round((_TARGET_PX - float(median)) * 0.5)))
	if radius > 0:
		var grown := stroke.duplicate()
		var r2 := radius * radius
		for y in h:
			var row := y * w
			for x in w:
				if stroke[row + x] == 0:
					continue
				var y0 := maxi(0, y - radius)
				var y1 := mini(h - 1, y + radius)
				var x0 := maxi(0, x - radius)
				var x1 := mini(w - 1, x + radius)
				for yy in range(y0, y1 + 1):
					var dy := yy - y
					var grow_row := yy * w
					for xx in range(x0, x1 + 1):
						var dx := xx - x
						if dx * dx + dy * dy <= r2:
							grown[grow_row + xx] = 1
		stroke = grown
	for y in h:
		for x in w:
			if stroke[y * w + x] == 1:
				img.set_pixel(x, y, _STROKE)
	err = img.save_png("res://assets/icon.png")
	if err != OK:
		push_error("save png: %s" % error_string(err))
		quit(1)
		return
	_write_ico(img, "res://assets/icon.ico")
	print("icon %sx%s median %s radius %s" % [w, h, median, radius])
	quit()


func _run(mask: PackedByteArray, w: int, h: int, x: int, y: int, dx: int, dy: int) -> int:
	var n := 1
	var cx := x + dx
	var cy := y + dy
	while cx >= 0 and cy >= 0 and cx < w and cy < h and mask[cy * w + cx] == 1:
		n += 1
		cx += dx
		cy += dy
	cx = x - dx
	cy = y - dy
	while cx >= 0 and cy >= 0 and cx < w and cy < h and mask[cy * w + cx] == 1:
		n += 1
		cx -= dx
		cy -= dy
	return n


func _write_ico(img: Image, path: String) -> void:
	var sizes: Array[int] = [16, 32, 48, 256]
	var blobs: Array[PackedByteArray] = []
	for size in sizes:
		var copy := img.duplicate()
		if copy.get_width() != size or copy.get_height() != size:
			copy.resize(size, size, Image.INTERPOLATE_LANCZOS)
		var tmp := OS.get_temp_dir().path_join("vipassana_icon_%s.png" % size)
		copy.save_png(tmp)
		blobs.append(FileAccess.get_file_as_bytes(tmp))
	var count := blobs.size()
	var out := PackedByteArray()
	out.resize(6 + 16 * count)
	out.encode_u16(0, 0)
	out.encode_u16(2, 1)
	out.encode_u16(4, count)
	var offset := out.size()
	for i in count:
		var blob := blobs[i]
		var size := sizes[i]
		var entry := 6 + i * 16
		var dim := 0 if size >= 256 else size
		out.encode_u8(entry, dim)
		out.encode_u8(entry + 1, dim)
		out.encode_u16(entry + 4, 1)
		out.encode_u16(entry + 6, 32)
		out.encode_u32(entry + 8, blob.size())
		out.encode_u32(entry + 12, offset)
		offset += blob.size()
		out.append_array(blob)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("save ico failed")
		return
	f.store_buffer(out)
	f.close()
