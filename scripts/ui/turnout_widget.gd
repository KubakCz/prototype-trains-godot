class_name TurnoutWidget
extends TrackMarkerWidget
## One floating, clickable marker for one [Turnout].
##
## Created and positioned by [MarkerOverlay]. A miniature of the turnout's actual
## three legs, so the widget reads the same way the track does - a right-hand
## turnout looks right-handed - with whatever text [member caption] asks for under
## it. A click throws the points, which is what makes a turnout hittable when the
## camera is too far out to pick the 3D node.
##
## Everything about following the camera, keeping clear of the signal widgets and
## collapsing when far away comes from [TrackMarkerWidget] - step 3 pulled that
## out of here so signals and turnouts de-clutter against each other rather than
## each ignoring the other's existence.

## What is written under the miniature. Still an open question, so the overlay
## cycles it; [CompoundTurnoutWidget] shares the same choice.
enum Caption {
	## The miniature alone.
	NO_TEXT,
	TURNOUT_NAME,
	## [code]NORMAL[/code] or [code]REVERSE[/code], in the accent colour.
	TURNOUT_POSITION,
	## The name, then the position.
	ALL,
}

const _SCHEMATIC_RADIUS := 22.0
const _LABEL_HEIGHT := 15.0
const _PADDING := Vector2(9.0, 4.0)

const _COLOR_SET := Color(0.25, 1.0, 0.35)
const _COLOR_UNSET := Color(0.85, 0.2, 0.18)
const _COLOR_LABEL := Color(0.93, 0.94, 0.96)
const _COLOR_NORMAL := Color(0.92, 0.93, 0.95)
const _COLOR_REVERSE := Color(1.0, 0.65, 0.08)

var turnout: Turnout
var caption := Caption.ALL: set = _set_caption


func _ready() -> void:
	super._ready()
	if turnout != null and not turnout.position_changed.is_connected(queue_redraw):
		turnout.position_changed.connect(queue_redraw)


#region Widget contract
func marker_anchor() -> Vector3:
	return turnout.overlay_anchor()


func accent_color() -> Color:
	return (_COLOR_REVERSE if turnout.turnout_position == Turnout.Position.REVERSE
			else _COLOR_NORMAL)


func activate() -> void:
	if turnout.player_operable:
		turnout.throw_points()


func is_alive() -> bool:
	return turnout != null and is_instance_valid(turnout)


## Sized for the longer of the two positions, so throwing the points does not
## make the widget jump.
func expanded_size() -> Vector2:
	var box := Vector2(_SCHEMATIC_RADIUS * 2.4, _SCHEMATIC_RADIUS * 2.0)
	if caption == Caption.NO_TEXT:
		return box
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text_width := font.get_string_size(_caption_text(true), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, font_size).x
	return Vector2(maxf(text_width + _PADDING.x * 2.0, box.x), box.y + _LABEL_HEIGHT)


func _draw_expanded(accent: Color) -> void:
	var is_reverse := turnout.turnout_position == Turnout.Position.REVERSE
	_draw_legs(is_reverse)
	if caption != Caption.NO_TEXT:
		_draw_caption(accent, is_reverse)
#endregion


#region Drawing
## The three legs, projected through the camera so the miniature keeps the real
## layout: which side the branch is on, and which way the toe faces.
func _draw_legs(is_reverse: bool) -> void:
	var box_height: float = size.y if caption == Caption.NO_TEXT else size.y - _LABEL_HEIGHT
	var centre := Vector2(size.x * 0.5, box_height * 0.5)
	var toe := _project(Turnout.Leg.TOE)
	var through := _project(Turnout.Leg.THROUGH)
	var diverging := _exaggerate(through, _project(Turnout.Leg.DIVERGING))
	var set_arm := diverging if is_reverse else through
	var dead_arm := through if is_reverse else diverging

	# Dead leg first, so the route that is actually set is drawn over it.
	draw_line(centre, centre + dead_arm * _SCHEMATIC_RADIUS, _COLOR_UNSET, 2.0)
	# The set route runs right through the points as one line, toe to exit.
	draw_line(centre + toe * _SCHEMATIC_RADIUS, centre, _COLOR_SET, 3.0)
	draw_line(centre, centre + set_arm * _SCHEMATIC_RADIUS, _COLOR_SET, 3.0)
	draw_circle(centre, 2.5, _COLOR_LABEL)


## Opens the angle between the two forward legs out to something a 44 px picture
## can show.
##
## A properly built turnout diverges by only a few degrees, and drawn at true
## scale the miniature is three collinear lines. So the divergence is amplified -
## about its true sense, so a right-hand turnout still looks right-handed - while
## the through leg keeps its faithful direction and carries the main line's own
## curvature.
func _exaggerate(through: Vector2, diverging: Vector2) -> Vector2:
	const GAIN := 5.0
	var limit := deg_to_rad(52.0)
	if through == Vector2.ZERO or diverging == Vector2.ZERO:
		return diverging
	return through.rotated(clampf(through.angle_to(diverging) * GAIN, -limit, limit))


## A leg's heading at the points, as a unit vector on screen.
func _project(leg: Turnout.Leg) -> Vector2:
	var origin := turnout.points_position()
	var tip := turnout.leg_position(leg, turnout.leg_length)
	if camera.is_position_behind(origin) or camera.is_position_behind(tip):
		return Vector2.ZERO
	var screen := camera.unproject_position(tip) - camera.unproject_position(origin)
	return screen.normalized() if screen.length() > 0.5 else Vector2.ZERO


## The caption along the bottom edge: the name in the label colour, the position
## in the accent colour, so the word says what the border and the leader say.
func _draw_caption(accent: Color, is_reverse: bool) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var position_text := _position_text(is_reverse)
	var whole := font.get_string_size(_caption_text(is_reverse), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, font_size).x
	var at := Vector2((size.x - whole) * 0.5, size.y - _PADDING.y)
	if _shows_name():
		draw_string(font, at, str(turnout.name), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
				_COLOR_LABEL)
	if not position_text.is_empty():
		at.x += whole - font.get_string_size(position_text, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, font_size).x
		draw_string(font, at, position_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, accent)


func _caption_text(is_reverse: bool) -> String:
	return join_caption(str(turnout.name) if _shows_name() else "", _position_text(is_reverse))


func _shows_name() -> bool:
	return caption == Caption.TURNOUT_NAME or caption == Caption.ALL


## Empty when the caption leaves the position out.
func _position_text(is_reverse: bool) -> String:
	if caption != Caption.TURNOUT_POSITION and caption != Caption.ALL:
		return ""
	return "REVERSE" if is_reverse else "NORMAL"


## A caption's two parts on one line, either of them possibly absent. Shared with
## [CompoundTurnoutWidget].
static func join_caption(name_text: String, position_text: String) -> String:
	if name_text.is_empty() or position_text.is_empty():
		return name_text + position_text
	return "%s  %s" % [name_text, position_text]
#endregion


func _set_caption(value: Caption) -> void:
	if caption == value:
		return
	caption = value
	refresh_size()
	queue_redraw()
