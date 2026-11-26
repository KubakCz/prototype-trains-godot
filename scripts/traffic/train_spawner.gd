@tool
class_name TrainSpawner
extends Node
## Puts trains on the level and counts them. One per level, with the level's list of
## routes - [TrainRoute] children - under it.
##
## When the level loads, [member initial_trains] trains are put down at random interest
## points: stations, where a train stands for its first dwell, and connections alike.
## From then on only [OutsideConnection]s take new trains, one at a time, at least
## [member min_spawn_interval] seconds apart and never while [member max_trains] are
## on the level.
##
## A spawn picks a route at random, an entry point of the route, a train type of the
## route and a free track of the entry. A track is free when no train is anywhere on the
## sector the new one would be put into: from a few metres behind its tail forward to
## the first signal ahead of its nose - the entry signal of a connection, the exit
## signal of a station - whatever that signal shows. If none is, the spawner tries
## another route and, failing that, again a second later. Whether the train may go on
## past that signal is the player's call: at red it rolls in and stops there.

## Every spawner joins this group, for the debug panel to find.
const GROUP := &"train_spawners"

signal train_spawned(train: Train)
## A spawned train left the level by its destination. [param completed] is whether it
## went through every stop on the way.
signal train_left(train: Train, completed: bool)

## Free track wanted behind a new train's tail, in metres.
const CLEAR_BEHIND := 15.0
## How far ahead the sector is looked for. A level with no signal within this of
## a spawn point has a sector this long.
const SECTOR_REACH := 2000.0
## After a spawn the next is due between one and this many times the minimum interval
## later.
const JITTER := 2.0
## How long after a spawn that found no room the spawner looks again, in seconds.
const RETRY_INTERVAL := 1.0

## The most trains the level holds at once, those standing wrecked included.
@export_range(1, 50) var max_trains := 4
## The least time between two spawns while the level runs, in seconds.
@export_range(1.0, 600.0, 1.0, "suffix:s") var min_spawn_interval := 60.0:
	set(value):
		min_spawn_interval = value
		# Changed while the level runs: the wait starts again from now.
		if is_node_ready():
			_since_spawn = 0.0
			_next_due = _due_after_spawn()
## Trains put on the level when it loads.
@export_range(0, 50) var initial_trains := 2
## Zero rolls the dice differently every run; anything else makes a level repeat.
@export var random_seed := 0:
	set(value):
		random_seed = value
		if is_node_ready():
			_reseed()
## Where new trains are added. Unset, a sibling called Trains, else this node's parent.
@export var trains_parent: Node

## Spawned, and how those ended, since the level loaded.
var spawned_count := 0
var left_count := 0
var completed_count := 0

var _rng := RandomNumberGenerator.new()
var _since_spawn := 0.0
var _next_due := 0.0
var _serial := 0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_reseed()
	_next_due = _due_after_spawn()
	_spawn_initial.call_deferred()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_since_spawn += delta
	if _since_spawn < _next_due or train_count() >= max_trains:
		return
	if spawn_random(false) != null:
		_since_spawn = 0.0
		_next_due = _due_after_spawn()
	else:
		_since_spawn = _next_due - RETRY_INTERVAL


func _reseed() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()


## Seconds until the next spawn is due, and how long the spawner has waited.
func time_to_next_spawn() -> float:
	return maxf(_next_due - _since_spawn, 0.0)


func routes() -> Array[TrainRoute]:
	var found: Array[TrainRoute] = []
	for child in get_children():
		var route := child as TrainRoute
		if route != null:
			found.append(route)
	return found


## Trains on the level now, spawned by this or authored into it.
func train_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(Train.GROUP):
		if not node.is_queued_for_deletion():
			count += 1
	return count


func _due_after_spawn() -> float:
	return _rng.randf_range(min_spawn_interval, min_spawn_interval * JITTER)


func _spawn_initial() -> void:
	for i in initial_trains:
		if train_count() >= max_trains or spawn_random(true) == null:
			break


#region Choosing
## Puts one train on the level, by the dice: a route, an entry of it, a type of it and a
## free track. [param at_load] lets stations be entries too. Returns the train, or null
## when nothing fits - no route, or no free track at any entry.
func spawn_random(at_load: bool) -> Train:
	for route in _shuffled(routes()):
		if route.stops.is_empty() or route.train_types.is_empty():
			continue
		var type: TrainType = route.train_types[_rng.randi_range(0, route.train_types.size() - 1)]
		if type == null or type.locomotive == null:
			continue
		for entry in _shuffled(route.entries):
			if not at_load and not entry is OutsideConnection:
				continue
			for track in _shuffled(entry.tracks()):
				var train := spawn_at(route, entry, track, type)
				if train != null:
					return train
	return null


## Puts a train of [param type] on [param track] of [param entry], bound for the stops of
## [param route] - if there is room for it. Null when the rail is too short or another
## train is in the way. How the dice-driven spawns end up placing a train, and how a
## test places one without them.
func spawn_at(route: TrainRoute, entry: InterestPoint, track: InterestTrack,
		type: TrainType) -> Train:
	var wagons := type.roll_wagons(_rng)
	var length := consist_length(type, wagons)
	var pose := _pose(route, entry, track, length)
	if pose.is_empty():
		return null
	var rail: Rail = pose["rail"]
	if not is_clear(rail, pose["distance"], pose["facing"], length):
		return null
	return _create(route, entry, type, wagons, rail, pose["distance"], pose["facing"])


## The rail and distance of the middle and the facing for a train of [param length] at
## [param track] of [param entry]: nose on the stop mark at a station, facing whichever
## way leads to the route's stops; nose on the mark, facing in, at a connection. Empty
## when it cannot go there.
func _pose(route: TrainRoute, entry: InterestPoint, track: InterestTrack,
		length: float) -> Dictionary:
	var connection := entry as OutsideConnection
	if connection != null:
		if not track.can_spawn():
			return {}
		var pose := connection.spawn_pose(track, length)
		if not pose.is_empty():
			pose["rail"] = track.rail
		return pose
	var facing := _facing_towards(route, track.rail, track.distance)
	# Back from the nose to the middle, across any points behind the platform.
	var back := TrackWalker.walk(track.rail, track.stop_distance(facing), -facing, length * 0.5)
	if back.is_blocked():
		return {}
	return {"rail": back.rail, "distance": back.distance, "facing": -back.direction}


## The way along [param rail] from [param distance] that reaches the route's stops - the
## first one that only one way reaches, the points as they are set now. Either, at the
## dice, when nothing decides it.
func _facing_towards(route: TrainRoute, rail: Rail, distance: float) -> int:
	for stop in route.stops:
		var ways: Array[int] = []
		for facing: int in [1, -1]:
			var walk := TrackWalker.walk(rail, distance, facing, 3000.0)
			for track in stop.tracks():
				if walk.covers(track.rail, track.distance):
					ways.append(facing)
					break
		if ways.size() == 1:
			return ways[0]
	return 1 if _rng.randf() < 0.5 else -1


## Whether a train of [param length] metres centred at [param distance] on
## [param rail], nose towards [param facing], would be put into an empty sector: no
## train from [constant CLEAR_BEHIND] behind its tail up to the first signal ahead of
## its nose, the points as they are set now.
func is_clear(rail: Rail, distance: float, facing: int, length: float) -> bool:
	var half := length * 0.5
	var mine: Array[TrackWalker.Span] = []
	mine.append_array(sector_ahead(rail, distance, facing, half).spans)
	mine.append_array(TrackWalker.walk(rail, distance, -facing, half + CLEAR_BEHIND).spans)
	for node in get_tree().get_nodes_in_group(Train.GROUP):
		var other := node as Train
		if other == null or other.is_queued_for_deletion() or other.rail == null:
			continue
		for theirs in other.occupied_spans():
			for span in mine:
				if span.overlaps(theirs):
					return false
	return true


## The walk from a new train's middle up to the first signal ahead of its nose (its
## [member TrackWalker.Step.blocking_signal]), or to the first points set against it
## or the end of the line when there is no signal before them.
static func sector_ahead(rail: Rail, distance: float, facing: int,
		half: float) -> TrackWalker.Step:
	return TrackWalker.walk(rail, distance, facing, half + SECTOR_REACH, half, [], true)


## Nose to tail of a train of [param type] with [param wagons], couplings included.
static func consist_length(type: TrainType, wagons: Array[WagonType]) -> float:
	var length := type.locomotive.length
	for wagon in wagons:
		length += Train.COUPLING_GAP + wagon.length
	return length


func _shuffled(items: Array) -> Array:
	var copy := items.duplicate()
	for i in range(copy.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var kept: Variant = copy[i]
		copy[i] = copy[j]
		copy[j] = kept
	return copy
#endregion


func _create(route: TrainRoute, entry: InterestPoint, type: TrainType,
		wagons: Array[WagonType], rail: Rail, distance: float, facing: int) -> Train:
	var train := Train.new()
	_serial += 1
	train.name = "%s %d" % [type.display_name, _serial]
	train.rail = rail
	train.distance = distance
	train.facing = facing
	train.max_speed = type.max_speed
	train.locomotive = type.locomotive
	train.wagons = wagons
	train.load_factor = type.roll_load(_rng)
	train.livery = Livery.random(_rng)
	var stops: Array[InterestPoint] = []
	stops.assign(route.stops)
	train.route = stops
	_parent().add_child(train)
	train.route_finished.connect(_on_route_finished.bind(train))
	var station := entry as Station
	if station != null:
		train.dwell_at(station)
	else:
		train.roll_safely(type.max_speed)
	spawned_count += 1
	train_spawned.emit(train)
	return train


func _on_route_finished(completed: bool, train: Train) -> void:
	left_count += 1
	if completed:
		completed_count += 1
	train_left.emit(train, completed)


func _parent() -> Node:
	if trains_parent != null:
		return trains_parent
	var sibling := get_parent().get_node_or_null("Trains")
	return sibling if sibling != null else get_parent()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var found := routes()
	if found.is_empty():
		warnings.append("No TrainRoute children: nothing can be spawned.")
	# A connection puts a train down with its nose on the mark and the rest outside.
	for route in found:
		var longest := 0.0
		for type in route.train_types:
			if type != null and type.locomotive != null:
				longest = maxf(longest, type.longest_length())
		for entry in route.entries:
			var connection := entry as OutsideConnection
			if connection == null:
				continue
			for track in connection.tracks():
				if not track.can_spawn() or not track.rail.is_inside_tree():
					continue
				var room := OutsideConnection.room_outside(track)
				if room < longest:
					warnings.append("%s/%s has %.0f m of rail outside its mark, and route %s sends trains up to %.0f m long in there." % [
							connection.name, track.name, room, route.name, longest])
	return warnings
