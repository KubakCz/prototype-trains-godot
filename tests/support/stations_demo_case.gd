class_name StationsDemoCase
extends TestCase
## Shared fixture for the suites that drive [code]scenes/demos/stations.tscn[/code], built
## by tools/build_stations_demo.gd: a double main line, NorthMain and SouthMain, 5 m
## apart, running west to east with an S-bend at each end and a gate beyond each (West,
## East). Central spans both mains and the CentralLoop north of them; the Mine's two
## dead-end loading tracks (MineBranch, MineSiding) leave the south main to the
## south-west; the Factory's dead-end siding leaves the north main to the north-east;
## the Halt stands on both mains between the factory and the East gate. A scissors
## crossover joins the mains at each end of Central and of the Halt (WestCrossover,
## EastCrossover, HaltWestCrossover, HaltEastCrossover). The loop runs 10 m north of the
## north main.
##
## Signalled the way stations are: an entry signal on both mains outside each end of
## Central and of the Halt (CentralWestEntryNorth ... HaltEastEntrySouth), an exit
## signal 5 m past each end of every station platform (CentralWestExitLoop,
## HaltEastExitNorth, ...; MineExitTrackA, MineExitTrackB and FactoryExitSiding off the
## dead ends), and nothing at the points in between. Every one of its 21 signals starts
## at danger, so a test that drives a train clears the ones it needs - [method clear],
## [method clear_all] - and sets any points it wants with [method throw].
##
## Every test gets a fresh copy of the scene with the spawner switched off, so no train
## is there that the test did not put there. A test that wants the spawner's own
## behaviour switches it back on - see [method silence].
##
## Distances worth knowing, along both mains (x + 746 on the straight): the gates' marks
## 80 m in from the rail's ends (80 and 1652), Central's at 666 with a 120 m platform,
## the Halt's at 1226 with a 90 m one; the entry signals at 326 and 1006 (Central),
## 1056 and 1396 (the Halt). A train stops with its nose on the end of the platform it
## is heading for ([method stop_mark]): on the mains 606 westbound and 726 eastbound at
## Central, 1181 and 1271 at the Halt. The mine's marks are 172 m down MineBranch and
## 95 m down MineSiding, both rails running away from the main into a buffer; the
## factory's is 100 m down FactorySiding, the same - all three with 90 m platforms. Read
## the exact ones off the points with [method mark] and [method stop_mark] rather than
## writing them down.

const DEMO_SCENE := "res://scenes/demos/stations.tscn"

var demo: Node
var spawner: TrainSpawner
var north_main: Rail
var south_main: Rail
var central_loop: Rail
var mine_branch: Rail
var mine_siding: Rail
var factory_siding: Rail
var west_gate: OutsideConnection
var east_gate: OutsideConnection
var central: Station
var mine: Station
var factory: Station
var halt: Station
var express_type: TrainType
var local_type: TrainType
var loaded_type: TrainType
var empty_type: TrainType


func before_each() -> void:
	await reload(silence)


## Starts the scene again, with [param prepare] run on it before it enters the tree:
## for a test that wants the spawner's dice or its settings from the first frame.
func reload(prepare: Callable) -> void:
	if demo != null and is_instance_valid(demo):
		demo.queue_free()
		await physics_frames(2)
	demo = await load_scene(DEMO_SCENE, prepare)
	spawner = demo.get_node("Spawner")
	north_main = demo.get_node("Rails/NorthMain")
	south_main = demo.get_node("Rails/SouthMain")
	central_loop = demo.get_node("Rails/CentralLoop")
	mine_branch = demo.get_node("Rails/MineBranch")
	mine_siding = demo.get_node("Rails/MineSiding")
	factory_siding = demo.get_node("Rails/FactorySiding")
	west_gate = demo.get_node("Interest/WestGate")
	east_gate = demo.get_node("Interest/EastGate")
	central = demo.get_node("Interest/Central")
	mine = demo.get_node("Interest/Mine")
	factory = demo.get_node("Interest/Factory")
	halt = demo.get_node("Interest/Halt")
	express_type = load("res://train_types/express.tres")
	local_type = load("res://train_types/local.tres")
	loaded_type = load("res://train_types/loaded_freight.tres")
	empty_type = load("res://train_types/empty_freight.tres")


## Nothing arrives by itself and nothing is there when the scene loads.
static func silence(scene: Node) -> void:
	var spawner_node: TrainSpawner = scene.get_node("Spawner")
	spawner_node.initial_trains = 0
	spawner_node.min_spawn_interval = 600.0


func trains() -> Array[Train]:
	var found: Array[Train] = []
	for node in tree.get_nodes_in_group(Train.GROUP):
		var train := node as Train
		if train != null and not train.is_queued_for_deletion():
			found.append(train)
	return found


## Every signal of the demo, in scene order.
func signals() -> Array[RailSignal]:
	var found: Array[RailSignal] = []
	for child in demo.get_node("Signals").get_children():
		var rail_signal := child as RailSignal
		if rail_signal != null:
			found.append(rail_signal)
	return found


func signal_named(signal_name: String) -> RailSignal:
	return demo.get_node("Signals/" + signal_name) as RailSignal


## Puts the named signals to clear.
func clear(names: Array[String]) -> void:
	for signal_name in names:
		signal_named(signal_name).aspect = RailSignal.Aspect.CLEAR


func clear_all() -> void:
	for rail_signal in signals():
		rail_signal.aspect = RailSignal.Aspect.CLEAR


## Sets the turnout at [param path] under the demo (Turnouts/LoopWest,
## Compounds/WestCrossover/NorthWest) to [param position].
func throw(path: String, position: Turnout.Position) -> void:
	(demo.get_node(path) as Turnout).turnout_position = position


## The distance of [param point]'s mark on [param rail].
func mark(point: InterestPoint, rail: Rail) -> float:
	for track in point.tracks():
		if track.rail == rail:
			return track.distance
	push_error("%s has no mark on %s" % [point.name, rail.name])
	return NAN


## [param point]'s track on [param rail].
func track_on(point: InterestPoint, rail: Rail) -> InterestTrack:
	for track in point.tracks():
		if track.rail == rail:
			return track
	push_error("%s has no track on %s" % [point.name, rail.name])
	return null


## Where a train travelling [param direction] along [param rail] stops at [param point]
## with its nose: the end of the platform it is heading for.
func stop_mark(point: InterestPoint, rail: Rail, direction: int) -> float:
	return track_on(point, rail).stop_distance(direction)


## Where [param train]'s nose is, as the distance along [param rail] - NAN when the
## nose is on another rail.
static func nose_on(train: Train, rail: Rail) -> float:
	var nose := train.nose()
	return nose.distance if nose.rail == rail else NAN


## A train of [param type] with [param wagons] wagons, [param load] full, standing on
## [param rail] with its middle at [param at], throttle open, bound for [param route].
func make_train(type: TrainType, rail: Rail, at: float, facing: int,
		route: Array[InterestPoint], wagons := 2, load := 0.0) -> Train:
	var train := Train.new()
	train.name = type.display_name
	train.rail = rail
	train.distance = at
	train.facing = facing
	train.max_speed = type.max_speed
	train.locomotive = type.locomotive
	var cars: Array[WagonType] = []
	for i in wagons:
		cars.append(type.wagon)
	train.wagons = cars
	train.load_factor = load
	train.route = route
	demo.get_node("Trains").add_child(train)
	return train


## A train standing with its throttle shut: it stays where it is put.
func park(type: TrainType, rail: Rail, at: float, facing: int, wagons := 1) -> Train:
	var train := make_train(type, rail, at, facing, stops([]), wagons)
	train.throttle = 0
	return train


func drive(count: int) -> void:
	await physics_frames(count)


## Drives until [param done] says so, at most [param limit] frames. Whether it got there.
func drive_until(done: Callable, limit := 3600) -> bool:
	for i in limit:
		if done.call():
			return true
		await physics_frames(1)
	return done.call()


## [param points] as the typed array a route is.
static func stops(points: Array) -> Array[InterestPoint]:
	var typed: Array[InterestPoint] = []
	typed.assign(points)
	return typed
