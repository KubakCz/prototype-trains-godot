class_name CompoundTurnoutWidget
extends TrackMarkerWidget
## The one floating control for a [CompoundTurnout]: a click cycles the whole
## assembly, however many sets of points it is made of.
##
## A miniature of the assembly's whole track with its set routes in green, and
## under it the same [enum TurnoutWidget.Caption] a single turnout's widget
## carries - the position being the assembly's own ([code]STRAIGHT[/code],
## [code]CROSS[/code], ...), not its members'.
##
## The schematic is drawn in the assembly's own frame and then turned to match
## the camera, rather than projected point by point like [TurnoutWidget]'s. Two
## tracks 4.5 m apart over a 40 m crossover are a 10:1 sliver at any honest
## scale, so the across-track direction is stretched until the X is visible, and
## an independent stretch is only possible in a frame where "across" means
## something.

const _SCHEMATIC_BOX := Vector2(78.0, 50.0)
const _LABEL_HEIGHT := 15.0
const _PADDING := Vector2(9.0, 4.0)
## Room left around the drawing inside the box.
const _INSET := 7.0
## The most the across-track direction is stretched relative to the along-track
## one. Enough to open a three-way's branches, not so much that a crossover turns
## into a ladder.
const _MAX_STRETCH := 6.0
## How many samples a piece of track is drawn with.
const _SAMPLES := 8

const _COLOR_SET := Color(0.25, 1.0, 0.35)
const _COLOR_UNSET := Color(0.85, 0.2, 0.18)
const _COLOR_LABEL := Color(0.93, 0.94, 0.96)
const _COLOR_NORMAL := Color(0.92, 0.93, 0.95)
const _COLOR_REVERSE := Color(1.0, 0.65, 0.08)

var compound: CompoundTurnout
var caption := TurnoutWidget.Caption.ALL: set = _set_caption


func _ready() -> void:
	super._ready()
	if compound != null and not compound.position_changed.is_connected(_on_position_changed):
		compound.position_changed.connect(_on_position_changed)


#region Widget contract
func marker_anchor() -> Vector3:
	return compound.overlay_anchor()


## White in the first position - straight, parallel - orange in any other, red
## when the members are in a combination the assembly does not describe.
func accent_color() -> Color:
	match compound.compound_position:
		0:
			return _COLOR_NORMAL
		CompoundTurnout.MIXED:
			return _COLOR_UNSET
		_:
			return _COLOR_REVERSE


func activate() -> void:
	if compound.player_operable:
		compound.cycle()


func is_alive() -> bool:
	return compound != null and is_instance_valid(compound)


func expanded_size() -> Vector2:
	if caption == TurnoutWidget.Caption.NO_TEXT:
		return _SCHEMATIC_BOX
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text_width := font.get_string_size(_caption_text(), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, font_size).x
	return Vector2(maxf(text_width + _PADDING.x * 2.0, _SCHEMATIC_BOX.x),
			_SCHEMATIC_BOX.y + _LABEL_HEIGHT)


func _draw_expanded(accent: Color) -> void:
	_draw_schematic()
	if caption != TurnoutWidget.Caption.NO_TEXT:
		_draw_caption(accent)
#endregion


#region Drawing
## The whole assembly: every piece of its track in red, the set routes over it
## in green.
func _draw_schematic() -> void:
	var frame := _schematic_frame()
	if frame.is_empty():
		return
	for piece in compound.track_pieces():
		_draw_span(piece, frame, _COLOR_UNSET, 2.0)
	for route in compound.route_spans():
		_draw_span(route, frame, _COLOR_SET, 3.0)
	for member in compound.members:
		draw_circle(_to_widget(member.points_position(), frame), 2.0, _COLOR_LABEL)


func _draw_span(span: TrackWalker.Span, frame: Dictionary, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in _SAMPLES + 1:
		var at := span.rail.clamp_distance(lerpf(span.from, span.to, float(i) / float(_SAMPLES)))
		points.append(_to_widget(span.rail.sample_position(at), frame))
	draw_polyline(points, color, width)


## How the world maps onto the widget: the assembly's along- and across-track
## axes, how much each is scaled, and which way each points on screen. Empty
## when the camera cannot see the assembly well enough to say.
func _schematic_frame() -> Dictionary:
	var centre := compound.centre()
	var along := compound.heading()
	var across := along.cross(Vector3.UP).normalized()
	# How far the drawing reaches along and across the track.
	var reach_along := 0.0
	var reach_across := 0.0
	for piece in compound.track_pieces():
		for i in _SAMPLES + 1:
			var at := piece.rail.clamp_distance(lerpf(piece.from, piece.to,
					float(i) / float(_SAMPLES)))
			var offset := piece.rail.sample_position(at) - centre
			reach_along = maxf(reach_along, absf(offset.dot(along)))
			reach_across = maxf(reach_across, absf(offset.dot(across)))
	if reach_along <= 0.0 or camera.is_position_behind(centre):
		return {}

	# Which way the track runs on screen, and the across direction as the
	# perpendicular to it on the side the real across axis lands - so a
	# right-hand three-way stays right-handed whatever the camera does.
	var origin := camera.unproject_position(centre)
	var screen_along := camera.unproject_position(centre + along * 10.0) - origin
	if screen_along.length() < 0.5:
		screen_along = Vector2.RIGHT
	screen_along = screen_along.normalized()
	var screen_across := screen_along.orthogonal()
	var raw_across := camera.unproject_position(centre + across * 10.0) - origin
	if raw_across.dot(screen_across) < 0.0:
		screen_across = -screen_across

	# The drawing is turned to follow the track, so it has to fit the box's
	# smaller half in every direction.
	var box := Vector2(size.x, size.y if caption == TurnoutWidget.Caption.NO_TEXT
			else size.y - _LABEL_HEIGHT)
	var radius := minf(box.x, box.y) * 0.5 - _INSET
	var along_scale := (maxf(box.x, box.y) * 0.5 - _INSET) / reach_along
	var across_scale := along_scale
	if reach_across > 1e-3:
		across_scale = clampf(radius * 0.7 / reach_across, along_scale,
				along_scale * _MAX_STRETCH)
	# Keep the turned drawing inside the box: shrink until its corners fit.
	var corner := (screen_along * reach_along * along_scale).abs() \
			+ (screen_across * reach_across * across_scale).abs()
	var fit := minf((box.x * 0.5 - _INSET) / maxf(corner.x, 1e-3),
			(box.y * 0.5 - _INSET) / maxf(corner.y, 1e-3))
	if fit < 1.0:
		along_scale *= fit
		across_scale *= fit
	return {
		"centre": centre,
		"along": along,
		"across": across,
		"along_scale": along_scale,
		"across_scale": across_scale,
		"screen_along": screen_along,
		"screen_across": screen_across,
		"middle": box * 0.5,
	}


func _to_widget(point: Vector3, frame: Dictionary) -> Vector2:
	var offset := point - (frame["centre"] as Vector3)
	var a := offset.dot(frame["along"] as Vector3) * float(frame["along_scale"])
	var c := offset.dot(frame["across"] as Vector3) * float(frame["across_scale"])
	return (frame["middle"] as Vector2) + (frame["screen_along"] as Vector2) * a \
			+ (frame["screen_across"] as Vector2) * c


## Laid out like [TurnoutWidget]'s: the name in the label colour, the position in
## the accent colour.
func _draw_caption(accent: Color) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var position_text := _position_text()
	var whole := font.get_string_size(_caption_text(), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, font_size).x
	var at := Vector2((size.x - whole) * 0.5, size.y - _PADDING.y)
	if _shows_name():
		draw_string(font, at, str(compound.name), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
				_COLOR_LABEL)
	if not position_text.is_empty():
		at.x += whole - font.get_string_size(position_text, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, font_size).x
		draw_string(font, at, position_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, accent)


func _caption_text() -> String:
	return TurnoutWidget.join_caption(str(compound.name) if _shows_name() else "",
			_position_text())


func _shows_name() -> bool:
	return caption == TurnoutWidget.Caption.TURNOUT_NAME or caption == TurnoutWidget.Caption.ALL


## Empty when the caption leaves the position out.
func _position_text() -> String:
	if caption != TurnoutWidget.Caption.TURNOUT_POSITION and caption != TurnoutWidget.Caption.ALL:
		return ""
	return compound.position_label(compound.compound_position)
#endregion


## The label names the position, and position names differ in length.
func _on_position_changed() -> void:
	refresh_size()
	queue_redraw()


func _set_caption(value: TurnoutWidget.Caption) -> void:
	if caption == value:
		return
	caption = value
	refresh_size()
	queue_redraw()
