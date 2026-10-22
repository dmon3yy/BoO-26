class_name UiKit
extends RefCounted
## Shared look for text and panels: the Hearthstone pixel font at native size.

const FONT_PATH := "res://game/art/fonts/hearthstone.fnt"
const INK := Color(0.93, 0.9, 0.82)
const DIM := Color(0.6, 0.62, 0.7)
const GOLD := Color(0.95, 0.78, 0.38)

static var _font: Font


static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH)
	return _font


static func label(text: String, pos: Vector2, color: Color = INK, width: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	if width > 0.0:
		l.custom_minimum_size.x = width     # size alone is reset when the text lays out
		l.size.x = width
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func panel(rect: Rect2, alpha: float = 0.82) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.09, alpha)
	sb.border_color = Color(0.72, 0.58, 0.32)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	p.add_theme_stylebox_override("panel", sb)
	return p
