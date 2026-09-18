@tool
class_name RailSignal
extends Node3D
## A stop signal standing beside a [Rail], governing one direction of travel.
##
## A signal lives at [member distance] along [member rail] and applies to trains
## travelling one way only: the way that leaves the signal on their right, which
## is the side it physically stands on. Stopping trains in both directions
## therefore takes two signals, one on each side of the track, and that is
## deliberate rather than a simplification - a signal is a property of a
## direction of travel, not of a place.
##
## Two aspects, and every signal starts at [constant Aspect.DANGER]:
##
## - [constant Aspect.DANGER] - a train travelling the governed way stops with
##   its nose at the signal and waits with its throttle still open, exactly as it
##   waits at points set against it, and rolls on the moment the signal clears.
## - [constant Aspect.CLEAR] - trains pass. A cleared signal stays clear until
##   something changes it.
##
## [TrackWalker] is what enforces this: it treats a signal at danger as the end
## of the walk. One rule there is worth knowing here - a signal only stops a
## train whose [i]nose has not already passed it[/i], so putting a signal back to
## danger under a moving train lets that train out rather than stranding it
## half-way past.
##
## Seams for later steps. Step 7's braking wants to know how far ahead the signal
## is, which is [member TrackWalker.Step.travelled] on a walk that ends here.
## Step 8 drives signals rather than the player: [member aspect]'s setter is the
## single entry point whoever is changing it, [signal aspect_changed] reports
## every change, and [member player_operable] is how an interlocking takes a
## signal off the player.

## What the signal is showing. [constant DANGER] is first so that a signal left
## out of a level file, or freshly added in the editor, is at stop.
enum Aspect {
	## Red: trains travelling the governed way stop here.
	DANGER,
	## Green: trains pass.
	CLEAR,
}

## Which way along the rail the trains this signal governs are travelling.
enum Governs {
	## Towards increasing distance on [member rail].
	TOWARDS_RAIL_END,
	## Towards decreasing distance on [member rail].
	TOWARDS_RAIL_START,
}

## How far down the governed direction the heading is measured, and how long the
## arrow on the debug draw runs.
const _HEADING_PROBE := 8.0

const _COLOR_DANGER := Color(0.85, 0.2, 0.18)
const _COLOR_CLEAR := Color(0.25, 1.0, 0.35)
const _COLOR_POST := Color(0.30, 0.31, 0.33)
const _COLOR_HEAD := Color(0.11, 0.12, 0.14)
## How much of its colour an unlit lamp keeps, so the head still reads as a
## two-lamp signal rather than as two black squares.
const _LAMP_DIM := 0.22

## Heights on the mast, every one of them measured up from the railhead rather
## than from the ground. How high the lamps sit above the track is what a driver
## reads, and it must not change with whatever the ground beside the track is
## doing; the mast is simply stretched downwards until it reaches that ground.
const _MAST_TOP := 4.2
const _HEAD_CENTRE := 5.0
const _HEAD_TOP := 6.0
const _LAMP_DANGER_HEIGHT := 5.5
const _LAMP_CLEAR_HEIGHT := 4.5
## Shortest the mast may get where the ground beside the track stands higher than
## the track itself - a cutting, or a signal on the low side of a cambered curve.
const _MAST_MIN_HEIGHT := 1.0

## Emitted whenever the aspect changes, however it was changed.
signal aspect_changed

@export_group("Placement")
## The rail this signal stands beside.
@export var rail: Rail: set = _set_rail
## Metres along [member rail] at which the signal stands, and where a train it
## stops comes to rest with its nose.
@export var distance := 0.0: set = _set_distance
## Which way the trains it governs are travelling. The signal stands on their
## right, so this also decides which side of the track the mast goes on.
@export var governs := Governs.TOWARDS_RAIL_END: set = _set_governs
## How far to the right of the track's centre line the mast stands.
@export var side_offset := 2.6: set = _set_side_offset

@export_group("Aspect")
@export var aspect := Aspect.DANGER: set = _set_aspect
## Whether clicking the signal in the running game changes it. Turned off for a
## signal that step 8's interlocking drives on the player's behalf.
@export var player_operable := true

@export_group("Debug Draw")
## The stop line across the track and the arrow showing which way the signal
## applies, both in the aspect's colour.
@export var debug_draw := true: set = _set_debug_draw
@export var overlay_lift := 0.35

var _debug_mesh: MeshInstance3D
## Upright, ground-anchored root the whole model hangs off. See [method mast_frame].
var _mast: Node3D
var _mast_frame := Transform3D.IDENTITY
var _mast_lift := 0.0
var _post: MeshInstance3D
var _head: MeshInstance3D
var _lamp_danger: MeshInstance3D
var _lamp_clear: MeshInstance3D
var _picker: StaticBody3D
var _picker_box: BoxShape3D
## Whether the mouse is over the 3D mast. See [method is_pointer_over].
var _pointer_over := false
static var _debug_material: StandardMaterial3D


func _ready() -> void:
	_attach_to_rail()
	if not Engine.is_editor_hint():
		# Same as [Turnout]: without this a CollisionObject3D never sees a click.
		get_viewport().physics_object_picking = true
	_place_on_rail()
	_rebuild_model()
	_refresh_debug_mesh()


func _enter_tree() -> void:
	_attach_to_rail()


func _exit_tree() -> void:
	if rail != null:
		rail.detach(self)


#region Topology
## True when the signal has a rail long enough to stand on.
func is_usable() -> bool:
	return rail != null and rail.rail_length() > 0.0


## [member distance], kept on the rail.
func signal_distance() -> float:
	return rail.clamp_distance(distance) if rail != null else 0.0


## +1 when the governed move runs towards increasing distance on the rail.
func governed_direction() -> int:
	return 1 if governs == Governs.TOWARDS_RAIL_END else -1


## Every distance at which this signal touches [param query_rail]. The same shape
## as [method Turnout.distances_on], because [TrackWalker] asks both the same way.
func distances_on(query_rail: Rail) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	if query_rail != null and query_rail == rail:
		found.append(signal_distance())
	return found


## Whether a train travelling [param direction] along [param query_rail] is
## stopped here. The direction test is the whole one-directional rule: a train
## going the other way never sees this signal at all.
func blocks(query_rail: Rail, direction: int) -> bool:
	if aspect == Aspect.CLEAR or rail == null or query_rail != rail:
		return false
	return signi(direction) == governed_direction()


func is_clear() -> bool:
	return aspect == Aspect.CLEAR
#endregion


#region Geometry
## Where the signal stands on the track, in global space. A train stopped here
## comes to rest with its nose on this point.
func signal_position() -> Vector3:
	if rail == null:
		return global_position
	return rail.sample_position(signal_distance())


## The frame the mast is built in: standing on the ground beside the track,
## upright, looking along the governed direction so that +X is still the right
## hand of the trains it stops.
##
## Deliberately not the signal node's own transform. That one is the rail's, so
## it pitches with the gradient, banks with the curve's tilt and is anchored to
## the railhead - a mast built in it leans over and hangs in the air wherever the
## ground falls away beside the track.
func mast_frame() -> Transform3D:
	return _mast_frame


## Where the mast stands, in global space: on the ground beside the track, which
## on a slope is neither under the rail nor at the rail's height.
func mast_position() -> Vector3:
	return _mast_frame.origin


## How far the railhead is above the ground at the mast. Everything on the mast
## is positioned this much higher than its nominal height above the track, which
## is what keeps the lamps at a constant height above the rails.
func mast_lift() -> float:
	return _mast_lift


## Centre of the click collider, in global space. The mast is a moving target -
## how tall it is depends on the ground under it - so anything aiming at it asks.
func click_target_position() -> Vector3:
	return _mast_frame * Vector3(0.0, _picker_height() * 0.5, 0.0)


## Where the floating widget's leader line lands: above the head, so the widget
## is visibly tied to its own mast rather than to the track it applies to.
func overlay_anchor() -> Vector3:
	return mast_position() + Vector3.UP * (_mast_lift + 5.2)


## Unit vector along the direction this signal governs, in global space.
func governed_heading() -> Vector3:
	if rail == null:
		return Vector3.FORWARD
	return rail.sample_forward(signal_distance()) * float(governed_direction())


## A point [param along] metres down the governed direction, following the real
## rail. What anything drawing the signal's direction should aim at: on a curve
## the tangent at the signal and the track a few metres on are not the same line.
func ahead_position(along := _HEADING_PROBE) -> Vector3:
	if rail == null:
		return global_position
	return rail.sample_position(rail.clamp_distance(
			signal_distance() + float(governed_direction()) * along))


## Puts the node on the rail with its -Z along the governed direction, so the
## mast can be positioned in plain local space and +X is the train's right.
func _place_on_rail() -> void:
	if rail == null or not rail.is_inside_tree() or not is_inside_tree():
		return
	if rail.rail_length() <= 0.0:
		return
	var up := rail.sample_up(signal_distance())
	global_transform = Transform3D(
			Rail.basis_from_forward_up(governed_heading(), up), signal_position())
	_update_mast_frame()


## Recomputes where the mast stands and how far the railhead is above it, and
## moves the model there. The ground query behind [method Rail.ground_frame] is
## the one expensive part, which is why the answer is kept rather than worked out
## again by every caller that wants to know where the mast is.
func _update_mast_frame() -> void:
	if rail == null or not rail.is_inside_tree() or not is_inside_tree():
		return
	if rail.rail_length() <= 0.0:
		return
	_mast_frame = rail.ground_frame(signal_distance(), governed_heading(), side_offset)
	_mast_lift = signal_position().y - _mast_frame.origin.y
	if _mast != null:
		_mast.global_transform = _mast_frame
#endregion


#region Player operation
## The single entry point for changing what a signal shows, whoever changes it.
## Step 8's interlocking drives signals through this same setter.
func _set_aspect(value: Aspect) -> void:
	var changed := aspect != value
	aspect = value
	_refresh_lamps()
	_refresh_debug_mesh()
	if changed:
		aspect_changed.emit()


func toggle_aspect() -> void:
	aspect = Aspect.DANGER if aspect == Aspect.CLEAR else Aspect.CLEAR


func _on_picker_input(_camera: Node, event: InputEvent, _at: Vector3,
		_normal: Vector3, _shape: int) -> void:
	if player_operable and event.is_action_pressed(&"interact"):
		toggle_aspect()


## True while the mouse is over the 3D mast. Same as [method Turnout.is_pointer_over]:
## the floating widget answers for its own rect, and a readout wants either.
func is_pointer_over() -> bool:
	return _pointer_over


func _set_pointer_over(value: bool) -> void:
	_pointer_over = value
#endregion


#region Editor authoring
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if rail == null:
		warnings.append("No rail set.")
		return warnings
	var length := rail.rail_length()
	if length <= 0.0:
		warnings.append("Rail '%s' has no length." % rail.name)
		return warnings
	if distance < 0.0 or distance > length:
		warnings.append("distance %.1f m is off rail '%s' (0 - %.1f m)."
				% [distance, rail.name, length])
	# A signal at the very end it governs towards can still be reached. One at
	# the end it faces has no track in front of it for a train to arrive on.
	var approach := signal_distance() if governed_direction() > 0 else length - signal_distance()
	if approach <= 0.01:
		warnings.append(("The signal stands at the %s of the rail and governs trains coming "
				+ "from there, so nothing can ever approach it. Flip 'governs', or move it "
				+ "along the rail.") % ("start" if governed_direction() > 0 else "end"))
	return warnings
#endregion


#region Model
## Mast, head and two lamps - red over green, the lit one emissive so the aspect
## survives being a few pixels on a zoomed-out screen. The head faces back down
## the track at the trains the signal governs, which is the side the lamps are
## on. Step 6 replaces this with a real model.
## Everything hangs off [member _mast], which stands on the ground rather than on
## the track, so the post is as long as it has to be to get from that ground up
## to its nominal height above the railhead.
func _rebuild_model() -> void:
	if not is_inside_tree():
		return
	_update_mast_frame()
	if _mast == null:
		_mast = Node3D.new()
		_mast.name = "Mast"
		# Not built in the signal's own frame: that one leans with the track.
		# This one is written straight into global space by _update_mast_frame.
		_mast.top_level = true
		add_child(_mast, false, Node.INTERNAL_MODE_BACK)
		_mast.global_transform = _mast_frame
	if _post == null:
		_post = _add_box("Post", _COLOR_POST, Vector3(0.22, 1.0, 0.22))
		_head = _add_box("Head", _COLOR_HEAD, Vector3(0.95, 2.0, 0.22))
		_lamp_danger = _add_box("LampDanger", _COLOR_DANGER, Vector3(0.6, 0.6, 0.12))
		_lamp_clear = _add_box("LampClear", _COLOR_CLEAR, Vector3(0.6, 0.6, 0.12))
	if _picker == null:
		_picker = StaticBody3D.new()
		_picker.name = "ClickTarget"
		_picker.input_ray_pickable = true
		var shape := CollisionShape3D.new()
		_picker_box = BoxShape3D.new()
		shape.shape = _picker_box
		_picker.add_child(shape)
		_mast.add_child(_picker)
		if not _picker.input_event.is_connected(_on_picker_input):
			_picker.input_event.connect(_on_picker_input)
		_picker.mouse_entered.connect(_set_pointer_over.bind(true))
		_picker.mouse_exited.connect(_set_pointer_over.bind(false))

	# The mast's origin is on the ground, and +Z is back down the track towards
	# the trains the signal governs, so the lamps face the drivers they stop.
	# Every height is measured from the railhead, hence the lift.
	var post_height := maxf(_mast_lift + _MAST_TOP, _MAST_MIN_HEIGHT)
	(_post.mesh as BoxMesh).size = Vector3(0.22, post_height, 0.22)
	_post.position = Vector3(0.0, post_height * 0.5, 0.0)
	_head.position = Vector3(0.0, _mast_lift + _HEAD_CENTRE, 0.0)
	_lamp_danger.position = Vector3(0.0, _mast_lift + _LAMP_DANGER_HEIGHT, 0.14)
	_lamp_clear.position = Vector3(0.0, _mast_lift + _LAMP_CLEAR_HEIGHT, 0.14)
	var picker_height := _picker_height()
	_picker_box.size = Vector3(1.7, picker_height, 1.7)
	_picker.position = Vector3(0.0, picker_height * 0.5, 0.0)
	_refresh_lamps()


## The click collider runs the whole way from the ground to the top of the head,
## so a signal on a bank is no harder to hit than one on the flat.
func _picker_height() -> float:
	return maxf(_mast_lift + _HEAD_TOP, _MAST_MIN_HEIGHT)


## Lights the lamp the signal is showing and dims the other one.
func _refresh_lamps() -> void:
	if _lamp_danger == null or _lamp_clear == null:
		return
	_set_lamp(_lamp_danger, _COLOR_DANGER, aspect == Aspect.DANGER)
	_set_lamp(_lamp_clear, _COLOR_CLEAR, aspect == Aspect.CLEAR)


func _set_lamp(lamp: MeshInstance3D, color: Color, lit: bool) -> void:
	var material := lamp.material_override as StandardMaterial3D
	material.albedo_color = color if lit else color * _LAMP_DIM
	material.emission_enabled = lit
	material.emission = color
	material.emission_energy_multiplier = 1.6 if lit else 0.0


func _add_box(node_name: String, color: Color, size: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = material
	_mast.add_child(instance)
	return instance
#endregion


#region Debug draw
## A line across the track where a train stops, plus an arrow down the governed
## direction, both in the aspect's colour: between them they say what the signal
## is showing and who it is showing it to.
func _refresh_debug_mesh() -> void:
	if not is_inside_tree():
		return
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "SignalDebugDraw"
		# Drawn in global space, like the turnout's: the node's own transform is
		# derived from the rail, so ignoring it keeps the maths free of round trips.
		_debug_mesh.top_level = true
		add_child(_debug_mesh, false, Node.INTERNAL_MODE_BACK)

	var mesh := ImmediateMesh.new()
	_debug_mesh.mesh = mesh
	if not debug_draw or not is_usable():
		return

	const STEPS := 6
	var color := _COLOR_CLEAR if aspect == Aspect.CLEAR else _COLOR_DANGER
	var frame := rail.sample_transform(signal_distance())
	var lift := Vector3.UP * overlay_lift
	var across := frame.basis.x * 1.9
	var base := frame.origin + lift
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _get_debug_material())
	_line(mesh, base - across, base + across, color)
	_line(mesh, base + across,
			mast_position() + Vector3.UP * (_mast_lift + overlay_lift), color)

	# The arrow runs along the real track, so on a curve it still points where a
	# train would actually go.
	var previous := base
	for i in range(1, STEPS + 1):
		var point := ahead_position(_HEADING_PROBE * float(i) / float(STEPS)) + lift
		_line(mesh, previous, point, color)
		previous = point
	var back := ahead_position(_HEADING_PROBE * 0.75) + lift - previous
	if back.length_squared() > 1e-9 and across.length_squared() > 1e-9:
		var side := across.normalized() * 0.55
		_line(mesh, previous, previous + back + side, color)
		_line(mesh, previous, previous + back - side, color)
	mesh.surface_end()


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
func _attach_to_rail() -> void:
	if rail != null:
		rail.attach(self)


func _set_rail(value: Rail) -> void:
	if rail != null:
		rail.detach(self)
	rail = value
	_attach_to_rail()
	_place_on_rail()
	_rebuild_model()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_distance(value: float) -> void:
	distance = value
	_place_on_rail()
	_rebuild_model()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_governs(value: Governs) -> void:
	governs = value
	_place_on_rail()
	_rebuild_model()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_side_offset(value: float) -> void:
	side_offset = value
	_place_on_rail()
	_rebuild_model()
	_refresh_debug_mesh()


func _set_debug_draw(value: bool) -> void:
	debug_draw = value
	_refresh_debug_mesh()
#endregion
