@tool
class_name Station
extends InterestPoint
## Somewhere a train on its way stops for a while: a platform beside each of its
## tracks, and a building beside the outermost one, both in the station's colour.
##
## The platforms are low slabs as long as each track's [member InterestTrack.platform_length].
## Two neighbouring tracks far enough apart share an island between them; a track
## without one gets a platform on its outer side - the building's side for a station
## of one track. A track with neighbours close on both sides gets none: there is no
## room for one.
##
## A train whose route says the next stop is this station brakes to stand with its
## nose on the stop mark of whichever track it is on, the end of the platform it is
## heading for ([method InterestTrack.stop_distance]) - even through a signal at clear -
## waits [member dwell_time] and goes on. Passing a station that is not the next
## stop on its route changes nothing.
##
## Every track wants an exit signal each way it can be left by - a signal between the
## platform's end and the first points, or the end of the line - so that a train that
## has done its stop waits there for the player rather than running on into a junction.

## What a stop does to the freight wagons.
enum Cargo {
	## Nothing: a passenger station, or a stop that only waits.
	NONE,
	## The wagons fill to the brim during the stop: a mine.
	LOAD,
	## The wagons empty during the stop: a factory.
	UNLOAD,
}

## Which side of the tracks the building stands on, looking along the first track's
## rail towards its end.
enum Side {
	NONE,
	LEFT,
	RIGHT,
}

## The building: along the track, high to the eaves, deep, and the roof on top. A
## plain box with a gable roof.
const BUILDING_SIZE := Vector3(16.0, 4.5, 7.0)
const ROOF_HEIGHT := 2.6
## How far past the platform's end an exit signal has to stand, at least, for a train
## to stop at the end of the platform first: a train stops this short of a red. The
## same as [constant Train.STOP_SHORT], which this class cannot name.
const EXIT_CLEARANCE := 3.0
## Between the centre line of the outermost track and the building's wall, in metres:
## room for an outer platform and a path behind it.
const BUILDING_GAP := 7.5
## A platform's edge stands this far from the centre line of its track, clear of the
## widest car; its top this far above the railhead.
const PLATFORM_EDGE := 1.75
const PLATFORM_HEIGHT := 0.35
## How wide an outer platform is, and an island at most. Narrower than the least,
## the space between two tracks holds no island.
const PLATFORM_WIDTH := 4.0
const ISLAND_WIDTH := 6.0
const PLATFORM_LEAST_WIDTH := 2.0
## A platform is built of straight pieces at most this long, so it follows a curve.
const PLATFORM_PIECE := 6.0
## The walls go this far into the ground, so that a slope does not show daylight
## under them.
const _FOOTING := 1.5

## How long a train stands here, in seconds.
@export_range(0.0, 60.0, 0.5, "suffix:s") var dwell_time := 5.0
@export var cargo := Cargo.NONE
@export var building_side := Side.RIGHT:
	set(value):
		building_side = value
		_marker_moved()

var _building: Node3D
var _platforms: Node3D
var _wall_material: StandardMaterial3D
var _roof_material: StandardMaterial3D
var _platform_material: StandardMaterial3D


func _enter_tree() -> void:
	super._enter_tree()
	add_to_group(Ground.STANDING_GROUP)


func _exit_tree() -> void:
	super._exit_tree()
	remove_from_group(Ground.STANDING_GROUP)


## The ground under the building and the platforms has been cut anew (see
## [constant Ground.STANDING_GROUP]).
func ground_changed() -> void:
	_marker_moved()


func is_square() -> bool:
	return false


## The mark of this station's track that lies on [param query_rail], if any.
func mark_on(query_rail: Rail) -> InterestTrack:
	for track in tracks():
		if track.rail == query_rail:
			return track
	return null


## The building, or null when [member building_side] is NONE or nothing is built yet.
func building() -> Node3D:
	return _building if _building != null and _building.visible else null


## The platforms, one [Node3D] each with its pieces under it, or none before the
## station is in the tree.
func platforms() -> Array[Node3D]:
	var found: Array[Node3D] = []
	if _platforms != null:
		for child in _platforms.get_children():
			found.append(child as Node3D)
	return found


func _marker_moved() -> void:
	if not is_inside_tree():
		return
	_place_platforms()
	_place_building()


func _place_building() -> void:
	var found := tracks()
	if building_side == Side.NONE or found.is_empty() \
			or found[0].rail.rail_length() <= 0.0 or not found[0].rail.is_inside_tree():
		if _building != null:
			_building.visible = false
		return
	_ensure_building()
	# Across the tracks, measured from the middle, on the building's side: the track
	# furthest out is the one the building stands beside.
	var first := found[0]
	var forward := first.rail.sample_forward(first.distance)
	forward.y = 0.0
	if forward.length_squared() < 1e-9:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var side := 1.0 if building_side == Side.RIGHT else -1.0
	var across := forward.cross(Vector3.UP) * side
	var outermost := first
	var furthest := -INF
	for track in found:
		if not track.rail.is_inside_tree():
			continue
		var out := track.position().dot(across)
		if out > furthest:
			furthest = out
			outermost = track
	var frame := outermost.rail.ground_frame(outermost.distance, forward,
			side * (BUILDING_GAP + BUILDING_SIZE.z * 0.5))
	_building.global_transform = frame
	_building.visible = true


func _refresh_colors() -> void:
	if _wall_material != null:
		_wall_material.albedo_color = color()
		_roof_material.albedo_color = color().darkened(0.45)
	if _platform_material != null:
		_platform_material.albedo_color = color().lightened(0.25)


#region Platforms
## Which side of which track each platform goes, and how wide: see the class
## description. Each entry is the track it runs along, the offset of its middle to
## that rail's right and its width.
func _platform_layout() -> Array[Dictionary]:
	var found: Array[InterestTrack] = []
	for track in tracks():
		if track.rail.is_inside_tree() and track.rail.rail_length() > 0.0:
			found.append(track)
	if found.is_empty():
		return []
	# Every track's place across the station, to the right of the first one's rail.
	var right := _right_of(found[0])
	var origin := found[0].position()
	found.sort_custom(func(a: InterestTrack, b: InterestTrack) -> bool:
		return (a.position() - origin).dot(right) < (b.position() - origin).dot(right))
	var across: Array[float] = []
	for track in found:
		across.append((track.position() - origin).dot(right))

	var layout: Array[Dictionary] = []
	var served: Array[bool] = []
	served.resize(found.size())
	served.fill(false)
	for i in found.size() - 1:
		var room := across[i + 1] - across[i] - 2.0 * PLATFORM_EDGE
		if room < PLATFORM_LEAST_WIDTH:
			continue
		layout.append(_platform_beside(found[i], right, (across[i + 1] - across[i]) * 0.5,
				minf(room, ISLAND_WIDTH)))
		served[i] = true
		served[i + 1] = true
	var last := found.size() - 1
	var outer := PLATFORM_EDGE + PLATFORM_WIDTH * 0.5
	if found.size() == 1:
		var side := -1.0 if building_side == Side.LEFT else 1.0
		layout.append(_platform_beside(found[0], right, side * outer, PLATFORM_WIDTH))
	else:
		if not served[0]:
			layout.append(_platform_beside(found[0], right, -outer, PLATFORM_WIDTH))
		if not served[last]:
			layout.append(_platform_beside(found[last], right, outer, PLATFORM_WIDTH))
	return layout


## A platform along [param track], [param offset] metres towards [param right] of it.
func _platform_beside(track: InterestTrack, right: Vector3, offset: float,
		width: float) -> Dictionary:
	var along := track.rail.sample_forward(track.distance).cross(Vector3.UP)
	var sense := 1.0 if along.dot(right) >= 0.0 else -1.0
	return {"track": track, "offset": offset * sense, "width": width}


## Level and square to [param track]'s rail at its mark, to the right looking towards
## the rail's end.
static func _right_of(track: InterestTrack) -> Vector3:
	var forward := track.rail.sample_forward(track.distance)
	forward.y = 0.0
	if forward.length_squared() < 1e-9:
		forward = Vector3.FORWARD
	return forward.normalized().cross(Vector3.UP)


func _place_platforms() -> void:
	if _platforms == null:
		_platforms = Node3D.new()
		_platforms.name = "Platforms"
		_platforms.top_level = true
		add_child(_platforms, false, Node.INTERNAL_MODE_BACK)
		_platform_material = StandardMaterial3D.new()
		_refresh_colors()
	for child in _platforms.get_children():
		_platforms.remove_child(child)
		child.queue_free()
	_platforms.global_transform = Transform3D.IDENTITY
	for entry in _platform_layout():
		_platforms.add_child(_build_platform(entry["track"] as InterestTrack,
				entry["offset"] as float, entry["width"] as float))


## One platform: straight pieces along the rail, each standing on the ground at its
## middle, its top [constant PLATFORM_HEIGHT] above the railhead.
func _build_platform(track: InterestTrack, offset: float, width: float) -> Node3D:
	var platform := Node3D.new()
	platform.name = "Platform%s" % track.name
	var rail := track.rail
	var start := rail.clamp_distance(track.distance - track.platform_length * 0.5)
	var end := rail.clamp_distance(track.distance + track.platform_length * 0.5)
	var pieces := maxi(1, ceili((end - start) / PLATFORM_PIECE))
	var step := (end - start) / float(pieces)
	for i in pieces:
		var middle := start + step * (float(i) + 0.5)
		var frame := rail.ground_frame(middle, rail.sample_forward(middle), offset)
		var top := rail.sample_position(middle).y + PLATFORM_HEIGHT
		var height := top - frame.origin.y + _FOOTING
		var piece := MeshInstance3D.new()
		piece.name = "PlatformPiece%d" % i
		var box := BoxMesh.new()
		# A little longer than its share, so that the pieces close up round a curve.
		box.size = Vector3(width, height, step + 0.2)
		piece.mesh = box
		piece.material_override = _platform_material
		piece.transform = frame.translated_local(Vector3.UP * (top - frame.origin.y - height * 0.5))
		platform.add_child(piece)
	return platform
#endregion


func _ensure_building() -> void:
	if _building != null:
		return
	_building = Node3D.new()
	_building.name = "Building"
	_building.top_level = true
	add_child(_building, false, Node.INTERNAL_MODE_BACK)
	_wall_material = StandardMaterial3D.new()
	_roof_material = StandardMaterial3D.new()
	_refresh_colors()
	# Built in the ground frame: -Z along the track, X across it.
	var walls := MeshInstance3D.new()
	walls.name = "Walls"
	var box := BoxMesh.new()
	box.size = Vector3(BUILDING_SIZE.z, BUILDING_SIZE.y + _FOOTING, BUILDING_SIZE.x)
	walls.mesh = box
	walls.material_override = _wall_material
	walls.position = Vector3.UP * (BUILDING_SIZE.y - _FOOTING) * 0.5
	_building.add_child(walls)
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var prism := PrismMesh.new()
	# A prism's ridge runs along Z, the length of the building.
	prism.size = Vector3(BUILDING_SIZE.z + 0.8, ROOF_HEIGHT, BUILDING_SIZE.x + 0.8)
	roof.mesh = prism
	roof.material_override = _roof_material
	roof.position = Vector3.UP * (BUILDING_SIZE.y + ROOF_HEIGHT * 0.5)
	_building.add_child(roof)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := super._get_configuration_warnings()
	for track in tracks():
		for direction: int in [1, -1]:
			var way := "end" if direction > 0 else "start"
			var exit := track.guarding_signal(direction)
			if exit == null:
				if not _ends_in_buffer(track, direction):
					warnings.append("%s has no exit signal towards the rail's %s: a signal governing trains leaving that way, between the platform and the first points." % [
							track.name, way])
			elif float(direction) * (exit.signal_distance() - track.stop_distance(direction)) < EXIT_CLEARANCE:
				warnings.append("%s's exit signal %s stands on the platform: it has to be %.0f m past the platform's end towards the rail's %s." % [
						track.name, exit.name, EXIT_CLEARANCE, way])
	return warnings


## Whether the track runs from the mark into the end of the line that way without
## meeting any points - a bay, with nowhere to leave to.
static func _ends_in_buffer(track: InterestTrack, direction: int) -> bool:
	if not track.rail.is_inside_tree():
		return true
	var walk := TrackWalker.walk(track.rail, track.distance, direction,
			track.rail.rail_length() + 1.0)
	return walk.at_dead_end and walk.spans.size() == 1
