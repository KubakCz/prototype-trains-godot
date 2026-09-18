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

const _COLOR_SET := Color(0.25, 1.0, 0.35)
const _COLOR_UNSET := Color(0.85, 0.2, 0.18)
const _COLOR_POINTS := Color(1.0, 1.0, 1.0)
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
## Whether clicking the turnout in the running game throws it. Turned off for
## turnouts that a step-4 compound assembly drives on the player's behalf.
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
## Upright, ground-anchored root the marker hangs off. See [method marker_frame].
var _marker: Node3D
var _marker_frame := Transform3D.IDENTITY
var _marker_lift := 0.0
var _post: MeshInstance3D
var _banner_pivot: Node3D
var _banner: MeshInstance3D
var _picker: StaticBody3D
## Whether the mouse is over the 3D marker. Only a readout uses it, but it is the
## model's own business: the floating widget has the same for its own rect.
var _pointer_over := false
static var _debug_material: StandardMaterial3D


func _ready() -> void:
	_attach_to_rails()
	if align_branch_on_ready and not Engine.is_editor_hint():
		align_branch_to_turnout()
	if not Engine.is_editor_hint():
		# Physics object picking is what turns a left click into an
		# `input_event` on `_picker`. Cheap, and off by default.
		get_viewport().physics_object_picking = true
	_place_on_rail()
	_rebuild_marker()
	_refresh_debug_mesh()


func _enter_tree() -> void:
	_attach_to_rails()


func _exit_tree() -> void:
	_detach_from_rails()


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


## The frame the marker is built in: standing on the ground beside the track, on
## the side the branch leaves, upright, looking along the through leg.
##
## Deliberately not the turnout node's own transform. That one is the rail's, so
## it pitches with the gradient, banks with the curve's tilt and is anchored to
## the railhead - a post built in it leans over and hangs in the air wherever the
## ground falls away beside the track.
func marker_frame() -> Transform3D:
	return _marker_frame


## Where the marker post stands, in global space: on the ground beside the track.
func marker_position() -> Vector3:
	return _marker_frame.origin


## How far the railhead is above the ground at the marker. The banner is hung
## this much higher than its nominal height, so it stays level with the track
## rather than with the ground the post happens to stand on.
func marker_lift() -> float:
	return _marker_lift


## Centre of the click collider, in global space. Where the marker stands depends
## on the ground under it, so anything aiming at it asks rather than guesses.
func click_target_position() -> Vector3:
	return _marker_frame * Vector3(0.0, _marker_lift + _PICKER_HEIGHT, 0.0)


## Where the floating overlay widget's leader line lands, in global space. Just
## above the marker, so the widget is visibly tied to its turnout.
func overlay_anchor() -> Vector3:
	return points_position() + Vector3.UP * 2.4


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
	if leg == Leg.DIVERGING:
		return branch_rail.sample_position(branch_rail.clamp_distance(
				branch_distance() + float(branch_exit_sign()) * along))
	var sign := diverge_sign() if leg == Leg.THROUGH else -diverge_sign()
	return main_rail.sample_position(main_rail.clamp_distance(
			points_distance() + float(sign) * along))


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
	if main_rail == null or not main_rail.is_inside_tree() or not is_inside_tree():
		return
	if main_rail.rail_length() <= 0.0:
		return
	var up := main_rail.sample_up(points_distance())
	global_transform = Transform3D(
			Rail.basis_from_forward_up(through_direction(), up), points_position())
	_update_marker_frame()


## Recomputes where the marker stands and how far the railhead is above it, and
## moves the marker there. The ground query behind [method Rail.ground_frame] is
## the one expensive part, which is why the answer is kept rather than worked out
## again by every caller that wants to know where the marker is.
func _update_marker_frame() -> void:
	if main_rail == null or not main_rail.is_inside_tree() or not is_inside_tree():
		return
	if main_rail.rail_length() <= 0.0:
		return
	_marker_frame = main_rail.ground_frame(points_distance(), through_direction(),
			float(branch_side()) * _MARKER_OFFSET)
	_marker_lift = points_position().y - _marker_frame.origin.y
	if _marker != null:
		_marker.global_transform = _marker_frame
#endregion


#region Player operation
## The single entry point for throwing a turnout, whoever throws it. A step-4
## compound assembly drives its members through this.
func throw_points() -> void:
	turnout_position = (Position.NORMAL if turnout_position == Position.REVERSE
			else Position.REVERSE)


func _on_picker_input(_camera: Node, event: InputEvent, _at: Vector3,
		_normal: Vector3, _shape: int) -> void:
	if player_operable and event.is_action_pressed(&"interact"):
		throw_points()


## True while the mouse is over the 3D marker. The floating widget answers for
## itself ([method TrackMarkerWidget.is_pointer_over]); between the two, a
## readout can say which turnout the player is pointing at.
func is_pointer_over() -> bool:
	return _pointer_over


func _set_pointer_over(value: bool) -> void:
	_pointer_over = value
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
## something to hit. Step 6 generates the real point blades.
## Everything hangs off [member _marker], which stands on the ground rather than
## on the track, so the post is as long as it has to be to get from that ground
## up to its nominal height above the railhead.
func _rebuild_marker() -> void:
	if not is_inside_tree():
		return
	_update_marker_frame()
	if _marker == null:
		_marker = Node3D.new()
		_marker.name = "Marker"
		# Not built in the turnout's own frame: that one leans with the track.
		# This one is written straight into global space by _update_marker_frame.
		_marker.top_level = true
		add_child(_marker, false, Node.INTERNAL_MODE_BACK)
		_marker.global_transform = _marker_frame
	if _post == null:
		_post = _add_box("Post", _COLOR_POST, Vector3(0.26, 1.0, 0.26))
	if _banner_pivot == null:
		_banner_pivot = Node3D.new()
		_banner_pivot.name = "BannerPivot"
		_marker.add_child(_banner_pivot)
		_banner = MeshInstance3D.new()
		_banner.name = "Banner"
		_banner.mesh = BoxMesh.new()
		_banner.material_override = StandardMaterial3D.new()
		_banner_pivot.add_child(_banner)
		(_banner.mesh as BoxMesh).size = Vector3(0.2, 0.2, 1.9)
		# Offset along the pivot's own -Z, so the banner reads as an arm pointing
		# at the route rather than a bar sitting across it.
		_banner.position = Vector3(0.0, 0.0, -0.95)
	if _picker == null:
		_picker = StaticBody3D.new()
		_picker.name = "ClickTarget"
		_picker.input_ray_pickable = true
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 2.2
		shape.shape = sphere
		_picker.add_child(shape)
		_marker.add_child(_picker)
		if not _picker.input_event.is_connected(_on_picker_input):
			_picker.input_event.connect(_on_picker_input)
		_picker.mouse_entered.connect(_set_pointer_over.bind(true))
		_picker.mouse_exited.connect(_set_pointer_over.bind(false))

	# The marker's own origin is already beside the track on the branch side and
	# on the ground, so the only thing left to work out is how far the post has
	# to reach up to keep the banner level with the track.
	var post_height := maxf(_marker_lift + _POST_TOP, _POST_MIN_HEIGHT)
	(_post.mesh as BoxMesh).size = Vector3(0.26, post_height, 0.26)
	_post.position = Vector3(0.0, post_height * 0.5, 0.0)
	_picker.position = Vector3(0.0, _marker_lift + _PICKER_HEIGHT, 0.0)
	_refresh_banner()


## Swings the banner onto the set route and recolours it. Uses the leg's heading
## rather than its tangent at the points - from the tangents the two routes are
## indistinguishable, and the banner would never appear to move.
func _refresh_banner() -> void:
	if _banner_pivot == null or _banner == null or not is_usable():
		return
	var local := (_marker.global_basis.inverse() * leg_heading(set_leg())).normalized()
	# A yaw of theta sends local -Z to (-sin, 0, -cos), so match that to `local`.
	var yaw := atan2(-local.x, -local.z)
	_banner_pivot.transform = Transform3D(
			Basis(Vector3.UP, yaw), Vector3(0.0, _marker_lift + _BANNER_HEIGHT, 0.0))
	var material := _banner.material_override as StandardMaterial3D
	material.albedo_color = (_COLOR_REVERSE if turnout_position == Position.REVERSE
			else _COLOR_NORMAL)


func _add_box(node_name: String, color: Color, size: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = material
	_marker.add_child(instance)
	return instance
#endregion


#region Debug draw
## Three stubs sampled along the real rails: the toe and the set route in green,
## the dead leg in red. Sampling rather than drawing straight lines means the
## overlay curves with the track and so shows the actual connection.
func _refresh_debug_mesh() -> void:
	if not is_inside_tree():
		return
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "TurnoutDebugDraw"
		# Drawn in global space: the node's own transform is derived from the
		# rail, so ignoring it keeps the leg maths free of round trips.
		_debug_mesh.top_level = true
		add_child(_debug_mesh, false, Node.INTERNAL_MODE_BACK)

	var mesh := ImmediateMesh.new()
	_debug_mesh.mesh = mesh
	if not debug_draw or not is_usable():
		return

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _get_debug_material())
	for leg: Leg in [Leg.TOE, Leg.THROUGH, Leg.DIVERGING]:
		_draw_leg(mesh, leg)
	var base := points_position()
	_line(mesh, base, base + Vector3.UP * (overlay_lift + 1.4), _COLOR_POINTS)
	mesh.surface_end()


## One leg, sampled outwards from the points along the real rail and drawn as a
## band of three lines so it reads as a highlighted route from a distance rather
## than disappearing into the track below it. A leg the points are set against
## gets a cross at its far end.
func _draw_leg(mesh: ImmediateMesh, leg: Leg) -> void:
	const STEP := 0.75
	const HALF_WIDTH := 0.45
	var is_set := leg_is_set(leg)
	var color := _COLOR_SET if is_set else _COLOR_UNSET
	var rail: Rail = branch_rail if leg == Leg.DIVERGING else main_rail
	var from := branch_distance() if leg == Leg.DIVERGING else points_distance()
	var direction: int
	match leg:
		Leg.DIVERGING:
			direction = branch_exit_sign()
		Leg.THROUGH:
			direction = diverge_sign()
		_:
			direction = -diverge_sign()

	var steps := maxi(1, ceili(leg_length / STEP))
	var previous := Vector3.ZERO
	var previous_side := Vector3.ZERO
	for i in steps + 1:
		var at := rail.clamp_distance(from + float(direction) * leg_length
				* float(i) / float(steps))
		var point := rail.sample_position(at) + Vector3.UP * overlay_lift
		var side := rail.sample_transform(at).basis.x * HALF_WIDTH
		if i > 0:
			for offset: float in [-1.0, 0.0, 1.0]:
				_line(mesh, previous + previous_side * offset, point + side * offset, color)
		previous = point
		previous_side = side
	if not is_set:
		# A cross on the dead end, so "this way is closed" survives being a few
		# pixels of red on a zoomed-out screen.
		var up := Vector3.UP * HALF_WIDTH * 1.6
		_line(mesh, previous - previous_side - up, previous + previous_side + up, color)
		_line(mesh, previous - previous_side + up, previous + previous_side - up, color)


func _line(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to)


static func _get_debug_material() -> StandardMaterial3D:
	if _debug_material == null:
		_debug_material = StandardMaterial3D.new()
		_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_debug_material.vertex_color_use_as_albedo = true
		_debug_material.vertex_color_is_srgb = true
		_debug_material.disable_receive_shadows = true
		_debug_material.no_depth_test = true
	return _debug_material
#endregion


#region Rail registration
func _attach_to_rails() -> void:
	if main_rail != null:
		main_rail.attach(self)
	if branch_rail != null:
		branch_rail.attach(self)


func _detach_from_rails() -> void:
	if main_rail != null:
		main_rail.detach(self)
	if branch_rail != null:
		branch_rail.detach(self)


func _set_main_rail(value: Rail) -> void:
	if main_rail != null:
		main_rail.detach(self)
	main_rail = value
	_attach_to_rails()
	_place_on_rail()
	_rebuild_marker()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_branch_rail(value: Rail) -> void:
	if branch_rail != null:
		branch_rail.detach(self)
	branch_rail = value
	_attach_to_rails()
	# Which side the marker stands on is read off the branch, so it moves too.
	_rebuild_marker()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_main_distance(value: float) -> void:
	main_distance = value
	_place_on_rail()
	_rebuild_marker()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_diverge_towards(value: DivergeTowards) -> void:
	diverge_towards = value
	_place_on_rail()
	_rebuild_marker()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_branch_end(value: RailEnd) -> void:
	branch_end = value
	_rebuild_marker()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_turnout_position(value: Position) -> void:
	var changed := turnout_position != value
	turnout_position = value
	_refresh_banner()
	_refresh_debug_mesh()
	if changed:
		position_changed.emit()


func _set_debug_draw(value: bool) -> void:
	debug_draw = value
	_refresh_debug_mesh()
#endregion
