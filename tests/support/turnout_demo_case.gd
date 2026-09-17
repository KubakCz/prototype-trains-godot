class_name TurnoutDemoCase
extends TestCase
## Fixture for the [code]scenes/demos/turnouts.tscn[/code] layout: a main line
## with a passing loop (LoopWest / LoopEast) and a dead-end stub (StubPoints), on
## flat ground, so every turnout case is reachable in one scene.
##
## A fresh copy of the scene is built for every test and thrown away afterwards, so
## a suite of driving scenarios cannot leak a train from one test into the next.
## Every train starts stopped; [method place_shuttle] is what sets one moving.
##
## Lives under [code]tests/support[/code] rather than next to the suites because
## the runner only collects [code]*_test.gd[/code].

const DEMO_SCENE := "res://scenes/demos/turnouts.tscn"

var demo: Node
var main_line: Rail
var loop_line: Rail
var stub_line: Rail
## The points at the west end of the passing loop: left-hand, diverging towards
## the end of the main rail.
var west: Turnout
## The points into the dead-end siding: right-hand.
var stub: Turnout
## The points at the east end of the passing loop: right-hand, diverging towards
## the start of the main rail, so its toe faces the other way from the other two.
var east: Turnout
## The train the driving tests drive. 16 m long, 16 m/s.
var shuttle: Train


func before_each() -> void:
	demo = await load_scene(DEMO_SCENE)
	main_line = demo.get_node("Rails/MainLine")
	loop_line = demo.get_node("Rails/LoopLine")
	stub_line = demo.get_node("Rails/StubLine")
	west = demo.get_node("Turnouts/LoopWest")
	stub = demo.get_node("Turnouts/StubPoints")
	east = demo.get_node("Turnouts/LoopEast")
	shuttle = demo.get_node("Trains/Shuttle")
	for train: Train in demo.get_node("Trains").get_children():
		train.throttle = 0


## The three turnouts, west to east.
func turnouts() -> Array[Turnout]:
	return [west, stub, east]


func set_points(at_west: Turnout.Position, at_stub: Turnout.Position,
		at_east: Turnout.Position) -> void:
	west.turnout_position = at_west
	stub.turnout_position = at_stub
	east.turnout_position = at_east


## Puts the shuttle on a rail with its throttle open.
func place_shuttle(rail: Rail, at: float, facing: int) -> void:
	shuttle.rail = rail
	shuttle.distance = at
	shuttle.facing = facing
	shuttle.throttle = 1


## Runs the simulation for [param count] physics frames - 16 m/s and 60 frames per
## second of game time, so 60 frames is 16 m of track.
func drive(count: int) -> void:
	await physics_frames(count)


## The one-line readout the debug panel shows, for [method TestCase.note].
func shuttle_state() -> String:
	var blocked := shuttle.blocked_description()
	return "on %-9s @ %6.1f / %6.1f m  nose %-12s throttle %+d  %s" % [
		shuttle.rail.name, shuttle.distance, shuttle.rail.rail_length(),
		"along rail" if shuttle.facing == Train.ALONG_RAIL else "against rail",
		shuttle.throttle, blocked if not blocked.is_empty() else "clear"]


## Where the shuttle's nose is. It sits on a different rail from the tail while the
## train straddles the points, which is the whole reason body placement goes through
## [TrackWalker] rather than adding to [member Train.distance].
func shuttle_nose() -> TrackWalker.Step:
	return TrackWalker.walk(shuttle.rail, shuttle.distance, shuttle.facing,
			shuttle.body_length * 0.5)


## Where the shuttle's tail is.
func shuttle_tail() -> TrackWalker.Step:
	return TrackWalker.walk(shuttle.rail, shuttle.distance, -shuttle.facing,
			shuttle.body_length * 0.5)
