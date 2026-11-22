@tool
class_name OutsideConnection
extends InterestPoint
## A way on to and off the level. Trains are put on the level here, and a train whose
## route ends here is taken off it.
##
## Each track has a mark on its rail. The end of the rail the mark is nearer to is
## the *outside*: the mark is where a train has finished leaving, so it is meant to
## have room beyond it for the longest train - a tunnel, usually, so that the train
## goes out of sight on its way. A train is put on the level with its tail just inside
## the mark, facing in, and is taken off it once its tail has gone out past the mark.
##
## A connection that is not a train's destination is nothing but the end of a rail
## to it - it turns round or stops there like at any dead end.

## How far inside the mark the tail of a new train stands, in metres.
const SPAWN_INSET := 1.0


func is_square() -> bool:
	return true


## Which way along [param track]'s rail is out: -1 towards the rail's start, 1 towards
## its end, whichever is nearer the mark.
static func outward(track: InterestTrack) -> int:
	return -1 if track.distance < track.rail.rail_length() * 0.5 else 1


## Whether a train whose two ends are at [param front] and [param rear] has left by
## this connection: both ends out past the mark of one of its tracks that takes trains
## off the level. A train held against the end of the rail has left too, when either
## end is past the mark - a train longer than the room beyond the mark can never get
## its tail out, and would be turning round at the buffer for ever.
func has_left(front: TrackWalker.Location, rear: TrackWalker.Location,
		at_end_of_line := false) -> bool:
	for track in tracks():
		if not track.can_absorb():
			continue
		var out := float(outward(track))
		var front_out := (front.rail == track.rail
				and out * (front.distance - track.distance) >= 0.0)
		var rear_out := (rear.rail == track.rail
				and out * (rear.distance - track.distance) >= 0.0)
		if (front_out and rear_out) or (at_end_of_line and (front_out or rear_out)):
			return true
	return false


## Where a train of [param length] metres goes on [param track]: the distance of its
## middle and the way its nose points, or null when the rail is too short for it.
func spawn_pose(track: InterestTrack, length: float) -> Dictionary:
	var inward := -outward(track)
	var middle := track.distance + float(inward) * (length * 0.5 + SPAWN_INSET)
	var nose := middle + float(inward) * length * 0.5
	if nose < 0.0 or nose > track.rail.rail_length():
		return {}
	# `facing` is a Train's: 1 along the rail, -1 against it. Not named here, so
	# that Train can name this class.
	return {"distance": middle, "facing": inward}


## The room beyond the mark of [param track], in metres.
static func room_outside(track: InterestTrack) -> float:
	return track.distance if outward(track) < 0 else track.rail.rail_length() - track.distance


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := super._get_configuration_warnings()
	for track in tracks():
		if track.rail.rail_length() > 0.0 and room_outside(track) < 1.0:
			warnings.append("%s's mark is at the end of %s: no room outside it for a train to go out of sight." % [
					track.name, track.rail.name])
	return warnings
