class_name TurnoutWidget
extends SchematicMarkerWidget
## One floating, clickable marker for one [Turnout].
##
## Created and positioned by [MarkerOverlay]. A miniature of the turnout's actual
## three legs, so the widget reads the same way the track does - a right-hand
## turnout looks right-handed - with whatever text [member caption] asks for under
## it. A click throws the points, which is what makes a turnout hittable when the
## camera is too far out to pick the 3D node.

const _SCHEMATIC_RADIUS := 22.0

var turnout: Turnout


func _ready() -> void:
	super._ready()
	if turnout != null and not turnout.position_changed.is_connected(queue_redraw):
		turnout.position_changed.connect(queue_redraw)


#region Widget contract
func marker_anchor() -> Vector3:
	return turnout.overlay_anchor()


func accent_color() -> Color:
	return _COLOR_REVERSE if _is_reverse() else _COLOR_NORMAL


func activate() -> void:
	if turnout.player_operable:
		turnout.throw_points()


func is_alive() -> bool:
	return turnout != null and is_instance_valid(turnout)


## Sized for the longer of the two positions, so throwing the points does not
## make the widget jump.
func expanded_size() -> Vector2:
	return _size_with_caption(Vector2(_SCHEMATIC_RADIUS * 2.4, _SCHEMATIC_RADIUS * 2.0),
			_position_name(true))


func _subject_name() -> String:
	return str(turnout.name)


func _position_word() -> String:
	return _position_name(_is_reverse())
#endregion


#region Drawing
## The three legs, projected through the camera so the miniature keeps the real
## layout: which side the branch is on, and which way the toe faces.
func _draw_schematic() -> void:
	var is_reverse := _is_reverse()
	var centre := _schematic_box() * 0.5
	var toe := _project(Turnout.Leg.TOE)
	var through := _project(Turnout.Leg.THROUGH)
	var diverging := _exaggerate(through, _project(Turnout.Leg.DIVERGING))
	var set_arm := diverging if is_reverse else through
	var dead_arm := through if is_reverse else diverging

	# Dead leg first, so the route that is actually set is drawn over it.
	draw_line(centre, centre + dead_arm * _SCHEMATIC_RADIUS, _COLOR_STOP, 2.0)
	# The set route runs right through the points as one line, toe to exit.
	draw_line(centre + toe * _SCHEMATIC_RADIUS, centre, _COLOR_GO, 3.0)
	draw_line(centre, centre + set_arm * _SCHEMATIC_RADIUS, _COLOR_GO, 3.0)
	draw_circle(centre, 2.5, _COLOR_TEXT)


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
#endregion


func _caption_text(is_reverse: bool) -> String:
	return _caption_for(_position_name(is_reverse))


func _is_reverse() -> bool:
	return turnout.turnout_position == Turnout.Position.REVERSE


static func _position_name(is_reverse: bool) -> String:
	return "REVERSE" if is_reverse else "NORMAL"
