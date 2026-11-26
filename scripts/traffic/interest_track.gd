@tool
class_name InterestTrack
extends Node
## One track an [InterestPoint] spans: a rail and the spot on it that matters - the
## middle of the platform at a [Station], or the mark a new train's nose is put on and
## a leaving train's tail has to clear at an [OutsideConnection].
##
## A child of its point, so a station with four tracks is a [Station] with four of
## these under it. Not a spatial node: the point draws itself over the middle of its
## tracks, and nothing else needs the track's own position drawn.

## What a track of an [OutsideConnection] is for. A station's tracks ignore it.
enum Role {
	## Trains both enter and leave here.
	BOTH,
	## Trains enter the level here, and are never taken off it.
	IN,
	## Trains leave the level here, and are never put on it.
	OUT,
}

@export var rail: Rail: set = _set_rail
## Distance along [member rail], in metres. At a station, the middle of the platform.
## At a connection, where a new train's nose is put down, and the line a leaving
## train has to clear completely to have left the level.
@export var distance := 0.0: set = _set_distance
@export var role := Role.BOTH
## A station's platform, centred on [member distance], in metres. Its two ends are the
## track's stop marks, one for each way: a train stops with its **nose** on the end it
## is heading for ([method stop_distance]), so trains both ways stand on the same
## stretch. A connection's tracks ignore it.
@export_range(10.0, 300.0, 1.0, "suffix:m") var platform_length := 80.0: set = _set_platform_length


func location() -> TrackWalker.Location:
	return TrackWalker.Location.new(rail, distance)


## Where the mark is in the world, or the origin with no rail.
func position() -> Vector3:
	if rail == null or rail.rail_length() <= 0.0 or not rail.is_inside_tree():
		return Vector3.ZERO
	return rail.sample_position(distance)


## The first signal a train travelling [param direction] along the rail from the mark
## reaches before any points or the end of the line - whatever it shows. Null when
## there is none: a station track without its exit signal that way, a connection
## track without its entry signal.
func guarding_signal(direction: int) -> RailSignal:
	if rail == null or not rail.is_inside_tree() or rail.rail_length() <= 0.0:
		return null
	var walk := TrackWalker.walk(rail, distance, direction, rail.rail_length(),
			TrackWalker.OBEY_ALL_SIGNALS, [], true)
	return walk.blocking_signal if walk.spans.size() == 1 else null


## Where a train travelling [param direction] along the rail stops at a station: the
## end of the platform it is heading for, nose on it.
func stop_distance(direction: int) -> float:
	var at := distance + float(signi(direction)) * platform_length * 0.5
	return rail.clamp_distance(at) if rail != null else at


func can_spawn() -> bool:
	return role != Role.OUT


func can_absorb() -> bool:
	return role != Role.IN


func _set_rail(value: Rail) -> void:
	rail = value
	_changed()


func _set_distance(value: float) -> void:
	distance = value
	_changed()


func _set_platform_length(value: float) -> void:
	platform_length = value
	update_configuration_warnings()
	var point := get_parent() as InterestPoint
	if point != null:
		point.update_configuration_warnings()
		# A station's platforms are as long as this.
		point._marker_moved()


func _changed() -> void:
	update_configuration_warnings()
	var point := get_parent() as InterestPoint
	if point != null:
		point.refresh()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if rail == null:
		warnings.append("No rail set.")
	elif rail.is_inside_tree() and (distance < 0.0 or distance > rail.rail_length()):
		warnings.append("Distance %.1f m is off %s, which is %.1f m long." % [
				distance, rail.name, rail.rail_length()])
	if not get_parent() is InterestPoint:
		warnings.append("Belongs under a Station or an OutsideConnection.")
	return warnings
