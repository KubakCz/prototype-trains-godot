@tool
class_name Train
extends Node3D
## A box that drives along a [Rail] at constant speed.
##
## Travel direction is deliberately split into two independent values, because a
## train's forward is its own, not the rail's:
##
## - [member facing] is which way the nose points along the rail. A train facing
##   [constant AGAINST_RAIL] on a rail drawn west-to-east is a train pointing west.
## - [member throttle] is whether it drives nose-first, sits still, or backs up.
##
## So driving forward always moves the nose forward, whichever way the underlying
## curve happens to run.
##
## Movement and body placement both go through [TrackWalker], so a train drives
## from rail to rail through [Turnout]s without knowing they are there, and stops
## when its leading end reaches points that are set against it.

## Nose points towards increasing rail distance.
const ALONG_RAIL := 1
## Nose points towards decreasing rail distance.
const AGAINST_RAIL := -1

## What to do at a genuine dead end: a rail end with no turnout attached, and so
## nowhere to be handed on to. Still a placeholder - real levels will end their
## track at buffer stops or at a connection off the level - but it keeps an
## unattended prototype running instead of parking every train.
enum EndBehavior {
	## Stop dead and drop the throttle.
	STOP,
	## Back up along the rail without turning around: the nose keeps pointing at
	## the end of the line.
	REVERSE,
	## Turn the train around and keep driving nose-first.
	TURN_AROUND,
}

## Distances below this count as not moving, which is how the train tells
## reaching a dead end from already resting against one.
const _AT_REST := 1e-4

const _COLOR_BODY := Color(0.16, 0.32, 0.52)
const _COLOR_NOSE := Color(1.0, 0.82, 0.1)

@export var rail: Rail: set = _set_rail
## Distance of the train's centre along [member rail], in metres.
@export var distance := 0.0: set = _set_distance
@export_enum("Along rail:1", "Against rail:-1") var facing := ALONG_RAIL: set = _set_facing
## -1 backs up, 0 stands still, 1 drives nose-first.
@export_range(-1, 1, 1) var throttle := 1
## Constant travel speed in metres per second, in either direction.
@export var speed := 10.0
@export var end_behavior := EndBehavior.TURN_AROUND

@export_group("Body")
@export var body_length := 14.0: set = _set_body_length
@export var body_width := 2.9: set = _set_body_width
@export var body_height := 3.4: set = _set_body_height

## Points that are refusing this train, while they refuse it. The train holds at
## them with its throttle still open and rolls on as soon as they are thrown.
var blocking_turnout: Turnout
## Whether the train is sitting against a dead end.
var at_dead_end := false

var _body: MeshInstance3D
var _nose: MeshInstance3D
## Set while a new position is written field by field, so the body is placed once
## at the end instead of after each of the three setters.
var _suspend_placement := false


func _ready() -> void:
	_rebuild_body()
	_place_on_rail()
	# In the editor the train is a preview: it follows inspector edits, but does
	# not drive off on its own.
	set_physics_process(not Engine.is_editor_hint())


## Two walks per frame: one from the centre out past the leading end, to find
## what the train is about to run into, and one to move the centre as far as that
## allows. Splitting them is what makes a train stop with its nose on the points
## rather than overshooting them by half its length.
func _physics_process(delta: float) -> void:
	blocking_turnout = null
	at_dead_end = false
	if rail == null or throttle == 0:
		return
	var motion := signi(throttle * facing)
	var half := body_length * 0.5
	var travel := speed * delta

	var probe := TrackWalker.walk(rail, distance, motion, half + travel)
	var allowed := probe.travelled - half
	if allowed > _AT_REST:
		var moved := TrackWalker.walk(rail, distance, motion, allowed)
		# The rail underneath may have changed. The nose has not turned round, so
		# `facing` becomes whichever direction on the new rail still points that
		# way - which is what the walk reports.
		_apply_state(moved.rail, moved.distance, moved.direction * throttle)
	if not probe.is_blocked():
		return

	blocking_turnout = probe.blocking_turnout
	at_dead_end = probe.at_dead_end
	# Points set against the train: hold, throttle still open, and roll on the
	# moment the player throws them. Only a dead end falls back to
	# `end_behavior`, and only once the train has come to rest against it.
	if at_dead_end and allowed <= _AT_REST:
		_handle_end_of_rail()


## Nothing is attached to this rail end, so there is nowhere to be handed on to.
func _handle_end_of_rail() -> void:
	match end_behavior:
		EndBehavior.STOP:
			throttle = 0
		EndBehavior.REVERSE:
			throttle = -throttle
		EndBehavior.TURN_AROUND:
			facing = -facing


## What is stopping the train, for the debug readouts.
func blocked_description() -> String:
	if blocking_turnout != null:
		return "held by %s (set %s)" % [blocking_turnout.name,
				Turnout.Position.keys()[blocking_turnout.turnout_position]]
	return "at dead end" if at_dead_end else ""


#region Placement
## Places the box using the rail positions under its two ends, so a long body
## sits along a curve as a chord rather than pivoting about its centre.
##
## The ends are found by walking rather than by adding to [member distance], so a
## train halfway through a turnout has one end on each rail and is drawn as the
## chord between them.
func _place_on_rail() -> void:
	if _suspend_placement or rail == null or not rail.is_inside_tree() or not is_inside_tree():
		return
	if rail.rail_length() <= 0.0:
		return
	var half := body_length * 0.5
	var front_step := TrackWalker.walk(rail, distance, facing, half)
	var rear_step := TrackWalker.walk(rail, distance, -facing, half)
	var front := front_step.rail.sample_position(front_step.distance)
	var rear := rear_step.rail.sample_position(rear_step.distance)
	var up := rail.sample_up(rail.clamp_distance(distance))
	var forward := front - rear
	if forward.length_squared() < 1e-9:
		# Body shorter than the sampling resolution, or a degenerate rail.
		forward = rail.sample_forward(distance) * float(facing)
	global_transform = Transform3D(
			Rail.basis_from_forward_up(forward, up), (front + rear) * 0.5)


## Writes a whole new position at once, so the setters below do not each rebuild
## the body from a half-updated state.
func _apply_state(new_rail: Rail, new_distance: float, new_facing: int) -> void:
	_suspend_placement = true
	rail = new_rail
	distance = new_distance
	facing = new_facing
	_suspend_placement = false
	_place_on_rail()


func _set_rail(value: Rail) -> void:
	rail = value
	_place_on_rail()


func _set_distance(value: float) -> void:
	distance = value
	_place_on_rail()


func _set_facing(value: int) -> void:
	facing = ALONG_RAIL if value >= 0 else AGAINST_RAIL
	_place_on_rail()
#endregion


#region Body meshes
## Body plus a bright marker slab over the nose, so which end is the front is
## obvious from any angle. Both are internal children: generated, never saved.
func _rebuild_body() -> void:
	if not is_inside_tree():
		return
	if _body == null:
		_body = _add_box("Body", _COLOR_BODY)
	if _nose == null:
		_nose = _add_box("NoseMarker", _COLOR_NOSE)

	_body.mesh.size = Vector3(body_width, body_height, body_length)
	_body.position = Vector3(0.0, body_height * 0.5, 0.0)

	var nose_height := body_height * 0.25
	_nose.mesh.size = Vector3(body_width * 0.75, nose_height, body_length * 0.12)
	# -Z is forward, so the marker sits over the front of the roof.
	_nose.position = Vector3(
			0.0,
			body_height + nose_height * 0.5,
			-body_length * 0.5 + _nose.mesh.size.z * 0.5)


func _add_box(node_name: String, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = BoxMesh.new()
	instance.material_override = material
	add_child(instance, false, Node.INTERNAL_MODE_BACK)
	return instance


func _set_body_length(value: float) -> void:
	body_length = maxf(value, 0.1)
	_rebuild_body()
	_place_on_rail()


func _set_body_width(value: float) -> void:
	body_width = maxf(value, 0.1)
	_rebuild_body()


func _set_body_height(value: float) -> void:
	body_height = maxf(value, 0.1)
	_rebuild_body()
#endregion
