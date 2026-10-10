@tool
class_name Crossing
extends Node3D
## Where two rails cross each other on the level, with no way of getting from one
## to the other - a diamond.
##
## Nothing about driving changes here: both rails run straight through, and
## [TrackWalker] never stops at a crossing (it only ever casts a rail's
## attachments to [Turnout] and [RailSignal]). What a crossing is for is being
## [i]known about[/i]. Two trains on the two rails can still meet in the middle,
## so step 9's blocks treat a crossing as joining both tracks into one block, and
## step 6's rail meshes need to cut the running rails where they cross. Both
## start from here: the two rails, the distance along each at which they meet,
## and which trains are standing over it right now.
##
## The crossing registers itself as an attachment on both rails, the same as a
## turnout or a signal, so anything walking the network can find it.

const _COLOR_CLEAR := Color(1.0, 0.85, 0.2)
const _COLOR_OCCUPIED := Color(1.0, 0.35, 0.1)

## How far apart, horizontally, the two rails may be at the authored distances
## before the crossing is reported as not actually being on them.
const _MAX_GAP := 0.3
## Sample spacing for [method locate]'s first pass. The second pass refines the
## hit to a few centimetres.
const _COARSE_STEP := 1.0
const _FINE_STEP := 0.05

## Emitted whenever the set of trains over the crossing changes.
signal occupancy_changed

@export var rail_a: Rail: set = _set_rail_a
## Metres along [member rail_a] at which it crosses [member rail_b].
@export var distance_a := 0.0: set = _set_distance_a
@export var rail_b: Rail: set = _set_rail_b
## Metres along [member rail_b] at which it crosses [member rail_a].
@export var distance_b := 0.0: set = _set_distance_b
## Finds where the two rails cross and writes both distances. Where they cross
## more than once, keeps the crossing nearest the distances already set.
@export_tool_button("Locate Crossing") var _locate_button := locate
## Run [method locate] again when the level starts, after the rails have snapped
## to the ground - snapping changes the rails' arc lengths a little, and so where
## along each one the crossing sits. Runtime only, like
## [member Rail.snap_on_ready].
@export var locate_on_ready := true
## Trains found in this group are checked for standing over the crossing.
@export var train_group: StringName = &"trains"

@export_group("Debug Draw")
@export var debug_draw := true: set = _set_debug_draw
## Half the length of each diagonal of the diamond drawn over the crossing.
@export var marker_size := 3.0
## Height above the railhead the diamond floats at.
@export var overlay_lift := 0.55

var _occupants: Array[Train] = []
var _debug_mesh: MeshInstance3D
static var _debug_material: StandardMaterial3D


func _ready() -> void:
	_attach_to_rails()
	if locate_on_ready and not Engine.is_editor_hint():
		locate()
	_place()
	_refresh_debug_mesh()
	set_physics_process(not Engine.is_editor_hint())


func _enter_tree() -> void:
	_attach_to_rails()


func _exit_tree() -> void:
	_detach_from_rails()


func _physics_process(_delta: float) -> void:
	var found := _find_occupants()
	if found == _occupants:
		return
	_occupants = found
	_refresh_debug_mesh()
	occupancy_changed.emit()


#region Topology
## True when both rails are present, distinct and long enough to be sampled.
func is_usable() -> bool:
	return (rail_a != null and rail_b != null and rail_a != rail_b
			and rail_a.rail_length() > 0.0 and rail_b.rail_length() > 0.0)


## Every distance at which this crossing touches [param rail]. The same shape as
## [method Turnout.distances_on], so a walk collecting what lies ahead can ask
## all three kinds of attachment the same question.
func distances_on(rail: Rail) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	if rail == null:
		return found
	if rail == rail_a:
		found.append(rail_a.clamp_distance(distance_a))
	if rail == rail_b:
		found.append(rail_b.clamp_distance(distance_b))
	return found


## The rail crossing [param rail] here, or null if [param rail] is neither.
func other_rail(rail: Rail) -> Rail:
	if rail == rail_a:
		return rail_b
	if rail == rail_b:
		return rail_a
	return null


## Where the two rails meet, in global space.
func crossing_position() -> Vector3:
	return rail_a.sample_position(rail_a.clamp_distance(distance_a)) if rail_a != null \
			else global_position


## Angle between the two rails, in degrees, from 0 to 90.
func crossing_angle_degrees() -> float:
	if not is_usable():
		return 0.0
	var a := _flat(rail_a.sample_forward(rail_a.clamp_distance(distance_a)))
	var b := _flat(rail_b.sample_forward(rail_b.clamp_distance(distance_b)))
	var angle := rad_to_deg(a.angle_to(b))
	return 180.0 - angle if angle > 90.0 else angle
#endregion


#region Occupancy
## The trains with any part of their body over the crossing, on either rail.
func occupants() -> Array[Train]:
	return _occupants if not Engine.is_editor_hint() else _find_occupants()


func is_occupied() -> bool:
	return not occupants().is_empty()


func _find_occupants() -> Array[Train]:
	var found: Array[Train] = []
	if not is_usable() or not is_inside_tree():
		return found
	var at_a := rail_a.clamp_distance(distance_a)
	var at_b := rail_b.clamp_distance(distance_b)
	for node in get_tree().get_nodes_in_group(train_group):
		var train := node as Train
		if train != null and (train.occupies(rail_a, at_a) or train.occupies(rail_b, at_b)):
			found.append(train)
	return found
#endregion


#region Editor authoring
## Finds where the two rails cross, in plan, and writes [member distance_a] and
## [member distance_b]. Plan rather than 3D because two rails crossing on a slope
## need not meet to the centimetre in height, and a rail passing [i]over[/i]
## another on a bridge is not a crossing anyone would author.
func locate() -> void:
	if not is_usable():
		push_warning("Crossing '%s' cannot locate: both rails must be set, distinct, and have a curve."
				% name)
		return
	var hits := _intersections(rail_a, 0.0, rail_a.rail_length(),
			rail_b, 0.0, rail_b.rail_length(), _COARSE_STEP)
	if hits.is_empty():
		push_warning("Crossing '%s': '%s' and '%s' do not cross." % [name, rail_a.name, rail_b.name])
		return
	var best := hits[0]
	for hit in hits:
		if absf(hit.x - distance_a) < absf(best.x - distance_a):
			best = hit
	# Refine around the coarse hit: the polyline is only as close to the curve
	# as its sample spacing allows.
	var span := _COARSE_STEP * 2.0
	var fine := _intersections(rail_a, best.x - span, best.x + span,
			rail_b, best.y - span, best.y + span, _FINE_STEP)
	if not fine.is_empty():
		best = fine[0]
	distance_a = best.x
	distance_b = best.y
	update_configuration_warnings()


## Every crossing of the two rails' plan polylines between the given distances,
## as (distance on a, distance on b).
static func _intersections(a: Rail, a_from: float, a_to: float, b: Rail, b_from: float,
		b_to: float, step: float) -> PackedVector2Array:
	var hits := PackedVector2Array()
	var a_points := _plan_samples(a, a_from, a_to, step)
	var b_points := _plan_samples(b, b_from, b_to, step)
	for i in a_points.size() - 1:
		var p := Vector2(a_points[i].x, a_points[i].y)
		var p_next := Vector2(a_points[i + 1].x, a_points[i + 1].y)
		for j in b_points.size() - 1:
			var q := Vector2(b_points[j].x, b_points[j].y)
			var q_next := Vector2(b_points[j + 1].x, b_points[j + 1].y)
			var hit: Variant = Geometry2D.segment_intersects_segment(p, p_next, q, q_next)
			if hit == null:
				continue
			var point: Vector2 = hit
			var t_a := p.distance_to(point) / maxf(p.distance_to(p_next), 1e-9)
			var t_b := q.distance_to(point) / maxf(q.distance_to(q_next), 1e-9)
			hits.append(Vector2(lerpf(a_points[i].z, a_points[i + 1].z, t_a),
					lerpf(b_points[j].z, b_points[j + 1].z, t_b)))
	return hits


## Plan position (x, z) and distance along the rail, packed as (x, z, distance).
static func _plan_samples(rail: Rail, from: float, to: float, step: float) -> PackedVector3Array:
	var samples := PackedVector3Array()
	var start := rail.clamp_distance(from)
	var end := rail.clamp_distance(to)
	var count := maxi(1, ceili((end - start) / step))
	for i in count + 1:
		var at := lerpf(start, end, float(i) / float(count))
		var point := rail.sample_position(at)
		samples.append(Vector3(point.x, point.z, at))
	return samples


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if rail_a == null or rail_b == null:
		warnings.append("Both rails must be set.")
		return warnings
	if rail_a == rail_b:
		warnings.append("A rail cannot cross itself here; set two different rails.")
		return warnings
	if not is_usable():
		warnings.append("Both rails need a curve with some length.")
		return warnings
	var a := rail_a.sample_position(rail_a.clamp_distance(distance_a))
	var b := rail_b.sample_position(rail_b.clamp_distance(distance_b))
	var gap := Vector2(a.x - b.x, a.z - b.z).length()
	if gap > _MAX_GAP:
		warnings.append("The rails are %.2f m apart at the set distances. Press Locate Crossing."
				% gap)
	elif absf(a.y - b.y) > 1.0:
		warnings.append("The rails are %.1f m apart in height here - a bridge, not a crossing."
				% absf(a.y - b.y))
	return warnings
#endregion


#region Debug draw
## A diamond whose corners sit on the two rails either side of the crossing, so
## it lies along both tracks and reads as "these two cross" from any angle.
## Yellow when clear, orange while a train is over it.
func _refresh_debug_mesh() -> void:
	if not is_inside_tree():
		return
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "CrossingDebugDraw"
		_debug_mesh.top_level = true
		add_child(_debug_mesh, false, Node.INTERNAL_MODE_BACK)
	var mesh := ImmediateMesh.new()
	_debug_mesh.mesh = mesh
	if not debug_draw or not is_usable():
		return
	var color := _COLOR_OCCUPIED if not _occupants.is_empty() else _COLOR_CLEAR
	var lift := Vector3.UP * overlay_lift
	var at_a := rail_a.clamp_distance(distance_a)
	var at_b := rail_b.clamp_distance(distance_b)
	var corners: Array[Vector3] = [
		rail_a.sample_position(rail_a.clamp_distance(at_a + marker_size)) + lift,
		rail_b.sample_position(rail_b.clamp_distance(at_b + marker_size)) + lift,
		rail_a.sample_position(rail_a.clamp_distance(at_a - marker_size)) + lift,
		rail_b.sample_position(rail_b.clamp_distance(at_b - marker_size)) + lift,
	]
	# Alternating between the rails keeps the two diagonals on the two tracks,
	# whatever the angle, so the outline is always a diamond and never a bow tie.
	var centre := crossing_position() + lift
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _get_debug_material())
	for i in corners.size():
		_line(mesh, corners[i], corners[(i + 1) % corners.size()], color)
	# Inner outline, so the marker survives being a few pixels wide.
	for i in corners.size():
		var inner_from := centre.lerp(corners[i], 0.8)
		var inner_to := centre.lerp(corners[(i + 1) % corners.size()], 0.8)
		_line(mesh, inner_from, inner_to, color)
	_line(mesh, centre, centre + Vector3.UP * 1.4, color)
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
func _attach_to_rails() -> void:
	if rail_a != null:
		rail_a.attach(self)
	if rail_b != null:
		rail_b.attach(self)


func _detach_from_rails() -> void:
	if rail_a != null:
		rail_a.detach(self)
	if rail_b != null:
		rail_b.detach(self)


## The node itself sits on the crossing, so it can be found and selected there.
func _place() -> void:
	if is_usable() and is_inside_tree():
		global_position = crossing_position()


static func _flat(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 1e-9 else Vector3.FORWARD


func _set_rail_a(value: Rail) -> void:
	if rail_a != null:
		rail_a.detach(self)
	rail_a = value
	# Only once in the tree: a crossing that never enters it would never leave
	# it either, and would stay on the rail's list after being freed.
	if is_inside_tree():
		_attach_to_rails()
	_place()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_rail_b(value: Rail) -> void:
	if rail_b != null:
		rail_b.detach(self)
	rail_b = value
	# Only once in the tree: a crossing that never enters it would never leave
	# it either, and would stay on the rail's list after being freed.
	if is_inside_tree():
		_attach_to_rails()
	_place()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_distance_a(value: float) -> void:
	distance_a = value
	_place()
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_distance_b(value: float) -> void:
	distance_b = value
	_refresh_debug_mesh()
	update_configuration_warnings()


func _set_debug_draw(value: bool) -> void:
	debug_draw = value
	_refresh_debug_mesh()
#endregion
