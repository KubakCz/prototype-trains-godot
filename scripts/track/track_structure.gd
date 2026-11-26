@tool
class_name TrackStructure
extends Node3D
## Something built along a stretch of one rail - a [Bridge] or a [Tunnel] - from
## [member from_distance] to [member to_distance] along [member rail].
##
## Authored like a turnout: pick the rail and the two distances in the inspector.
## [TrackMesher]'s [b]Find Bridges & Tunnels[/b] button proposes them from the
## terrain, as a first draft. The structure builds its own mesh, which is never
## saved, and tells the track mesher how the track runs through it (see
## [method ballast_mode]).

@export var rail: Rail:
	set(value):
		rail = value
		_changed()
@export var from_distance := 0.0:
	set(value):
		from_distance = value
		_changed()
@export var to_distance := 20.0:
	set(value):
		to_distance = value
		_changed()

## A span ending this close to its rail's end is taken to run off it: a tunnel
## authored to "802.5" on a rail 802.51 m long still swallows the dead end.
const END_TOLERANCE := 0.5

var _instance: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		rebuild()
	else:
		# After the rails have snapped and the turnouts welded their branches.
		rebuild.call_deferred()


## Whether [param at] along [param query_rail] is on this structure.
func covers(query_rail: Rail, at: float) -> bool:
	if query_rail != rail or rail == null:
		return false
	var start := start_distance()
	var end := end_distance()
	if start <= END_TOLERANCE:
		start = -INF
	if end >= rail.rail_length() - END_TOLERANCE:
		end = INF
	return at >= start and at <= end


func start_distance() -> float:
	return minf(from_distance, to_distance)


func end_distance() -> float:
	return maxf(from_distance, to_distance)


func span_length() -> float:
	return end_distance() - start_distance()


func is_usable() -> bool:
	return rail != null and rail.curve != null and rail.rail_length() > 0.0 and span_length() > 0.5


## How the track's ballast runs over this structure.
func ballast_mode() -> TrackMeshBuilder.Ballast:
	return TrackMeshBuilder.Ballast.BED


## The generated mesh, or null before the first build.
func mesh_instance() -> MeshInstance3D:
	return _instance


func rebuild() -> void:
	if not is_inside_tree():
		return
	if _instance == null:
		_instance = MeshInstance3D.new()
		_instance.name = "Mesh"
		_instance.top_level = true
		add_child(_instance, false, Node.INTERNAL_MODE_BACK)
	_instance.global_transform = Transform3D.IDENTITY
	if not is_usable() or not rail.is_inside_tree():
		_instance.mesh = null
		return
	# Sit the node itself on the middle of the span, so it is where you would
	# click to select it. The mesh ignores it: it is built in global space.
	var middle := rail.sample_position(rail.clamp_distance(
			(start_distance() + end_distance()) * 0.5))
	if not global_position.is_equal_approx(middle):
		global_position = middle
	_instance.mesh = _build_mesh(rail.ground_surfaces())


## Overridden: the structure's mesh, in global space.
func _build_mesh(_surfaces: Array[SurfaceSnapper.Surface]) -> ArrayMesh:
	return null


#region Helpers for the shapes
## Railhead frame at [param at]: on the track, upright rather than banked or
## pitched - a structure stands plumb whatever the track does - with -Z along
## the rail's own direction.
func flat_frame(at: float) -> Transform3D:
	var frame := TrackLayout.frame_at(rail, at)
	var forward := Vector3(-frame.basis.z.x, 0.0, -frame.basis.z.z)
	if forward.length_squared() < 1e-9:
		forward = Vector3.FORWARD
	return Transform3D(Rail.basis_from_forward_up(forward.normalized(), Vector3.UP),
			frame.origin)


## Ground height under [param point], or the level the track's own bed would be
## at when there is no ground there at all.
func ground_y(surfaces: Array[SurfaceSnapper.Surface], point: Vector3, fallback: float) -> float:
	var height = SurfaceSnapper.height_at(surfaces, point.x, point.z)
	return fallback if height == null else float(height)


## Distances from [param from] to [param to] spaced at most [param step] apart,
## both ends included.
static func distances(from: float, to: float, step: float) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	var count := maxi(1, ceili((to - from) / step))
	for i in count + 1:
		found.append(lerpf(from, to, float(i) / float(count)))
	return found


## Every [Ground] among [param surfaces], each brought up to date with
## [method Ground.refresh_shapes] - the track and the tunnels cut into it.
static func refresh_grounds(surfaces: Array[SurfaceSnapper.Surface]) -> Array[Ground]:
	var grounds: Array[Ground] = []
	for surface in surfaces:
		if surface.ground != null:
			surface.ground.refresh_shapes()
			grounds.append(surface.ground)
	return grounds


## Each of [param vectors] turned round: the left-hand normals of a strip
## from its right-hand ones.
static func negated(vectors: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for v in vectors:
		result.append(-v)
	return result
#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if rail == null:
		warnings.append("No rail set.")
	elif rail.rail_length() > 0.0 and (start_distance() < -END_TOLERANCE
			or end_distance() > rail.rail_length() + END_TOLERANCE):
		warnings.append("The span %.1f - %.1f m runs off rail '%s' (0 - %.1f m)."
				% [start_distance(), end_distance(), rail.name, rail.rail_length()])
	if span_length() <= 0.5:
		warnings.append("The span is empty: set from_distance and to_distance.")
	return warnings


func _changed() -> void:
	update_configuration_warnings()
	if is_inside_tree():
		rebuild()

