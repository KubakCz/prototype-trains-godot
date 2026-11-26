class_name InterestPointWidget
extends TrackMarkerWidget
## The badge over an [InterestPoint]: a pill for a station, a box for a connection, in
## the point's colour, with its name written inside. Drawn on the floating marker layer
## rather than in 3D so that it is sized in interface pixels - it grows with the UI
## scale together with every other piece of text on screen.
##
## Sits on the top of the point's poles rather than floating above a leader line, and
## never collapses to a dot: the stations are what a dispatcher finds their way by. Not
## clickable - the 3D world behind it gets every click.
##
## With [member InterestPoint.show_names] off it is a bare circle or square.

const HEIGHT := 22.0
const FONT_SIZE := 14
## Room between the name and the badge's ends.
const PADDING := 8.0
const _BORDER := Color(1.0, 1.0, 1.0, 0.85)
const _CORNER_BOX := 3

var point: InterestPoint

var _style := StyleBoxFlat.new()


func _init() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_style.set_border_width_all(2)
	_style.border_color = _BORDER
	_style.anti_aliasing = true


func _process(_delta: float) -> void:
	# The name can be switched off, and renamed in the editor, at any time.
	var wanted := expanded_size()
	if not collapsed and size != wanted:
		size = wanted


func marker_anchor() -> Vector3:
	return point.marker_position()


func expanded_size() -> Vector2:
	if point == null or not InterestPoint.show_names:
		return Vector2(HEIGHT, HEIGHT)
	var text := ThemeDB.fallback_font.get_string_size(point.label(),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x
	return Vector2(maxf(text + 2.0 * PADDING, HEIGHT), HEIGHT)


func accent_color() -> Color:
	return point.color()


func is_alive() -> bool:
	return is_instance_valid(point) and point.is_inside_tree()


func collapsible() -> bool:
	return false


## Centred on the top of the poles.
func desired_rect(viewport: Vector2) -> Rect2:
	var extent := size * scale
	var top_left := anchor_screen - extent * 0.5
	return Rect2(top_left.clamp(Vector2.ZERO, Vector2(
			maxf(viewport.x - extent.x, 0.0), maxf(viewport.y - extent.y, 0.0))), extent)


## The badge's own centre: no leader line unless the layout had to push it aside.
func leader_start() -> Vector2:
	return position + size * 0.5 * scale


func _draw_frame(accent: Color) -> void:
	_style.bg_color = accent
	_style.set_corner_radius_all(_CORNER_BOX if point.is_square() else int(size.y * 0.5))
	draw_style_box(_style, Rect2(Vector2.ZERO, size))


func _draw_expanded(accent: Color) -> void:
	if not InterestPoint.show_names:
		return
	var font := ThemeDB.fallback_font
	# Dark letters on a light colour, light ones on a dark colour.
	var ink := Color(0.05, 0.05, 0.06) if accent.get_luminance() > 0.5 else Color.WHITE
	var baseline := (size.y + font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) * 0.5
	draw_string(font, Vector2(0.0, baseline), point.label(), HORIZONTAL_ALIGNMENT_CENTER,
			size.x, FONT_SIZE, ink)
