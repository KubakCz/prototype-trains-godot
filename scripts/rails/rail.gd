@tool
class_name Rail
extends Path3D
## A single stretch of track that trains travel along by arc length.
##
## Distances are metres measured from the first curve point, so [code]0.0[/code]
## is the start of the rail and [method rail_length] its end. Which end is which
## matters beyond bookkeeping: turnouts are defined relative to a rail's start or
## end direction, so a rail's drawn direction is part of the level data.
##
## A train's own travel direction is independent of this - see [Train].

## Half-distance used for the finite-difference tangent. Small enough to stay
## accurate on tight curves, large enough to avoid float noise.
const _TANGENT_PROBE := 0.01

const _COLOR_RAIL := Color(0.85, 0.85, 0.9)
const _COLOR_SLEEPER := Color(0.35, 0.27, 0.2)
const _COLOR_ARROW := Color(0.2, 0.85, 1.0)
const _COLOR_START := Color(0.2, 1.0, 0.3)
const _COLOR_END := Color(1.0, 0.25, 0.2)

@export_group("Surface Snapping")
## Node whose [MeshInstance3D] descendants act as the ground. When unset, every
## node in [member surface_group] is used instead.
@export var surface_root: Node3D
## Group fallback for [member surface_root], so a rail can be dropped into a
## level without wiring it up by hand.
@export var surface_group: StringName = &"snap_surface"
## Height the railhead is kept above the surface.
@export var surface_offset := 0.25
## Also lift the bezier handles onto the surface, so tangents follow the slope
## instead of shooting into or out of the ground.
@export var snap_handles := true
## Snap when the level starts. Snapping in the editor is left to the button
## below, so opening a scene never silently edits it.
@export var snap_on_ready := true
@export_tool_button("Snap Points To Surface") var _snap_button := snap_points_to_surface

@export_group("Debug Draw")
@export var debug_draw := true: set = _set_debug_draw
## Standard gauge, in metres.
@export var track_gauge := 1.435
@export var sleeper_spacing := 2.0
## Distance between the chevrons marking the rail's own direction.
@export var arrow_spacing := 15.0

var _debug_mesh: MeshInstance3D
static var _debug_material: StandardMaterial3D


func _ready() -> void:
	if curve == null:
		curve = Curve3D.new()
	if not curve_changed.is_connected(_on_curve_changed):
		curve_changed.connect(_on_curve_changed)
	if not curve.changed.is_connected(_refresh_debug_mesh):
		curve.changed.connect(_refresh_debug_mesh)
	if snap_on_ready and not Engine.is_editor_hint():
		snap_points_to_surface()
	_refresh_debug_mesh()


#region Sampling
## Total arc length of the rail, in metres.
func rail_length() -> float:
	return curve.get_baked_length() if curve != null else 0.0


func clamp_distance(distance: float) -> float:
	return clampf(distance, 0.0, rail_length())


## Position at [param distance], in global space.
func sample_position(distance: float) -> Vector3:
	return global_transform * sample_local_position(distance)


## Unit vector towards increasing distance, in global space.
func sample_forward(distance: float) -> Vector3:
	return (global_basis * sample_local_forward(distance)).normalized()


## Up vector at [param distance] (curve tilt included), in global space.
func sample_up(distance: float) -> Vector3:
	return (global_basis * sample_local_up(distance)).normalized()


## Transform at [param distance] whose -Z axis looks towards increasing
## distance, in global space.
func sample_transform(distance: float) -> Transform3D:
	return global_transform * sample_local_transform(distance)


func sample_local_position(distance: float) -> Vector3:
	if curve == null:
		return Vector3.ZERO
	return curve.sample_baked(distance, true)


func sample_local_forward(distance: float) -> Vector3:
	var length := rail_length()
	if length <= 0.0:
		return Vector3.FORWARD
	var behind := sample_local_position(clampf(distance - _TANGENT_PROBE, 0.0, length))
	var ahead := sample_local_position(clampf(distance + _TANGENT_PROBE, 0.0, length))
	var forward := ahead - behind
	if forward.length_squared() < 1e-12:
		return Vector3.FORWARD
	return forward.normalized()


func sample_local_up(distance: float) -> Vector3:
	if curve == null or not curve.up_vector_enabled:
		return Vector3.UP
	var up := curve.sample_baked_up_vector(distance, true)
	return up.normalized() if up.length_squared() > 1e-12 else Vector3.UP


func sample_local_transform(distance: float) -> Transform3D:
	return Transform3D(
			basis_from_forward_up(sample_local_forward(distance), sample_local_up(distance)),
			sample_local_position(distance))


## Orthonormal basis whose -Z looks along [param forward] (Godot's convention for
## which way a node faces) and whose +Y is as close to [param up] as the forward
## direction allows.
static func basis_from_forward_up(forward: Vector3, up: Vector3) -> Basis:
	var back := -forward.normalized()
	var right := up.cross(back)
	if right.length_squared() < 1e-9:
		# Looking straight along `up`; any perpendicular axis will do.
		right = Vector3.RIGHT.cross(back)
	if right.length_squared() < 1e-9:
		right = Vector3.FORWARD.cross(back)
	right = right.normalized()
	return Basis(right, back.cross(right), back)
#endregion


#region Surface snapping
## Drops every curve point, and optionally its handles, onto the ground.
func snap_points_to_surface() -> void:
	if curve == null or curve.point_count == 0:
		push_warning("Rail '%s' has no curve points to snap." % name)
		return
	var surfaces := SurfaceSnapper.collect(_surface_nodes())
	if surfaces.is_empty():
		push_warning(("Rail '%s' found no snapping surface. Set 'surface_root', " +
				"or add the ground to the '%s' group.") % [name, surface_group])
		return

	var to_local := global_transform.affine_inverse()
	var snapped := 0
	for index in curve.point_count:
		var point := curve.get_point_position(index)
		var point_global := global_transform * point
		var height = _surface_height(surfaces, point_global)
		if height == null:
			continue
		curve.set_point_position(index,
				to_local * Vector3(point_global.x, height, point_global.z))
		if snap_handles:
			_snap_handle(surfaces, to_local, index, true)
			_snap_handle(surfaces, to_local, index, false)
		snapped += 1
	if snapped < curve.point_count:
		push_warning("Rail '%s': %d of %d points had no surface below them and were left alone."
				% [name, curve.point_count - snapped, curve.point_count])


## Handles are stored relative to their point, so only the handle's Y offset is
## rewritten - enough to put its tip at surface height without moving the curve
## sideways.
func _snap_handle(surfaces: Array[SurfaceSnapper.Surface], to_local: Transform3D,
		index: int, is_in: bool) -> void:
	var handle := curve.get_point_in(index) if is_in else curve.get_point_out(index)
	if handle.is_zero_approx():
		return
	var point := curve.get_point_position(index)
	var tip_global := global_transform * (point + handle)
	var height = _surface_height(surfaces, tip_global)
	if height == null:
		return
	var tip_local := to_local * Vector3(tip_global.x, height, tip_global.z)
	handle.y = tip_local.y - point.y
	if is_in:
		curve.set_point_in(index, handle)
	else:
		curve.set_point_out(index, handle)


func _surface_height(surfaces: Array[SurfaceSnapper.Surface], global_point: Vector3) -> Variant:
	var height = SurfaceSnapper.height_at(surfaces, global_point.x, global_point.z)
	return null if height == null else height + surface_offset


func _surface_nodes() -> Array[Node]:
	if surface_root != null:
		return [surface_root]
	var nodes: Array[Node] = []
	if is_inside_tree():
		nodes.assign(get_tree().get_nodes_in_group(surface_group))
	return nodes
#endregion


#region Debug draw
func _set_debug_draw(value: bool) -> void:
	debug_draw = value
	_refresh_debug_mesh()


func _on_curve_changed() -> void:
	# The Curve3D instance itself may have been swapped out.
	if curve != null and not curve.changed.is_connected(_refresh_debug_mesh):
		curve.changed.connect(_refresh_debug_mesh)
	_refresh_debug_mesh()


## Rebuilds the line overlay: two running rails, sleepers, direction chevrons and
## end markers. Drawn in local space, because the mesh instance is an
## untransformed internal child.
func _refresh_debug_mesh() -> void:
	if not is_inside_tree():
		return
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "RailDebugDraw"
		# Internal, so it never lands in the saved scene.
		add_child(_debug_mesh, false, Node.INTERNAL_MODE_BACK)

	var mesh := ImmediateMesh.new()
	_debug_mesh.mesh = mesh
	var length := rail_length()
	if not debug_draw or length <= 0.0:
		return

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _get_debug_material())
	_draw_running_rails(mesh, length)
	_draw_sleepers(mesh, length)
	_draw_direction_arrows(mesh, length)
	_draw_end_marker(mesh, 0.0, _COLOR_START)
	_draw_end_marker(mesh, length, _COLOR_END)
	mesh.surface_end()


func _draw_running_rails(mesh: ImmediateMesh, length: float) -> void:
	const STEP := 0.5
	var half_gauge := track_gauge * 0.5
	var steps := maxi(1, ceili(length / STEP))
	var previous := sample_local_transform(0.0)
	for i in range(1, steps + 1):
		var frame := sample_local_transform(length * float(i) / float(steps))
		for side in [-half_gauge, half_gauge]:
			_line(mesh, previous.origin + previous.basis.x * side,
					frame.origin + frame.basis.x * side, _COLOR_RAIL)
		previous = frame


func _draw_sleepers(mesh: ImmediateMesh, length: float) -> void:
	if sleeper_spacing <= 0.0:
		return
	var overhang := track_gauge * 0.75
	var distance := sleeper_spacing * 0.5
	while distance < length:
		var frame := sample_local_transform(distance)
		_line(mesh, frame.origin - frame.basis.x * overhang,
				frame.origin + frame.basis.x * overhang, _COLOR_SLEEPER)
		distance += sleeper_spacing


## Chevrons pointing the way the curve itself runs, towards increasing distance.
## Trains may well be travelling against them.
func _draw_direction_arrows(mesh: ImmediateMesh, length: float) -> void:
	if arrow_spacing <= 0.0:
		return
	const HALF_LENGTH := 1.2
	const HALF_WIDTH := 0.7
	var lift := Vector3.UP * 0.4
	var distance := arrow_spacing * 0.5
	while distance < length:
		var frame := sample_local_transform(distance)
		var forward := -frame.basis.z
		var tip := frame.origin + forward * HALF_LENGTH + lift
		var base := frame.origin - forward * HALF_LENGTH * 0.5 + lift
		_line(mesh, tip, base + frame.basis.x * HALF_WIDTH, _COLOR_ARROW)
		_line(mesh, tip, base - frame.basis.x * HALF_WIDTH, _COLOR_ARROW)
		distance += arrow_spacing


func _draw_end_marker(mesh: ImmediateMesh, distance: float, color: Color) -> void:
	const HEIGHT := 2.5
	var frame := sample_local_transform(distance)
	var top := frame.origin + Vector3.UP * HEIGHT
	_line(mesh, frame.origin, top, color)
	_line(mesh, top - frame.basis.x, top + frame.basis.x, color)


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
	return _debug_material
#endregion
