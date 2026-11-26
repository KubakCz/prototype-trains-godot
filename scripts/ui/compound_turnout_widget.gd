class_name CompoundTurnoutWidget
extends SchematicMarkerWidget
## The one floating control for a [CompoundTurnout]: a click cycles the whole
## assembly, however many sets of points it is made of.
##
## A miniature of the assembly's whole track with its set routes in green, and
## under it the same [enum SchematicMarkerWidget.Caption] a single turnout's widget
## carries - the position being the assembly's own ([code]STRAIGHT[/code],
## [code]CROSS[/code], ...), not its members'.
##
## The schematic is drawn in the assembly's own frame and then turned to match
## the camera, rather than projected point by point like [TurnoutWidget]'s. Two
## tracks 4.5 m apart over a 40 m crossover are a 10:1 sliver at any honest
## scale, so the across-track direction is stretched until the X is visible, and
## an independent stretch is only possible in a frame where "across" means
## something.

## How the world maps onto the widget: the assembly's along- and across-track
## axes, how much each is scaled, and which way each points on screen.
class SchematicFrame:
	var centre: Vector3
	var along: Vector3
	var across: Vector3
	var along_scale: float
	var across_scale: float
	var screen_along: Vector2
	var screen_across: Vector2
	## The middle of the miniature's box, in widget coordinates.
	var middle: Vector2

	func to_widget(point: Vector3) -> Vector2:
		var offset := point - centre
		var a := offset.dot(along) * along_scale
		var c := offset.dot(across) * across_scale
		return middle + screen_along * a + screen_across * c


const _SCHEMATIC_BOX := Vector2(78.0, 50.0)
## Room left around the drawing inside the box.
const _INSET := 7.0
## The most the across-track direction is stretched relative to the along-track
## one. Enough to open a three-way's branches, not so much that a crossover turns
## into a ladder.
const _MAX_STRETCH := 6.0
## How many samples a piece of track is drawn with.
const _SAMPLES := 8

var compound: CompoundTurnout


func _ready() -> void:
	super._ready()
	# The caption names the position, and position names differ in length.
	if compound != null and not compound.position_changed.is_connected(_restyle):
		compound.position_changed.connect(_restyle)


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
			return _COLOR_STOP
		_:
			return _COLOR_REVERSE


func activate() -> void:
	if compound.player_operable:
		compound.cycle()


func is_alive() -> bool:
	return compound != null and is_instance_valid(compound)


func expanded_size() -> Vector2:
	return _size_with_caption(_SCHEMATIC_BOX, _position_word())


func _subject_name() -> String:
	return str(compound.name)


func _position_word() -> String:
	return compound.position_label(compound.compound_position)
#endregion


#region Drawing
## The whole assembly: every piece of its track in red, the set routes over it
## in green.
func _draw_schematic() -> void:
	var frame := _schematic_frame()
	if frame == null:
		return
	for piece in compound.track_pieces():
		_draw_span(piece, frame, _COLOR_STOP, 2.0)
	for route in compound.route_spans():
		_draw_span(route, frame, _COLOR_GO, 3.0)
	for member in compound.members:
		draw_circle(frame.to_widget(member.points_position()), 2.0, _COLOR_TEXT)


func _draw_span(span: TrackWalker.Span, frame: SchematicFrame, color: Color,
		width: float) -> void:
	var points := PackedVector2Array()
	for point in _span_points(span):
		points.append(frame.to_widget(point))
	draw_polyline(points, color, width)


## [constant _SAMPLES] points along [param span], both ends included.
func _span_points(span: TrackWalker.Span) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in _SAMPLES + 1:
		var at := span.rail.clamp_distance(lerpf(span.from, span.to, float(i) / float(_SAMPLES)))
		points.append(span.rail.sample_position(at))
	return points


## How the world maps onto the widget, or null when the camera cannot see the
## assembly well enough to say.
func _schematic_frame() -> SchematicFrame:
	var centre := compound.centre()
	var along := compound.heading()
	var across := along.cross(Vector3.UP).normalized()
	# How far the drawing reaches along and across the track.
	var reach_along := 0.0
	var reach_across := 0.0
	for piece in compound.track_pieces():
		for point in _span_points(piece):
			var offset := point - centre
			reach_along = maxf(reach_along, absf(offset.dot(along)))
			reach_across = maxf(reach_across, absf(offset.dot(across)))
	if reach_along <= 0.0 or camera.is_position_behind(centre):
		return null

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
	var box := _schematic_box()
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

	var frame := SchematicFrame.new()
	frame.centre = centre
	frame.along = along
	frame.across = across
	frame.along_scale = along_scale
	frame.across_scale = across_scale
	frame.screen_along = screen_along
	frame.screen_across = screen_across
	frame.middle = box * 0.5
	return frame
#endregion


func _caption_text() -> String:
	return _caption_for(_position_word())
