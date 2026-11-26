class_name TrackOverlay
extends RefCounted
## The route overlay [Turnout] and [CompoundTurnout] draw on the track: bands of
## three lines sampled along the real rails, so they curve with the track, green
## where a route is set and red where it is not, with a cross on a dead end.
## Names only [Rail] and [DebugLines], so either may use it.

const COLOR_SET := Color(0.25, 1.0, 0.35)
const COLOR_UNSET := Color(0.85, 0.2, 0.18)
const COLOR_POINTS := Color(1.0, 1.0, 1.0)
## Spacing of the samples along a band.
const STEP := 0.75
const _HALF_WIDTH := 0.45


## How many segments a band [param length] metres long is drawn in.
static func sample_count(length: float) -> int:
	return maxi(1, ceili(length / STEP))


## A band of three lines through [param rail] at each of [param distances], so it
## reads as a highlighted route from a distance rather than disappearing into the
## track below it.
static func band(mesh: ImmediateMesh, rail: Rail, distances: PackedFloat64Array, lift: float,
		color: Color) -> void:
	var previous := Vector3.ZERO
	var previous_side := Vector3.ZERO
	for i in distances.size():
		var point := rail.sample_position(distances[i]) + Vector3.UP * lift
		var side := rail.sample_transform(distances[i]).basis.x * _HALF_WIDTH
		if i > 0:
			for offset: float in [-1.0, 0.0, 1.0]:
				DebugLines.line(mesh, previous + previous_side * offset,
						point + side * offset, color)
		previous = point
		previous_side = side


## A cross on the end of a leg no route leaves by, so "this way is closed"
## survives being a few pixels of red on a zoomed-out screen.
static func dead_end(mesh: ImmediateMesh, rail: Rail, at: float, lift: float,
		color: Color) -> void:
	var point := rail.sample_position(at) + Vector3.UP * lift
	var side := rail.sample_transform(at).basis.x * _HALF_WIDTH
	var up := Vector3.UP * _HALF_WIDTH * 1.6
	DebugLines.line(mesh, point - side - up, point + side + up, color)
	DebugLines.line(mesh, point - side + up, point + side - up, color)


## The white stalk marking where a set of points sits.
static func points_post(mesh: ImmediateMesh, base: Vector3, lift: float) -> void:
	DebugLines.line(mesh, base, base + Vector3.UP * (lift + 1.4), COLOR_POINTS)
