class_name StationsDemoCase
extends TestCase
## Shared fixture for the suites that drive [code]scenes/demos/stations.tscn[/code]:
## three parallel lines 5 m apart, a crossover from the north line onto the middle one,
## two gates (outside connections) with three tracks each, three stations - one across
## all three lines, a mine on two of them, a factory on two - and the spawner with its
## five routes.
##
## Every test gets a fresh copy of the scene with the spawner switched off, so no train
## is there that the test did not put there. A test that wants the spawner's own
## behaviour switches it back on - see [method silence].
##
## Distances along every line are x + 250: the west gate's marks are at 110 (x = -140),
## the east gate's at 390, Central Station at 250, the mine at 150, the factory at 350.

const DEMO_SCENE := "res://scenes/demos/stations.tscn"

var demo: Node
var spawner: TrainSpawner
var north_line: Rail
var middle_line: Rail
var south_line: Rail
var west_gate: OutsideConnection
var east_gate: OutsideConnection
var central: Station
var coal_mine: Station
var factory: Station
var express_type: TrainType
var local_type: TrainType
var loaded_type: TrainType
var empty_type: TrainType


func before_each() -> void:
	await reload(silence)


## Starts the scene again, with [param prepare] run on it before it enters the tree:
## for a test that wants the spawner's dice or its settings from the first frame.
func reload(prepare: Callable) -> void:
	if demo != null:
		demo.queue_free()
		await physics_frames(2)
	demo = await load_scene(DEMO_SCENE, prepare)
	spawner = demo.get_node("Spawner")
	north_line = demo.get_node("Rails/NorthLine")
	middle_line = demo.get_node("Rails/MiddleLine")
	south_line = demo.get_node("Rails/SouthLine")
	west_gate = demo.get_node("Interest/WestGate")
	east_gate = demo.get_node("Interest/EastGate")
	central = demo.get_node("Interest/CentralStation")
	coal_mine = demo.get_node("Interest/CoalMine")
	factory = demo.get_node("Interest/Factory")
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
