@tool
class_name Turnout
extends Node3D
## Where one rail diverges from another, and the rule for who is allowed past.
##
## A turnout lives at [member main_distance] along [member main_rail] - which runs
## straight through it - and welds one end of [member branch_rail] to that point.
## It therefore has three legs:
##
## - the [b]toe[/b], along the main rail on the side the points face,
## - the [b]through[/b] leg, the main rail carrying on past the points,
## - the [b]diverging[/b] leg, the branch rail leaving the points.
##
## [member diverge_towards] says which way along the main rail the diverging move
## leads, and so which of the two main-rail legs is the toe. Which side the branch
## leaves on is not authored at all: it falls out of where the branch curve's
## points are, so the same script makes a left-hand turnout, a right-hand one, a
## turnout on a curve or a symmetric Y.
##
## Passage rules, and the whole point of the node:
##
## - From the toe, a train always passes, taking whichever route is set. This is a
##   [i]facing[/i] move.
## - From the through or the diverging leg, a train passes only if the points are
##   set for the leg it is standing on. This is a [i]trailing[/i] move, and if the
##   points are against it the train stops at them and waits. See [TrackWalker],
##   which is what actually walks a train through.

## Which route the points are set for.
enum Position {
	## The through route: a train from the toe stays on the main rail.
	NORMAL,
	## The diverging route: a train from the toe is switched onto the branch.
	REVERSE,
}

## An end of a rail, by the rail's own drawn direction.
enum RailEnd { START, END }

## The three tracks meeting at the points.
enum Leg {
	## Along the main rail, on the side the points face. Always connected.
	TOE,
	## The main rail carrying on past the points. Connected when normal.
	THROUGH,
	## The branch rail leaving the points. Connected when reverse.
	DIVERGING,
}

## Which way along the main rail the diverging move leads. The opposite side is
## the toe, so this is also "which end of the main rail the points face".
enum DivergeTowards { RAIL_START, RAIL_END }

## Where a train ends up once it is through the points. Kept here rather than in
## [TrackWalker] so that the walker can name this script without this script
## having to name the walker back.
class Exit:
	var rail: Rail
	var distance: float
	## Travel direction on [member rail], towards increasing distance when +1.
	var direction: int

	func _init(p_rail: Rail, p_distance: float, p_direction: int) -> void:
		rail = p_rail
		distance = p_distance
		direction = p_direction

	## The distance [param along] metres on from here in [member direction], kept
	## on the rail.
	func distance_at(along: float) -> float:
		return rail.clamp_distance(distance + float(direction) * along)


## Every leg, toe first.
const LEGS: Array[Leg] = [Leg.TOE, Leg.THROUGH, Leg.DIVERGING]

## How close to the points a train has to be for this turnout to claim it. Also
## the tolerance on telling two legs of a self-connecting rail apart.
const AT_POINTS := 0.05

## Beyond this, the branch is leaving the points at an angle no train could take,
## and the level almost certainly needs Align Branch To Turnout run on it.
const _MAX_DIVERGE_DEGREES := 45.0

## How far down a leg [method branch_side] and [method leg_heading] look to work
## out which way it actually goes. Long enough for a real turnout's divergence to
## be unambiguous, short enough that the leg has not started curving back.
const _LEG_PROBE := 14.0

const _COLOR_POST := Color(0.30, 0.31, 0.33)
const _COLOR_NORMAL := Color(0.92, 0.93, 0.95)
const _COLOR_REVERSE := Color(1.0, 0.65, 0.08)

## The marker's dimensions. The offset is measured horizontally from the centre
## line; the heights are measured up from the railhead, not from the ground, so
## that the banner stays level with the track and the post is stretched down to
## whatever ground it happens to stand on.
const _MARKER_OFFSET := 2.4
const _POST_TOP := 1.5
const _BANNER_HEIGHT := 1.6
const _PICKER_HEIGHT := 0.9
## Shortest the post may get where the ground beside the track stands higher than
## the track itself.
const _POST_MIN_HEIGHT := 0.6

## Emitted whenever the points move, however they were moved.
signal position_changed
## Emitted when the player clicks the 3D marker, whether or not that throws the
## points. A [CompoundTurnout] listens to its members through this, so a click on
## any of them cycles the whole assembly.
signal clicked

@export_group("Main Rail")
## The rail that runs straight through the points.
@export var main_rail: Rail: set = _set_main_rail
## Metres along [member main_rail] at which the points sit.
@export var main_distance := 0.0: set = _set_main_distance
## Which way along the main rail the diverging move leads. The toe faces the
## other way, so this decides which trains make a facing move and which a
## trailing one.
@export var diverge_towards := DivergeTowards.RAIL_END: set = _set_diverge_towards

@export_group("Branch Rail")
## The diverging route. One of its ends is welded to the points.
@export var branch_rail: Rail: set = _set_branch_rail
## Which end of [member branch_rail] is the one at the points.
@export var branch_end := RailEnd.START: set = _set_branch_end
## Moves the branch curve's attached end onto the points and turns its handle so
## the branch leaves tangent to the main rail. Run this after moving either rail.
@export_tool_button("Align Branch To Turnout") var _align_button := align_branch_to_turnout
## Re-run the alignment when the level starts, after the rails have snapped
## themselves to the ground. Snapping moves both rails independently and by
## different amounts, so without this a hand-aligned branch drifts a few
## centimetres off the points and trains visibly jump on handover. Runtime only,
## like [member Rail.snap_on_ready].
@export var align_branch_on_ready := true

@export_group("Position")
@export var turnout_position := Position.NORMAL: set = _set_turnout_position
## Whether clicking the turnout in the running game throws it. A
## [CompoundTurnout] turns this off on its members, because it drives them on the
## player's behalf.
@export var player_operable := true

@export_group("Debug Draw")
## The three-leg overlay: the set route and the toe in green, the dead leg in
## red. Driven by [MarkerOverlay] at runtime, so its overlay modes can hide it.
@export var debug_draw := true: set = _set_debug_draw
## How far along each leg the overlay is drawn.
@export var leg_length := 12.0
## Height above the railhead the overlay floats at.
@export var overlay_lift := 0.55

var _debug_mesh: MeshInstance3D
## The post and banner beside the track, standing on the ground.
var _marker := TracksideModel.new()
var _banner_pivot: Node3D
var _banner: MeshInstance3D
## The [CompoundTurnout] this turnout is a member of, or null. Set by the
## assembly, never authored. Typed as [Node3D] so this script does not have to
## name that one back - the same reason [Rail] keeps its attachments untyped.
var assembly: Node3D: set = _set_assembly


func _ready() -> void:
	if align_branch_on_ready and not Engine.is_editor_hint():
		align_branch_to_turnout()
	_place_on_rail()
	_rebuild_marker()
	_refresh_debug_mesh()


func _enter_tree() -> void:
	_attach_to_rails()
	add_to_group(Ground.STANDING_GROUP)


func _exit_tree() -> void:
	_detach_from_rails()
	remove_from_group(Ground.STANDING_GROUP)


## The ground under the marker has been cut anew (see [constant Ground.STANDING_GROUP]).
func ground_changed() -> void:
	_update_marker_frame()


#region Topology
## True when both rails are present and long enough to be sampled.
func is_usable() -> bool:
	return (main_rail != null and main_rail.rail_length() > 0.0
			and branch_rail != null and branch_rail.rail_length() > 0.0)


## [member main_distance], kept on the rail.
func points_distance() -> float:
	return main_rail.clamp_distance(main_distance) if main_rail != null else 0.0


## Distance along the branch rail at which it meets the points: its start or its
## far end, depending on [member branch_end].
func branch_distance() -> float:
	if branch_rail == null:
		return 0.0
	return 0.0 if branch_end == RailEnd.START else branch_rail.rail_length()


## +1 when the diverging move runs towards increasing distance on the main rail.
func diverge_sign() -> int:
	return 1 if diverge_towards == DivergeTowards.RAIL_END else -1


## Travel direction on the branch rail for a train leaving the points along it.
func branch_exit_sign() -> int:
	return 1 if branch_end == RailEnd.START else -1


## Every distance at which this turnout touches [param rail]. The walker uses it
## to find the next turnout ahead of a train.
func distances_on(rail: Rail) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	if rail == null:
		return found
	if rail == main_rail:
		found.append(points_distance())
	if rail == branch_rail:
		found.append(branch_distance())
	return found


## Where a train arriving at the points on [param from_rail] at
## [param from_distance], travelling in [param direction], comes out - or
## [code]null[/code] if the points are set against it and it has to wait.
func traverse(from_rail: Rail, from_distance: float, direction: int) -> Exit:
	if not is_usable():
		return null
	var is_reverse := turnout_position == Position.REVERSE
	var diverge := diverge_sign()
	var points := points_distance()

	# The branch leg is tested first, because when a rail is both the main and
	# the branch - a rail looping back onto itself - the arrival distance and
	# direction are the only things telling the two legs apart.
	if (from_rail == branch_rail and direction == -branch_exit_sign()
			and absf(from_distance - branch_distance()) <= AT_POINTS):
		# Trailing move up the diverging route.
		return Exit.new(main_rail, points, -diverge) if is_reverse else null

	if from_rail == main_rail and absf(from_distance - points) <= AT_POINTS:
		if direction == diverge:
			# Facing move out of the toe: always allowed, onto whichever route
			# is set. This is the only leg a train can never be refused from.
			if is_reverse:
				return Exit.new(branch_rail, branch_distance(), branch_exit_sign())
			return Exit.new(main_rail, points, diverge)
		# Trailing move down the through leg.
		return null if is_reverse else Exit.new(main_rail, points, -diverge)

	# Not actually at this turnout. Treated as blocked, which is the safe answer;
	# the walker only calls this for a turnout it matched by distance.
	return null
#endregion


#region Geometry
## The points, in global space.
func points_position() -> Vector3:
	if main_rail == null:
		return global_position
	return main_rail.sample_position(points_distance())


## Where the marker post stands, in global space: on the ground beside the track.
func marker_position() -> Vector3:
	return _marker.frame.origin


## How far the railhead is above the ground at the marker. The banner is hung
## this much higher than its nominal height, so it stays level with the track
## rather than with the ground the post happens to stand on.
func marker_lift() -> float:
	return _marker.lift


## Centre of the click collider, in global space. Where the marker stands depends
## on the ground under it, so anything aiming at it asks rather than guesses.
func click_target_position() -> Vector3:
	return _marker.frame * Vector3(0.0, _marker.lift + _PICKER_HEIGHT, 0.0)


## Where the floating overlay widget's leader line lands, in global space. Just
## above the marker, so the widget is visibly tied to its turnout.
func overlay_anchor() -> Vector3:
	return points_position() + Vector3.UP * 2.4


## Where [param leg] starts and which way it runs: the points, on the leg's
## rail, travelling away from them. What a walk out along that leg starts from.
func leg_exit(leg: Leg) -> Exit:
	match leg:
		Leg.DIVERGING:
			return Exit.new(branch_rail, branch_distance(), branch_exit_sign())
		Leg.THROUGH:
			return Exit.new(main_rail, points_distance(), diverge_sign())
		_:
			return Exit.new(main_rail, points_distance(), -diverge_sign())


## Unit vector leaving the points along the toe leg.
func toe_direction() -> Vector3:
	if main_rail == null:
		return Vector3.FORWARD
	return main_rail.sample_forward(points_distance()) * float(-diverge_sign())


## Unit vector leaving the points along the through leg - the direction of a
## facing move with the points normal.
func through_direction() -> Vector3:
	return -toe_direction()


## Unit vector leaving the points along the branch.
func diverging_direction() -> Vector3:
	if branch_rail == null:
		return through_direction()
	return branch_rail.sample_forward(branch_distance()) * float(branch_exit_sign())


## +1 when the branch leaves to the right of a train making the facing move,
## -1 when it leaves to the left. Level data, read off the curves rather than
## authored - which is what lets one script be a left-hand turnout, a right-hand
## one, or a symmetric Y.
##
## Measured a few metres along, not at the points: a correctly aligned branch
## leaves exactly tangent to the main rail, so at the points itself there is no
## sideways component to read. Comparing against where the main rail has got to
## by then, rather than against the points, keeps the answer right for a turnout
## sitting on a curve.
func branch_side() -> int:
	if not is_usable():
		return 1
	var travel := through_direction()
	var up := main_rail.sample_up(points_distance())
	var right := travel.cross(up)
	if right.length_squared() < 1e-9:
		return 1
	var probe := minf(_LEG_PROBE, branch_rail.rail_length())
	var offset := leg_position(Leg.DIVERGING, probe) - leg_position(Leg.THROUGH, probe)
	return 1 if offset.dot(right.normalized()) >= 0.0 else -1


## Global position [param along] metres out along [param leg], following the
## actual rail rather than a straight line.
func leg_position(leg: Leg, along: float) -> Vector3:
	if not is_usable():
		return global_position
	var exit := leg_exit(leg)
	return exit.rail.sample_position(exit.distance_at(along))


## Which way [param leg] visibly heads: the chord from the points out to
## [method leg_position], not the tangent at the points.
##
## The distinction matters. A correctly aligned branch leaves exactly tangent to
## the main rail, so at the points the through and diverging legs point the same
## way and anything drawn from the tangents cannot tell them apart. What a reader
## recognises as the shape of a turnout only appears a few metres along.
func leg_heading(leg: Leg, along := _LEG_PROBE) -> Vector3:
	var chord := leg_position(leg, along) - points_position()
	if chord.length_squared() < 1e-9:
		return through_direction() if leg != Leg.TOE else toe_direction()
	return chord.normalized()


## Whether a train standing on [param leg] is connected through the points.
func leg_is_set(leg: Leg) -> bool:
	match leg:
		Leg.THROUGH:
			return turnout_position == Position.NORMAL
		Leg.DIVERGING:
			return turnout_position == Position.REVERSE
		_:
			return true


## The leg the points are currently set to, out of the toe.
func set_leg() -> Leg:
	return Leg.DIVERGING if turnout_position == Position.REVERSE else Leg.THROUGH


## Angle in degrees between the branch and the main rail at the points. Near zero
## is a well-aligned turnout; the branch is meant to curve away further along.
func diverge_angle_degrees() -> float:
	if not is_usable():
		return 0.0
	return rad_to_deg(through_direction().angle_to(diverging_direction()))


## Puts the node itself on the rail, -Z along the through leg, so the marker
## boxes can be positioned in plain local space.
func _place_on_rail() -> void:
	if not _on_rail():
		return
	var up := main_rail.sample_up(points_distance())
	global_transform = Transform3D(
			Rail.basis_from_forward_up(through_direction(), up), points_position())


## Stands the marker on the ground beside the track, on the side the branch
## leaves, looking along the through leg.
func _update_marker_frame() -> void:
	if _on_rail():
		_marker.place(main_rail, points_distance(), through_direction(),
				float(branch_side()) * _MARKER_OFFSET)


func _on_rail() -> bool:
	return (main_rail != null and main_rail.is_inside_tree() and is_inside_tree()
			and main_rail.rail_length() > 0.0)
#endregion


#region Player operation
## The single entry point for throwing a turnout, whoever throws it. A
## [CompoundTurnout] drives its members through this.
func throw_points() -> void:
	turnout_position = (Position.NORMAL if turnout_position == Position.REVERSE
			else Position.REVERSE)


func _on_marker_pressed() -> void:
	clicked.emit()
	if player_operable:
		throw_points()


## True while the mouse is over the 3D marker. The floating widget answers for
## itself ([method TrackMarkerWidget.is_pointer_over]); between the two, a
## readout can say which turnout the player is pointing at.
func is_pointer_over() -> bool:
	return _marker.pointer_over
#endregion


#region Editor authoring
## Welds the branch curve's attached end onto the points, and turns its handle so
## the branch leaves tangent to the main rail. Tangency is what makes the handover
## smooth - a train crossing the points must not change direction abruptly - so
## the branch is expected to curve away over its next segment, not at the points.
func align_branch_to_turnout() -> void:
	if not is_usable():
		push_warning("Turnout '%s' cannot align: both rails must be set and have a curve." % name)
		return
	var curve := branch_rail.curve
	if curve.point_count < 2:
		push_warning("Turnout '%s' cannot align: branch '%s' needs at least two curve points."
				% [name, branch_rail.name])
		return

	var index := 0 if branch_end == RailEnd.START else curve.point_count - 1
	var to_branch := branch_rail.global_transform.affine_inverse()
	var local_point := to_branch * points_position()
	var local_heading := (branch_rail.global_basis.inverse() * through_direction()).normalized()

	# The handle on the interior side of the attached point is the one that sets
	# the departure tangent: `out` at the curve's start, `in` at its end, since
	# `in` handles point back down the curve.
	var interior := curve.get_point_out(index) if index == 0 else curve.get_point_in(index)
	var handle_length := interior.length()
	if handle_length < 0.5:
		var neighbour := curve.get_point_position(index + (1 if index == 0 else -1))
		handle_length = maxf(2.0, local_point.distance_to(neighbour) * 0.35)

	curve.set_point_position(index, local_point)
	var handle := local_heading * handle_length
	if index == 0:
		curve.set_point_out(index, handle)
		curve.set_point_in(index, -handle)
	else:
		curve.set_point_in(index, handle)
		curve.set_point_out(index, -handle)
	_place_on_rail()
	_update_marker_frame()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if main_rail == null:
		warnings.append("No main rail set.")
	elif main_rail.rail_length() <= 0.0:
		warnings.append("Main rail '%s' has no length." % main_rail.name)
	if branch_rail == null:
		warnings.append("No branch rail set.")
	elif branch_rail.curve == null or branch_rail.curve.point_count < 2:
		warnings.append("Branch rail '%s' needs at least two curve points." % branch_rail.name)
	if main_rail != null and main_rail == branch_rail:
		warnings.append("Main and branch rail are the same rail. Legs are then told apart "
				+ "by distance alone, which only works if the points and the attached end "
				+ "are far apart.")
	if not is_usable():
		return warnings

	var length := main_rail.rail_length()
	if main_distance < 0.0 or main_distance > length:
		warnings.append("main_distance %.1f m is off the main rail (0 - %.1f m)."
				% [main_distance, length])
	var toe_run := points_distance() if diverge_sign() > 0 else length - points_distance()
	if toe_run <= AT_POINTS:
		warnings.append(("The toe leg has no length: the points sit at the %s end of the main "
				+ "rail and face off it, so no train can make a facing move.")
				% ("start" if diverge_sign() > 0 else "end"))

	var gap := points_position().distance_to(
			branch_rail.sample_position(branch_distance()))
	if gap > 0.25:
		warnings.append("Branch '%s' meets the points %.2f m away. Run Align Branch To Turnout."
				% [branch_rail.name, gap])
	var angle := diverge_angle_degrees()
	if angle > _MAX_DIVERGE_DEGREES:
		warnings.append(("Branch leaves the points at %.0f deg, which no train could take. "
				+ "Run Align Branch To Turnout, or check branch_end and diverge_towards.")
				% angle)
	return warnings
#endregion


#region Marker meshes
## Post plus a banner that swings to point along whichever route is set: the
## smallest thing that reads as a turnout from a distance and gives the mouse
## something to hit. The blades themselves are part of the generated track
## ([TrackMesher]) and swing across when the points are thrown; this is still
## what the player clicks.
func _rebuild_marker() -> void:
	if not is_inside_tree():
		return
	_update_marker_frame()
	if _marker.root == null:
		var root := _marker.build(self, "Marker", _COLOR_POST, 0.26)
		_banner_pivot = Node3D.new()
		_banner_pivot.name = "BannerPivot"
		root.add_child(_banner_pivot)
		# White until _refresh_banner colours it, as a fresh material is.
		_banner = TracksideModel.add_box(_banner_pivot, "Banner", Color.WHITE,
				Vector3(0.2, 0.2, 1.9))
		# Offset along the pivot's own -Z, so the banner reads as an arm pointing
		# at the route rather than a bar sitting across it.
		_banner.position = Vector3(0.0, 0.0, -0.95)
		var sphere := SphereShape3D.new()
		sphere.radius = 2.2
		_marker.add_click_target(sphere)
		_marker.pressed.connect(_on_marker_pressed)
	_marker.stretch_post(_POST_TOP, _POST_MIN_HEIGHT)
	_marker.click_target.position = Vector3(0.0, _marker.lift + _PICKER_HEIGHT, 0.0)
	_refresh_banner()


## Swings the banner onto the set route and recolours it. Uses the leg's heading
## rather than its tangent at the points - from the tangents the two routes are
## indistinguishable, and the banner would never appear to move.
func _refresh_banner() -> void:
	if _banner_pivot == null or _banner == null or not is_usable():
		return
	var local := (_marker.root.global_basis.inverse() * leg_heading(set_leg())).normalized()
	# A yaw of theta sends local -Z to (-sin, 0, -cos), so match that to `local`.
	var yaw := atan2(-local.x, -local.z)
	_banner_pivot.transform = Transform3D(
			Basis(Vector3.UP, yaw), Vector3(0.0, _marker.lift + _BANNER_HEIGHT, 0.0))
	var material := _banner.material_override as StandardMaterial3D
	material.albedo_color = (_COLOR_REVERSE if turnout_position == Position.REVERSE
			else _COLOR_NORMAL)
#endregion


#region Debug draw
## Three stubs sampled along the real rails: the toe and the set route in green,
## the dead leg in red, which gets a cross at its far end.
func _refresh_debug_mesh() -> void:
	if not is_inside_tree():
		return
	# Drawn in global space: the node's own transform is derived from the rail,
	# so ignoring it keeps the leg maths free of round trips.
	_debug_mesh = DebugLines.ensure_instance(self, _debug_mesh, "TurnoutDebugDraw", true)
	var mesh := ImmediateMesh.new()
	_debug_mesh.mesh = mesh
	# A member of a compound turnout leaves its legs to the assembly, which draws
	# the routes through all of its members at once. Drawn one member at a time,
	# a three-way's second set of points would paint its toe green straight over
	# the first one's dead leg.
	if not debug_draw or not is_usable() or assembly != null:
		return

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, DebugLines.material(true))
	for leg in LEGS:
		_draw_leg(mesh, leg)
	TrackOverlay.points_post(mesh, points_position(), overlay_lift)
	mesh.surface_end()


func _draw_leg(mesh: ImmediateMesh, leg: Leg) -> void:
	var exit := leg_exit(leg)
	var steps := TrackOverlay.sample_count(leg_length)
	var distances := PackedFloat64Array()
	for i in steps + 1:
		distances.append(exit.distance_at(leg_length * float(i) / float(steps)))
	var is_set := leg_is_set(leg)
	var color := TrackOverlay.COLOR_SET if is_set else TrackOverlay.COLOR_UNSET
	TrackOverlay.band(mesh, exit.rail, distances, overlay_lift, color)
	if not is_set:
		TrackOverlay.dead_end(mesh, exit.rail, distances[steps], overlay_lift, color)
#endregion


#region Rail registration
func _attach_to_rails() -> void:
	if main_rail != null:
		main_rail.attach(self)
	if branch_rail != null:
		branch_rail.attach(self)


func _detach_from_rails() -> void:
	_detach(main_rail)
	_detach(branch_rail)


func _detach(rail: Rail) -> void:
	if rail != null:
		rail.detach(self)


func _set_main_rail(value: Rail) -> void:
	_detach(main_rail)
	main_rail = value
	_attach_to_rails()
	_place_on_rail()
	_geometry_changed()


func _set_branch_rail(value: Rail) -> void:
	_detach(branch_rail)
	branch_rail = value
	_attach_to_rails()
	# Which side the marker stands on is read off the branch, so it moves too.
	_geometry_changed()


func _set_main_distance(value: float) -> void:
	main_distance = value
	_place_on_rail()
	_geometry_changed()


func _set_diverge_towards(value: DivergeTowards) -> void:
	diverge_towards = value
	_place_on_rail()
	_geometry_changed()


func _set_branch_end(value: RailEnd) -> void:
	branch_end = value
	_geometry_changed()


func _set_turnout_position(value: Position) -> void:
	var changed := turnout_position != value
	turnout_position = value
	_refresh_banner()
	_refresh_debug_mesh()
	if changed:
		position_changed.emit()


func _set_debug_draw(value: bool) -> void:
	# The overlay pushes its mode onto every turnout every frame.
	if debug_draw == value:
		return
	debug_draw = value
	_refresh_debug_mesh()


func _set_assembly(value: Node3D) -> void:
	assembly = value
	_refresh_debug_mesh()


func _geometry_changed() -> void:
	_rebuild_marker()
	_refresh_debug_mesh()
	update_configuration_warnings()
#endregion
