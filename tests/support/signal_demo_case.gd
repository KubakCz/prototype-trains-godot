class_name SignalDemoCase
extends TestCase
## Fixture for the [code]scenes/demos/signals.tscn[/code] layout: a straight
## 280 m main line with a dead-end siding off it, seven signals, and three
## trains, on flat ground.
##
## The signals are placed to cover every case step 3 has to answer in one scene:
##
## - [b]Home[/b] / [b]HomeBack[/b] at 60 m and 56 m - a back-to-back pair, one for
##   each direction of travel, close enough that their widgets must be shifted
##   apart from each other.
## - [b]YardA[/b] / [b]YardB[/b] / [b]YardC[/b] at 120, 124 and 128 m - three in a
##   row, alternating direction: the crowding case.
## - [b]Section[/b] at 240 m, past the turnout, and far enough from the camera's
##   starting position to be collapsed by distance.
## - [b]SidingExit[/b] on the branch, governing trains coming out of the siding.
##
## A fresh copy of the scene is built for every test. Every train starts stopped;
## [method place] is what sets one moving.
##
## Lives under [code]tests/support[/code] rather than next to the suites because
## the runner only collects [code]*_test.gd[/code].

const DEMO_SCENE := "res://scenes/demos/signals.tscn"

var demo: Node
var main_line: Rail
var siding_line: Rail
## The points into the dead-end siding, at 190 m. Left-hand.
var points: Turnout

## Governs trains running towards the end of the main line, at 60 m.
var home: RailSignal
## Its opposite number, governing trains running the other way, at 56 m.
var home_back: RailSignal
var yard_a: RailSignal
var yard_b: RailSignal
var yard_c: RailSignal
## Past the turnout at 240 m, so a train has to cross points to reach it.
var section: RailSignal
## On the branch, governing trains coming out of the siding.
var siding_exit: RailSignal

## 16 m long, 16 m/s. The train the driving tests drive.
var local: Train
## 20 m long, 12 m/s, facing the other way down the main line.
var goods: Train
## 11 m long, in the siding.
var shunter: Train


func before_each() -> void:
	demo = await load_scene(DEMO_SCENE)
	main_line = demo.get_node("Rails/MainLine")
	siding_line = demo.get_node("Rails/SidingLine")
	points = demo.get_node("Turnouts/SidingPoints")
	home = demo.get_node("Signals/Home")
	home_back = demo.get_node("Signals/HomeBack")
	yard_a = demo.get_node("Signals/YardA")
	yard_b = demo.get_node("Signals/YardB")
	yard_c = demo.get_node("Signals/YardC")
	section = demo.get_node("Signals/Section")
	siding_exit = demo.get_node("Signals/SidingExit")
	local = demo.get_node("Trains/Local")
	goods = demo.get_node("Trains/Goods")
	shunter = demo.get_node("Trains/Shunter")
	for train: Train in demo.get_node("Trains").get_children():
		train.throttle = 0


## Every signal in the demo, in the order they stand along the track.
func rail_signals() -> Array[RailSignal]:
	return [home_back, home, yard_a, yard_b, yard_c, section, siding_exit]


func set_all(aspect: RailSignal.Aspect) -> void:
	for rail_signal: RailSignal in rail_signals():
		rail_signal.aspect = aspect


## Puts a train on a rail with its throttle open.
func place(train: Train, rail: Rail, at: float, facing: int) -> void:
	train.rail = rail
	train.distance = at
	train.facing = facing
	train.throttle = 1


## Runs the simulation for [param count] physics frames. The Local runs at
## 16 m/s and there are 60 frames to a second of game time, so 60 frames is 16 m.
func drive(count: int) -> void:
	await physics_frames(count)


## The one-line readout the debug panel shows, for [method TestCase.note].
func state(train: Train) -> String:
	var blocked := train.blocked_description()
	return "%-8s on %-10s @ %6.1f / %6.1f m  nose %-12s throttle %+d  %s" % [
		train.name, train.rail.name, train.distance, train.rail.rail_length(),
		"along rail" if train.facing == Train.ALONG_RAIL else "against rail",
		train.throttle, blocked if not blocked.is_empty() else "clear"]


## Where a train's nose is. Signals are deliberately not obeyed by this walk -
## it is measuring the train, not asking permission.
func nose_of(train: Train) -> TrackWalker.Step:
	return TrackWalker.walk(train.rail, train.distance, train.facing,
			train.body_length * 0.5)
