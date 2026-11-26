extends StationsDemoCase
## The spawner and the way off the level: where trains are put, how many and how often,
## which routes they get, the sector a new train needs empty, and what a connection
## does with a train that reaches it.
##
## A train is put down at a gate with its nose on the mark, facing in, the whole of it
## outside - between the mark and the end of the rail; at a station with its nose on
## the stop mark for the way it faces. Every signal in the demo starts at danger, so a
## spawned train runs in and stops at its gate's entry signal - Central's west entry
## signals (326 m, 246 m in from the mark) on the west gate's tracks, the Halt's east
## entry signals (1396 m, 256 m in) on the east gate's.

const WEST_NORTH_ENTRY := "CentralWestEntryNorth"


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
			var nose := train.nose()
			assert_near(nose.distance, central.mark_on(nose.rail).stop_distance(train.facing), 0.01,
					"with its nose on the stop mark for the way it faces")
		else:
			at_gate += 1
		await _free(train)
	note("%d at stations, %d at gates" % [at_station, at_gate])
	assert_greater(float(at_station), 0.0, "some of them stood at the station")
	assert_greater(float(at_gate), 0.0, "and some at the gates")


func test_a_train_placed_at_a_station_faces_the_way_to_its_stops() -> void:
	# The loop only leads east with its east points set for it, and those points set
	# for the loop close the north main - so the loop goes last.
	var route: TrainRoute = spawner.get_node("StationLocal")
	for track: InterestTrack in [central.tracks()[1], central.tracks()[2], central.tracks()[0]]:
		if track.rail == central_loop:
			throw("Turnouts/LoopEast", Turnout.Position.REVERSE)
		var train := spawner.spawn_at(route, central, track, local_type)
		if not assert_not_null(train, "a train fits on %s" % track.name):
			continue
		assert_eq(train.facing, 1, "on %s it faces east, towards the Halt" % track.name)
		assert_eq(train.nose().rail, track.rail, "its nose is on %s's rail" % track.name)
		assert_near(train.nose().distance, track.stop_distance(1), 0.01,
				"on the eastbound stop mark of %s" % track.name)
		assert_eq(train.dwelling_at, central, "and stands at the station")
		assert_eq(train.route_index, 0, "which is not one of its stops")
		await _free(train)


func test_while_the_level_runs_only_connections_spawn_trains() -> void:
	spawner.random_seed = 9
	for i in 40:
		var train := spawner.spawn_random(false)
		if assert_not_null(train, "a train is spawned"):
			assert_null(train.dwelling_at, "it is not standing at a station")
			var gate := _entry_of(train)
			assert_near(train.nose().distance, mark(gate, train.rail), 0.01,
					"%s stands with its nose on the %s gate's mark" % [train.name, gate.label()])
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
	# The demo's gate tracks all work both ways; make the west gate's north one an out track.
	west_gate.tracks()[0].role = InterestTrack.Role.OUT
	spawner.random_seed = 21
	var seen := {}
	for i in 60:
		var train := spawner.spawn_random(false)
		if train == null:
			continue
		seen["%s/%d" % [train.rail.name, train.facing]] = true
		await _free(train)
	note("tracks used: %s" % [seen.keys()])
	assert_false(seen.has("NorthMain/1"), "nothing enters by the west gate's out track")
	assert_true(seen.has("SouthMain/1"), "the west gate's other track gets trains")
	assert_true(seen.has("NorthMain/-1") and seen.has("SouthMain/-1"),
			"and so do both of the east gate's")


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


#region Where a new train is put
func test_a_train_at_a_gate_stands_outside_with_its_nose_on_the_mark() -> void:
	for gate: OutsideConnection in [west_gate, east_gate]:
		var route: TrainRoute = spawner.get_node("Express" if gate == west_gate else "ExpressWest")
		for track in gate.tracks():
			var train := spawner.spawn_at(route, gate, track, express_type)
			if not assert_not_null(train, "a train is put on %s/%s" % [gate.label(), track.name]):
				continue
			var inward := -OutsideConnection.outward(track)
			var tail := train.distance - float(train.facing) * train.half_length()
			note("%s/%s: mark %.2f, nose %.2f, tail %.2f, rail %.1f m" % [gate.label(), track.name,
					track.distance, train.nose().distance, tail, track.rail.rail_length()])
			assert_eq(train.facing, inward, "on %s/%s it faces in" % [gate.label(), track.name])
			assert_near(train.nose().distance, track.distance, 0.01,
					"with its nose on %s/%s's mark" % [gate.label(), track.name])
			assert_between(tail, 0.0, track.rail.rail_length(), "and its tail still on the rail")
			assert_less(float(inward) * (tail - track.distance), 0.0, "outside the mark")
			await _free(train)


func test_a_train_too_long_for_the_rail_outside_the_mark_is_refused() -> void:
	# A gate whose mark is 30 m from the start of the north main: too little for any train.
	var gate := OutsideConnection.new()
	gate.name = "TightGate"
	var track := InterestTrack.new()
	track.name = "Tight"
	track.rail = north_main
	track.distance = 30.0
	gate.add_child(track)
	demo.get_node("Interest").add_child(gate)
	var route: TrainRoute = spawner.get_node("Express")
	assert_true(spawner.spawn_at(route, gate, track, express_type) == null,
			"an express does not fit in the 30 m outside the mark, and is not put down")
	assert_true(gate.spawn_pose(track, 31.0).is_empty(), "there is no pose for a train of 31 m")
	assert_false(gate.spawn_pose(track, 29.0).is_empty(), "but there is for one of 29 m")
	gate.queue_free()


func test_the_spawner_warns_of_a_gate_too_short_for_a_routes_trains() -> void:
	assert_true(spawner._get_configuration_warnings().is_empty(), "the demo's spawner has no warnings")
	var gate := OutsideConnection.new()
	gate.name = "TightGate"
	var track := InterestTrack.new()
	track.name = "Tight"
	track.rail = north_main
	track.distance = 30.0
	gate.add_child(track)
	demo.get_node("Interest").add_child(gate)
	var route := TrainRoute.new()
	route.name = "Squeezed"
	route.train_types = [express_type]
	route.entries = [gate]
	route.stops = [central, east_gate]
	spawner.add_child(route)
	var warnings := spawner._get_configuration_warnings()
	note(", ".join(warnings))
	assert_eq(warnings.size(), 1, "one warning: the one track of the one route")
	assert_true(warnings.size() == 1 and warnings[0].contains("Tight") and warnings[0].contains("Squeezed"),
			"naming the track and the route")
	track.role = InterestTrack.Role.OUT
	assert_true(spawner._get_configuration_warnings().is_empty(),
			"a track that takes no trains in needs no room for them")
	route.queue_free()
	gate.queue_free()
#endregion


#region The sector a new train needs
## A new train of 40 m on the west gate's north track, eastbound with its middle at
## 100 m: tail at 80, nose at 120, the entry signal at 326 m ends its sector.
const PROBE_AT := 100.0
const PROBE_LENGTH := 40.0


func _probe_clear() -> bool:
	return spawner.is_clear(north_main, PROBE_AT, 1, PROBE_LENGTH)


func test_the_sector_runs_from_the_new_trains_middle_to_the_first_signal_ahead() -> void:
	var step := TrainSpawner.sector_ahead(north_main, PROBE_AT, 1, PROBE_LENGTH * 0.5)
	var entry := signal_named(WEST_NORTH_ENTRY)
	assert_eq(step.blocking_signal, entry, "the sector ends at the gate's entry signal")
	assert_near(step.distance, entry.signal_distance(), 0.01, "on the signal itself")
	entry.aspect = RailSignal.Aspect.CLEAR
	step = TrainSpawner.sector_ahead(north_main, PROBE_AT, 1, PROBE_LENGTH * 0.5)
	assert_eq(step.blocking_signal, entry, "it ends there at clear as well")


func test_a_train_far_ahead_but_short_of_the_entry_signal_blocks_a_spawn() -> void:
	assert_true(_probe_clear(), "with nothing on the line the sector is clear")
	# 80 m beyond the new train's nose - well past the 60 m the old rule looked ahead.
	var standing := park(local_type, north_main, 200.0, 1)
	await physics_frames(2)
	assert_false(_probe_clear(), "a train standing 80 m ahead, short of the entry signal, blocks it")
	var route: TrainRoute = spawner.get_node("Express")
	assert_null(spawner.spawn_at(route, west_gate, west_gate.tracks()[0], express_type),
			"and the spawner puts no train on that track")
	assert_true(spawner.is_clear(south_main, PROBE_AT, 1, PROBE_LENGTH),
			"the other main, beside it, is clear")
	standing.queue_free()


func test_a_train_past_the_entry_signal_does_not_block_a_spawn() -> void:
	var entry := signal_named(WEST_NORTH_ENTRY)
	var standing := park(local_type, north_main, entry.signal_distance() + 30.0, 1)
	await physics_frames(2)
	note("train %.1f m long, its tail at %.1f m, the signal at %.1f m" % [standing.train_length(),
			standing.distance - standing.half_length(), entry.signal_distance()])
	assert_true(_probe_clear(), "a train wholly past the entry signal leaves the sector clear")
	entry.aspect = RailSignal.Aspect.CLEAR
	await physics_frames(2)
	assert_true(_probe_clear(), "and it still does with the signal at clear")


func test_a_train_straddling_the_entry_signal_blocks_a_spawn() -> void:
	var entry := signal_named(WEST_NORTH_ENTRY)
	park(local_type, north_main, entry.signal_distance() + 5.0, 1)
	await physics_frames(2)
	assert_false(_probe_clear(), "a train with its tail short of the signal is in the sector")


func test_room_behind_the_new_trains_tail_must_be_clear_too() -> void:
	# Westbound train, so "behind" is east of it: middle at 100, tail at 120 facing west.
	var behind_tail := PROBE_AT + PROBE_LENGTH * 0.5
	var standing := park(local_type, north_main, 300.0, 1)
	standing.distance = behind_tail + TrainSpawner.CLEAR_BEHIND - 5.0 + standing.half_length()
	await physics_frames(2)
	assert_false(spawner.is_clear(north_main, PROBE_AT, -1, PROBE_LENGTH),
			"a train within %.0f m behind the tail blocks it" % TrainSpawner.CLEAR_BEHIND)
	standing.distance = behind_tail + TrainSpawner.CLEAR_BEHIND + 5.0 + standing.half_length()
	await physics_frames(2)
	assert_true(spawner.is_clear(north_main, PROBE_AT, -1, PROBE_LENGTH),
			"one further back than that does not")


func test_a_spawn_is_allowed_again_once_the_train_ahead_has_gone_past_the_signal() -> void:
	var route: TrainRoute = spawner.get_node("Express")
	var track := west_gate.tracks()[0]
	var first := spawner.spawn_at(route, west_gate, track, express_type)
	if not assert_not_null(first, "the first train fits"):
		return
	await drive(1800)
	note("%s @ %.1f m: %s" % [first.name, first.distance, first.blocked_description()])
	assert_null(spawner.spawn_at(route, west_gate, track, express_type),
			"no second train while the first waits at the entry signal")
	# Let it in, on towards Central.
	clear([WEST_NORTH_ENTRY])
	var entry := signal_named(WEST_NORTH_ENTRY)
	var past := await drive_until(func() -> bool:
		return first.distance - first.half_length() > entry.signal_distance() + 1.0, 3000)
	assert_true(past, "the first train has gone past the entry signal")
	var second := spawner.spawn_at(route, west_gate, track, express_type)
	assert_not_null(second, "then a second one is put on the track")


func test_a_train_spawned_at_a_red_entry_signal_rolls_in_and_stops_at_it() -> void:
	var entry := signal_named(WEST_NORTH_ENTRY)
	var route: TrainRoute = spawner.get_node("Express")
	var train := spawner.spawn_at(route, west_gate, west_gate.tracks()[0], express_type)
	if not assert_not_null(train, "a train is spawned at the west gate"):
		return
	assert_greater(train.current_speed, 0.0, "it comes in rolling")
	await drive(2400)
	note("%s @ %.1f m: %s" % [train.name, train.distance, train.blocked_description()])
	assert_eq(train.blocking_signal, entry, "it is held at the entry signal")
	assert_eq(train.current_speed, 0.0, "standing")
	assert_false(train.tripped, "having stopped for it rather than running past")
	assert_between(entry.signal_distance() - train.nose().distance, 0.0, Train.STOP_SHORT + 0.1,
			"its nose just short of the signal")


func test_every_gate_track_has_its_entry_signal_and_every_spawn_stops_at_it() -> void:
	for gate: OutsideConnection in [west_gate, east_gate]:
		for track in gate.tracks():
			var entry := track.guarding_signal(-OutsideConnection.outward(track))
			if not assert_not_null(entry, "%s/%s has an entry signal" % [gate.label(), track.name]):
				continue
			var route: TrainRoute = spawner.get_node("Express" if gate == west_gate else "ExpressWest")
			var train := spawner.spawn_at(route, gate, track, express_type)
			if not assert_not_null(train, "a train is spawned on %s/%s" % [gate.label(), track.name]):
				continue
			await drive(2400)
			assert_eq(train.blocking_signal, entry, "the train from %s/%s is held at %s" % [
					gate.label(), track.name, entry.name])
			await _free(train)
#endregion


#region Leaving the level
func test_a_train_that_clears_its_destination_leaves_the_level() -> void:
	var train := make_train(express_type, north_main, 1400.0, 1, stops([east_gate]))
	var train_id := train.get_instance_id()
	var results := []
	var tails := []
	train.route_finished.connect(func(done: bool) -> void:
		results.append(done)
		tails.append(train.distance - train.half_length()))
	var leaving_mark := mark(east_gate, north_main)
	await drive_until(_gone.bind(train_id), 3000)
	assert_true(_gone(train_id), "the train is gone")
	assert_eq(results, [true], "having gone through every stop of its route")
	if assert_eq(tails.size(), 1, "it was taken off once"):
		note("taken off with its tail at %.2f, the mark at %.2f" % [tails[0], leaving_mark])
		assert_between(tails[0], leaving_mark, leaving_mark + 1.0,
				"as soon as its tail had cleared the mark")


func test_a_train_that_missed_a_station_still_leaves_but_incomplete() -> void:
	var train := make_train(express_type, north_main, 1400.0, 1, stops([central, east_gate]))
	var train_id := train.get_instance_id()
	var results := []
	train.route_finished.connect(func(done: bool) -> void: results.append(done))
	await drive_until(_gone.bind(train_id), 3000)
	assert_eq(results, [false], "it left without having been to Central")


func test_the_spawner_counts_what_leaves() -> void:
	clear_all()
	var route: TrainRoute = spawner.get_node("Express")
	var left := []
	spawner.train_left.connect(func(_t: Train, done: bool) -> void: left.append(done))
	var train := spawner.spawn_at(route, west_gate, west_gate.tracks()[0], express_type)
	if not assert_not_null(train, "an express is spawned"):
		return
	var train_id := train.get_instance_id()
	await drive_until(_gone.bind(train_id), 12000)
	assert_eq(left, [true], "it left having visited the station and gone out by the east gate")
	assert_eq(spawner.left_count, 1, "one train has left")
	assert_eq(spawner.completed_count, 1, "and it completed its route")


func test_a_connection_that_is_not_the_destination_is_just_a_dead_end() -> void:
	# Bound for the east gate, running west into the west gate's south track.
	var train := make_train(local_type, south_main, 150.0, -1, stops([east_gate]), 1)
	await drive(1500)
	assert_true(is_instance_valid(train), "the train was not taken off the level")
	assert_eq(train.facing, 1, "it turned round at the end of the line")
	assert_false(train.completed, "and it has not finished anything")


func test_a_track_that_only_lets_trains_in_does_not_take_one_off() -> void:
	# The west gate's north track made an in track: its own destination, and still no way out.
	west_gate.tracks()[0].role = InterestTrack.Role.IN
	var train := make_train(local_type, north_main, 150.0, -1, stops([west_gate]), 1)
	await drive(1500)
	assert_true(is_instance_valid(train), "the train is still on the level")
	assert_eq(train.facing, 1, "it turned round at the end of the line")


func test_a_train_held_at_the_end_of_its_destination_has_left() -> void:
	# A connection with its mark only 3 m from the end of the rail: a train cannot get its
	# tail past the mark, and leaves as soon as it stands at the end.
	var gate := OutsideConnection.new()
	gate.name = "ShortGate"
	var track := InterestTrack.new()
	track.rail = north_main
	track.distance = north_main.rail_length() - 3.0
	gate.add_child(track)
	demo.add_child(gate)
	var train := make_train(local_type, north_main, north_main.rail_length() - 60.0, 1,
			stops([gate]), 1)
	var train_id := train.get_instance_id()
	var results := []
	train.route_finished.connect(func(done: bool) -> void: results.append(done))
	await drive_until(_gone.bind(train_id), 3000)
	assert_true(_gone(train_id), "the train is off the level")
	assert_eq(results, [true], "at the end of the line")
#endregion
