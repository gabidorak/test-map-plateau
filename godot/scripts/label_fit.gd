extends RefCounted
## Keeps a Label3D's text inside the plate or panel it is written on: fit measures the text with the label's font (its
## lines, its wrapping width, its outline) and lowers the font size (and the outline with it) until it fits `box`, m
## (width, height); a label that fits keeps its size. The box and the size it was given are kept on the label
## (meta), so set_text can refit it from that size when its text changes.

const MIN_SIZE := 8


static func fit(l: Label3D, box: Vector2) -> void:
	if not l.has_meta("fit_box"):
		l.set_meta("fit_box", box)
		l.set_meta("fit_size", l.font_size)
		l.set_meta("fit_outline", l.outline_size)
	var full: int = l.get_meta("fit_size")
	var outline: int = l.get_meta("fit_outline")
	var font: Font = l.font if l.font else ThemeDB.fallback_font
	var wrap := l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.width > 0.0
	var brk := TextServer.BREAK_MANDATORY
	if wrap:
		brk |= TextServer.BREAK_WORD_BOUND
		if l.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART:
			brk |= TextServer.BREAK_ADAPTIVE
		elif l.autowrap_mode == TextServer.AUTOWRAP_ARBITRARY:
			brk |= TextServer.BREAK_GRAPHEME_BOUND
	var fits := func(size: int) -> bool:
		var o := outline * float(size) / full
		var s := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, l.width if wrap else -1.0, size, -1,
				brk)
		s.y += l.text.count("\n") * l.line_spacing
		s = (s + Vector2(o, o)) * l.pixel_size
		return s.x <= box.x and s.y <= box.y
	# the largest size that fits (by halves: a wrapped text shrunk can fall back to fewer lines, so not by ratio)
	var size := full
	if not fits.call(full):
		var lo := MIN_SIZE
		var hi := full - 1
		while lo < hi:
			var mid := (lo + hi + 1) / 2
			if fits.call(mid):
				lo = mid
			else:
				hi = mid - 1
		size = lo
	l.font_size = size
	l.outline_size = roundi(outline * float(size) / full)


## Sets the text of a label given a box by fit, and fits it again (from the size it had before its first fit).
static func set_text(l: Label3D, text: String) -> void:
	l.text = text
	if l.has_meta("fit_box"):
		fit(l, l.get_meta("fit_box"))
