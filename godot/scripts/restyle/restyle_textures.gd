extends RefCounted
## Procedural textures for the restyled buildings' materials (a material's "texture" in data/restyle/_library.json or
## in a spec): a new one is a case in make() and its painter. Tiling squares, tinted by the material's colour; the
## kit's textures (scripts/villa/villa_kit.gd texture(): stone, ashlar, panels, slats...) work too.


static func make(name: String) -> Image:
	var img: Image
	match name:
		"solar": img = _solar()
		"cladding": img = _cladding()
		"brick": img = _brick()
		"boards": img = _boards()
		_: return null
	img.generate_mipmaps()
	return img


static func _paint(n: int, f: Callable) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			img.set_pixel(x, y, f.call(x, y))
	return img


## Photovoltaic panels: dark blue cells in a lighter grid, an aluminium frame round each panel (128 x 64 px).
static func _solar() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	return _paint(256, func(x: int, y: int) -> Color:
		var px := x % 128
		var py := y % 64
		if px < 3 or px > 124 or py < 3 or py > 60:
			return Color("#b9bec4")
		if (px - 3) % 15 == 0 or (py - 3) % 15 == 0:
			return Color("#4f648a")
		return Color("#1c2a47").lightened(rng.randf() * 0.05))


## Metal cladding: panels 64 x 128 px, thin dark joints, each panel a shade of its own.
static func _cladding() -> Image:
	return _paint(256, func(x: int, y: int) -> Color:
		if x % 64 < 2 or y % 128 < 2:
			return Color(0.55, 0.56, 0.58)
		var k := (x / 64) * 7 + (y / 128) * 13
		return Color(0.93, 0.93, 0.94).darkened(float(k % 5) * 0.012))


## Brick in running bond: 64 x 21 px bricks, 3 px mortar.
static func _brick() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 72
	var shades := []
	for k in 64:
		shades.append(Color("#a4573e").lightened(rng.randf_range(-0.12, 0.12)))
	return _paint(256, func(x: int, y: int) -> Color:
		var row := y / 21
		var bx := x + (32 if row % 2 == 1 else 0)
		if y % 21 < 3 or bx % 64 < 3:
			return Color("#cfc6b8")
		return shades[(row * 5 + bx / 64) % 64])


## Wooden boards, vertical: 32 px wide, grain along them.
static func _boards() -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var tone := []
	for k in 8:
		tone.append(Color("#b38a5c").lightened(rng.randf_range(-0.1, 0.1)))
	return _paint(256, func(x: int, y: int) -> Color:
		if x % 32 < 2:
			return Color("#5e4630")
		var c: Color = tone[x / 32]
		return c.darkened(0.06 * (0.5 + 0.5 * sin(float(y) * 0.11 + float(x % 32) * 0.7))))
