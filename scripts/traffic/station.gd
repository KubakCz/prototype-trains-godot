@tool
class_name Station
extends InterestPoint
## Somewhere a train on its way stops for a while: a platform on each of its tracks.
##
## A train whose route says the next stop is this station brakes to stand with its
## middle on the mark of whichever track it is on - even through a signal at clear -
## waits [member dwell_time] and goes on. Passing a station that is not the next
## stop on its route changes nothing.

## What a stop does to the freight wagons.
enum Cargo {
	## Nothing: a passenger station, or a stop that only waits.
	NONE,
	## The wagons fill to the brim during the stop: a mine.
	LOAD,
	## The wagons empty during the stop: a factory.
	UNLOAD,
}

## How long a train stands here, in seconds.
@export_range(0.0, 60.0, 0.5, "suffix:s") var dwell_time := 5.0
@export var cargo := Cargo.NONE


func is_square() -> bool:
	return false


## The mark of this station's track that lies on [param query_rail], if any.
func mark_on(query_rail: Rail) -> InterestTrack:
	for track in tracks():
		if track.rail == query_rail:
			return track
	return null
