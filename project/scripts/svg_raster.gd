class_name SvgRaster
extends RefCounted


static func rasterize(svg_text: String, scale: float) -> Image:
	var img := Image.new()
	img.load_svg_from_string(svg_text, scale)
	return img


static func rasterize_crop(svg_text: String, crop: Rect2, scale: float) -> Image:
	var vb := "%s %s %s %s" % [crop.position.x, crop.position.y, crop.size.x, crop.size.y]
	var s := svg_text
	var re := RegEx.new()
	for pair in [["width", str(crop.size.x)], ["height", str(crop.size.y)], ["viewBox", vb]]:
		re.compile("%s=\"[^\"]*\"" % pair[0])
		s = re.sub(s, "%s=\"%s\"" % [pair[0], pair[1]], false)
	return rasterize(s, scale)
