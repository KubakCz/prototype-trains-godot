extends StationsDemoCase
## The spawner and the way off the level: where trains are put, how many and how often,
## which routes they get, and what a connection does with a train that reaches it.

const MINE_ROUTE_STOPS := 2


func _all_routes() -> Array[TrainRoute]:
	return spawner.routes()


## A spawned train's entry point: the gate it stands at, from the way it faces.
func _entry_of(train: Train) -> OutsideConnection:
	return west_gate if train.facing > 0 else east_gate


## Whether the node with this instance id has been freed: a train that left cannot be
## held by a lambda, so it is asked about by its id.
func _gone(id: int) -> bool:
	return not is_instance_id_valid(id)


func _free(train: Train) -> void:
	train.queue_free()
	await physics_frames(2)


func test_the_level_opens_with_its_initial_trains() -> void:
	await reload(func(scene: Node) -> void:
		var node: TrainSpawner = scene.get_node("Spawner")
		node.initial_trains = 4
		node.random_seed = 3
		node.min_spawn_interval = 600.0)
	await physics_frames(5)
	note("%d trains: %s" % [trains().size(), ", ".join(trains().map(func(t: Train) -> String: return str(t.name)))])
	assert_eq(trains().size(), 4, "four trains were put down")
	assert_eq(spawner.spawned_count, 4, "and counted")
	for train in trains():
		assert_false(train.route.is_empty(), "%s has a route" % train.name)


func test_trains_placed_at_load_may_stand_at_stations_and_connections() -> void:
	spawner.random_seed = 5
	var at_station := 0
	var at_gate := 0
	for i in 40:
		var train := spawner.spawn_random(true)
		if train == null:
			continue
		if train.dwelling_at != null:
			at_station += 1
			assert_eq(train.dwelling_at, central, "a train placed at a station is dwelling at it")
			assert_near(train.distance, 250.0, 0.001, "on its mark")
		else:
			at_gate += 1
		await _free(train)
	note("%d at stations, %d at gates" % [at_station, at_gate])
	assert_greater(float(at_station), 0.0, "some of them stood at the station")
	assert_greater(float(at_gate), 0.0, "and some at the gates")


func test_a_train_placed_at_a_station_faces_the_way_to_its_stops() -> void:
	var route: TrainRoute = spawner.get_node("StationLocal")
	for track in central.tracks():
		var train := spawner.spawn_at(route, central, track, local_type)
		if not assert_not_null(train, "a train fits on %s" % track.name):
			continue
		assert_eq(train.facing, 1, "on %s it faces east, towards the east gate" % track.name)
		assert_eq(train.dwelling_at, central, "and stands at the station")
		assert_eq(train.route_index, 0, "which is not one of its stops")
		await _free(train)


func test_while_the_level_runs_only_connections_spawn_trains() -> void:
	spawner.random_seed = 9
	for i in 40:
		var train := spawner.spawn_random(false)
		if assert_not_null(train, "a train is spawned"):
			assert_null(train.dwelling_at, "it is not standing at a station")
			assert_greater(float(train.route.size()), 1.0, "its route is not the station-only one")
			await _free(train)


func test_trains_come_no_closer_together_than_the_minimum_interval() -> void:
	spawner.max_trains = 50
	spawner.min_spawn_interval = 10.0
	var times: Array[int] = []
	spawner.train_spawned.connect(func(_t: Train) -> void: times.append(Engine.get_physics_frames()))
	await physics_frames(6000)
	note("spawned at frames %s" % [times])
	assert_greater(float(times.size()), 2.0, "several trains came")
	for i in range(1, times.size()):
		var gap := float(times[i] - times[i - 1]) / 60.0
		assert_greater(gap, 9.99, "spawn %d came %.1f s after the one before" % [i, gap])
		assert_less(gap, 21.0, "and not much later than the longest wait")


func test_the_level_never_holds_more_than_the_maximum() -> void:
	spawner.max_trains = 2
	spawner.min_spawn_interval = 5.0
	var most := 0
	for i in 80:
		await physics_frames(60)
		most = maxi(most, trains().size())
	note("most trains at once: %d, spawned %d" % [most, spawner.spawned_count])
	assert_less(float(most), 2.01, "never more than two at once")
	assert_greater(float(spawner.spawned_count), 1.0, "but it did put some on")


func test_a_wreck_still_counts_towards_the_maximum() -> void:
	spawner.max_trains = 1
	spawner.min_spawn_interval = 5.0
	await drive_until(func() -> bool: return spawner.spawned_count == 1, 3000)
	var train := trains()[0]
	train.derail("test")
	await physics_frames(3000)
	assert_eq(spawner.spawned_count, 1, "no train came while the wreck stood")
	assert_eq(trains().size(), 1, "only the wreck is on the level")


func test_a_track_with_a_train_on_it_is_not_free() -> void:
	var route := _all_routes()[0]
	var track := west_gate.tracks()[0]
	var first := spawner.spawn_at(route, west_gate, track, route.train_types[0])
	assert_not_null(first, "the first train fits")
	var second := spawner.spawn_at(route, west_gate, track, route.train_types[0])
	assert_null(second, "the second finds the track taken")
	var other := spawner.spawn_at(route, west_gate, west_gate.tracks()[1], route.train_types[0])
	assert_not_null(other, "the next track is free")


func test_trains_never_start_on_a_track_that_only_takes_them_off() -> void:
	spawner.random_seed = 21
	var seen := {}
	for i in 60:
		var train := spawner.spawn_random(false)
		if train == null:
			continue
		seen["%s/%d" % [train.rail.name, train.facing]] = true
		await _free(train)
	note("tracks used: %s" % [seen.keys()])
	assert_false(seen.has("SouthLine/1"), "nothing enters the west gate's out track")
	assert_false(seen.has("NorthLine/-1"), "nor the east gate's north track")
	assert_false(seen.has("MiddleLine/-1"), "nor its middle one")
	assert_true(seen.has("NorthLine/1") and seen.has("MiddleLine/1"),
			"the west gate's in tracks both get trains")
	assert_true(seen.has("SouthLine/-1"), "and so does the east gate's")


func test_a_spawned_trains_route_is_one_of_the_levels_lines_for_its_entry_and_type() -> void:
	spawner.random_seed = 33
	for i in 30:
		var train := spawner.spawn_random(false)
		if train == null:
			continue
		var entry := _entry_of(train)
		var matched := false
		for route in _all_routes():
			var names: Array = route.train_types.map(func(t: TrainType) -> String: return t.display_name)
			var type_name := str(train.name).substr(0, str(train.name).rfind(" "))
			if route.stops == train.route and route.entries.has(entry) and names.has(type_name):
				matched = true
		assert_true(matched, "%s (route %s from %s) matches a line of the list" % [
				train.name, ">".join(train.route.map(func(p: InterestPoint) -> String: return p.label())),
				entry.label()])
		await _free(train)


func test_every_train_gets_an_engine_livery() -> void:
	var train := spawner.spawn_random(false)
	if assert_not_null(train, "a train is spawned"):
		assert_not_null(train.livery, "it is painted")


func test_the_same_seed_gives_the_same_trains() -> void:
	var runs: Array = []
	for round in 2:
		await reload(func(scene: Node) -> void:
			var node: TrainSpawner = scene.get_node("Spawner")
			node.initial_trains = 0
			node.min_spawn_interval = 600.0
			node.random_seed = 77)
		var made: Array[String] = []
		for i in 6:
			var train := spawner.spawn_random(i % 2 == 0)
			if train != null:
				made.append("%s on %s @ %.1f facing %d, %s" % [train.name, train.rail.name,
						train.distance, train.facing, train.livery.label()])
				await _free(train)
		runs.append(made)
	note("first run: %s" % [runs[0]])
	assert_false((runs[0] as Array).is_empty(), "trains were made")
	assert_eq(runs[0], runs[1], "a second run with the seed puts the same trains in the same places")


#region Leaving the level
func test_a_train_that_clears_its_destination_leaves_the_level() -> void:
	var train := make_train(express_type, north_line, 330.0, 1, stops([east_gate]))
	var train_id := train.get_instance_id()
	var results := []
	train.route_finished.connect(func(done: bool) -> void: results.append(done))
	await drive_until(_gone.bind(train_id), 3000)
	assert_true(_gone(train_id), "the train is gone")
	assert_eq(results, [true], "having gone through every stop of its route")


func test_a_train_that_missed_a_station_still_leaves_but_incomplete() -> void:
	var train := make_train(express_type, north_line, 330.0, 1, stops([central, east_gate]))
	var train_id := train.get_instance_id()
	var results := []
	train.route_finished.connect(func(done: bool) -> void: results.append(done))
	await drive_until(_gone.bind(train_id), 3000)
	assert_eq(results, [false], "it left without having been to Central Station")


func test_the_spawner_counts_what_leaves() -> void:
	var route: TrainRoute = spawner.get_node("Express")
	var left := []
	spawner.train_left.connect(func(_t: Train, done: bool) -> void: left.append(done))
	var train := spawner.spawn_at(route, west_gate, west_gate.tracks()[0], express_type)
	if not assert_not_null(train, "an express is spawned"):
		return
	var train_id := train.get_instance_id()
	await drive_until(_gone.bind(train_id), 9000)
	assert_eq(left, [true], "it left having visited the station and gone out by the east gate")
	assert_eq(spawner.left_count, 1, "one train has left")
	assert_eq(spawner.completed_count, 1, "and it completed its route")


func test_a_connection_that_is_not_the_destination_is_just_a_dead_end() -> void:
	# Bound for the east gate, running west into the west gate's south track.
	var train := make_train(local_type, south_line, 60.0, -1, stops([east_gate]), 1)
	await drive(1500)
	assert_true(is_instance_valid(train), "the train was not taken off the level")
	assert_eq(train.facing, 1, "it turned round at the end of the line")
	assert_false(train.completed, "and it has not finished anything")


func test_a_track_that_only_lets_trains_in_does_not_take_one_off() -> void:
	# The west gate's north track is an in track: its own destination, and still no way out.
	var train := make_train(local_type, north_line, 60.0, -1, stops([west_gate]), 1)
	await drive(1500)
	assert_true(is_instance_valid(train), "the train is still on the level")
	assert_eq(train.facing, 1, "it turned round at the end of the line")


func test_a_train_held_at_the_end_of_its_destination_has_left() -> void:
	# A connection with its mark only 3 m from the end of the rail: a train cannot get its
	# tail past the mark, and leaves as soon as it stands at the end.
	var gate := OutsideConnection.new()
	gate.name = "ShortGate"
	var track := InterestTrack.new()
	track.rail = north_line
	track.distance = 497.0
	gate.add_child(track)
	demo.add_child(gate)
	var train := make_train(local_type, north_line, 440.0, 1, stops([gate]), 1)
	var train_id := train.get_instance_id()
	var results := []
	train.route_finished.connect(func(done: bool) -> void: results.append(done))
	await drive_until(_gone.bind(train_id), 3000)
	assert_true(_gone(train_id), "the train is off the level")
	assert_eq(results, [true], "at the end of the line")
#endregion
