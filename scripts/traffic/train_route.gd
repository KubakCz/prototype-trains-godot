@tool
class_name TrainRoute
extends Node
## One line of a level's list of routes: the trains of these types, arriving at one of
## these entry points, go through these stops in this order and finish at the last.
##
## A line serves several types and several entry points at once, so the list stays
## short - "passenger trains from either end stop at the central station, then leave
## by the other end" is one line. The [TrainSpawner] picks a line at random, then an
## entry from it, then a type, so lines are how a level steers who goes where.
##
## The stops are stations with an [OutsideConnection] last: a route always ends by
## leaving the level, and never by stopping somewhere in it. An entry may be a station
## too: those are where trains placed when the level loads can stand.

@export var train_types: Array[TrainType] = []
@export var entries: Array[InterestPoint] = []
## In the order the train goes through them. The last is where it leaves.
@export var stops: Array[InterestPoint] = []


## The destination: the last stop, if it is a way off the level.
func destination() -> OutsideConnection:
	return stops.back() as OutsideConnection if not stops.is_empty() else null


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if train_types.is_empty():
		warnings.append("No train types: no train will ever take this route.")
	if entries.is_empty():
		warnings.append("No entry points: no train will ever start this route.")
	if stops.is_empty():
		warnings.append("No stops: a route has to end at an OutsideConnection.")
	elif destination() == null:
		warnings.append("The last stop has to be an OutsideConnection.")
	for i in stops.size() - 1:
		if stops[i] is OutsideConnection:
			warnings.append("Stop %d, %s, is an OutsideConnection: only the last stop may be." % [
					i + 1, stops[i].name])
	for entry in entries:
		if not stops.is_empty() and entry == stops[0]:
			warnings.append("%s is both an entry and the first stop." % entry.name)
	return warnings
