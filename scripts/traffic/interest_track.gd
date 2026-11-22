@tool
class_name InterestTrack
extends Node
## One track an [InterestPoint] spans: a rail and the spot on it that matters - the
## mark a train stands on at a [Station], or the line a train crosses to enter or
## leave the level at an [OutsideConnection].
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
## Distance along [member rail], in metres. At a station, the middle of the platform:
## a train stops with its own middle here. At a connection, the line a train has to
## clear completely to have left the level.
@export var distance := 0.0: set = _set_distance
@export var role := Role.BOTH


func location() -> TrackWalker.Location:
	return TrackWalker.Location.new(rail, distance)


## Where the mark is in the world, or the origin with no rail.
func position() -> Vector3:
	if rail == null or rail.rail_length() <= 0.0 or not rail.is_inside_tree():
		return Vector3.ZERO
	return rail.sample_position(distance)


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
