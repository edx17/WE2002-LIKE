class_name KitTexture
extends RefCounted
## Builds a player's shirt texture at runtime: team kit (assets/kits/<id>.png)
## + the player's number, big on the back and small on the chest, with an
## outline. Same UV contract as the generator: u 0.5 = chest, 0/1 = back.
## Cached per kit+number, so a whole squad shares at most 11 textures per kit.

const KIT_DIR := "res://assets/kits/"
## Chunky 5×7 digits, era-appropriate and readable from the broadcast camera.
const DIGITS := {
	"0": ["01110", "11011", "11011", "11011", "11011", "11011", "01110"],
	"1": ["00110", "01110", "11110", "00110", "00110", "00110", "11111"],
	"2": ["01110", "11011", "00011", "00110", "01100", "11000", "11111"],
	"3": ["11110", "00011", "00011", "01110", "00011", "00011", "11110"],
	"4": ["00110", "01110", "11010", "11010", "11111", "00010", "00010"],
	"5": ["11111", "11000", "11110", "00011", "00011", "11011", "01110"],
	"6": ["01110", "11000", "11000", "11110", "11011", "11011", "01110"],
	"7": ["11111", "00011", "00110", "00110", "01100", "01100", "01100"],
	"8": ["01110", "11011", "11011", "01110", "11011", "11011", "01110"],
	"9": ["01110", "11011", "11011", "01111", "00011", "00011", "01110"],
}

static var _cache := {}


static func build(kit: Dictionary, number: int) -> Texture2D:
	var id := str(kit.get("id", ""))
	var key := "%s#%d" % [id, number]
	if _cache.has(key):
		return _cache[key]
	var img: Image
	var path := KIT_DIR + id + ".png"
	if ResourceLoader.exists(path):
		img = (load(path) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	else:
		img = Image.create(512, 512, false, Image.FORMAT_RGBA8)
		img.fill(Color.html(str(kit.get("primary", "#cccccc"))))
	if number > 0:
		var fill := Color.html(str(kit.get("number", kit.get("secondary", "#ffffff"))))
		var outline := Color.html(str(kit.get("number_outline", kit.get("primary", "#000000"))))
		var h := img.get_height()
		# Back: centred on u = 0 (wraps around the seam), v 0.36..0.8.
		draw_number(img, str(number), 0.0, 1.0 - 0.8, 0.44 * h, fill, outline)
		# Chest: small, centred.
		draw_number(img, str(number), 0.5, 1.0 - 0.83, 0.13 * h, fill, outline)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Draws `text` centred horizontally at u, top at v (0 = image top), `height` px tall.
static func draw_number(img: Image, text: String, u: float, v_top: float, height: float, fill: Color, outline: Color) -> void:
	var cell := maxi(1, roundi(height / 7.0))
	var gap := cell
	var width := text.length() * 5 * cell + (text.length() - 1) * gap
	var x0 := roundi(u * img.get_width() - width * 0.5)
	var y0 := roundi(v_top * img.get_height())
	var border := maxi(1, cell / 3)
	for pass_i in 2:
		var grow := border if pass_i == 0 else 0
		var color := outline if pass_i == 0 else fill
		for ci in text.length():
			var glyph: Array = DIGITS.get(text[ci], [])
			var gx := x0 + ci * (5 * cell + gap)
			for row in glyph.size():
				for col in 5:
					if (glyph[row] as String)[col] == "1":
						_rect_wrapped(img, gx + col * cell - grow, y0 + row * cell - grow, cell + grow * 2, cell + grow * 2, color)


static func _rect_wrapped(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var iw := img.get_width()
	var y1 := clampi(y, 0, img.get_height())
	var y2 := clampi(y + h, 0, img.get_height())
	if y2 <= y1:
		return
	for xx in [x, x + iw, x - iw]:
		var x1 := clampi(xx, 0, iw)
		var x2 := clampi(xx + w, 0, iw)
		if x2 > x1:
			img.fill_rect(Rect2i(x1, y1, x2 - x1, y2 - y1), color)
