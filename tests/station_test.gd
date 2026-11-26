extends StationsDemoCase
## A train whose next stop is a station brakes to stand with its nose on the end of the
## platform it is heading for - the stop mark for its way of travel - dwells, does what
## the station does to its freight, and goes on; a train whose next stop is anything
## else does not stop there at all.
##
## Every signal in the demo starts at danger, so each test clears what lies on its
## train's way. Central's north track has a 120 m platform on its mark at 666 m: an
## eastbound train stops with its nose at 726, a westbound one at 606, and the exit
## signals stand 5 m beyond (CentralEastExitNorth at 731, CentralWestExitNorth at 601).
## Eastbound on the north main from 595 m there is nothing between the train and the
## platform.

const EAST_EXIT := "CentralEastExitNorth"


func test_the_next_station_is_stopped_at_with_the_nose_on_the_stop_mark() -> void:
	var at := stop_mark(central, north_main, 1)
	var train := make_train(express_type, north_main, 595.0, 1, stops([central, east_gate]))
	var reached := []
	train.reached.connect(func(point: InterestPoint) -> void: reached.append(point))
	var stopped := await drive_until(func() -> bool: return train.dwelling_at != null)
	assert_true(stopped, "the train comes to rest at the station")
	note("%s: nose at %.3f m, stop mark at %.3f, %s" % [train.name, nose_on(train, north_main), at,
			train.state_name()])
	assert_near(nose_on(train, north_main), at, 0.02, "its nose is on the eastbound stop mark")
	assert_eq(train.current_speed, 0.0, "it is standing")
	assert_eq(train.state, Train.State.DWELLING, "the marker says it is dwelling")
	assert_eq(train.dwelling_at, central, "at Central")
	assert_eq(reached, [central], "reaching it was reported once")
	assert_eq(train.route_index, 1, "and the next stop is the gate")


func test_the_stop_marks_are_the_ends_of_the_platform() -> void:
	var track := track_on(central, north_main)
	assert_eq(track.platform_length, 120.0, "Central's platforms are 120 m long")
	assert_near(track.stop_distance(1), track.distance + 60.0, 0.001, "eastbound the stop is its east end")
	assert_near(track.stop_distance(-1), track.distance - 60.0, 0.001, "westbound its west end")
	var siding := track_on(factory, factory_siding)
	siding.platform_length = 300.0
	assert_near(siding.stop_distance(-1), 0.0, 0.001, "a platform longer than the rail stops at its start")
	assert_near(siding.stop_distance(1), factory_siding.rail_length(), 0.001, "and at its end")


func test_a_station_stops_the_train_whatever_the_signals_beyond_it_say() -> void:
	# The exit signal beyond the platform is at clear: nothing but the station stops it.
	clear([EAST_EXIT])
	var train := make_train(express_type, north_main, 595.0, 1, stops([central, east_gate]))
	await drive_until(func() -> bool: return train.dwelling_at != null)
	assert_null(train.blocking_signal, "it is not held by a signal")
	assert_eq(train.dwelling_at, central, "it is dwelling at the station")
	assert_near(nose_on(train, north_main), stop_mark(central, north_main, 1), 0.02,
			"with its nose on the stop mark")


func test_the_train_dwells_for_the_stations_time_and_then_goes_on() -> void:
	clear([EAST_EXIT])
	var at := stop_mark(central, north_main, 1)
	var train := make_train(express_type, north_main, 595.0, 1, stops([central, east_gate]))
	await drive_until(func() -> bool: return train.dwelling_at != null)
	var frames_dwelt := 0
	while train.dwelling_at != null and frames_dwelt < 2000:
		await physics_frames(1)
		frames_dwelt += 1
	note("dwelt %d frames, %.1f s" % [frames_dwelt, float(frames_dwelt) / 60.0])
	assert_between(float(frames_dwelt) / 60.0, central.dwell_time - 0.1, central.dwell_time + 0.1,
			"it stood for the station's dwell time")
	await drive(120)
	assert_greater(train.current_speed, 1.0, "then it is away again")
	assert_greater(nose_on(train, north_main), at + 2.0, "its nose past the stop mark")
	assert_eq(train.state, Train.State.DRIVING, "driving")
	var stopped_again := await drive_until(func() -> bool: return train.dwelling_at != null, 600)
	assert_false(stopped_again, "it does not stop at the same station twice")


func test_after_its_stop_the_train_waits_at_the_red_exit_signal() -> void:
	var exit_signal := signal_named(EAST_EXIT)
	var train := make_train(express_type, north_main, 595.0, 1, stops([central, east_gate]))
	await drive_until(func() -> bool: return train.dwelling_at != null)
	await drive_until(func() -> bool: return train.dwelling_at == null, 2000)
	await drive(900)
	note("%s @ %.1f m: %s" % [train.name, train.distance, train.blocked_description()])
	assert_eq(train.blocking_signal, exit_signal, "the train is held at Central's exit signal")
	assert_eq(train.current_speed, 0.0, "standing")
	assert_between(exit_signal.signal_distance() - nose_on(train, north_main), 0.0,
			Train.STOP_SHORT + 0.1, "with its nose just short of the signal")


func test_a_station_that_is_not_the_next_stop_is_driven_through() -> void:
	clear_all()
	var at := mark(central, north_main)
	var train := make_train(express_type, north_main, 375.0, 1, stops([east_gate]))
	var fastest := 0.0
	for i in 1500:
		await physics_frames(1)
		if train.distance > at - 70.0 and train.distance < at + 70.0:
			fastest = maxf(fastest, train.current_speed)
			assert_null(train.dwelling_at, "no stop at Central")
	assert_greater(fastest, 17.0, "it went through at line speed, %.1f m/s" % fastest)


func test_a_red_signal_before_the_station_still_holds_the_train() -> void:
	# Central's west entry signal stands outside its points, 280 m short of the platform.
	var signal_node := signal_named("CentralWestEntryNorth")
	var train := make_train(express_type, north_main, 150.0, 1, stops([central, east_gate]))
	await drive(1500)
	assert_eq(train.blocking_signal, signal_node, "held at the red signal")
	assert_null(train.dwelling_at, "it never reached the station")
	assert_eq(train.route_index, 0, "so the station is still its next stop")


func test_a_train_too_fast_to_stop_in_time_passes_the_station() -> void:
	# Nose 15 m short of the stop mark at 18 m/s: 27 m is what its brakes need at the very least.
	clear([EAST_EXIT])
	var at := stop_mark(central, north_main, 1)
	var train := make_train(express_type, north_main, 0.0, 1, stops([central, east_gate]))
	train.distance = at - 15.0 - train.half_length()
	train.roll(18.0)
	await drive(240)
	assert_null(train.dwelling_at, "it is not dwelling")
	assert_eq(train.route_index, 0, "the station was missed")
	assert_greater(nose_on(train, north_main), at + 10.0, "and its nose is past the stop mark")
	assert_false(train.tripped, "missing a station is not a fault")


func test_a_station_with_several_tracks_is_stopped_at_on_whichever_the_train_is_on() -> void:
	for row: Array in [[south_main, 605.0], [central_loop, 40.0]]:
		var line: Rail = row[0]
		var train := make_train(local_type, line, row[1], 1, stops([central, east_gate]), 1)
		await drive_until(func() -> bool: return train.dwelling_at != null)
		assert_eq(train.dwelling_at, central, "on %s it stops at Central" % line.name)
		assert_near(nose_on(train, line), stop_mark(central, line, 1), 0.02,
				"with its nose on %s's eastbound stop mark" % line.name)
		train.queue_free()
		await physics_frames(2)


func test_a_train_going_the_other_way_stops_at_the_other_end_of_the_same_platform() -> void:
	var track := track_on(central, south_main)
	var westbound := make_train(local_type, south_main, 755.0, -1, stops([central, west_gate]), 1)
	await drive_until(func() -> bool: return westbound.dwelling_at != null)
	note("westbound: nose at %.2f, tail at %.2f, platform %.1f - %.1f" % [
			westbound.distance - westbound.half_length(), westbound.distance + westbound.half_length(),
			track.stop_distance(-1), track.stop_distance(1)])
	assert_near(nose_on(westbound, south_main), track.stop_distance(-1), 0.02,
			"a westbound train stands with its nose on the west end of the platform")
	assert_between(westbound.distance + westbound.half_length(), track.stop_distance(-1),
			track.stop_distance(1), "and the rest of it on the platform")
	westbound.queue_free()
	await physics_frames(2)
	var eastbound := make_train(local_type, south_main, 605.0, 1, stops([central, east_gate]), 1)
	await drive_until(func() -> bool: return eastbound.dwelling_at != null)
	assert_near(nose_on(eastbound, south_main), track.stop_distance(1), 0.02,
			"an eastbound one with its nose on the east end")
	assert_between(eastbound.distance - eastbound.half_length(), track.stop_distance(-1),
			track.stop_distance(1), "on the same stretch of platform")


func test_the_stop_mark_is_found_across_the_points() -> void:
	# From the mine branch over MineSplit set for loading track B: the stop mark is on
	# MineSiding, a rail the train is not on yet.
	throw("Turnouts/MineSplit", Turnout.Position.REVERSE)
	var train := make_train(empty_type, mine_branch, 40.0, 1, stops([mine, east_gate]), 2)
	var stopped := await drive_until(func() -> bool: return train.dwelling_at != null)
	note("%s: nose on %s at %.2f" % [train.name, train.nose().rail.name, train.nose().distance])
	assert_true(stopped, "the train stops at the mine")
	assert_eq(train.nose().rail, mine_siding, "on loading track B")
	assert_near(nose_on(train, mine_siding), stop_mark(mine, mine_siding, 1), 0.02,
			"with its nose on track B's stop mark")


func test_a_mine_fills_the_wagons_while_the_train_stands() -> void:
	var train := make_train(empty_type, mine_branch, 135.0, 1, stops([mine, east_gate]), 3, 0.0)
	await drive_until(func() -> bool: return train.dwelling_at == mine)
	assert_near(nose_on(train, mine_branch), stop_mark(mine, mine_branch, 1), 0.02,
			"it stands with its nose on loading track A's stop mark")
	assert_eq(train.load_factor, 0.0, "it arrives empty")
	var mass_before := train.total_mass()
	await physics_frames(int(mine.dwell_time * 60.0 * 0.5))
	note("half way through the stop: load %.1f" % train.load_factor)
	assert_between(train.load_factor, 0.2, 0.8, "half full half way through")
	await drive_until(func() -> bool: return train.dwelling_at == null)
	assert_eq(train.load_factor, 1.0, "it leaves full")
	assert_greater(train.total_mass(), mass_before + 100.0, "and heavier")


func test_a_factory_empties_the_wagons() -> void:
	var train := make_train(loaded_type, factory_siding, 40.0, 1, stops([factory, west_gate]), 3, 1.0)
	await drive_until(func() -> bool: return train.dwelling_at == factory)
	assert_eq(train.load_factor, 1.0, "it arrives full")
	await drive_until(func() -> bool: return train.dwelling_at == null)
	assert_eq(train.load_factor, 0.0, "it leaves empty")


func test_a_station_that_does_nothing_leaves_the_load_alone() -> void:
	var train := make_train(loaded_type, north_main, 595.0, 1, stops([central, east_gate]), 3, 1.0)
	await drive_until(func() -> bool: return train.dwelling_at == central)
	await drive_until(func() -> bool: return train.dwelling_at == null)
	assert_eq(train.load_factor, 1.0, "a freight train stopping at a passenger station keeps its load")


func test_passenger_coaches_carry_nothing_to_load() -> void:
	var train := make_train(local_type, mine_branch, 135.0, 1, stops([mine, east_gate]), 2)
	await drive_until(func() -> bool: return train.dwelling_at == mine)
	await drive_until(func() -> bool: return train.dwelling_at == null)
	assert_eq(train.load_factor, 0.0, "a mine does nothing to a coach")


func test_stops_are_made_in_the_order_of_the_route() -> void:
	# Factory first, Central second: Central is passed first and driven through, the
	# factory is stopped at, and then the train carries on.
	clear([EAST_EXIT])
	throw("Turnouts/FactoryJunction", Turnout.Position.REVERSE)
	var train := make_train(express_type, north_main, 595.0, 1, stops([factory, central, east_gate]))
	await drive_until(func() -> bool: return train.dwelling_at != null, 5000)
	assert_eq(train.dwelling_at, factory, "the first stop is the factory, not the station before it")
	assert_near(nose_on(train, factory_siding), stop_mark(factory, factory_siding, 1), 0.02,
			"with its nose on the siding's stop mark")
	assert_eq(train.next_stop(), central, "Central, behind it now, is what comes next")


func test_a_derailed_train_does_not_dwell_or_load() -> void:
	var train := make_train(empty_type, mine_branch, 135.0, 1, stops([mine, east_gate]), 2)
	await drive_until(func() -> bool: return train.dwelling_at == mine)
	train.derail("test")
	assert_null(train.dwelling_at, "a wreck is not dwelling")
	assert_eq(train.state, Train.State.DERAILED, "it is a wreck")
	await physics_frames(600)
	assert_eq(train.load_factor, 0.0, "and loads nothing")


func test_the_front_marker_is_cyan_while_dwelling() -> void:
	assert_eq(Train.state_color(Train.State.DWELLING), Color(0.2, 0.85, 1.0), "cyan")
	assert_false(Train.state_blinks(Train.State.DWELLING), "steady")


func test_a_train_held_by_a_red_on_the_platform_has_not_arrived() -> void:
	# A signal 10 m past the Halt's mark stands on its platform, 35 m short of the
	# eastbound stop mark: a train held there has the mark under it but its nose short
	# of where it stops, so it has not arrived.
	var rail_signal := RailSignal.new()
	rail_signal.name = "OnThePlatform"
	rail_signal.rail = north_main
	rail_signal.distance = mark(halt, north_main) + 10.0
	rail_signal.governs = RailSignal.Governs.TOWARDS_RAIL_END
	demo.get_node("Signals").add_child(rail_signal)
	var train := make_train(express_type, north_main, 1150.0, 1, stops([halt, east_gate]))
	await drive(1500)
	note("%s @ %.1f m: %s" % [train.name, train.distance, train.blocked_description()])
	assert_true(train.occupies(north_main, mark(halt, north_main)), "the Halt's mark is under the train")
	assert_eq(train.blocking_signal, rail_signal, "it is held at the signal")
	assert_null(train.dwelling_at, "and is not dwelling")
	assert_eq(train.route_index, 0, "the Halt is still its next stop")
	rail_signal.aspect = RailSignal.Aspect.CLEAR
	var stopped := await drive_until(func() -> bool: return train.dwelling_at != null, 1200)
	assert_true(stopped, "with the signal cleared it draws up to the platform's end")
	assert_near(nose_on(train, north_main), stop_mark(halt, north_main, 1), 0.02,
			"and stops with its nose on the stop mark")
