class_name TurnoutWidget
extends TrackMarkerWidget
## One floating, clickable marker for one [Turnout].
##
## Created and positioned by [MarkerOverlay]; the two styles are the ones the
## overlay's turnout modes offer. Both throw the points when clicked, which is
## what makes a turnout hittable when the camera is too far out to pick the 3D
## node.
##
## Everything about following the camera, keeping clear of the signal widgets and
## collapsing when far away comes from [TrackMarkerWidget] - step 3 pulled that
## out of here so signals and turnouts de-clutter against each other rather than
## each ignoring the other's existence.

enum Style {
	## Name and position letter only: a guaranteed click target.
	BADGE,
	## A miniature of the turnout's actual three legs, so the widget reads the
	## same way the track does - a right-hand turnout looks right-handed.
	SCHEMATIC,
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
var style := Style.SCHEMATIC: set = _set_style


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


func expanded_size() -> Vector2:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text_width := font.get_string_size(_label_text(true), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, font_size).x
	if style == Style.BADGE:
		return Vector2(text_width, font.get_height(font_size)) + _PADDING * 2.0
	return Vector2(maxf(text_width + _PADDING.x * 2.0, _SCHEMATIC_RADIUS * 2.4),
			_SCHEMATIC_RADIUS * 2.0 + _LABEL_HEIGHT)


func _draw_expanded(accent: Color) -> void:
	var is_reverse := turnout.turnout_position == Turnout.Position.REVERSE
	if style == Style.SCHEMATIC:
		_draw_legs(is_reverse)
	_draw_label(accent, is_reverse)
#endregion


#region Drawing
## The three legs, projected through the camera so the miniature keeps the real
## layout: which side the branch is on, and which way the toe faces.
func _draw_legs(is_reverse: bool) -> void:
	var centre := Vector2(size.x * 0.5, (size.y - _LABEL_HEIGHT) * 0.5)
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


func _draw_label(accent: Color, is_reverse: bool) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text := _label_text(is_reverse)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var baseline: float = (size.y - _PADDING.y if style == Style.SCHEMATIC
			else (size.y + text_size.y) * 0.5 - font.get_descent(font_size))
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, baseline), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
			accent if style == Style.BADGE else _COLOR_LABEL)


func _label_text(is_reverse: bool) -> String:
	if style == Style.BADGE:
		return "%s  %s" % [turnout.name, "R" if is_reverse else "N"]
	return str(turnout.name)
#endregion


func _set_style(value: Style) -> void:
	if style == value:
		return
	style = value
	refresh_size()
	queue_redraw()
