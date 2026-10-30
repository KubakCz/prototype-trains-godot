class_name TrainDemoCase
extends TestCase
## Shared fixture for the suites that drive [code]scenes/demos/trains.tscn[/code]:
## three parallel lines 5 m apart, a crossover from the north line onto the middle
## one, a red signal at the far end of each line and a clear one part way along the
## north line to put back in front of a train.
##
## Every test gets a fresh copy of the scene with every train stopped and parked
## where it starts, so a test sets up exactly the trains it is about.

const DEMO_SCENE := "res://scenes/demos/trains.tscn"

var demo: Node
var north_line: Rail
var middle_line: Rail
var south_line: Rail
var link: Rail
var crossover: CompoundTurnout
var north_points: Turnout
var middle_points: Turnout

## Clear to begin with: the one to put back to danger in front of a train.
var north_overrun: RailSignal
var north_stop: RailSignal
var middle_stop: RailSignal
var south_stop: RailSignal

## Passenger locomotive and two coaches, 48 m, 160 t, 18 m/s.
var express: Train
## Freight locomotive and four wagons, full: 70 m, 438 t, 12 m/s.
var loaded_freight: Train
## The same consist empty: 70 m, 198 t.
var empty_freight: Train
## A shunter standing on the south line beyond its stop signal, facing west.
var stalled: Train


func before_each() -> void:
	demo = await load_scene(DEMO_SCENE)
	north_line = demo.get_node("Rails/NorthLine")
	middle_line = demo.get_node("Rails/MiddleLine")
	south_line = demo.get_node("Rails/SouthLine")
	link = demo.get_node("Rails/CrossoverLink")
	crossover = demo.get_node("Compounds/Crossover")
	north_points = crossover.get_node("NorthPoints")
	middle_points = crossover.get_node("MiddlePoints")
	north_overrun = demo.get_node("Signals/NorthOverrun")
	north_stop = demo.get_node("Signals/NorthStop")
	middle_stop = demo.get_node("Signals/MiddleStop")
	south_stop = demo.get_node("Signals/SouthStop")
	express = demo.get_node("Trains/Express")
	loaded_freight = demo.get_node("Trains/LoadedFreight")
	empty_freight = demo.get_node("Trains/EmptyFreight")
	stalled = demo.get_node("Trains/Stalled")
	for train in trains():
		train.throttle = 0
		train.current_speed = 0.0


func trains() -> Array[Train]:
	return [express, loaded_freight, empty_freight, stalled]


## Puts a train on a rail facing east with its throttle open, running at
## [param speed] - a rolling start, or a standing one at 0.
func place(train: Train, rail: Rail, at: float, speed := 0.0) -> void:
	train.rail = rail
	train.distance = at
	train.facing = Train.ALONG_RAIL
	train.throttle = 1
	train.current_speed = 0.0
	train.roll(speed)


## Places [param train] so its nose stands [param short] metres short of
## [param at] on [param rail], facing east.
func place_nose(train: Train, rail: Rail, at: float, short: float, speed := 0.0) -> void:
	place(train, rail, at - short - train.half_length(), speed)


## How far the nose is short of [param at] on its rail: negative once past it.
func nose_short_of(train: Train, at: float) -> float:
	return at - train.nose().distance


func drive(count: int) -> void:
	await physics_frames(count)


## Drives until [param done] says so, at most [param limit] frames. Whether it
## got there.
func drive_until(done: Callable, limit := 3600) -> bool:
	for _frame in limit:
		if bool(done.call()):
			return true
		await physics_frames(1)
	return bool(done.call())


func state(train: Train) -> String:
	var blocked := train.blocked_description()
	return "%-13s %-8s %5.2f m/s  brake %4.2f  nose %s @ %6.2f  %s" % [train.name,
			train.state_name(), train.current_speed, train.braking, train.nose().rail.name,
			train.nose().distance, blocked if not blocked.is_empty() else "clear"]
