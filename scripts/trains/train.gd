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

## Nose points towards increasing rail distance.
const ALONG_RAIL := 1
## Nose points towards decreasing rail distance.
const AGAINST_RAIL := -1

## What to do on reaching either end of the rail. Placeholder behaviour until
## turnouts can hand the train over to a neighbouring rail.
enum EndBehavior {
	## Stop dead and drop the throttle.
	STOP,
	## Back up along the rail without turning around: the nose keeps pointing at
	## the end of the line.
	REVERSE,
	## Turn the train around and keep driving nose-first.
	TURN_AROUND,
}

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

var _body: MeshInstance3D
var _nose: MeshInstance3D


func _ready() -> void:
	_rebuild_body()
	_place_on_rail()
	# In the editor the train is a preview: it follows inspector edits, but does
	# not drive off on its own.
	set_physics_process(not Engine.is_editor_hint())


func _physics_process(delta: float) -> void:
	if rail == null or throttle == 0:
		return
	var travel := float(throttle) * float(facing) * speed * delta
	var next := distance + travel
	var lower := _min_distance()
	var upper := _max_distance()
	if next < lower or next > upper:
		distance = clampf(next, lower, upper)
		_handle_end_of_rail()
	else:
		distance = next


## Reached the end of the line. Without turnouts there is nowhere to hand over
## to, so fall back to [member end_behavior].
func _handle_end_of_rail() -> void:
	match end_behavior:
		EndBehavior.STOP:
			throttle = 0
		EndBehavior.REVERSE:
			throttle = -throttle
		EndBehavior.TURN_AROUND:
			facing = -facing


#region Placement
## Places the box using the rail positions under its two ends, so a long body
## sits along a curve as a chord rather than pivoting about its centre.
func _place_on_rail() -> void:
	if rail == null or not rail.is_inside_tree() or not is_inside_tree():
		return
	var length := rail.rail_length()
	if length <= 0.0:
		return
	var half := minf(body_length * 0.5, length * 0.5)
	var front := rail.sample_position(rail.clamp_distance(distance + facing * half))
	var rear := rail.sample_position(rail.clamp_distance(distance - facing * half))
	var up := rail.sample_up(rail.clamp_distance(distance))
	var forward := front - rear
	if forward.length_squared() < 1e-9:
		# Body shorter than the sampling resolution, or a degenerate rail.
		forward = rail.sample_forward(distance) * float(facing)
	global_transform = Transform3D(
			Rail.basis_from_forward_up(forward, up), (front + rear) * 0.5)


## Keeps the whole body on the rail rather than letting it hang off the end.
func _min_distance() -> float:
	return minf(body_length * 0.5, rail.rail_length() * 0.5)


func _max_distance() -> float:
	return rail.rail_length() - _min_distance()


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
