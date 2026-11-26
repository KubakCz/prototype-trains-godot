@tool
class_name TrackMesher
extends Node3D
## The level's track as meshes: one of these per level, anywhere in the scene.
## It finds every [Rail], [Bridge] and [Tunnel] in the scene it belongs to,
## works the track out with [TrackLayout] and builds it with
## [TrackMeshBuilder] - square chunks of static track, plus one small mesh per
## turnout for its blades, which swing across whenever the points are thrown.
##
## [b]Nothing it builds is saved[/b]: the meshes are internal children, built as
## the level loads, so they can never disagree with the rails. In the editor it
## rebuilds by itself - [member auto_rebuild] - a moment after the rails stop
## changing, so dragging a curve point costs nothing until it is let go. The
## [b]Rebuild Track[/b] button forces one.

## Emitted after every build.
signal rebuilt

## Rebuild in the editor whenever a rail, turnout or structure changes, once it
## has stopped changing for [member rebuild_delay] seconds.
@export var auto_rebuild := true
@export_range(0.1, 3.0, 0.05, "suffix:s") var rebuild_delay := 0.5
@export_tool_button("Rebuild Track") var _rebuild_button := rebuild
## Proposes a [Bridge] wherever the track runs high over the ground and a
## [Tunnel] wherever it runs under it, skipping stretches already covered. A
## first draft: check the spans and pick each bridge's style afterwards.
@export_tool_button("Find Bridges & Tunnels") var _find_button := find_structures
## How long the blades take to swing across.
@export_range(0.05, 3.0, 0.05, "suffix:s") var blade_throw_time := 0.6

const _POLL := 0.25
## How far either side of the centre line [Ground] has to keep below the bed:
## the ballast's top and the least of its sides. Past that the ground is left
## as authored - a level's carving shapes its own cuttings.
const _BED_CLEAR := 1.8
## How far past a rail's end the bed carries on: the track runs on 1.4 m to a
## buffer stop.
const _END_RUN := 2.0

## The layout the current meshes were built from.
var layout: TrackLayout
## How long the last build took, in milliseconds.
var last_build_msec := 0.0

var _chunks: Dictionary[Vector2i, MeshInstance3D] = {}
var _blades: Dictionary[Turnout, MeshInstance3D] = {}
var _blade_weights: Dictionary[Turnout, float] = {}
var _structures: Array[TrackStructure] = []
var _built_signature := 0
var _seen_signature := 0
var _unchanged_for := 0.0
var _poll_timer := 0.0


func _enter_tree() -> void:
	add_to_group(Ground.SHAPER_GROUP)


func _exit_tree() -> void:
	remove_from_group(Ground.SHAPER_GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		rebuild()
	else:
		# After every rail has snapped and every turnout welded its branch on.
		rebuild.call_deferred()


func _process(delta: float) -> void:
	_swing_blades(delta)
	if Engine.is_editor_hint() and auto_rebuild:
		_poll_timer += delta
		if _poll_timer < _POLL:
			return
		_poll_timer = 0.0
		var now := signature()
		if now != _seen_signature:
			_seen_signature = now
			_unchanged_for = 0.0
		else:
			_unchanged_for += _POLL
			if now != _built_signature and _unchanged_for >= rebuild_delay:
				rebuild()


func rebuild() -> void:
	if not is_inside_tree():
		return
	var started := Time.get_ticks_usec()
	var rails := _scene_rails()
	_structures = _scene_structures()
	layout = TrackLayout.build(rails)
	# A dead end inside a tunnel is a way off the level, not a buffer stop.
	layout.buffer_stops.assign(layout.buffer_stops.filter(
			func(stop: TrackLayout.BufferStop) -> bool:
				for structure in _structures:
					if structure is Tunnel and structure.covers(stop.rail, stop.distance):
						return false
				return true))

	var builder := TrackMeshBuilder.new()
	var surfaces: Array[SurfaceSnapper.Surface] = []
	if not rails.is_empty():
		surfaces = rails[0].ground_surfaces()
	# The track cuts its bed into the ground: if it has moved since the ground
	# was built, the ground has to be cut again - before the ballast is laid on it.
	var grounds := TrackStructure.refresh_grounds(surfaces)
	builder.ground_height = func(point: Vector3) -> Variant:
		return SurfaceSnapper.height_at(surfaces, point.x, point.z)
	builder.ground_color = func(point: Vector3) -> Color:
		for ground in grounds:
			var color = ground.surface_color_at(point.x, point.z)
			if color != null:
				return color
		return TrackMeshBuilder.GRASS
	builder.ballast_mode = func(rail: Rail, at: float) -> TrackMeshBuilder.Ballast:
		for structure in _structures:
			if structure.covers(rail, at):
				return structure.ballast_mode()
		return TrackMeshBuilder.Ballast.BED

	_show_chunks(builder.build_chunks(layout))
	_show_blades(TrackMeshBuilder.build_blades(layout))
	if Engine.is_editor_hint():
		# In the game each structure builds itself once as the level loads; in
		# the editor the rails under it may just have moved.
		for structure in _structures:
			structure.rebuild()
	_built_signature = signature()
	_seen_signature = _built_signature
	last_build_msec = float(Time.get_ticks_usec() - started) / 1000.0
	rebuilt.emit()


#region What was built
## The chunk instances, by chunk cell.
func chunks() -> Dictionary[Vector2i, MeshInstance3D]:
	return _chunks


## The instance drawing [param turnout]'s blades, or null.
func blade_instance(turnout: Turnout) -> MeshInstance3D:
	return _blades.get(turnout) as MeshInstance3D


## How far [param turnout]'s blades have swung: 0 lying normal, 1 reverse.
func blade_weight(turnout: Turnout) -> float:
	return _blade_weights.get(turnout, 0.0)


func structures() -> Array[TrackStructure]:
	return _structures


func _show_chunks(meshes: Dictionary[Vector2i, ArrayMesh]) -> void:
	for cell in _chunks.keys():
		if not meshes.has(cell):
			_chunks[cell].queue_free()
			_chunks.erase(cell)
	for cell in meshes:
		if not _chunks.has(cell):
			var instance := MeshInstance3D.new()
			instance.name = "Chunk_%d_%d" % [cell.x, cell.y]
			instance.top_level = true
			add_child(instance, false, Node.INTERNAL_MODE_BACK)
			_chunks[cell] = instance
		_chunks[cell].global_transform = Transform3D.IDENTITY
		_chunks[cell].mesh = meshes[cell]


func _show_blades(meshes: Dictionary[Turnout, ArrayMesh]) -> void:
	for turnout in _blades.keys():
		if not meshes.has(turnout) or not is_instance_valid(turnout):
			_blades[turnout].queue_free()
			_blades.erase(turnout)
			_blade_weights.erase(turnout)
	for turnout in meshes:
		if not _blades.has(turnout):
			var instance := MeshInstance3D.new()
			instance.name = "Blades_%s" % turnout.name
			instance.top_level = true
			add_child(instance, false, Node.INTERNAL_MODE_BACK)
			_blades[turnout] = instance
			# Lying where the points are now, not swinging across from normal.
			_blade_weights[turnout] = _target_weight(turnout)
		_blades[turnout].global_transform = Transform3D.IDENTITY
		_blades[turnout].mesh = meshes[turnout]
		_blades[turnout].set_blend_shape_value(0, _blade_weights[turnout])


static func _target_weight(turnout: Turnout) -> float:
	return 1.0 if turnout.turnout_position == Turnout.Position.REVERSE else 0.0


## Moves every blade towards wherever its points are set. Polled rather than
## driven by [signal Turnout.position_changed], so a turnout thrown before the
## track was built, or by the inspector, ends up right all the same.
func _swing_blades(delta: float) -> void:
	var rate := delta / maxf(blade_throw_time, 1e-3)
	for turnout in _blades:
		if not is_instance_valid(turnout):
			continue
		var weight := _blade_weights[turnout]
		var target := _target_weight(turnout)
		if is_equal_approx(weight, target):
			continue
		weight = move_toward(weight, target, rate)
		_blade_weights[turnout] = weight
		var t := weight * weight * (3.0 - 2.0 * weight)
		_blades[turnout].set_blend_shape_value(0, t)
#endregion


#region Scene
## The scene this mesher builds for: the one it was saved in.
func _scene_root() -> Node:
	if owner != null:
		return owner
	return get_parent() if get_parent() != null else self


func _scene_rails() -> Array[Rail]:
	var found: Array[Rail] = []
	for node in _descendants(_scene_root()):
		if node is Rail:
			found.append(node as Rail)
	return found


func _scene_structures() -> Array[TrackStructure]:
	var found: Array[TrackStructure] = []
	for node in _descendants(_scene_root()):
		if node is TrackStructure:
			found.append(node as TrackStructure)
	return found


static func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		found.append(node)
		stack.append_array(node.get_children())
	return found


## Everything a rebuild depends on, hashed: every rail's curve and placement,
## every turnout's welding, every structure's span. Throwing points is not in
## it - the blades swing for that, nothing is rebuilt.
func signature() -> int:
	var parts: Array = []
	for node in _descendants(_scene_root()):
		if node is Rail:
			var rail := node as Rail
			parts.append(rail.global_transform)
			parts.append(rail.track_gauge)
			if rail.curve != null:
				for i in rail.curve.point_count:
					parts.append(rail.curve.get_point_position(i))
					parts.append(rail.curve.get_point_in(i))
					parts.append(rail.curve.get_point_out(i))
					parts.append(rail.curve.get_point_tilt(i))
		elif node is Turnout:
			var turnout := node as Turnout
			parts.append([turnout.main_rail, turnout.main_distance, turnout.diverge_towards,
					turnout.branch_rail, turnout.branch_end])
		elif node is TrackStructure:
			var structure := node as TrackStructure
			parts.append([structure.rail, structure.from_distance, structure.to_distance,
					(structure as Bridge).style if structure is Bridge else -1])
	return hash(parts)
#endregion


#region The ground under the track
## For [Ground]: the bed of every rail, which the ground must lie under - so it
## can never show through the ballast, however the terrain between two snapped
## curve points bulges. Tunnels are left out; their mouths shape the ground
## themselves. A [Ground] answers this as it builds, before the track is, so it
## is worked out from the rails directly rather than from [member layout].
func ground_cuts(ground: Ground) -> Array[Dictionary]:
	var cuts: Array[Dictionary] = []
	var spacing := clampf(ground.cell_diagonal() * 0.35, 0.5, 2.0)
	var structures := _scene_structures()
	for rail in _scene_rails():
		var length := rail.rail_length()
		if length <= 0.0:
			continue
		var tunnels: Array[TrackStructure] = []
		var stations: Array[float] = []
		for structure in structures:
			if structure is Tunnel and structure.rail == rail and structure.is_usable():
				tunnels.append(structure)
				stations.append_array([structure.start_distance() - 0.01,
						structure.end_distance() + 0.01])
		var at := -_END_RUN
		while at < length + _END_RUN:
			stations.append(at)
			at += spacing
		stations.append(length + _END_RUN)
		stations.sort()
		var line := PackedVector3Array()
		for station in stations:
			var on_rail := clampf(station, 0.0, length)
			var in_tunnel := false
			for tunnel in tunnels:
				if tunnel.covers(rail, on_rail):
					in_tunnel = true
			if in_tunnel:
				if line.size() >= 2:
					cuts.append(_cut(line))
				line = PackedVector3Array()
				continue
			var bed := rail.sample_position(on_rail) \
					+ rail.sample_forward(on_rail) * (station - on_rail) \
					+ Vector3.DOWN * rail.surface_offset
			line.append(bed)
		if line.size() >= 2:
			cuts.append(_cut(line))
	return cuts


static func _cut(line: PackedVector3Array) -> Dictionary:
	return {"line": line, "half_width": _BED_CLEAR}
#endregion


#region Find bridges and tunnels
## See [member _find_button]; the work is [StructureFinder]'s.
func find_structures() -> void:
	var rails := _scene_rails()
	if rails.is_empty():
		return
	StructureFinder.propose(_scene_root(), rails, _scene_structures())
	rebuild()
#endregion
