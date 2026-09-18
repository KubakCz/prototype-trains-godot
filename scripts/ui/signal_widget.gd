class_name SignalWidget
extends TrackMarkerWidget
## The floating marker for one [RailSignal]: what it is showing, what it is
## called, and - the part a turnout widget never had to answer - which direction
## of travel it applies to.
##
## Direction is the hard half. A signal governs trains going one way, so a widget
## that only showed red or green would be telling half a story: the player has to
## know at a glance whether the red in front of them is theirs or the one facing
## the other way on the same piece of track. All three styles answer it, and the
## overlay cycles them because which answer reads best from a dispatcher's camera
## is not settled yet:
##
## - [constant Style.ARROW] - the badge itself is an arrow pointing the governed
##   way. Unmissable, and its collapsed form is an arrowhead rather than a dot.
## - [constant Style.PILL] - a plate with the lamp, the name and a small arrow
##   glyph. The quietest, and closest to the turnout badge.
## - [constant Style.SCHEMATIC] - a miniature of the real thing: a piece of track
##   with an arrowhead at the governed end and the lamp standing beside it, in the
##   same visual language as [TurnoutWidget]'s schematic.
##
## The direction is projected through the camera rather than assumed, so the
## arrow turns with the layout as the camera orbits.

enum Style {
	## The whole badge is an arrow pointing the governed way.
	ARROW,
	## A plate with the lamp, the name and an arrow glyph.
	PILL,
	## A miniature of the track with the lamp beside it.
	SCHEMATIC,
}

const _LAMP_RADIUS := 6.0
const _PADDING := Vector2(8.0, 5.0)
## How far the arrow's point sticks out past the body of the badge.
const _TIP := 11.0
const _GLYPH := 12.0
const _SCHEMATIC_SIZE := Vector2(86.0, 46.0)
const _LABEL_HEIGHT := 15.0

const _COLOR_CLEAR := Color(0.25, 1.0, 0.35)
const _COLOR_DANGER := Color(0.85, 0.2, 0.18)
const _COLOR_TRACK := Color(0.62, 0.64, 0.68)
const _COLOR_LABEL := Color(0.93, 0.94, 0.96)

var rail_signal: RailSignal
var style := Style.ARROW: set = _set_style


func _ready() -> void:
	super._ready()
	if rail_signal != null and not rail_signal.aspect_changed.is_connected(queue_redraw):
		rail_signal.aspect_changed.connect(queue_redraw)


#region Widget contract
func marker_anchor() -> Vector3:
	return rail_signal.overlay_anchor()


func accent_color() -> Color:
	return _COLOR_CLEAR if rail_signal.is_clear() else _COLOR_DANGER


func activate() -> void:
	if rail_signal.player_operable:
		rail_signal.toggle_aspect()


func is_alive() -> bool:
	return rail_signal != null and is_instance_valid(rail_signal)


func expanded_size() -> Vector2:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text_width := font.get_string_size(str(rail_signal.name), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, font_size).x
	var line := maxf(font.get_height(font_size), _LAMP_RADIUS * 2.0)
	match style:
		Style.ARROW:
			return Vector2(text_width + _LAMP_RADIUS * 2.0 + _TIP + _PADDING.x * 3.0,
					line + _PADDING.y * 2.0)
		Style.PILL:
			return Vector2(text_width + _LAMP_RADIUS * 2.0 + _GLYPH + _PADDING.x * 3.0,
					line + _PADDING.y * 2.0)
		_:
			return Vector2(maxf(text_width + _PADDING.x * 2.0, _SCHEMATIC_SIZE.x),
					_SCHEMATIC_SIZE.y + _LABEL_HEIGHT)
#endregion


#region Drawing
## The arrow style carries its meaning in its outline, so it replaces the frame
## rather than drawing inside the default one.
func _draw_frame(accent: Color) -> void:
	if style != Style.ARROW:
		super._draw_frame(accent)
		return
	var background := _COLOR_BACKGROUND
	if is_pointer_over():
		background = background.lightened(0.3)
	var outline := _arrow_polygon()
	draw_colored_polygon(outline, background)
	# Closed, so the point is drawn rather than left open.
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, accent, 1.0)


## A banner with a point on the leading end and a notch in its tail, built
## pointing right and mirrored when the governed direction runs the other way
## across the screen.
func _arrow_polygon() -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var points := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(w - _TIP, 0.0),
		Vector2(w, h * 0.5),
		Vector2(w - _TIP, h),
		Vector2(0.0, h),
		Vector2(_TIP * 0.5, h * 0.5),
	])
	if _points_left():
		for i in points.size():
			points[i] = Vector2(w - points[i].x, points[i].y)
	return points


func _draw_expanded(accent: Color) -> void:
	match style:
		Style.ARROW:
			_draw_arrow_contents(accent)
		Style.PILL:
			_draw_pill_contents(accent)
		_:
			_draw_schematic_contents(accent)


## Lamp and name, pushed away from whichever end the point is on so neither runs
## into it.
func _draw_arrow_contents(accent: Color) -> void:
	var inset := _TIP * 0.5 + _PADDING.x
	var left := _points_left()
	var lamp_x: float = size.x - inset if left else inset
	var far_edge: float = _TIP * 0.5 if left else size.x - _TIP * 0.5
	draw_circle(Vector2(lamp_x, size.y * 0.5), _LAMP_RADIUS, accent)
	_draw_centred_name((lamp_x + far_edge) * 0.5, size.y * 0.5, _COLOR_LABEL)


## Lamp, name, and a small triangle at the trailing edge pointing the governed
## way - the same information as the arrow style, in a quieter shape.
func _draw_pill_contents(accent: Color) -> void:
	draw_circle(Vector2(_PADDING.x + _LAMP_RADIUS, size.y * 0.5), _LAMP_RADIUS, accent)
	var glyph_centre := Vector2(size.x - _PADDING.x - _GLYPH * 0.5, size.y * 0.5)
	var direction := -1.0 if _points_left() else 1.0
	draw_colored_polygon(PackedVector2Array([
		glyph_centre + Vector2(direction * _GLYPH * 0.5, 0.0),
		glyph_centre + Vector2(-direction * _GLYPH * 0.4, -_GLYPH * 0.42),
		glyph_centre + Vector2(-direction * _GLYPH * 0.4, _GLYPH * 0.42),
	]), accent)
	var from := _PADDING.x + _LAMP_RADIUS * 2.0
	_draw_centred_name((from + size.x - _PADDING.x - _GLYPH) * 0.5, size.y * 0.5, _COLOR_LABEL)


## A piece of track with an arrowhead at the governed end and the lamp standing
## beside it, drawn along the track's own direction on screen so the miniature
## keeps the real layout the way the turnout schematic does.
func _draw_schematic_contents(accent: Color) -> void:
	var centre := Vector2(size.x * 0.5, (size.y - _LABEL_HEIGHT) * 0.5)
	var heading := _screen_heading()
	var reach: float = minf(size.x * 0.5, _SCHEMATIC_SIZE.x * 0.5) - _PADDING.x
	var tip := centre + heading * reach
	var tail := centre - heading * reach
	draw_line(tail, tip, _COLOR_TRACK, 2.0)
	var back := -heading * 9.0
	var side := Vector2(-heading.y, heading.x) * 5.0
	draw_colored_polygon(PackedVector2Array([tip, tip + back + side, tip + back - side]),
			_COLOR_TRACK)
	# The lamp sits on the signal's own side of the track: to the right of a train
	# travelling the governed way, which on screen is the heading turned right.
	draw_circle(centre + Vector2(-heading.y, heading.x) * (_LAMP_RADIUS + 4.0),
			_LAMP_RADIUS, accent)
	_draw_centred_name(size.x * 0.5, size.y - _PADDING.y, _COLOR_LABEL)


## An arrowhead rather than a dot, so a collapsed arrow-style widget still says
## which way it faces.
func _draw_collapsed(accent: Color) -> void:
	if style != Style.ARROW:
		super._draw_collapsed(accent)
		return
	var centre := size * 0.5
	var heading := _screen_heading()
	var back := -heading * COLLAPSED_DIAMETER
	var side := Vector2(-heading.y, heading.x) * COLLAPSED_DIAMETER * 0.55
	draw_colored_polygon(PackedVector2Array([
		centre + heading * COLLAPSED_DIAMETER * 0.6,
		centre + back + side,
		centre + back - side,
	]), accent)


func _draw_centred_name(centre_x: float, baseline_y: float, color: Color) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text := str(rail_signal.name)
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(font, Vector2(centre_x - extent.x * 0.5,
			baseline_y + extent.y * 0.5 - font.get_descent(font_size)),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
#endregion


#region Direction
## The governed direction as a unit vector on screen, measured along the real
## track a few metres on rather than from the tangent at the signal, so it stays
## honest on a curve.
func _screen_heading() -> Vector2:
	if camera == null or not is_alive():
		return Vector2.RIGHT
	var origin := rail_signal.signal_position()
	var ahead := rail_signal.ahead_position()
	if camera.is_position_behind(origin) or camera.is_position_behind(ahead):
		return Vector2.RIGHT
	var delta := camera.unproject_position(ahead) - camera.unproject_position(origin)
	return delta.normalized() if delta.length() > 0.5 else Vector2.RIGHT


## Whether the governed direction runs right to left across the screen. The
## badge styles only need this much of the heading.
func _points_left() -> bool:
	return _screen_heading().x < 0.0
#endregion


func _set_style(value: Style) -> void:
	if style == value:
		return
	style = value
	refresh_size()
	queue_redraw()
